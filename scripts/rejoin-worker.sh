#!/usr/bin/env bash
# rejoin-worker.sh — Wipe and re-join a Talos worker node
#
# Use when a worker has stale data on its Ceph disk that prevents it from
# entering Talos maintenance mode (port 50000 closed or RST instead of open).
#
# Symptom: node missing from `kubectl get nodes`, port 50000 RST or stuck
# Cause:   previous Talos install on Ceph disk confuses boot sequence
# Fix:     wipe first 10MB of disk → ISO boot → maintenance mode → apply-config
#
# Usage:
#   NODE_IP=192.168.86.113 ./scripts/rejoin-worker.sh
#   make rejoin-worker NODE_IP=192.168.86.113
#
# Optional overrides:
#   WORKER_IPS   comma-separated list (default: reads from CLUSTER_WORKER_IPS or talconfig.yaml)
#   TALOS_OUT    path to generated configs (default: talos/_out)
#   SSH_KEY      SSH key for Proxmox nodes (default: ~/.ssh/id_ansible)
#   CEPH_POOL    Ceph pool name (default: thinkCentreCeph)
set -euo pipefail

NODE_IP="${NODE_IP:?Set NODE_IP to the worker target static IP, e.g. 192.168.86.113}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
TALOS_OUT="${TALOS_OUT:-${REPO_ROOT}/talos/_out}"
SSH_KEY="${SSH_KEY:-${HOME}/.ssh/id_ansible}"
CEPH_CONF="/etc/pve/ceph.conf"
CEPH_KEYRING="/etc/pve/priv/ceph.client.admin.keyring"
CEPH_POOL="${CEPH_POOL:-thinkCentreCeph}"

# All Proxmox node IPs to search
PVE_NODES="192.168.86.29 192.168.86.30 192.168.86.31 192.168.86.130 192.168.86.147"

log() { echo "[$(date '+%H:%M:%S')] $*"; }
die() { log "ERROR: $*"; exit 1; }

# --- Resolve config file ---
# Derive worker index from WORKER_IPS order, falling back to talconfig.yaml grep
WORKERS=()
if [[ -n "${WORKER_IPS:-}" ]]; then
  IFS=',' read -ra WORKERS <<< "$WORKER_IPS"
else
  # Try reading from talconfig.yaml
  TALCONFIG="${REPO_ROOT}/talos/talconfig.yaml"
  if [[ -f "$TALCONFIG" ]]; then
    WORKER_IPS_RAW=$(grep -A 100 'workers:' "$TALCONFIG" 2>/dev/null | grep 'ipAddress:' | awk '{print $2}' | tr '\n' ',' | sed 's/,$//' || true)
    if [[ -n "$WORKER_IPS_RAW" ]]; then
      IFS=',' read -ra WORKERS <<< "$WORKER_IPS_RAW"
    fi
  fi
fi

CONFIG_FILE=""
if [[ "${#WORKERS[@]}" -gt 0 ]]; then
  for i in "${!WORKERS[@]}"; do
    if [[ "${WORKERS[$i]}" == "$NODE_IP" ]]; then
      CONFIG_FILE="${TALOS_OUT}/worker-${i}.yaml"
      break
    fi
  done
fi

# Fallback: check for worker-N.yaml files and match by IP inside them
if [[ -z "$CONFIG_FILE" ]]; then
  for f in "${TALOS_OUT}"/worker-*.yaml; do
    [[ -f "$f" ]] || continue
    if grep -q "addresses:.*${NODE_IP}" "$f" 2>/dev/null || grep -q "\"${NODE_IP}\"" "$f" 2>/dev/null; then
      CONFIG_FILE="$f"
      break
    fi
  done
fi

[[ -n "$CONFIG_FILE" ]] || die "Could not determine config file for $NODE_IP. Check WORKER_IPS or talos/_out/worker-*.yaml"
[[ -f "$CONFIG_FILE" ]] || die "Config file $CONFIG_FILE not found. Run 'make bootstrap' first or check talos/_out/."
log "Config: $CONFIG_FILE"

# --- Find the VM on Proxmox ---
log "Searching Proxmox cluster for VM with target IP $NODE_IP..."
PVE_HOST=""
VMID=""
CONF_PATH=""

for pve in $PVE_NODES; do
  result=$(ssh -i "$SSH_KEY" -o StrictHostKeyChecking=accept-new -o ConnectTimeout=5 \
    "root@${pve}" \
    "grep -rl '${NODE_IP}' /etc/pve/nodes/*/qemu-server/ 2>/dev/null | head -1" 2>/dev/null || true)
  if [[ -n "$result" ]]; then
    PVE_HOST="$pve"
    VMID=$(basename "$result" .conf)
    CONF_PATH="$result"
    break
  fi
done

[[ -n "$PVE_HOST" ]] || die "Could not find VM with IP $NODE_IP on any Proxmox node. Check that the VM exists and ipconfig0 contains $NODE_IP."
log "Found VM $VMID on $PVE_HOST (config: $CONF_PATH)"

# Extract MAC and Ceph disk image name from VM config
VM_CONFIG=$(ssh -i "$SSH_KEY" "root@${PVE_HOST}" "cat '$CONF_PATH'" 2>/dev/null)
MAC=$(echo "$VM_CONFIG" | grep '^net0:' | grep -oiP '(?<=virtio=)[A-F0-9:]+' | head -1 | tr '[:upper:]' '[:lower:]')
DISK_RAW=$(echo "$VM_CONFIG" | grep '^scsi0:' | sed 's/^scsi0: *//' | cut -d, -f1)
DISK_POOL=$(echo "$DISK_RAW" | cut -d: -f1)
DISK_IMAGE=$(echo "$DISK_RAW" | cut -d: -f2)

log "MAC: $MAC | disk: ${DISK_POOL}/${DISK_IMAGE}"

# --- Stop VM ---
log "Stopping VM $VMID on $PVE_HOST..."
ssh -i "$SSH_KEY" "root@${PVE_HOST}" "qm stop $VMID 2>&1 || true; qm status $VMID"

# --- Wipe first 10MB of Ceph disk ---
log "Wiping disk ${DISK_POOL}/${DISK_IMAGE} (first 10 MiB)..."
ssh -i "$SSH_KEY" "root@${PVE_HOST}" "
  DEV=\$(rbd --conf $CEPH_CONF --keyring $CEPH_KEYRING --id admin device map ${DISK_POOL}/${DISK_IMAGE})
  dd if=/dev/zero of=\$DEV bs=1M count=10 status=progress
  rbd --conf $CEPH_CONF --keyring $CEPH_KEYRING --id admin device unmap \$DEV
"
log "Disk wiped."

# --- Start VM ---
log "Starting VM $VMID..."
ssh -i "$SSH_KEY" "root@${PVE_HOST}" "qm start $VMID"

# --- Wait for DHCP lease ---
log "Waiting for VM to get a DHCP IP (polling ARP table on $PVE_HOST)..."
DHCP_IP=""
for i in $(seq 1 80); do
  DHCP_IP=$(ssh -i "$SSH_KEY" "root@${PVE_HOST}" \
    "ip neigh show dev vmbr0 | grep -i '${MAC}' | grep -v 'fe80' | awk '{print \$1}'" 2>/dev/null | head -1 || true)
  if [[ -n "$DHCP_IP" ]]; then
    log "VM got DHCP IP: $DHCP_IP"
    break
  fi
  echo "  [${i}/80] no DHCP yet, waiting 10s..."
  sleep 10
done

[[ -n "$DHCP_IP" ]] || die "VM $VMID did not get a DHCP IP after 800s. Check the VM console on $PVE_HOST."

# --- Wait for Talos maintenance mode ---
log "Waiting for Talos maintenance mode at $DHCP_IP:50000 (ISO boot takes ~10min)..."
for i in $(seq 1 90); do
  if nc -z -w 3 "$DHCP_IP" 50000 2>/dev/null; then
    log "Talos maintenance mode is up at $DHCP_IP:50000"
    break
  fi
  if [[ "$i" -ge 90 ]]; then
    die "Talos maintenance mode did not open after 900s at $DHCP_IP:50000. Check the VM console."
  fi
  echo "  [${i}/90] port 50000 not open yet, waiting 10s..."
  sleep 10
done

# --- Apply config ---
log "Applying $CONFIG_FILE to $DHCP_IP (--insecure)..."
talosctl apply-config \
  --insecure \
  --nodes "$DHCP_IP" \
  --file "$CONFIG_FILE"

log "Done. Node is installing Talos to disk and will reboot to $NODE_IP."
log ""
log "Monitor join progress:"
log "  watch -n5 kubectl --kubeconfig ${TALOS_OUT}/kubeconfig get nodes -o wide"
log "  talosctl --talosconfig ${TALOS_OUT}/talosconfig health --nodes $NODE_IP"

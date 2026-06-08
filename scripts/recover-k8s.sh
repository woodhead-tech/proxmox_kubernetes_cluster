#!/usr/bin/env bash
# recover-k8s.sh - Re-bootstrap Talos K8s cluster after cert mismatch
#
# This script resets all Talos VMs to maintenance mode via Proxmox, generates
# fresh configs with new PKI, applies them, and re-bootstraps the cluster.
#
# install.wipe is set to false in patches, so existing disk data is preserved
# and etcd data on the control plane is retained (cluster state survives).
#
# Usage:
#   CLUSTER_VIP=192.168.86.100 \
#   CONTROLPLANE_IPS=192.168.86.101 \
#   WORKER_IPS=192.168.86.111,192.168.86.112,192.168.86.113 \
#   ./scripts/recover-k8s.sh
set -euo pipefail

CLUSTER_VIP="${CLUSTER_VIP:?Set CLUSTER_VIP}"
CONTROLPLANE_IPS="${CONTROLPLANE_IPS:?Set CONTROLPLANE_IPS}"
WORKER_IPS="${WORKER_IPS:?Set WORKER_IPS}"
TALOS_VERSION="${TALOS_VERSION:-v1.12.5}"
CLUSTER_NAME="${CLUSTER_NAME:-talos-proxmox}"
SSH_KEY="${SSH_KEY:-$HOME/.ssh/id_ansible}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
OUTPUT_DIR="${REPO_ROOT}/talos/_out"

# Proxmox node → VM ID mapping (update if VMs move)
declare -A VM_HOSTS=(
  ["192.168.86.101"]="root@192.168.86.130 400"   # CP on tower1
  ["192.168.86.111"]="root@192.168.86.30 410"    # worker-0 on thinkcentre2
  ["192.168.86.112"]="root@192.168.86.31 411"    # worker-1 on thinkcentre3
  ["192.168.86.113"]="root@192.168.86.147 412"   # worker-2 on zotac
)

log() { echo "[$(date '+%H:%M:%S')] $*"; }

proxmox_reset() {
  local node_ip=$1
  local entry="${VM_HOSTS[$node_ip]}"
  local pve_host vmid
  read -r pve_host vmid <<< "$entry"
  log "Resetting VM $vmid on $pve_host (node $node_ip)"
  ssh -i "$SSH_KEY" -o StrictHostKeyChecking=accept-new "$pve_host" "qm reset $vmid"
}

wait_for_maintenance() {
  local ip=$1
  local timeout=${2:-120}
  local elapsed=0
  log "Waiting for $ip to enter maintenance mode..."
  while [[ $elapsed -lt $timeout ]]; do
    if talosctl apply-config --insecure --nodes "$ip" --file /dev/null --dry-run 2>&1 | grep -q "error\|ok\|applied"; then
      log "$ip is in maintenance mode"
      return 0
    fi
    # Simpler check: port 50000 responds without TLS error
    if talosctl --nodes "$ip" version --insecure 2>&1 | grep -q "TAG\|Server"; then
      log "$ip is in maintenance mode"
      return 0
    fi
    sleep 5
    elapsed=$((elapsed + 5))
  done
  log "ERROR: $ip did not reach maintenance mode within ${timeout}s"
  return 1
}

IFS=',' read -ra CP_NODES <<< "$CONTROLPLANE_IPS"
IFS=',' read -ra WORKER_NODES <<< "$WORKER_IPS"

# --- Step 1: Reset workers first (preserves CP for now) ---
log "=== Resetting worker nodes ==="
for ip in "${WORKER_NODES[@]}"; do
  proxmox_reset "$ip"
done

# --- Step 2: Generate fresh configs ---
log "=== Generating Talos configs ==="
mkdir -p "$OUTPUT_DIR"
export CLUSTER_VIP TALOS_VERSION
FIRST_CP="${CP_NODES[0]}"
export CONTROLPLANE_IP="$FIRST_CP"
export WORKER_IP="${WORKER_NODES[0]}"

envsubst < "${REPO_ROOT}/talos/patches/controlplane.yaml" > "${OUTPUT_DIR}/cp-patch-0.yaml"
envsubst < "${REPO_ROOT}/talos/patches/worker.yaml" > "${OUTPUT_DIR}/worker-patch-0.yaml"

talosctl gen config "$CLUSTER_NAME" "https://${CLUSTER_VIP}:6443" \
  --config-patch-control-plane @"${OUTPUT_DIR}/cp-patch-0.yaml" \
  --config-patch-worker @"${OUTPUT_DIR}/worker-patch-0.yaml" \
  --output-dir "$OUTPUT_DIR" \
  --force

mv "${OUTPUT_DIR}/controlplane.yaml" "${OUTPUT_DIR}/controlplane-0.yaml"
mv "${OUTPUT_DIR}/worker.yaml" "${OUTPUT_DIR}/worker-0.yaml"

FIRST_WORKER="${WORKER_NODES[0]}"
for i in "${!WORKER_NODES[@]}"; do
  [[ "$i" -eq 0 ]] && continue
  ip="${WORKER_NODES[$i]}"
  log "Deriving worker config for $ip"
  sed "s/${FIRST_WORKER}/${ip}/g" "${OUTPUT_DIR}/worker-0.yaml" > "${OUTPUT_DIR}/worker-${i}.yaml"
done

export TALOSCONFIG="${OUTPUT_DIR}/talosconfig"
log "Configs generated in $OUTPUT_DIR"

# --- Step 3: Apply worker configs as they come up ---
log "=== Applying worker configs ==="
for i in "${!WORKER_NODES[@]}"; do
  ip="${WORKER_NODES[$i]}"
  wait_for_maintenance "$ip" 120
  log "Applying worker config to $ip"
  talosctl apply-config --insecure --nodes "$ip" --file "${OUTPUT_DIR}/worker-${i}.yaml"
done

# --- Step 4: Reset CP ---
log "=== Resetting control plane ==="
proxmox_reset "${CP_NODES[0]}"

# --- Step 5: Apply CP config ---
wait_for_maintenance "${CP_NODES[0]}" 180
log "Applying CP config to ${CP_NODES[0]}"
talosctl apply-config --insecure --nodes "${CP_NODES[0]}" --file "${OUTPUT_DIR}/controlplane-0.yaml"

# --- Step 6: Wait for CP then bootstrap ---
log "=== Waiting for CP to start (~60s) ==="
sleep 60

talosctl config endpoint "${CP_NODES[0]}"
talosctl config node "${CP_NODES[0]}"

log "Bootstrapping etcd (will fail gracefully if already bootstrapped)"
bootstrap_out=$(talosctl bootstrap --nodes "${CP_NODES[0]}" 2>&1) || {
  if echo "$bootstrap_out" | grep -q "AlreadyExists"; then
    log "etcd already bootstrapped, continuing"
  else
    log "ERROR: bootstrap failed: $bootstrap_out"
    exit 1
  fi
}

# --- Step 7: Fetch kubeconfig ---
log "Waiting for K8s API to be available..."
sleep 30

talosctl kubeconfig "${OUTPUT_DIR}/kubeconfig" --nodes "${CP_NODES[0]}" --force

log "======================================"
log "Recovery complete!"
log "  talosconfig: ${OUTPUT_DIR}/talosconfig"
log "  kubeconfig:  ${OUTPUT_DIR}/kubeconfig"
log ""
log "Next: run 'make certs-push' to store certs in Vaultwarden"
log "======================================"

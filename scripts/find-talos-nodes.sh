#!/usr/bin/env bash
# find-talos-nodes.sh — Locate Talos nodes in maintenance mode across the subnet
#
# Problem: After reset, Talos boots into maintenance mode and acquires a DHCP IP.
# bootstrap.sh expects nodes at their final static IPs, so it fails to connect.
#
# This script:
#   1. Reads VM MAC addresses from Proxmox VM configs (tag: talos-proxmox)
#   2. Runs a ping sweep to populate ARP tables
#   3. Matches MAC → current IP via 'ip neigh' on a Proxmox node
#   4. Outputs a table: final_ip → current_ip → DHCP/OK
#   5. Optionally generates talosctl apply-config commands for DHCP scenario
#
# Usage:
#   ./scripts/find-talos-nodes.sh
#   ./scripts/find-talos-nodes.sh --apply   # also apply configs to DHCP nodes
#
# Env vars:
#   CONTROLPLANE_IPS   comma-separated final CP IPs   (default: 192.168.86.101)
#   WORKER_IPS         comma-separated final worker IPs (default: 192.168.86.111,112,113)
#   SSH_KEY            path to Proxmox SSH key (default: ~/.ssh/id_ansible)
#   TALOS_DIR          path to talos/_out/ (default: talos/_out relative to repo root)
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
SSH_KEY="${SSH_KEY:-${HOME}/.ssh/id_ansible}"
SSH_OPTS="-i ${SSH_KEY} -o StrictHostKeyChecking=accept-new -o ConnectTimeout=5"
TALOS_DIR="${REPO_ROOT}/talos/_out"

CONTROLPLANE_IPS="${CONTROLPLANE_IPS:-192.168.86.101}"
WORKER_IPS="${WORKER_IPS:-192.168.86.111,192.168.86.112,192.168.86.113}"

# Proxmox nodes to scan
PVE_NODES="192.168.86.29 192.168.86.30 192.168.86.31 192.168.86.130 192.168.86.147"
# Which PVE node to use for the ARP ping sweep (pick one with a full view of vmbr0)
ARP_PROBE_NODE="192.168.86.29"

APPLY_MODE=0
[[ "${1:-}" == "--apply" ]] && APPLY_MODE=1

log()  { echo "[$(date '+%H:%M:%S')] $*"; }
ok()   { echo "  [OK]     $*"; }
warn() { echo "  [WARN]   $*"; }
info() { echo "  [INFO]   $*"; }

# --- Build expected IP list ---
IFS=',' read -ra ALL_FINAL_IPS <<< "${CONTROLPLANE_IPS},${WORKER_IPS}"
IFS=',' read -ra CP_IPS <<< "${CONTROLPLANE_IPS}"
IFS=',' read -ra WORKER_IP_LIST <<< "${WORKER_IPS}"

log "Scanning for Talos nodes..."
log "Expected IPs: ${ALL_FINAL_IPS[*]}"
echo ""

# --- Step 1: Collect MACs from Proxmox VMs tagged 'talos-proxmox' ---
declare -A MAC_TO_FINAL_IP
declare -A MAC_TO_VMID

log "Reading VM configs from Proxmox nodes..."
for pve in $PVE_NODES; do
  node_name=$(ssh $SSH_OPTS "root@${pve}" "hostname" 2>/dev/null || echo "$pve")

  # Get all VM IDs on this node
  vmids=$(ssh $SSH_OPTS "root@${pve}" \
    "qm list 2>/dev/null | awk 'NR>1 {print \$1}'" 2>/dev/null || true)

  for vmid in $vmids; do
    config=$(ssh $SSH_OPTS "root@${pve}" "qm config ${vmid} 2>/dev/null" || true)

    # Only process VMs tagged as talos-proxmox
    if echo "$config" | grep -q "talos-proxmox"; then
      mac=$(echo "$config" | grep '^net0:' | grep -oE '([0-9A-Fa-f]{2}:){5}[0-9A-Fa-f]{2}' | head -1 | tr '[:upper:]' '[:lower:]')
      if [[ -n "$mac" ]]; then
        MAC_TO_VMID["$mac"]="${vmid}@${pve}(${node_name})"
        info "VMID ${vmid} on ${node_name}: MAC=${mac}"
      fi
    fi
  done
done

if [[ ${#MAC_TO_VMID[@]} -eq 0 ]]; then
  echo ""
  log "ERROR: No Talos VMs found (tag: talos-proxmox). Check that VMs are created."
  exit 1
fi

# We expect one MAC per final IP — map in order: CPs first, then workers
SORTED_MACS=($(for m in "${!MAC_TO_VMID[@]}"; do echo "$m"; done | sort))
for i in "${!SORTED_MACS[@]}"; do
  [[ $i -lt ${#ALL_FINAL_IPS[@]} ]] && MAC_TO_FINAL_IP["${SORTED_MACS[$i]}"]="${ALL_FINAL_IPS[$i]}"
done

echo ""
log "Ping-sweeping 192.168.86.50-254 to populate ARP tables (this takes ~5s)..."
ssh $SSH_OPTS "root@${ARP_PROBE_NODE}" \
  'for i in $(seq 50 254); do ping -c1 -W1 192.168.86.$i &>/dev/null & done; wait; sleep 1' \
  2>/dev/null

# --- Step 2: Look up current IPs from ARP table ---
ARP_TABLE=$(ssh $SSH_OPTS "root@${ARP_PROBE_NODE}" "ip neigh show" 2>/dev/null)

declare -A MAC_TO_CURRENT_IP
while IFS= read -r line; do
  ip=$(echo "$line" | awk '{print $1}')
  mac=$(echo "$line" | awk '{print $5}' | tr '[:upper:]' '[:lower:]')
  [[ -n "$mac" && "$mac" != "<incomplete>" ]] && MAC_TO_CURRENT_IP["$mac"]="$ip"
done <<< "$ARP_TABLE"

# --- Step 3: Print table + collect DHCP nodes ---
echo ""
printf "%-20s %-20s %-20s %-12s %s\n" "EXPECTED IP" "CURRENT IP" "STATUS" "VMID" "MAC"
printf "%-20s %-20s %-20s %-12s %s\n" "-----------" "----------" "------" "----" "---"

declare -A DHCP_TO_FINAL    # dhcp_ip → final_ip
declare -A FINAL_TO_DHCP    # final_ip → dhcp_ip

all_at_final=1

for mac in "${SORTED_MACS[@]}"; do
  final_ip="${MAC_TO_FINAL_IP[$mac]:-UNKNOWN}"
  current_ip="${MAC_TO_CURRENT_IP[$mac]:-NOT_FOUND}"
  vmid="${MAC_TO_VMID[$mac]:-?}"

  if [[ "$current_ip" == "$final_ip" ]]; then
    status="OK (final)"
  elif [[ "$current_ip" == "NOT_FOUND" ]]; then
    status="NOT FOUND"
    all_at_final=0
  else
    status="DHCP"
    DHCP_TO_FINAL["$current_ip"]="$final_ip"
    FINAL_TO_DHCP["$final_ip"]="$current_ip"
    all_at_final=0
  fi

  printf "%-20s %-20s %-20s %-12s %s\n" "$final_ip" "$current_ip" "$status" "$vmid" "$mac"
done

echo ""

# --- Step 4: Summary ---
if [[ "$all_at_final" -eq 1 ]]; then
  log "All nodes are at their final static IPs. Safe to run 'make bootstrap'."
  exit 0
fi

DHCP_COUNT=${#DHCP_TO_FINAL[@]}
log "Found ${DHCP_COUNT} node(s) at DHCP IPs (maintenance mode)."
echo ""

if [[ "$APPLY_MODE" -eq 0 ]]; then
  log "To apply configs to DHCP nodes, run:"
  echo ""

  # Figure out CP vs worker for each DHCP node
  for dhcp_ip in "${!DHCP_TO_FINAL[@]}"; do
    final_ip="${DHCP_TO_FINAL[$dhcp_ip]}"

    # Determine config file
    config_file=""
    for i in "${!CP_IPS[@]}"; do
      [[ "${CP_IPS[$i]}" == "$final_ip" ]] && config_file="talos/_out/controlplane-${i}.yaml"
    done
    if [[ -z "$config_file" ]]; then
      for i in "${!WORKER_IP_LIST[@]}"; do
        [[ "${WORKER_IP_LIST[$i]}" == "$final_ip" ]] && config_file="talos/_out/worker-${i}.yaml"
      done
    fi

    echo "  # Node at DHCP ${dhcp_ip} → final ${final_ip}"
    echo "  talosctl apply-config --insecure --nodes ${dhcp_ip} --file ${config_file:-talos/_out/<config>.yaml}"
  done

  echo ""
  echo "  Or re-run with --apply to do this automatically:"
  echo "  CONTROLPLANE_IPS=${CONTROLPLANE_IPS} WORKER_IPS=${WORKER_IPS} ./scripts/find-talos-nodes.sh --apply"
  exit 1
fi

# --- Step 5: --apply mode: apply configs automatically ---
if [[ ! -d "$TALOS_DIR" ]]; then
  log "ERROR: ${TALOS_DIR} not found. Run config generation first:"
  log "  CLUSTER_VIP=192.168.86.100 CONTROLPLANE_IPS=${CONTROLPLANE_IPS} WORKER_IPS=${WORKER_IPS} make bootstrap"
  exit 1
fi

log "Applying configs to DHCP nodes..."
for dhcp_ip in "${!DHCP_TO_FINAL[@]}"; do
  final_ip="${DHCP_TO_FINAL[$dhcp_ip]}"

  config_file=""
  for i in "${!CP_IPS[@]}"; do
    [[ "${CP_IPS[$i]}" == "$final_ip" ]] && config_file="${TALOS_DIR}/controlplane-${i}.yaml"
  done
  if [[ -z "$config_file" ]]; then
    for i in "${!WORKER_IP_LIST[@]}"; do
      [[ "${WORKER_IP_LIST[$i]}" == "$final_ip" ]] && config_file="${TALOS_DIR}/worker-${i}.yaml"
    done
  fi

  if [[ -z "$config_file" || ! -f "$config_file" ]]; then
    warn "No config file found for final IP ${final_ip} — skipping ${dhcp_ip}"
    continue
  fi

  log "Applying config to ${dhcp_ip} (→ ${final_ip}) from ${config_file##*/}"
  talosctl apply-config --insecure --nodes "${dhcp_ip}" --file "${config_file}" && \
    ok "Applied to ${dhcp_ip}" || warn "Failed to apply to ${dhcp_ip}"
done

echo ""
log "Configs applied. Nodes will reboot and come up at final static IPs."
log "Wait 60-90s then check: ping ${CP_IPS[0]}"
log "Then bootstrap: talosctl --talosconfig ${TALOS_DIR}/talosconfig bootstrap --nodes ${CP_IPS[0]}"

#!/usr/bin/env bash
# bootstrap.sh - Generate Talos configs, apply them, and bootstrap the cluster
#
# Prerequisites:
#   - talosctl installed (matching TALOS_VERSION)
#   - VMs created and booted from Talos ISO (via Terraform)
#   - Network connectivity to VM IPs (static IPs or socat proxies)
#
# Usage: ./scripts/bootstrap.sh
set -euo pipefail

# --- Configuration (override via environment or edit here) ---
CLUSTER_NAME="${CLUSTER_NAME:-talos-proxmox}"
CLUSTER_VIP="${CLUSTER_VIP:?Set CLUSTER_VIP to your API server VIP}"
TALOS_VERSION="${TALOS_VERSION:-v1.12.5}"
CONTROLPLANE_IPS="${CONTROLPLANE_IPS:?Set CONTROLPLANE_IPS as comma-separated list}"
WORKER_IPS="${WORKER_IPS:?Set WORKER_IPS as comma-separated list}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
TALOS_DIR="${REPO_ROOT}/talos"
OUTPUT_DIR="${TALOS_DIR}/_out"

# --- Functions ---
log() { echo "[$(date '+%H:%M:%S')] $*"; }

# --- Parse node lists ---
IFS=',' read -ra CP_NODES <<< "${CONTROLPLANE_IPS}"
IFS=',' read -ra WORKER_NODES <<< "${WORKER_IPS}"

# --- Generate configs (single PKI generation) ---
# Generate once with the first CP's patch, then derive per-node configs via sed.
# This ensures all nodes share the same cluster PKI (CA, token, etc.).
log "Generating Talos machine configs for cluster '${CLUSTER_NAME}'"
mkdir -p "${OUTPUT_DIR}"

# Export shared vars for envsubst
export CLUSTER_VIP TALOS_VERSION

# Render CP patch for the first node (used as the base for gen config)
FIRST_CP_IP="${CP_NODES[0]}"
export CONTROLPLANE_IP="${FIRST_CP_IP}"
export WORKER_IP="${WORKER_NODES[0]}"
envsubst < "${TALOS_DIR}/patches/controlplane.yaml" > "${OUTPUT_DIR}/cp-patch-0.yaml"
envsubst < "${TALOS_DIR}/patches/worker.yaml" > "${OUTPUT_DIR}/worker-patch-0.yaml"

# Single gen config call -- produces controlplane.yaml, worker.yaml, talosconfig
talosctl gen config "${CLUSTER_NAME}" "https://${CLUSTER_VIP}:6443" \
  --config-patch-control-plane @"${OUTPUT_DIR}/cp-patch-0.yaml" \
  --config-patch-worker @"${OUTPUT_DIR}/worker-patch-0.yaml" \
  --output-dir "${OUTPUT_DIR}" \
  --force

# Rename base configs to node-0 versions
mv "${OUTPUT_DIR}/controlplane.yaml" "${OUTPUT_DIR}/controlplane-0.yaml"
mv "${OUTPUT_DIR}/worker.yaml" "${OUTPUT_DIR}/worker-0.yaml"

# Derive per-CP configs (replace the first CP's IP with each subsequent CP's IP)
for i in "${!CP_NODES[@]}"; do
  [[ "$i" -eq 0 ]] && continue
  ip="${CP_NODES[$i]}"
  log "Deriving controlplane config for ${ip}"
  sed "s/${FIRST_CP_IP}/${ip}/g" "${OUTPUT_DIR}/controlplane-0.yaml" > "${OUTPUT_DIR}/controlplane-${i}.yaml"
done

# Derive per-worker configs (replace the first worker's IP with each subsequent worker's IP)
FIRST_WORKER_IP="${WORKER_NODES[0]}"
for i in "${!WORKER_NODES[@]}"; do
  [[ "$i" -eq 0 ]] && continue
  ip="${WORKER_NODES[$i]}"
  log "Deriving worker config for ${ip}"
  sed "s/${FIRST_WORKER_IP}/${ip}/g" "${OUTPUT_DIR}/worker-0.yaml" > "${OUTPUT_DIR}/worker-${i}.yaml"
done

log "Configs generated in ${OUTPUT_DIR}"

# --- Apply control plane configs ---
for i in "${!CP_NODES[@]}"; do
  ip="${CP_NODES[$i]}"
  log "Applying controlplane config to ${ip}"
  talosctl apply-config \
    --insecure \
    --nodes "${ip}" \
    --file "${OUTPUT_DIR}/controlplane-${i}.yaml"
done

# --- Apply worker configs ---
for i in "${!WORKER_NODES[@]}"; do
  ip="${WORKER_NODES[$i]}"
  log "Applying worker config to ${ip}"
  talosctl apply-config \
    --insecure \
    --nodes "${ip}" \
    --file "${OUTPUT_DIR}/worker-${i}.yaml"
done

# --- Wait for nodes to be ready ---
log "Waiting for nodes to finish installing..."
sleep 30

# --- Bootstrap the cluster ---
FIRST_CP="${CP_NODES[0]}"
log "Bootstrapping etcd on ${FIRST_CP}"

# Set talosconfig
export TALOSCONFIG="${OUTPUT_DIR}/talosconfig"
talosctl config endpoint "${FIRST_CP}"
talosctl config node "${FIRST_CP}"

talosctl bootstrap --nodes "${FIRST_CP}"

log "Bootstrap initiated. Waiting for Kubernetes API..."
sleep 60

# --- Retrieve kubeconfig ---
log "Fetching kubeconfig"
talosctl kubeconfig "${OUTPUT_DIR}/kubeconfig" \
  --nodes "${FIRST_CP}" \
  --force

log "======================================"
log "Cluster bootstrap complete!"
log "======================================"

# --- Verify all nodes joined the cluster ---
EXPECTED_NODE_COUNT=$(( ${#CP_NODES[@]} + ${#WORKER_NODES[@]} ))
log "Waiting for all ${EXPECTED_NODE_COUNT} nodes to become Ready..."

VERIFY_TIMEOUT=300
VERIFY_INTERVAL=15
elapsed=0
READY_COUNT=0

export KUBECONFIG="${OUTPUT_DIR}/kubeconfig"
while [[ "$elapsed" -lt "$VERIFY_TIMEOUT" ]]; do
  READY_COUNT=$(kubectl get nodes --no-headers 2>/dev/null | grep -c " Ready " || true)
  if [[ "$READY_COUNT" -ge "$EXPECTED_NODE_COUNT" ]]; then
    break
  fi
  log "  ${READY_COUNT}/${EXPECTED_NODE_COUNT} nodes Ready — waiting ${VERIFY_INTERVAL}s..."
  sleep "${VERIFY_INTERVAL}"
  elapsed=$(( elapsed + VERIFY_INTERVAL ))
done

if [[ "$READY_COUNT" -lt "$EXPECTED_NODE_COUNT" ]]; then
  log "ERROR: Only ${READY_COUNT}/${EXPECTED_NODE_COUNT} nodes joined within ${VERIFY_TIMEOUT}s."
  log ""
  log "Expected IPs:"
  for ip in "${CP_NODES[@]}" "${WORKER_NODES[@]}"; do
    log "  ${ip}"
  done
  log ""
  log "Actual nodes:"
  kubectl get nodes -o wide 2>/dev/null || true
  log ""
  log "Check that all CONTROLPLANE_IPS and WORKER_IPS were reachable and booted from ISO."
  exit 1
fi

log "All ${READY_COUNT}/${EXPECTED_NODE_COUNT} nodes Ready."
log ""
log "Talos config:  ${OUTPUT_DIR}/talosconfig"
log "Kubeconfig:    ${OUTPUT_DIR}/kubeconfig"
log ""
log "Next steps:"
log "  export TALOSCONFIG=${OUTPUT_DIR}/talosconfig"
log "  export KUBECONFIG=${OUTPUT_DIR}/kubeconfig"
log "  kubectl get nodes"
log "  talosctl health --nodes ${FIRST_CP}"

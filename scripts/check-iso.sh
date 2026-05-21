#!/usr/bin/env bash
# check-iso.sh — Verify Talos ISO version on all Proxmox nodes matches talconfig.yaml
#
# Symptom if skipped: you wipe a node and boot it, only to discover 10 minutes
# later that the ISO is a different Talos version than the cluster was bootstrapped
# with. The machine config's installer image corrects this on first boot, but it
# causes unnecessary confusion and a slower join.
#
# Usage:
#   ./scripts/check-iso.sh
#   make check-iso
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
TALCONFIG="${REPO_ROOT}/talos/talconfig.yaml"
SSH_KEY="${SSH_KEY:-${HOME}/.ssh/id_ansible}"
ISO_PATH="${ISO_PATH:-/var/lib/vz/template/iso/talos-amd64.iso}"

PVE_NODES="192.168.86.29 192.168.86.30 192.168.86.31 192.168.86.130 192.168.86.147"

log()  { echo "[$(date '+%H:%M:%S')] $*"; }
ok()   { echo "  [OK]   $*"; }
warn() { echo "  [WARN] $*"; }
fail() { echo "  [FAIL] $*"; FAILED=1; }
FAILED=0

# --- Read expected version from talconfig.yaml ---
if [[ ! -f "$TALCONFIG" ]]; then
  log "ERROR: $TALCONFIG not found."
  exit 1
fi
EXPECTED_VERSION=$(grep 'talosVersion:' "$TALCONFIG" | awk '{print $2}' | tr -d '"')
[[ -n "$EXPECTED_VERSION" ]] || { log "ERROR: Could not read talosVersion from $TALCONFIG"; exit 1; }
log "Expected Talos version: $EXPECTED_VERSION"
echo ""

# --- Check ISO on each node ---
for pve in $PVE_NODES; do
  PVE_NAME=$(ssh -i "$SSH_KEY" -o StrictHostKeyChecking=accept-new -o ConnectTimeout=5 \
    "root@${pve}" "hostname" 2>/dev/null || echo "$pve")

  ISO_VERSION=$(ssh -i "$SSH_KEY" -o StrictHostKeyChecking=accept-new -o ConnectTimeout=5 \
    "root@${pve}" \
    "isoinfo -d -i '${ISO_PATH}' 2>/dev/null | grep 'Volume id:' | awk '{print \$NF}'" 2>/dev/null || true)

  if [[ -z "$ISO_VERSION" ]]; then
    # Try alternate: check if the file even exists
    ISO_EXISTS=$(ssh -i "$SSH_KEY" "root@${pve}" "ls '${ISO_PATH}' 2>/dev/null && echo yes || echo no" 2>/dev/null || echo "no")
    if [[ "$ISO_EXISTS" == "no" ]]; then
      warn "$PVE_NAME ($pve): ISO not found at $ISO_PATH  → run 'make prepare'"
    else
      warn "$PVE_NAME ($pve): could not read ISO version (isoinfo missing?)"
    fi
    FAILED=1
    continue
  fi

  # Volume id format: TALOS_V1_12_5 → normalize to v1.12.5
  ACTUAL_VERSION=$(echo "$ISO_VERSION" | sed 's/TALOS_V/v/' | tr '_' '.')

  if [[ "$ACTUAL_VERSION" == "$EXPECTED_VERSION" ]]; then
    ok "$PVE_NAME ($pve): $ACTUAL_VERSION"
  else
    fail "$PVE_NAME ($pve): ISO is $ACTUAL_VERSION but talconfig.yaml expects $EXPECTED_VERSION"
    fail "       Fix: re-run 'make prepare' or manually copy ${EXPECTED_VERSION} ISO to $ISO_PATH"
  fi
done

echo ""
if [[ "$FAILED" -ne 0 ]]; then
  log "ISO check FAILED. Fix mismatches before bootstrapping or rejoining nodes."
  exit 1
fi
log "All ISOs match $EXPECTED_VERSION. Safe to bootstrap or rejoin."

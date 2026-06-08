#!/usr/bin/env bash
# certs-vault.sh - Push/pull Talos cluster certs to/from Vaultwarden
#
# Requires:
#   - bw CLI installed
#   - BW_SESSION env var from: BW_SESSION=$(bw unlock --raw)
#
# Usage:
#   ./scripts/certs-vault.sh push    # upload _out/{talosconfig,kubeconfig}
#   ./scripts/certs-vault.sh pull    # download and write to _out/
#   ./scripts/certs-vault.sh check   # verify connectivity using pulled certs
set -euo pipefail

ACTION="${1:?Usage: $0 push|pull|check}"
VAULTWARDEN_URL="${VAULTWARDEN_URL:-https://vaultwarden.woodhead.tech}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
OUTPUT_DIR="${REPO_ROOT}/talos/_out"

# Vaultwarden item IDs (created June 5 2026, contain talosconfig and kubeconfig as notes)
TALOSCONFIG_ITEM_ID="df816e94-942e-4f6d-a455-8a8c7a24e427"
KUBECONFIG_ITEM_ID="0215de5d-228d-480e-8b94-135b55dfe076"

log() { echo "[$(date '+%H:%M:%S')] $*"; }

bw config server "$VAULTWARDEN_URL" > /dev/null 2>&1

case "$ACTION" in
push)
  [[ -n "${BW_SESSION:-}" ]] || { echo "ERROR: BW_SESSION env var not set. Run: export BW_SESSION=\$(bw unlock --raw)"; exit 1; }
  [[ -f "${OUTPUT_DIR}/talosconfig" ]] || { echo "ERROR: ${OUTPUT_DIR}/talosconfig not found"; exit 1; }
  [[ -f "${OUTPUT_DIR}/kubeconfig" ]] || { echo "ERROR: ${OUTPUT_DIR}/kubeconfig not found"; exit 1; }

  bw sync --session "$BW_SESSION" > /dev/null 2>&1 || true

  update_item() {
    local item_id="$1"
    local content="$2"
    bw get item "$item_id" --session "$BW_SESSION" 2>/dev/null | \
      python3 -c "
import sys, json
item = json.load(sys.stdin)
item['notes'] = sys.argv[1]
print(json.dumps(item))
" "$content" | bw encode | bw edit item "$item_id" --session "$BW_SESSION" > /dev/null
  }

  log "Pushing talosconfig..."
  update_item "$TALOSCONFIG_ITEM_ID" "$(cat "${OUTPUT_DIR}/talosconfig")"

  log "Pushing kubeconfig..."
  update_item "$KUBECONFIG_ITEM_ID" "$(cat "${OUTPUT_DIR}/kubeconfig")"

  bw sync --session "$BW_SESSION" > /dev/null 2>&1
  log "Certs pushed to Vaultwarden (items: Talos: talosconfig, Talos: kubeconfig)"
  ;;

pull)
  [[ -n "${BW_SESSION:-}" ]] || { echo "ERROR: BW_SESSION env var not set. Run: export BW_SESSION=\$(bw unlock --raw)"; exit 1; }
  log "Pulling certs from Vaultwarden..."
  bw sync --session "$BW_SESSION" > /dev/null 2>&1 || true

  mkdir -p "$OUTPUT_DIR"

  log "Pulling talosconfig..."
  tmp_talosconfig=$(mktemp)
  bw get item "$TALOSCONFIG_ITEM_ID" --session "$BW_SESSION" | \
    python3 -c "import sys,json; print(json.load(sys.stdin)['notes'])" \
    > "$tmp_talosconfig"
  mv "$tmp_talosconfig" "${OUTPUT_DIR}/talosconfig"

  log "Pulling kubeconfig..."
  tmp_kubeconfig=$(mktemp)
  bw get item "$KUBECONFIG_ITEM_ID" --session "$BW_SESSION" | \
    python3 -c "import sys,json; print(json.load(sys.stdin)['notes'])" \
    > "$tmp_kubeconfig"
  mv "$tmp_kubeconfig" "${OUTPUT_DIR}/kubeconfig"

  chmod 600 "${OUTPUT_DIR}/talosconfig" "${OUTPUT_DIR}/kubeconfig"

  log "Certs written to ${OUTPUT_DIR}/"
  log "  talosconfig: ${OUTPUT_DIR}/talosconfig"
  log "  kubeconfig:  ${OUTPUT_DIR}/kubeconfig"
  ;;

check)
  [[ -f "${OUTPUT_DIR}/talosconfig" ]] || { echo "ERROR: ${OUTPUT_DIR}/talosconfig not found — run pull first"; exit 1; }
  [[ -f "${OUTPUT_DIR}/kubeconfig" ]] || { echo "ERROR: ${OUTPUT_DIR}/kubeconfig not found — run pull first"; exit 1; }

  log "Checking talosctl connection..."
  if talosctl version --talosconfig "${OUTPUT_DIR}/talosconfig" --nodes 192.168.86.101 2>&1 | grep -q 'v1\.'; then
    log "talosctl: OK"
  else
    log "talosctl: FAILED"
    exit 1
  fi

  log "Checking kubectl connection..."
  if KUBECONFIG="${OUTPUT_DIR}/kubeconfig" kubectl get nodes --no-headers 2>&1 | grep -q 'Ready'; then
    node_count=$(KUBECONFIG="${OUTPUT_DIR}/kubeconfig" kubectl get nodes --no-headers 2>/dev/null | grep -c 'Ready' || echo 0)
    log "kubectl: OK (${node_count} nodes Ready)"
  else
    log "kubectl: FAILED or no nodes Ready"
    exit 1
  fi
  ;;

*)
  echo "Usage: $0 push|pull|check"
  exit 1
  ;;
esac

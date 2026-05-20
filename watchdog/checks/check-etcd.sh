#!/usr/bin/env bash
# Check Kubernetes/etcd cluster health.
# Layer 1: HTTP reachability of the K8s API server VIP.
# Layer 2: talosctl health check (requires talosconfig on this host).
# Escalates only — etcd recovery requires manual steps.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../lib/notify.sh"
source "$SCRIPT_DIR/../config.env"

K8S_VIP="${K8S_VIP_IP}:6443"
TALOSCONFIG="${TALOSCONFIG_PATH:-}"

# Layer 1: K8s API reachability
api_code=$(curl -sk --max-time 10 -o /dev/null -w "%{http_code}" \
    "https://${K8S_VIP}/healthz" 2>/dev/null || echo "000")

if [[ "$api_code" == "000" ]]; then
    log "check-etcd: K8s API at $K8S_VIP is unreachable — possible etcd or control plane failure"
    notify_discord ALERT "etcd" \
        "K8s API server ($K8S_VIP) is unreachable.\nPossible etcd quorum loss or control plane failure.\n\nManual steps:\n1. SSH to tower1 (192.168.86.130): check talos-cp-0 VM status\n2. Run: \`talosctl --talosconfig <path> health\`\n3. Check etcd member list: \`talosctl etcd members\`"
    exit 2
fi

if [[ "$api_code" != "200" ]] && [[ "$api_code" != "401" ]]; then
    # 401 is expected (unauthenticated), anything else is suspicious
    log "check-etcd: K8s API returned HTTP $api_code — unexpected"
    notify_discord WARN "etcd" "K8s API at $K8S_VIP returned unexpected HTTP $api_code."
    exit 1
fi

log "check-etcd: K8s API reachable (HTTP $api_code)"

# Layer 2: talosctl health (only if talosconfig is available on this host)
if [[ -n "$TALOSCONFIG" ]] && [[ -f "$TALOSCONFIG" ]]; then
    health=$(talosctl --talosconfig "$TALOSCONFIG" health 2>&1 || echo "FAIL")

    if echo "$health" | grep -qi "fail\|error\|unhealthy"; then
        log "check-etcd: talosctl health check failed — $health"
        notify_discord ALERT "etcd" \
            "talosctl health check reported issues:\n\`\`\`$(echo "$health" | tail -20)\`\`\`\nManual intervention required."
        exit 2
    fi

    log "check-etcd: talosctl health OK"
fi

exit 0

#!/usr/bin/env bash
# Check for stale ARP entries on the Traefik LXC.
# Symptom: ping to LXC IP works but Traefik cannot proxy to it.
# Detection: curl each critical LXC directly from Traefik. If unreachable,
# dump the ARP entry so the user knows exactly which MAC to fix.
# Remediation: delete stale ARP entry to force refresh, then verify.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../lib/notify.sh"
source "$SCRIPT_DIR/../config.env"

SSH_OPTS="-i $SSH_KEY -o StrictHostKeyChecking=no -o ConnectTimeout=10 -o BatchMode=yes"
TRAEFIK_HOST="root@${TRAEFIK_IP}"

# Critical LXCs to check from Traefik's perspective: "name:ip:port"
CRITICAL_SERVICES=(
    "authentik:${AUTHENTIK_IP}:9000"
    "monitoring:${MONITORING_IP}:3000"
    "adguard:${ADGUARD_IP}:3000"
)

issues=()

for entry in "${CRITICAL_SERVICES[@]}"; do
    name="${entry%%:*}"
    rest="${entry#*:}"
    ip="${rest%%:*}"
    port="${rest##*:}"

    # Check reachability from Traefik
    result=$(ssh $SSH_OPTS "$TRAEFIK_HOST" \
        "timeout 5 curl -s -o /dev/null -w '%{http_code}' http://${ip}:${port}/ 2>/dev/null || echo 000" \
        2>/dev/null || echo "SSH_FAIL")

    if [[ "$result" == "SSH_FAIL" ]]; then
        log "check-arp: Cannot SSH to Traefik ($TRAEFIK_IP)"
        notify_discord ALERT "arp" "Cannot SSH to Traefik LXC ($TRAEFIK_IP)."
        exit 2
    fi

    if [[ "$result" == "000" ]]; then
        # Service unreachable from Traefik — check if ping works (ARP indicator)
        ping_ok=$(ssh $SSH_OPTS "$TRAEFIK_HOST" \
            "ping -c 2 -W 2 ${ip} > /dev/null 2>&1 && echo OK || echo FAIL" 2>/dev/null || echo "FAIL")

        arp_entry=$(ssh $SSH_OPTS "$TRAEFIK_HOST" \
            "arp -n ${ip} 2>/dev/null || echo 'no entry'" 2>/dev/null || echo "unknown")

        if [[ "$ping_ok" == "OK" ]]; then
            # Ping works but curl doesn't — classic stale ARP or port issue
            log "check-arp: $name ($ip:$port) — ping OK but curl fails. ARP: $arp_entry"

            # Delete the stale ARP entry to force re-resolution
            ssh $SSH_OPTS "$TRAEFIK_HOST" \
                "arp -d ${ip} 2>/dev/null || true" 2>/dev/null || true

            # Wait and retry
            sleep 2
            retry=$(ssh $SSH_OPTS "$TRAEFIK_HOST" \
                "timeout 5 curl -s -o /dev/null -w '%{http_code}' http://${ip}:${port}/ 2>/dev/null || echo 000" \
                2>/dev/null || echo "000")

            if [[ "$retry" != "000" ]]; then
                log "check-arp: $name recovered after ARP flush"
                notify_discord WARN "arp" \
                    "Stale ARP detected for $name ($ip). Flushed ARP entry and service recovered.\nOld ARP: \`$arp_entry\`"
            else
                issues+=("$name ($ip:$port) — ping OK, curl fails, ARP flush did not help. ARP: $arp_entry")
            fi
        else
            log "check-arp: $name ($ip:$port) — unreachable (not an ARP issue)"
        fi
    else
        log "check-arp: $name OK (HTTP $result)"
    fi
done

if [[ ${#issues[@]} -gt 0 ]]; then
    msg=$(printf '%s\n' "${issues[@]}")
    notify_discord ALERT "arp" \
        "Possible ARP or routing issue. Manual check needed on Traefik ($TRAEFIK_IP):\n${msg}\n\nFix: \`arp -s <IP> <correct-MAC>\` on Traefik."
    exit 2
fi

exit 0

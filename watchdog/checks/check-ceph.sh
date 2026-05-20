#!/usr/bin/env bash
# Check Ceph cluster health. If slow ops detected, identify the OSD and attempt
# a restart if ops are older than SLOW_OP_AGE_SECONDS.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../lib/notify.sh"
source "$SCRIPT_DIR/../config.env"

SSH_OPTS="-i $SSH_KEY -o StrictHostKeyChecking=no -o ConnectTimeout=10 -o BatchMode=yes"
PVE_HOST="root@${PVE1_IP}"
SLOW_OP_AGE_SECONDS="${CEPH_SLOW_OP_AGE_SECONDS:-1800}"  # 30 min default

health=$(ssh $SSH_OPTS "$PVE_HOST" 'ceph health detail 2>/dev/null' || true)

if [[ -z "$health" ]]; then
    log "check-ceph: SSH to $PVE1_IP failed or ceph not available"
    notify_discord ALERT "ceph" "Cannot reach $PVE1_IP to check Ceph health."
    exit 2
fi

if echo "$health" | grep -q "HEALTH_OK"; then
    log "check-ceph: OK"
    exit 0
fi

# Slow ops detection
if echo "$health" | grep -qiE "slow (ops|requests|osd)"; then
    slow_summary=$(echo "$health" | grep -iE "slow (ops|requests|osd)" | head -5 | tr '\n' ' ')

    # Check if any ops are older than threshold
    old_ops=$(echo "$health" | grep -oP '\d+(?= sec old)' | sort -n | tail -1 || echo "0")

    if [[ "$old_ops" -ge "$SLOW_OP_AGE_SECONDS" ]]; then
        # Identify which OSDs are reporting slow ops
        slow_osds=$(ssh $SSH_OPTS "$PVE_HOST" \
            'ceph osd perf 2>/dev/null | awk "NR>1 && \$3>500 {print \$1}" | head -5' || true)

        log "check-ceph: SLOW OPS detected (oldest: ${old_ops}s). Slow OSDs: ${slow_osds:-unknown}"

        if [[ -n "$slow_osds" ]]; then
            for osd_id in $slow_osds; do
                log "check-ceph: Restarting OSD $osd_id"
                ssh $SSH_OPTS "$PVE_HOST" \
                    "systemctl restart ceph-osd@${osd_id}.service 2>/dev/null" || true
            done
            notify_discord WARN "ceph" \
                "Slow Ceph ops detected (oldest: ${old_ops}s). Restarted OSD(s): ${slow_osds}. Summary: ${slow_summary}"
            exit 1
        else
            notify_discord ALERT "ceph" \
                "Slow Ceph ops detected (oldest: ${old_ops}s) but cannot identify affected OSD. Manual check needed.\n\`\`\`${slow_summary}\`\`\`"
            exit 2
        fi
    else
        log "check-ceph: WARN slow ops (oldest: ${old_ops}s, below ${SLOW_OP_AGE_SECONDS}s threshold — monitoring)"
        exit 0
    fi
fi

# Any other non-OK state
log "check-ceph: WARN — $health"
notify_discord WARN "ceph" "Ceph health is not OK:\n\`\`\`$(echo "$health" | head -10)\`\`\`"
exit 1

#!/usr/bin/env bash
# Check corosync RSS on all Proxmox nodes.
# Warns at COROSYNC_WARN_MB (default 800MB), alerts at COROSYNC_CRIT_MB (default 1200MB).
# The systemd MemoryMax=1500M override will auto-restart corosync at 1500MB,
# but we want early warning before it gets there.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../lib/notify.sh"
source "$SCRIPT_DIR/../config.env"

SSH_OPTS="-i $SSH_KEY -o StrictHostKeyChecking=no -o ConnectTimeout=10 -o BatchMode=yes"

WARN_MB="${COROSYNC_WARN_MB:-800}"
CRIT_MB="${COROSYNC_CRIT_MB:-1200}"

PVE_NODES=(
    "${PVE1_IP:-192.168.86.29}:thinkcentre1"
    "${PVE2_IP:-192.168.86.30}:thinkcentre2"
    "${PVE3_IP:-192.168.86.31}:thinkcentre3"
    "${TOWER1_IP:-192.168.86.130}:tower1"
    "${ZOTAC_IP:-192.168.86.147}:zotac"
)

overall_exit=0
warn_nodes=()
crit_nodes=()

for entry in "${PVE_NODES[@]}"; do
    ip="${entry%%:*}"
    name="${entry##*:}"

    rss_kb=$(ssh $SSH_OPTS "root@${ip}" \
        'ps -o rss= -p $(pgrep corosync 2>/dev/null) 2>/dev/null || echo 0' 2>/dev/null || echo 0)
    rss_mb=$(( rss_kb / 1024 ))

    if [[ "$rss_mb" -ge "$CRIT_MB" ]]; then
        log "check-corosync: $name (${ip}) CRITICAL — ${rss_mb}MB RSS (threshold: ${CRIT_MB}MB)"
        crit_nodes+=("$name: ${rss_mb}MB")
        [[ $overall_exit -lt 2 ]] && overall_exit=2
    elif [[ "$rss_mb" -ge "$WARN_MB" ]]; then
        log "check-corosync: $name (${ip}) WARN — ${rss_mb}MB RSS (threshold: ${WARN_MB}MB)"
        warn_nodes+=("$name: ${rss_mb}MB")
        [[ $overall_exit -lt 1 ]] && overall_exit=1
    else
        log "check-corosync: $name (${ip}) OK — ${rss_mb}MB RSS"
    fi
done

if [[ ${#crit_nodes[@]} -gt 0 ]]; then
    msg="Corosync memory critical on: $(IFS=', '; echo "${crit_nodes[*]}")"
    msg+="\nSystemd will auto-restart at 1500MB. Manual check recommended."
    notify_discord ALERT "corosync" "$msg"
elif [[ ${#warn_nodes[@]} -gt 0 ]]; then
    msg="Corosync memory elevated on: $(IFS=', '; echo "${warn_nodes[*]}")"
    msg+="\nCritical threshold: ${CRIT_MB}MB. Auto-restart at 1500MB."
    notify_discord WARN "corosync" "$msg"
fi

exit $overall_exit

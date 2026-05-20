#!/usr/bin/env bash
# Check NFS mount responsiveness on arr-stack. If hung, force unmount and remount.
# Restart SABnzbd if it appears hung after NFS recovery.
#
# MAINTENANCE MODE: touch /opt/watchdog/maintenance/arr-stack to skip this check.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../lib/notify.sh"
source "$SCRIPT_DIR/../config.env"

MAINTENANCE_FLAG="/opt/watchdog/maintenance/arr-stack"

if [[ -f "$MAINTENANCE_FLAG" ]]; then
    log "check-nfs: arr-stack maintenance mode active — skipping"
    exit 0
fi

SSH_OPTS="-i $SSH_KEY -o StrictHostKeyChecking=no -o ConnectTimeout=10 -o BatchMode=yes"
ARR_HOST="root@${ARR_STACK_IP}"
NFS_MOUNT="${ARR_NFS_MOUNT:-/mnt/truenas-media}"
NFS_TIMEOUT="${NFS_CHECK_TIMEOUT:-15}"

# Test NFS mount responsiveness
nfs_result=$(ssh $SSH_OPTS "$ARR_HOST" \
    "timeout $NFS_TIMEOUT ls '$NFS_MOUNT' > /dev/null 2>&1 && echo OK || echo HUNG" 2>/dev/null || echo "SSH_FAIL")

case "$nfs_result" in
    OK)
        log "check-nfs: NFS mount responsive"
        exit 0
        ;;
    SSH_FAIL)
        log "check-nfs: Cannot SSH to arr-stack ($ARR_STACK_IP)"
        notify_discord ALERT "nfs" "Cannot SSH to arr-stack ($ARR_STACK_IP). Host may be down."
        exit 2
        ;;
    HUNG)
        log "check-nfs: NFS mount $NFS_MOUNT is hung — attempting recovery"

        # Force unmount and remount
        recovery=$(ssh $SSH_OPTS "$ARR_HOST" "
            umount -f -l '$NFS_MOUNT' 2>&1 || true
            sleep 3
            mount '$NFS_MOUNT' 2>&1 && echo REMOUNT_OK || echo REMOUNT_FAIL
        " 2>/dev/null || echo "SSH_FAIL")

        if [[ "$recovery" == *"REMOUNT_OK"* ]]; then
            log "check-nfs: NFS remounted successfully — restarting SABnzbd"

            # Restart SABnzbd if it's in a hung state
            ssh $SSH_OPTS "$ARR_HOST" \
                "docker compose -f /opt/arr-stack/docker-compose.yml restart sabnzbd 2>/dev/null || true"

            notify_discord WARN "nfs" \
                "NFS mount $NFS_MOUNT was hung on arr-stack. Remounted successfully and restarted SABnzbd."
            exit 1
        else
            log "check-nfs: NFS remount failed — $recovery"
            notify_discord ALERT "nfs" \
                "NFS mount $NFS_MOUNT is hung and remount failed on arr-stack.\nManual intervention needed.\nError: ${recovery}"
            exit 2
        fi
        ;;
esac

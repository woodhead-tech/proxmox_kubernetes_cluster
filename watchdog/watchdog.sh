#!/usr/bin/env bash
# Homelab watchdog orchestrator.
# Runs all health checks sequentially, logs results, notifies Discord on issues.
# Designed to run from cron every 5 minutes on the monitoring LXC.
#
# Exit codes: 0=all OK, 1=issues detected (some remediated), 2=escalation needed
set -euo pipefail

WATCHDOG_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG="$WATCHDOG_DIR/config.env"
LOG_DIR="/var/log/watchdog"
LOG_FILE="$LOG_DIR/watchdog.log"

source "$WATCHDOG_DIR/lib/notify.sh"

[[ -f "$CONFIG" ]] || { echo "ERROR: $CONFIG not found. Copy config.env.example to config.env."; exit 1; }
source "$CONFIG"

mkdir -p "$LOG_DIR"
exec > >(tee -a "$LOG_FILE") 2>&1

log "=== watchdog run start ==="

CHECKS=(
    "check-ceph"
    "check-arp"
    "check-nfs"
    "check-klipper"
    "check-etcd"
)

overall_exit=0

for check in "${CHECKS[@]}"; do
    script="$WATCHDOG_DIR/checks/${check}.sh"

    if [[ ! -x "$script" ]]; then
        log "SKIP $check — not executable or not found"
        continue
    fi

    set +e
    "$script"
    rc=$?
    set -e

    case $rc in
        0) log "$check: OK" ;;
        1) log "$check: WARN (remediation applied)"; [[ $overall_exit -lt 1 ]] && overall_exit=1 ;;
        2) log "$check: ALERT (escalation needed)"; overall_exit=2 ;;
        *) log "$check: unknown exit $rc"; overall_exit=2 ;;
    esac
done

log "=== watchdog run end (exit $overall_exit) ==="
exit $overall_exit

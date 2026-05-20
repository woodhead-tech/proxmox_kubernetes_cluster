#!/usr/bin/env bash
# Check Klipper/Moonraker printer state via Moonraker API.
# If a printer is in error or shutdown state, send FIRMWARE_RESTART.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../lib/notify.sh"
source "$SCRIPT_DIR/../config.env"

# "name:moonraker_ip:port"
PRINTERS=(
    "ender3:${KLIPPER_ENDER3_IP}:7125"
    "ender5pro:${KLIPPER_ENDER5PRO_IP}:7125"
)

for entry in "${PRINTERS[@]}"; do
    name="${entry%%:*}"
    rest="${entry#*:}"
    ip="${rest%%:*}"
    port="${rest##*:}"

    # Get printer state from Moonraker
    response=$(curl -s --max-time 10 "http://${ip}:${port}/printer/info" 2>/dev/null || echo "CURL_FAIL")

    if [[ "$response" == "CURL_FAIL" ]] || [[ -z "$response" ]]; then
        log "check-klipper: $name ($ip) — Moonraker unreachable"
        notify_discord WARN "klipper" "$name: Moonraker at $ip:$port is unreachable."
        continue
    fi

    state=$(echo "$response" | grep -o '"state":"[^"]*"' | cut -d'"' -f4 || echo "unknown")
    state_message=$(echo "$response" | grep -o '"state_message":"[^"]*"' | cut -d'"' -f4 || echo "")

    case "$state" in
        ready)
            log "check-klipper: $name — ready"
            ;;
        error|shutdown)
            log "check-klipper: $name — $state ($state_message). Sending FIRMWARE_RESTART."

            restart_result=$(curl -s --max-time 10 \
                -X POST "http://${ip}:${port}/printer/firmware_restart" \
                2>/dev/null || echo "FAIL")

            if echo "$restart_result" | grep -q '"result"'; then
                log "check-klipper: $name FIRMWARE_RESTART sent"
                notify_discord WARN "klipper" \
                    "$name was in \`$state\` state. Sent FIRMWARE_RESTART.\nReason: $state_message"
            else
                log "check-klipper: $name FIRMWARE_RESTART failed"
                notify_discord ALERT "klipper" \
                    "$name is in \`$state\` state and FIRMWARE_RESTART failed. Manual check needed.\nReason: $state_message"
            fi
            ;;
        printing|paused)
            log "check-klipper: $name — $state (active print, skipping)"
            ;;
        *)
            log "check-klipper: $name — unknown state: $state"
            ;;
    esac
done

exit 0

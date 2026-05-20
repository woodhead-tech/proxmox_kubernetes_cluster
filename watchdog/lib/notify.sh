#!/usr/bin/env bash
# Discord notification helper. Source this file, then call notify_discord.

notify_discord() {
    local level="$1"   # OK | WARN | ALERT
    local check="$2"   # check name
    local message="$3" # human-readable detail

    [[ -z "$DISCORD_WEBHOOK" ]] && return 0

    local color emoji
    case "$level" in
        OK)    color=3066993;  emoji="✅" ;;
        WARN)  color=16776960; emoji="⚠️" ;;
        ALERT) color=15158332; emoji="🚨" ;;
        *)     color=10070709; emoji="ℹ️" ;;
    esac

    local hostname
    hostname=$(hostname -s 2>/dev/null || echo "watchdog")

    local payload
    payload=$(printf '{"embeds":[{"title":"%s [WATCHDOG] %s","description":"%s","color":%d,"footer":{"text":"host: %s • %s"}}]}' \
        "$emoji" "$check" \
        "$(echo "$message" | sed 's/"/\\"/g; s/$/\\n/' | tr -d '\n')" \
        "$color" \
        "$hostname" \
        "$(date -u '+%Y-%m-%d %H:%M UTC')")

    curl -s -X POST "$DISCORD_WEBHOOK" \
        -H "Content-Type: application/json" \
        -d "$payload" \
        --max-time 10 \
        --retry 2 \
        > /dev/null
}

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*"
}

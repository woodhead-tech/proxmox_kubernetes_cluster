#!/usr/bin/env bash
# cloudflare-ddns.sh - Update Cloudflare DNS A records when public IP changes
#
# Designed to run via cron every 5 minutes on a Proxmox host.
# Checks current public IP against a local state file and updates
# Cloudflare A records if the IP has changed.
#
# Prerequisites:
#   - curl and jq installed
#   - Cloudflare API token with Zone:DNS:Edit permission
#   - Environment file at /etc/ddns/cloudflare.env (or passed via -e flag)
#
# Usage:
#   ./cloudflare-ddns.sh              # Uses default env file
#   ./cloudflare-ddns.sh -e /path/to/env
#   ./cloudflare-ddns.sh -v           # Verbose output
set -euo pipefail

# --- Defaults ---
ENV_FILE="/etc/ddns/cloudflare.env"
STATE_DIR="/var/lib/ddns"
STATE_FILE="${STATE_DIR}/current-ip"
VERBOSE=false
CF_API_BASE="https://api.cloudflare.com/client/v4"

# --- Parse flags ---
while getopts "e:v" opt; do
  case ${opt} in
    e) ENV_FILE="${OPTARG}" ;;
    v) VERBOSE=true ;;
    *) echo "Usage: $0 [-e env_file] [-v]" && exit 1 ;;
  esac
done

# --- Logging ---
log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*"; }
debug() { [[ "${VERBOSE}" == "true" ]] && log "DEBUG: $*"; }

# --- Load environment ---
if [[ ! -f "${ENV_FILE}" ]]; then
  log "ERROR: Environment file not found: ${ENV_FILE}"
  exit 1
fi
# shellcheck source=/dev/null
source "${ENV_FILE}"

# Validate required variables
: "${CF_API_TOKEN:?CF_API_TOKEN not set in ${ENV_FILE}}"
: "${CF_ZONE_ID:?CF_ZONE_ID not set in ${ENV_FILE}}"
: "${CF_RECORD_NAMES:?CF_RECORD_NAMES not set in ${ENV_FILE}}"

# --- Get current public IP ---
get_public_ip() {
  local ip
  # Try multiple sources for reliability
  ip=$(curl -s --max-time 10 https://api.ipify.org 2>/dev/null) ||
  ip=$(curl -s --max-time 10 https://ifconfig.me 2>/dev/null) ||
  ip=$(curl -s --max-time 10 https://icanhazip.com 2>/dev/null)

  # Validate it looks like an IPv4 address
  if [[ "${ip}" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    echo "${ip}"
  else
    return 1
  fi
}

# --- Get DNS record ID and current proxied state by name ---
# Outputs: "<id> <proxied>" e.g. "abc123 true"
get_record() {
  local name="$1"
  curl -s --max-time 10 \
    -H "Authorization: Bearer ${CF_API_TOKEN}" \
    -H "Content-Type: application/json" \
    "${CF_API_BASE}/zones/${CF_ZONE_ID}/dns_records?type=A&name=${name}" \
    | jq -r 'if (.result | length) > 0 then (.result[0].id + " " + (.result[0].proxied | tostring)) else "" end'
}

# --- Update a DNS record, preserving its current proxied state ---
update_record() {
  local record_id="$1"
  local name="$2"
  local ip="$3"
  local proxied="${4:-false}"  # preserve whatever was set; default to false for safety

  local response
  response=$(curl -s --max-time 10 \
    -X PUT \
    -H "Authorization: Bearer ${CF_API_TOKEN}" \
    -H "Content-Type: application/json" \
    --data "{\"type\":\"A\",\"name\":\"${name}\",\"content\":\"${ip}\",\"ttl\":300,\"proxied\":${proxied}}" \
    "${CF_API_BASE}/zones/${CF_ZONE_ID}/dns_records/${record_id}")

  local success
  success=$(echo "${response}" | jq -r '.success')
  if [[ "${success}" == "true" ]]; then
    log "Updated ${name} -> ${ip} (proxied=${proxied})"
  else
    log "ERROR: Failed to update ${name}: $(echo "${response}" | jq -r '.errors')"
    return 1
  fi
}

# --- Main ---
current_ip=$(get_public_ip) || {
  log "ERROR: Could not determine public IP"
  exit 1
}
debug "Current public IP: ${current_ip}"

# Check state file for previous IP
mkdir -p "${STATE_DIR}"
previous_ip=""
if [[ -f "${STATE_FILE}" ]]; then
  previous_ip=$(cat "${STATE_FILE}")
fi
debug "Previous IP: ${previous_ip:-none}"

# Exit early if IP hasn't changed
if [[ "${current_ip}" == "${previous_ip}" ]]; then
  debug "IP unchanged, nothing to do"
  exit 0
fi

log "IP changed: ${previous_ip:-unknown} -> ${current_ip}"

# Update each configured DNS record
IFS=',' read -ra RECORDS <<< "${CF_RECORD_NAMES}"
errors=0
for name in "${RECORDS[@]}"; do
  name=$(echo "${name}" | xargs)  # Trim whitespace
  debug "Looking up record ID for ${name}"

  read -r record_id proxied <<< "$(get_record "${name}")"
  if [[ -z "${record_id}" || "${record_id}" == "null" ]]; then
    log "ERROR: No A record found for ${name} -- create it in Cloudflare first"
    errors=$((errors + 1))
    continue
  fi

  debug "Record ID for ${name}: ${record_id} (proxied=${proxied})"
  update_record "${record_id}" "${name}" "${current_ip}" "${proxied}" || errors=$((errors + 1))
done

# Save new IP to state file if all updates succeeded
if [[ ${errors} -eq 0 ]]; then
  echo "${current_ip}" > "${STATE_FILE}"
  log "State file updated"
else
  log "WARNING: ${errors} record(s) failed to update, state file NOT updated"
  exit 1
fi

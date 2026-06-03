#!/bin/bash
# Mirror the primary AdGuard config (192.168.86.35) onto this secondary so both
# serve identical filtering/rewrites. Pulls via a restricted deploy key (the
# primary's authorized_keys forces `cat` of the config file). Restarts AGH only
# on change. Refuses to apply anything that doesn't look like a valid config.
set -euo pipefail
PRIMARY=192.168.86.35
KEY=/etc/adguard-mirror/id_mirror
DATA=/opt/adguardhome/data
DST=$DATA/AdGuardHome.yaml
TMP=$(mktemp)
trap 'rm -f "$TMP"' EXIT

ssh -i "$KEY" -o StrictHostKeyChecking=accept-new -o ConnectTimeout=10 \
    -o BatchMode=yes root@"$PRIMARY" true > "$TMP" 2>/dev/null || { echo "mirror: pull failed"; exit 1; }

# sanity gates — never poison the secondary with garbage
[ -s "$TMP" ] || { echo "mirror: empty pull, aborting"; exit 1; }
grep -q '^schema_version:' "$TMP" || { echo "mirror: not a valid AGH config, aborting"; exit 1; }
grep -q 'port: 53' "$TMP" || { echo "mirror: missing dns port, aborting"; exit 1; }

if [ ! -f "$DST" ] || ! cmp -s "$TMP" "$DST"; then
  install -o adguard -g adguard -m600 "$TMP" "$DST"
  systemctl restart adguardhome
  logger -t agh-mirror "config changed; mirrored from $PRIMARY and restarted AdGuard"
  echo "mirror: updated + restarted"
else
  echo "mirror: no change"
fi

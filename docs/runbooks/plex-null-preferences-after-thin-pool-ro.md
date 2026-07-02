# Plex Won't Bind Port 32400 — Preferences.xml Zeroed by Thin-Pool Read-Only Event

**Date:** 2026-07-01
**Severity:** medium
**Affected:** plex (LXC 203, 192.168.86.23) on tower1

## Symptom

- `plex.woodhead.tech` returns **502** (Traefik bad gateway).
- Nothing listening on `192.168.86.23:32400`; `curl` to `/identity` hangs/000.
- `systemctl status plexmediaserver` shows the service **active (running)** — misleadingly healthy — but the process never binds its HTTP port.
- Journal repeats: `Failed to load preferences at .../Preferences.xml`.

## Root Cause

`Preferences.xml` was **zeroed out** (806 bytes, 100% null bytes) during a prior LVM
thin-pool exhaustion / `emergency_ro` event on the tower1 node (2026-06-19). ext4
persisted the file's size metadata but the delayed-allocation data blocks were never
written before the filesystem went read-only, leaving an all-null file. Plex cannot
parse it, so it aborts HTTP listener startup while the systemd unit still reports
"running." This is fallout from the storage problem, NOT the NAS/media mount.

Note: `Preferences.xml` holds the `PlexOnlineToken` (account claim) and
`ProcessedMachineIdentifier`. When zeroed, both are unrecoverable → server comes back
**unclaimed**. The library database is stored separately and is unaffected.

## Diagnosis

```bash
# LXC up but service not serving
ssh -i ~/.ssh/id_ansible root@192.168.86.23 'systemctl is-active plexmediaserver; ss -tlnp | grep 32400 || echo "nothing on 32400"'

# The tell: preferences load failure in the journal
ssh -i ~/.ssh/id_ansible root@192.168.86.23 'journalctl -u plexmediaserver --no-pager -n 10'

# Confirm the file is null-corrupt (xxd/xmllint are NOT installed in the container — use od/tr)
PD="/var/lib/plexmediaserver/Library/Application Support/Plex Media Server"
ssh -i ~/.ssh/id_ansible root@192.168.86.23 "od -c \"$PD/Preferences.xml\" | head; tr -d '\000' < \"$PD/Preferences.xml\" | wc -c"
# 0 non-null bytes == fully corrupt

# Rule OUT the NAS/media chain (the usual suspect) so you fix the right thing:
ssh -i ~/.ssh/id_ansible root@192.168.86.130 'qm status 300; mount | grep truenas-media; timeout 8 ls /mnt/truenas-media | wc -l'
```

## Fix

```bash
PD="/var/lib/plexmediaserver/Library/Application Support/Plex Media Server"

# 1. Confirm the library DB is intact (this is what preserves your libraries)
ssh -i ~/.ssh/id_ansible root@192.168.86.23 "ls -lh \"$PD/Plug-in Support/Databases/com.plexapp.plugins.library.db\""

# 2. Move the corrupt Preferences.xml aside (do NOT delete — keep for forensics)
ssh -i ~/.ssh/id_ansible root@192.168.86.23 "mv \"$PD/Preferences.xml\" \"$PD/Preferences.xml.corrupt-$(date +%Y%m%d)\""

# 3. Restart Plex — it regenerates a fresh Preferences.xml and binds 32400
ssh -i ~/.ssh/id_ansible root@192.168.86.23 'systemctl restart plexmediaserver'
```

## Verification

```bash
# Local listener + HTTP 200
ssh -i ~/.ssh/id_ansible root@192.168.86.23 'ss -tlnp | grep 32400'
curl -s -o /dev/null -w "%{http_code}\n" http://192.168.86.23:32400/identity   # expect 200

# Public route recovered (302 = healthy redirect to /web)
curl -s -o /dev/null -w "%{http_code}\n" https://plex.woodhead.tech/web

# Note claimed="0" in /identity — server is unclaimed and needs a one-time re-claim:
#   open https://plex.woodhead.tech/web, sign in, claim the server.
#   Existing libraries re-attach from com.plexapp.plugins.library.db (no re-scan).
```

## Prevention / Mitigations

- **Root fix is the thin pool.** This corruption is a downstream symptom of tower1
  thin-pool exhaustion — see `runbooks/lvm-thin-pool-exhaustion.md`. Keep the pool
  below 80%.
- **Keep a config backup** so recovery restores the real `Preferences.xml` (with the
  token) instead of forcing a re-claim:
  ```bash
  ssh -i ~/.ssh/id_ansible root@192.168.86.130 \
    'vzdump 203 --storage backup-hdd --mode snapshot --compress zstd'
  # Restore just the file later by extracting Preferences.xml from the archive.
  ```
  Baseline backup taken 2026-07-01: `backup-hdd:/dump/vzdump-lxc-203-2026_07_01-20_54_52.tar.zst`.
- After any node `emergency_ro` event, audit small config files (Plex prefs, sqlite
  DBs) for null corruption before assuming services are clean.

## Notes

- The systemd unit reporting **active (running)** while the port is dead is the key
  gotcha — don't trust `systemctl` alone; always confirm the listener with `ss`.
- `xxd` and `xmllint` are not installed in the Plex LXC; use `od -c` and `tr -d '\000'`.
- Related: `runbooks/lvm-thin-pool-exhaustion.md`; tower1 thin-pool remediation is
  scheduled for the 2026-07-03 maintenance day (Kanboard #231).

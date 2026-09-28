# Plex Won't Bind Port 32400 — Preferences.xml Zeroed by Thin-Pool Read-Only Event

**Date:** 2026-07-01 (recurred 2026-09-27)
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

**Preferred: restore the real Preferences.xml from a PBS backup** (keeps the
account claim/token — no re-claim needed). Confirmed working 2026-09-27:

```bash
# 0. First clear the underlying thin-pool problem (see lvm-thin-pool-exhaustion.md)
#    and if the LXC tripped emergency_ro, stop it, fsck, and restart before this step:
ssh -i ~/.ssh/id_ansible root@192.168.86.130 'pct stop 203'
ssh -i ~/.ssh/id_ansible root@192.168.86.130 'e2fsck -f -y /dev/pve/vm-203-disk-0'
ssh -i ~/.ssh/id_ansible root@192.168.86.130 'pct start 203'
# fsck clears the emergency_ro flag but does NOT un-zero an already-corrupted file —
# Preferences.xml will still read as 0 non-null bytes after this.

# 1. Find the most recent PBS backup for VMID 203
ssh -i ~/.ssh/id_ansible root@192.168.86.130 'pvesm list pbs-tc3 --vmid 203'
# NOTE: if the newest snapshot is more than a few days old, the backup job for this
# LXC has silently stopped — file that as a separate issue, don't just accept a stale one.

# 2. Mount the snapshot's pxar archive directly (no full pct restore needed)
ssh -i ~/.ssh/id_ansible root@192.168.86.130 '
  export PBS_PASSWORD=$(cat /etc/pve/priv/storage/pbs-tc3.pw)
  export PBS_FINGERPRINT=$(grep fingerprint /etc/pve/storage.cfg | awk "{print \$2}")
  mkdir -p /mnt/pbs-restore-203
  proxmox-backup-client mount ct/203/<SNAPSHOT-TIMESTAMP> root.pxar /mnt/pbs-restore-203 \
    --repository root@pam@192.168.86.49:main'

# 3. Copy just Preferences.xml out and push it into the running container
PD="/var/lib/plexmediaserver/Library/Application Support/Plex Media Server"
ssh -i ~/.ssh/id_ansible root@192.168.86.130 \
  "pct push 203 \"/mnt/pbs-restore-203$PD/Preferences.xml\" \"$PD/Preferences.xml\" --user plex --group plex --perms 0600"

# 4. Unmount the PBS archive and restart Plex
ssh -i ~/.ssh/id_ansible root@192.168.86.130 'umount /mnt/pbs-restore-203; rmdir /mnt/pbs-restore-203'
ssh -i ~/.ssh/id_ansible root@192.168.86.23 'systemctl restart plexmediaserver'
```

**Fallback (no usable backup exists): let Plex regenerate and re-claim**

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
- **No rescue boot available right now?** You can still clear the pool's `D`
  (degraded) flag live by migrating one running LXC's disk off `local-lvm` onto the
  Ceph `vmdata` pool and deleting the freed source volume — no downtime for other
  tenants, verify-before-delete. Confirmed 2026-09-27 (moved `drawio`, VMID 229,
  8 GiB): `pct stop <vmid>`, `pct move-volume <vmid> rootfs vmdata` (rootfs moves
  require the container stopped, unlike `qm move-disk` for VMs), `pct start <vmid>`,
  verify the service actually serves, then `lvremove pve/vm-<vmid>-disk-0` on the
  Proxmox node. This buys headroom but does NOT fix the underlying capacity deficit —
  still schedule the rescue-boot root LV shrink.
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
- **2026-09-27 recurrence:** Same root cause fired again — tower1's VG still had no
  headroom (76 MiB free) three months after the first incident, so the rescue-boot
  root LV shrink was apparently never completed. The presenting symptom this time
  was Plex "file not accessible" playback errors, which turned out to be a *separate,
  co-occurring* issue: Sonarr/Radarr had renamed the affected files (e.g.
  `...1080p...` → `...WEBDL-720p...`) and Plex's library DB still pointed at the old
  filenames. A full `/library/sections/<id>/refresh?force=1` is slow on a large
  library and doesn't prioritize the folder you care about; use the scoped form
  instead: `GET /library/sections/<id>/refresh?path=<url-encoded-folder>&X-Plex-Token=...`
  to rescan just the affected show. Also found: LXC 203's PBS backups had silently
  stopped after 2026-07-16 (only 23 total, none since) — the only backup available
  for the Preferences.xml restore was 2.5 months stale. Investigate the backup
  schedule for VMID 203 as a follow-up; a stale-but-present backup is still far
  better than none (Preferences.xml itself changes rarely), but the gap should be
  closed.

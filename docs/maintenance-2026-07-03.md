# Maintenance Day — 2026-07-03

Planned homelab maintenance window (Brandon off Fri 2026-07-03). This doc tracks the
planned work and the prep/fixes done in the days before.

## Planned work

1. **tower1 LVM thin-pool remediation** (Kanboard #231)
   - As of 2026-07-01 tower1 `pve/data` was at 81.3% (over the 80% autoextend threshold),
     VG had only ~772 MiB free so autoextend can't fire.
   - Durable fix: rescue-boot, shrink the 39 GiB root LV (~9 GiB used) to ~22 GiB, freeing
     ~15 GiB for the thin pool. See `runbooks/lvm-thin-pool-exhaustion.md`.
   - **Alternative (no rescue boot):** all tower1 LXC rootfs are on `local-lvm`; Ceph
     `vmdata` (rbd) has ~589 GiB usable. Move LXC disks to `vmdata` via `pct move-volume`
     to relieve the pool instead. (Overlaps item 4.)

2. **Network rework** (Kanboard #232) — execute Project Popeye: OPNsense + Omada APs +
   VLAN segmentation. Router/OPNsense hardware has arrived.

3. **Ceph hardening** — P1 (#234): add ceph alert rules + a 3rd mgr on thinkcentre3;
   P2 (#235): fix `/var/log/ceph` (a file, not a dir), quarantine the stray
   `ceph-thinkcentre2` mgr dir on thinkcentre1, add a monitoring dead-man's-switch.
   Full incident report: `~/PROJECT_PLANS/ceph-review/2026-07-01-ceph-incident-report.md`.

4. **tower1 → Ceph LXC migration** — move plex (203), monitoring (205), drawio (229),
   immich (230) rootfs off tower1 `local-lvm` onto Ceph `vmdata`. **GO** — Ceph resilience
   is sound (size=3 / min_size=2 / host failure domain, `vmdata` MAX AVAIL ~589 GiB).
   Migrate one at a time; verify each RBD image before deleting the source LVM volume.

## Prep + fixes completed

### 2026-07-01
- **ragnar (LXC 227) taken down + stored** (tower1-pinned via AX210 `wlp40s0` passthrough)
  to buy pool margin. Backup: `tower1:/mnt/backup-hdd/dump/vzdump-lxc-227-2026_07_01-20_31_41.tar.zst`
  (verified). Pool dropped 81.3% → 70.4%. Restore later: `pct restore 227 <archive>` (#233).
- **Ceph MGR_DOWN fixed** — root cause was a cluster-wide power event (all 4 nodes rebooted
  ~13s apart) with mgr units left `disabled`. Enabled `ceph-mgr@thinkcentre1` (active) +
  `@thinkcentre2` (standby).
- **Prometheus restored** (had been down 12 days since the 06-19 tower1 RO event) and the
  ceph mgr prometheus exporter enabled (`:9283`, target up).

### 2026-07-02
- **Network stabilized.** A separate deployment completed and the temporary Popeye AP
  bridging was removed (`hostapd` stopped + disabled on zotac `.147` and tower1) — it was an
  L2 loop bridging WiFi → `vmbr0`, causing 40–50% packet loss on thinkcentre1 and corosync
  ring flapping. LAN now **0% loss, corosync 4/4 quorate**.
- **PBS back online + fresh restore points.** PBS (LXC 223, `.49`) had been stopped; now
  running. Backed up **all 20 configured guests (0 failures)** to `pbs-tc3`, including the 4
  tower1 migration guests (203, 205, 300, 400). Daily **prune (keep-daily 90) + GC** verified
  running/succeeding. → the migration now has verified backups.
- **tower1 thin pool: 71.35%**, 772 MiB VG free (stable).
- **Ceph HEALTH_OK** confirmed (mgr thinkcentre1 active + thinkcentre2 standby, 3/3 OSDs up).
- **Alert-rule fix** (commit `6275397`): guarded `ContainerHighMemory` with
  `(container_spec_memory_limit_bytes > 0)` — cleared 39 `+Inf` false positives (53 → 14 active).
- **Plex** re-claimed + restarted (fixed Xbox playback — stale `plex.direct` cert after the
  06-17→07-01 Preferences.xml regen changed the server identity).

## Day-of checklist
- [ ] Pull latest tower1 pool %: `lvs pve/data`; confirm no `emergency_ro`.
- [ ] Confirm PBS restore points current for 203/205/300/400 before deleting any LVM volume.
- [ ] Have the rescue-boot LV-shrink runbook and the Popeye IP migration table ready.
- [ ] Decide: rescue-boot root-LV shrink (#231) vs `pct move-volume` to Ceph (item 4) — the
      latter may make the rescue boot unnecessary.

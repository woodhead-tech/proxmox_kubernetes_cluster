# tower1 LVM thin pool: shrink root, grow `pve/data` (Kanboard #231)

Prepared 2026-09-29. Requires a reboot into a live/rescue environment (ext4 root
cannot be shrunk while mounted). **Physical access (keyboard + monitor + USB) needed.**

## Why

`pve/data` (thin pool on the 119 GiB NVMe) is at **82.5%** with **76 MiB** free in the VG.
`thin_pool_autoextend_threshold = 85` cannot fire with no free extents, so the pool
goes read-only when full and takes down every guest disk on it at once
(see `plex-null-preferences-after-thin-pool-ro.md`).

## State captured 2026-09-29

| Item | Value |
|---|---|
| Root LV `pve/root` | 39.56 GiB ext4, **14.8 GiB used** (3.9 GiB of that is `/var/log`) |
| Pool `pve/data` | 68.61 GiB, 82.53% data, 3.33% metadata; VG free 76 MiB |
| On the pool | `vm-203` plex 32G (50%), `vm-205` monitoring 50G (47%), `vm-300` truenas boot 16G (91%), `vm-400` 32G (8%, **stale**, see below) |
| Already on Ceph | ct229 drawio, ct230 immich, VM 400 boot disk |
| Ceph | 3 OSDs on the thinkcentres, **none on tower1**; HEALTH_WARN is BlueStore slow-op noise only |

Target: root 39.56 -> **24 GiB** (keeps ~9 GiB free), freeing ~15.5 GiB. Grow pool by
**+14 GiB** to ~82.6 GiB (~68% used), leaving ~1.5 GiB VG free so autoextend works again.

## Before the window (do these first, they are safe online)

1. **Remove the stale disk**: VM 400 boots from Ceph; `local-lvm:vm-400-disk-0` is only
   `unused1`. `qm set 400 --delete unused1` reclaims ~2.5 GiB of pool.
2. **Trim root**: `journalctl --vacuum-size=300M; apt clean` (frees ~3 GiB, more shrink margin).
3. **Backups** (PBS `pbs-tc3`), confirmed 2026-09-29: ct203 today, vm300 today, vm400 today.
   ct205 was stale (2026-07-16); fresh backup taken 2026-09-29 into `pbs-tc3`.
   drawio/immich have no PBS backups but live on Ceph and are not touched by this work.
4. **Saved LVM metadata**: `/root/pre-resize/` on tower1 (`pve-vg.conf`, `fstab`, `lsblk.txt`,
   `lvs.txt`). Copy off-box before the window.
5. Have a Linux live USB with `lvm2` + `e2fsprogs` (Proxmox ISO debug shell or Ubuntu live).

## Shutdown order (dependencies)

- `arr-stack` (LXC 202) mounts `/media` from TrueNAS NFS (`192.168.86.40:/mnt/tank/media`).
  Stop it first or its containers hang on a dead NFS mount.
- tower1 itself mounts the same export at `/mnt/truenas-media`. **Both Plex (203) and immich (230)
  bind-mount from it** (immich `mp0: /mnt/truenas-media/immich`). Stop BOTH before unmounting: unmounting
  first left immich's stop hook hung in `umount.nfs` (D state) for 25 min until it was `kill -9`'d.
  **Stop Plex (203), then `umount /mnt/truenas-media` BEFORE stopping VM 300**, or host
  shutdown hangs on the NFS mount.
- Order: arr-stack (202) -> plex (203) -> `umount /mnt/truenas-media` -> monitoring (205) ->
  drawio (229) -> immich (230) -> talos-cp-0 (VM 400) -> truenas (VM 300) last -> reboot.
- Expected impact: **K8s API is down** for the duration (single control plane on tower1;
  workers keep running existing pods), media/Plex/requests down, monitoring gap.
- Corosync stays quorate (4 nodes, expected votes 4 -> 3 remain). No Ceph `noout` needed
  (no OSDs on tower1).

## In the live environment

```bash
vgchange -ay pve
e2fsck -f /dev/pve/root                 # must be clean before shrinking
lvreduce -r -L 24G /dev/pve/root        # -r shrinks the filesystem FIRST, then the LV
vgs pve                                 # expect ~15.5 GiB free
lvextend -L +14G /dev/pve/data          # grows the thin pool data
lvs -a pve                              # confirm data ~82.6G, root 24G, no errors
e2fsck -fn /dev/pve/root                # read-only recheck
```

Never `lvreduce` root without `-r` (or a prior `resize2fs`): shrinking the LV under a larger
filesystem destroys it. If `e2fsck` reports errors, stop and do not shrink.

## Automated one-shot (unattended) - `scripts/tower1-shrink-root/`

Replaces the manual live-USB steps. `install.sh` (run on tower1) arms it; the **next reboot**
does the work with nobody at the console, then disarms itself.

1. **initramfs `premount`** (after udev activates LVs, before root is mounted): `e2fsck -fp`,
   refuses unless fs min size + 2 GiB fits in 23 GiB, `resize2fs` to 23 GiB, `lvreduce` to
   24 GiB, `resize2fs` back up to fill. Any failure logs and boots normally with root untouched.
   Idempotent (no-op once root <= 24 GiB). Escape hatch: `noshrink` on the kernel cmdline.
2. **`shrink-root-finalize.service`** (post-boot, before guests start): extends `pve/data` by
   14 GiB online (keeps ~1.5 GiB VG free), writes `/root/pre-resize/RESULT.txt`, then removes the
   hook and rebuilds the initramfs so it can never run again, pass or fail.
3. **Tested** with `scripts/tower1-shrink-root/test-loopback.sh` (throwaway loop VG, busybox
   applets first in PATH): normal shrink with checksummed data, idempotence, refusal when the fs
   is too full, refusal when mounted, `noshrink`, pool extend. 15/15 pass. The real initramfs
   was built to a scratch file and inspected (resize2fs/tune2fs/e2fsck/lvm/thin_check present).
   NOT testable without rebooting: the actual boot-time run on tower1.
4. **Window**: `install.sh` -> stop guests in the order above -> `reboot` -> read `RESULT.txt`
   (`STATUS: OK ...`), then start-order and `/post-deploy` checks.
5. **Disarm** before the reboot if plans change: `install.sh --disarm`.

## After boot

1. `lvs pve` / `pvesm status`: pool ~68%, VG free ~1.5 GiB. `df -h /` shows ~24 GiB.
2. Start **VM 300 (TrueNAS) first**, wait for the NFS export (`showmount -e 192.168.86.40`).
3. Then VM 400, then LXCs 203, 205, 229, 230, then arr-stack 202. Re-mount `/mnt/truenas-media`
   (autofs) and confirm Plex sees `/media`.
4. Run `/post-deploy`: Plex, arr-stack `/media` mount, Radarr/Bazarr, Grafana/Prometheus,
   K8s nodes Ready, Traefik routes, `dns` LXC.

## Rollback

- Filesystem problem: restore guests from PBS (`pbs-tc3`); root is reinstallable and
  `/etc/pve` is replicated on the other nodes.
- LVM layout: `vgcfgrestore -f /root/pre-resize/pve-vg.conf pve` (metadata only, run from
  the live environment before the pool is written to).

## Alternative with no rescue boot

Move the big pool volumes to Ceph instead (stop the LXC, then
`pct move-volume 205 rootfs vmdata --delete 1`, same for 203). Frees ~39 GiB of pool
(-> ~20% used), only needs brief per-LXC downtime, no physical access, and `vmdata` is
3% used / ~590 GiB free. Consider doing this even if the shrink also happens.

## Result: executed 2026-09-29

- Root 39.56 -> 24 GiB (fsck rc=0), `pve/data` 68.6 -> 82.6 GiB, pool 82.5% -> 68.55%, VG free 1.63 GiB.
  Hook disarmed itself (`STATUS: OK` in `/root/pre-resize/RESULT.txt`). Reboot took ~2 min; the
  initramfs shrink itself took seconds.
- Things that did not go to plan: (1) immich mount ordering above; (2) TrueNAS (VM 300) did not
  power down within 180 s and was force-terminated (NFS/ZFS came back fine); (3) after boot, CTs
  203/205/230 failed autostart because they raced TrueNAS's NFS export (started ~60 s after it) and
  had to be started by hand: consider `startup: order=2,up=90` on them; (4) arr-stack (202) is on
  another node, so a host reboot does not restart it: start it manually after tower1 is back.
- Still open: stale `local-lvm:vm-400-disk-0` (`unused1` on VM 400, ~2.5 GiB) not yet removed.

# tower1 LVM Thin Pool Near-Full: Relief via LXC Migration to Ceph

**Date:** 2026-10-22
**Severity:** high (pool exhaustion makes every tower1 LXC read-only)
**Affected:** tower1 (192.168.86.130) `pve/data` thin pool; monitoring LXC 205

## Symptom

Full health check showed `pve/data` at 93.46% with the VG nearly empty
(824 MiB free). No `D` flag yet (`twi-aotz--`), so writes were not blocked, but
auto-extend (`thin_pool_autoextend_threshold = 80`) cannot fire without VG free space.

## Root Cause

tower1's VG has had almost no free extents since 2026-06-19, so the pool cannot grow.
Pool consumers: `vm-205` (monitoring, 87% of 50G, ~43 GiB), `vm-300` (TrueNAS, 90.7% of 16G),
`vm-203` (Plex, 54% of 32G).

## Diagnosis

```bash
ssh -i ~/.ssh/id_ansible root@192.168.86.130 \
  'lvs pve --noheadings -o lv_name,lv_size,data_percent,attr; vgs pve --noheadings -o vg_free'
ssh -i ~/.ssh/id_ansible root@192.168.86.130 'pct config <vmid> | grep -E "rootfs|mp[0-9]"'
```

Pick the LXC with the largest used share still on `local-lvm`. Ceph `vmdata` had ~589 GiB
available, so capacity was not a constraint (`ceph -s` HEALTH_OK first).

## Fix

Live relief by moving one LXC rootfs to Ceph (no reboot, no root-LV shrink):

```bash
# 1. Stop the LXC (move-volume refuses a running container's rootfs)
ssh -i ~/.ssh/id_ansible root@192.168.86.130 'pct stop 205'
# 2. Detached copy; ~26 GB took roughly 15-20 minutes
ssh -i ~/.ssh/id_ansible root@192.168.86.130 \
  'nohup pct move-volume 205 rootfs vmdata > /tmp/monitoring-migrate.log 2>&1 & disown'
# 3. Poll until the process is gone and rootfs shows vmdata
ssh -i ~/.ssh/id_ansible root@192.168.86.130 'pgrep -fc "pct move-volume 205"; pct config 205 | grep -E "rootfs|unused"'
# 4. Start and verify BEFORE deleting the source
ssh -i ~/.ssh/id_ansible root@192.168.86.130 'pct start 205'
# 5. Remove the old volume (left behind as unused0)
ssh -i ~/.ssh/id_ansible root@192.168.86.130 'pct set 205 --delete unused0'
```

Blast radius while stopped: Prometheus, Grafana, Alertmanager and exporters on LXC 205 are
down. Confirm the dependency before stopping.

## Verification

```bash
ssh -i ~/.ssh/id_ansible root@192.168.86.25 'grep emergency /proc/mounts || echo clean; docker ps --filter health=unhealthy -q | wc -l'
curl -s http://192.168.86.25:3000/api/health      # database ok
curl -s -o /dev/null -w '%{http_code}\n' http://192.168.86.25:9090/-/healthy
ssh -i ~/.ssh/id_ansible root@192.168.86.130 'lvs pve/data --noheadings -o lv_name,data_percent,attr'
```

Result: pool 93.47% -> 41.09%, `D` flag clear, 14/14 containers up, 0 unhealthy.

## Prevention / Mitigations

- Next consumer to watch is `vm-300` (TrueNAS, 90.7% of 16G); a poor migration candidate
  since it is the NAS itself.
- Grafana briefly returned `000` at ~45s after start (still initialising); recheck after
  15s before suspecting a fault. cadvisor/nut-exporters sit in "health: starting" for a bit.
- Do not shrink the tower1 root LV online; see the lvm-thin-pool-exhaustion runbook note
  (rescue boot only, no remote recovery path).
- Claude Code: the auto-mode classifier blocked a combined `pct stop && move-volume` SSH
  one-liner as "Modify Shared Resources". Allow rules for tower1 `pct stop/start/move-volume/
  status/config/list`, `lvs`, `vgs` were added to `~/.claude/settings.json`. Issue each `pct`
  step as its own SSH call so the rules match. `lvremove` is deliberately not allowed.

## Notes

- `lvremove` is unnecessary: `pct set <vmid> --delete unused0` removes the leftover LV.
- This is the fourth LXC moved this way (drawio, immich, monitoring earlier attempts failed
  on filesystem corruption fixed by `e2fsck`; this run completed cleanly).

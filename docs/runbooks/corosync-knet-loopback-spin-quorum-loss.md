# Corosync knet Loopback Send-Failure Spin → Cluster-Wide Quorum Loss

**Date:** 2026-07-02
**Severity:** high (full PVE control-plane loss; running VMs/LXCs + Ceph unaffected)
**Affected:** All 4 Proxmox nodes (thinkcentre1/2/3 + tower1) — corosync / pmxcfs quorum

## Symptom

- `pvecm status` → `Quorate: No`, `Total votes: 1` on **every** node (each node isolated, sees only itself).
- `pvecm` / `pct` / `qm` and anything touching `/etc/pve` hangs (pmxcfs blocks without quorum).
- Public + LAN site responses slow (7–11 s) or timing out; sites still *served* but degraded.
- corosync pegging ~282% CPU (≈3 cores) per node; node load 10–21 with **0% iowait**.
- This followed an earlier L2 network flap (Popeye/Omada network rework). By the time of diagnosis the **network was already healthy** (see below) but quorum never recovered on its own.

## Root Cause

corosync's kronosnet (knet) transport got stuck in a **loopback send-failure spin loop**:

```
[KNET] loopback: send local failed. error=Resource temporarily unavailable
```

~20,000 of these per **minute** on the three thinkcentre nodes. corosync (real-time
SCHED_FIFO priority 99) spun retrying the failed local self-send, burning ~3 cores and
**starving the totem membership protocol** — so no node could complete membership, and each
formed its own single-node cluster. tower1 showed **no** loopback errors but was still
isolated (it alone = 1 vote, can't reach quorum) because the other three were non-functional.

**It was NOT:** the network (0% ICMP loss, 1400B DF frames passed, MTU 1500 everywhere, knet
links reported `connected`), MTU, socket buffers (raising `net.core.wmem_max/rmem_max` to match
tower1's 4 MB did **not** help), corosync config (`config_version: 16` consistent on all nodes),
or Ceph (HEALTH_OK the entire time with its own independent mon quorum).

**Why a rolling restart did NOT fix it:** restarting corosync one node at a time brought each
node back up *into a cluster where the other nodes were still spinning and flooding* — the fresh
node immediately re-entered the spin. Only killing every spin **simultaneously** and starting
clean works.

## Diagnosis

```bash
# Quorum view from each node — all showed Quorate: No, Total votes: 1
for n in 29 30 31 130; do ssh -i ~/.ssh/id_ansible root@192.168.86.$n 'pvecm status 2>/dev/null | grep -E "Quorate|Total votes"'; done

# Rule out network: small AND large (DF) frames both pass, 0% loss
ssh -i ~/.ssh/id_ansible root@192.168.86.29 'ping -c 15 -q 192.168.86.30 | grep loss'
ssh -i ~/.ssh/id_ansible root@192.168.86.29 'ping -c 3 -M do -s 1400 -q 192.168.86.30 | grep loss'

# knet links show "connected" but membership never forms
ssh -i ~/.ssh/id_ansible root@192.168.86.29 'corosync-cfgtool -s'

# THE smoking gun — loopback send failures flooding, corosync pegging CPU
ssh -i ~/.ssh/id_ansible root@192.168.86.29 'journalctl -u corosync --since "-60 sec" --no-pager | grep -c "loopback: send local failed"'  # ~20000
ssh -i ~/.ssh/id_ansible root@192.168.86.29 'ps -o %cpu= -C corosync'  # ~282

# Confirm it is pure CPU spin, not I/O and not Ceph
ssh -i ~/.ssh/id_ansible root@192.168.86.29 'ps -eo stat | grep -c "^D"; top -bn1 | grep "%Cpu"'  # 0 D-state, 0.0 wa
ssh -i ~/.ssh/id_ansible root@192.168.86.29 'ceph -s | grep -E "health|mon:"'  # HEALTH_OK, mon quorum fine

# config_version consistent across nodes (rules out config mismatch)
for n in 29 30 31 130; do ssh -i ~/.ssh/id_ansible root@192.168.86.$n 'grep config_version /etc/corosync/corosync.conf'; done
```

## Fix

**Coordinated all-node stop → then start** (a rolling restart does NOT work — see Root Cause).
The cluster is already quorum-less, so a brief simultaneous corosync stop loses nothing. Ceph
has its own mon quorum and is unaffected; running VMs/LXCs keep running.

```bash
# PHASE 1 — stop corosync on ALL nodes first (kill every spin simultaneously)
for n in 29 30 31 130; do ssh -i ~/.ssh/id_ansible root@192.168.86.$n 'systemctl stop corosync'; done

# PHASE 2 — then start corosync on ALL nodes
for n in 29 30 31 130; do ssh -i ~/.ssh/id_ansible root@192.168.86.$n 'systemctl start corosync'; done

# give membership ~20s to form, then verify (see below)
```

If quorum still does not return after this, escalate to rebooting the affected nodes **one at a
time** (Ceph is size=3/min_size=2, so one thinkcentre OSD down = HEALTH_WARN but stays available
— wait for `ceph -s` to return to HEALTH_OK before the next reboot).

## Verification

```bash
# Use corosync-quorumtool (reads corosync directly; does NOT hang on pmxcfs)
ssh -i ~/.ssh/id_ansible root@192.168.86.29 'corosync-quorumtool -s | grep -E "Quorate|Total votes"'
# Expect: Quorate: Yes, Total votes: 4

# corosync CPU back to normal, loopback errors gone
ssh -i ~/.ssh/id_ansible root@192.168.86.29 'ps -o %cpu= -C corosync; journalctl -u corosync --since "-15 sec" --no-pager | grep -c "loopback: send local failed"'
# Expect: ~1-3% CPU, 0 errors

# pmxcfs healthy — pvecm no longer hangs and /etc/pve is writable
ssh -i ~/.ssh/id_ansible root@192.168.86.29 'pvecm status | grep Quorate; touch /etc/pve/.wtest && rm -f /etc/pve/.wtest && echo "/etc/pve writable"'

# Services fast again (they were slow because corosync was eating cores on the ingress hosts)
curl -sk -o /dev/null -w '%{http_code} %{time_total}s\n' --resolve help.woodhead.tech:443:192.168.86.20 https://help.woodhead.tech/
```

## Prevention / Mitigations

- **Diagnostic shortcut:** any time the cluster is `Quorate: No` but `ping` (incl. large DF frames)
  is clean between nodes, immediately check `journalctl -u corosync | grep -c "loopback: send local failed"`
  and `ps -o %cpu= -C corosync`. High loopback-error rate + high corosync CPU = this incident →
  go straight to the coordinated stop/start; don't waste time on network/MTU/buffer theories.
- **Do not bother with a rolling restart** for this failure mode — it re-enters the spin. Coordinated
  stop-all-then-start-all is the fix.
- A future monitoring rule could alert on corosync CPU > ~50% sustained and/or a nonzero rate of
  `loopback: send local failed` in the corosync journal (dead-man's-switch style, since pmxcfs
  can't page for its own quorum loss).
- Likely **trigger** was the earlier L2 network flap (Omada/Popeye rework). Stabilize switch/L2
  changes before assuming corosync will self-heal — it may need this manual recovery afterward.

## Notes

- During diagnosis `net.core.wmem_max` / `net.core.rmem_max` were raised to `4194304` on
  thinkcentre1/2/3 (runtime `sysctl -w`, non-persistent, matches tower1's existing value). This did
  **not** fix the issue and is harmless; it reverts on reboot. Not part of the fix.
- Ceph mon quorum is **independent** of corosync/pmxcfs — Ceph stayed HEALTH_OK and kept serving
  I/O throughout. Losing PVE quorum ≠ losing storage.
- Related: [[lvm-thin-pool-exhaustion]] and the general homelab-admin note that pmxcfs/`pvecm`/`pct`
  hang when quorum is lost (which is why verification uses `corosync-quorumtool`, not `pvecm`).

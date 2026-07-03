# Stale ARP on Traefik Gateway → Cluster-Wide SSO Outage

**Date:** 2026-07-03
**Severity:** high (all ~18 Authentik-protected services unreachable; public/unauth sites fine)
**Affected:** traefik-gw (192.168.86.20) → Authentik (192.168.86.28) path; every route using `authentik@file`

## Symptom

- A single service (e.g. SABnzbd at `sabnzbd.woodhead.tech`) "isn't showing" — but on inspection
  **every** Authentik-protected service is down: `grafana`, `nas`, `requests`, `sabnzbd`, … all
  return `000` (connection timeout) through Traefik.
- Public / non-SSO sites (docs, consulting, help, plex) work fine.
- The service **containers are healthy** and reachable from other hosts; Authentik itself is healthy
  (`.29 → .28:9000` returns 204). Only Traefik's path to the backend/Authentik is broken.

## Root Cause

The Traefik gateway (`.20`) had a **stale `PERMANENT` (static) ARP/neighbor entry** for Authentik
(`.28`) — and a second entry stuck in `DELAY` for arr-stack (`.22`) — left over from the
Popeye/Omada network rework. A `PERMANENT` neighbor entry never re-validates, so even though the
MAC was actually still correct, the entry sat in a non-forwarding state and **blackholed all
traffic** from `.20` to `.28`. Because every SSO route runs the `authentik@file` forwardAuth
middleware **before** proxying to its backend, a broken `.20 → .28` path takes down *all*
Authentik-protected routes at once — not just the one you happened to notice.

Key tell: `ping .28` from `.20` = 100% loss while `ip neigh` shows the entry `PERMANENT`, but the
same host is reachable from every *other* node. Static ARP + selective 100% loss from one host =
this.

## Diagnosis

```bash
# One service down → check whether ALL authentik-protected routes are down (isolates the middleware)
for h in sabnzbd grafana nas requests; do
  echo -n "$h "; curl -sk -o /dev/null -w '%{http_code}\n' --max-time 8 \
    --resolve $h.woodhead.tech:443:192.168.86.20 https://$h.woodhead.tech/
done   # all 000 = authentik path broken; public sites (docs/help) still 200

# From Traefik host: can it reach Authentik's outpost and the backend?
ssh -i ~/.ssh/id_ansible root@192.168.86.20 \
  'curl -s -o /dev/null -w "authentik %{http_code}\n" --max-time 6 http://192.168.86.28:9000/outpost.goauthentik.io/ping'
# 000 = Traefik cannot reach Authentik

# Confirm Authentik is fine from elsewhere (proves it is a .20-local path problem)
ssh -i ~/.ssh/id_ansible root@192.168.86.29 \
  'curl -s -o /dev/null -w "%{http_code}\n" --max-time 6 http://192.168.86.28:9000/outpost.goauthentik.io/ping'   # 204

# THE smoking gun — ping + neighbor state from .20 to the affected host(s)
ssh -i ~/.ssh/id_ansible root@192.168.86.20 'ping -c 3 192.168.86.28 | grep loss; ip neigh | grep "192.168.86.28 "'
# 100% loss + "PERMANENT" (or FAILED/STALE that won't refresh) = stale neighbor entry
```

## Fix

Flush the stale neighbor entries on the Traefik host and let them re-resolve dynamically. This is
safe and self-healing (ARP re-resolution is automatic); no service restart needed.

```bash
ssh -i ~/.ssh/id_ansible root@192.168.86.20 '
  ip neigh del 192.168.86.28 dev eth0    # authentik (was PERMANENT)
  ip neigh del 192.168.86.22 dev eth0    # arr-stack (was DELAY)
  ping -c 2 192.168.86.28 >/dev/null; ping -c 2 192.168.86.22 >/dev/null   # nudge re-resolution
  ip neigh | grep -E "192.168.86.(28|22) "'   # expect: REACHABLE
```

Give the neighbor entry a few seconds to settle — the first TCP attempts right after the flush may
still time out while it transitions to `REACHABLE`.

## Verification

```bash
# From .20: Authentik + backend reachable, 0% loss
ssh -i ~/.ssh/id_ansible root@192.168.86.20 '
  ping -c 10 -i 0.2 192.168.86.28 | grep loss
  curl -s -o /dev/null -w "authentik %{http_code}\n" --max-time 4 http://192.168.86.28:9000/outpost.goauthentik.io/ping'
# Expect: 0% loss, 204

# SSO routes through Traefik return 302 (redirect to Authentik login = healthy)
for h in sabnzbd grafana nas requests; do
  echo -n "$h "; curl -sk -o /dev/null -w '%{http_code}\n' --max-time 8 \
    --resolve $h.woodhead.tech:443:192.168.86.20 https://$h.woodhead.tech/
done   # all 302 in ~0.05s
```

## Prevention / Mitigations

- **Find and remove the source of the `PERMANENT` ARP entry.** A static neighbor entry on `.20`
  was manually/config-added at some point. It won't self-heal and will go stale again on the next
  reboot or L2 change. Grep the repo/host for it (`ip neigh`, `/etc/network/`, systemd units,
  Ansible) and delete it so `.20` uses normal dynamic ARP.
- **After any network rework (switch/router/VLAN changes), sweep neighbor health**, especially on
  `traefik-gw` — stale L2 state is a recurring aftershock. Quick sweep:
  ```bash
  ssh -i ~/.ssh/id_ansible root@192.168.86.20 'ip neigh | grep -iE "PERMANENT|FAILED|STALE|INCOMPLETE"'
  ```
- Diagnostic shortcut for "one SSO service is down": immediately test *all* SSO routes. If they're
  all `000` but public sites are fine, it's the `.20 → .28` (Authentik) path, not the service.

## Notes

- The affected host's MAC was actually still **correct** — the failure was the neighbor *state*,
  not a wrong MAC. Don't get distracted comparing MACs; flush and re-resolve.
- Second aftershock from the Popeye/Omada network rework (the first was the corosync loopback spin —
  see [[corosync-knet-loopback-spin-quorum-loss]]). Both were stale/degraded L2 state that didn't
  self-heal after the network stabilized.
- 302 from an Authentik-protected route = healthy (redirect to SSO login). 000 = the forwardAuth
  path is broken.

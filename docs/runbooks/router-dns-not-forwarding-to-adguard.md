# Router DNS Not Forwarding to AdGuard — LAN Clients Get "Connection Refused" on *.woodhead.tech

**Date:** 2026-09-25
**Severity:** low (workaround exists per-device; not a service outage)
**Affected:** Any LAN client using the router (192.168.86.1) as its DNS server, for every `*.woodhead.tech` hostname

## Symptom

Browser/curl reports "connection refused" (or similar TLS/connect failure) hitting any
`*.woodhead.tech` subdomain from inside the LAN — reported first as `lab.woodhead.tech`
"giving errors" — while the service itself is completely healthy: Traefik and the backend
both respond `200`/`302` when tested directly (via `--resolve ...:127.0.0.1` from the
Traefik host itself, or from AdGuard).

## Root Cause

Public DNS for `*.woodhead.tech` is a real A record pointing at the home WAN IP
(`50.47.181.194` at time of writing) — not proxied through Cloudflare. AdGuard
(`192.168.86.35`) has the correct split-horizon rewrite:

```yaml
rewrites:
  - domain: '*.woodhead.tech'
    answer: 192.168.86.20
```

But the router at `192.168.86.1` does **not** forward DNS queries to AdGuard — it resolves
`*.woodhead.tech` straight to the public WAN IP itself. The router doesn't support NAT
hairpin/loopback, so any client that gets an answer of the router's own public IP for a
port it's simultaneously forwarding inbound gets a refused connection when trying to
reach it from inside the network.

This affects **every** LAN device using the router as its DNS server — it is not specific
to any one subdomain. `docs.woodhead.tech` (long-established, definitely-working service)
failed identically during diagnosis, confirming the DNS path, not the target service, was
the problem.

## Diagnosis

```bash
# Public DNS resolves correctly and matches the real WAN IP — not a DNS record problem
dig +short lab.woodhead.tech @1.1.1.1
curl -s https://ifconfig.me   # compare against the above

# AdGuard's split-horizon rewrite is correct
dig +short lab.woodhead.tech @192.168.86.35   # -> 192.168.86.20 (correct)

# But the router does NOT apply it
dig +short lab.woodhead.tech @192.168.86.1    # -> public WAN IP (wrong, for LAN clients)

# Confirm this machine is actually using the router as its resolver
resolvectl status   # Current DNS Server: 192.168.86.1

# Confirm the service itself is healthy, ruling out an actual outage
ssh root@192.168.86.20 \
  'curl -sk -o /dev/null -w "%{http_code}\n" --resolve lab.woodhead.tech:443:127.0.0.1 https://lab.woodhead.tech/'
# -> 200
```

## Fix

**Per-device workaround (applied 2026-09-25):**

```bash
# Find the active NetworkManager connection
nmcli connection show

# Point it at AdGuard directly, bypassing the router's non-forwarding resolver
nmcli connection modify <connection-name> ipv4.dns "192.168.86.35" ipv4.ignore-auto-dns yes
nmcli connection up <connection-name>
```

**Durable fix (not yet applied):** change the router's DHCP-handed-out DNS server to
`192.168.86.35` (AdGuard) so every LAN client gets split-horizon resolution automatically,
instead of patching each device individually. This is also expected to be resolved
naturally by the OPNsense/Popeye network migration (see `opnsense-install-popeye.md`),
since OPNsense's own DHCP would hand out AdGuard (or itself, chained to AdGuard) as DNS.

## Verification

```bash
dig +short lab.woodhead.tech    # -> 192.168.86.20 (was the public WAN IP before the fix)
curl -sk -o /dev/null -w "%{http_code}\n" https://lab.woodhead.tech/   # -> 200 (was connection refused)
dig +short google.com | head -1   # sanity check: general internet resolution still works
```

## Prevention / Mitigations

- No cluster-wide fix applied yet — only the one affected machine was repointed at AdGuard.
- Any other LAN device (phones, other laptops) using the router as DNS will exhibit the
  same symptom until either the router's DHCP DNS setting is changed or the Popeye/OPNsense
  migration lands.
- When troubleshooting "service X won't load" complaints from inside the LAN going forward,
  check the client's DNS resolver (`resolvectl status` / equivalent) before assuming a
  service-side outage — this fooled the initial triage into treating it as a
  service-specific issue.

## Notes

- Discovered while investigating a report of `lab.woodhead.tech` errors; it turned out to
  affect all `*.woodhead.tech` subdomains equally from the affected machine.
- Related: `stale-arp-traefik-sso-outage.md` and `../..(skill)/runbooks/ip-conflict-traefik-ingress-outage.md`
  cover other ways `*.woodhead.tech` access can break from inside the LAN (stale ARP,
  IP conflict on `.20`) — this one is DNS-path-specific and distinguishable because the
  backend/Traefik test from another host succeeds immediately.

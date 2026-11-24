# DDNS Silent Failure → Inbound Mail Outage (woodhead.tech)

**Date:** 2026-11-24
**Severity:** high
**Affected:** Mailcow (`mailserver`, LXC 212, `192.168.86.34`), Cloudflare DNS for `*.woodhead.tech`, `vault`, `wg`; DDNS updater on thinkcentre1 (`192.168.86.29`)

## Symptom

- GitHub device-verification emails to `@woodhead.tech` never arrived; no inbound mail at all.
- Mailcow looked healthy: all containers `Up`, mail queue empty, listening on 25/465/587/993.
- Cloudflare-**proxied** sites (`woodhead.tech`, `photos`) kept working, which hid the problem.
  DNS-only names (`mail`, `vault`, `wg`, wildcard) were unreachable from outside.

## Root Cause

Three independent failures stacked up:

1. **DDNS updater died silently on every cron run since 2026-07-14.**
   `scripts/ddns/cloudflare-ddns.sh` runs under `set -euo pipefail` and defined
   ```bash
   debug() { [[ "${VERBOSE}" == "true" ]] && log "DEBUG: $*"; }
   ```
   Without `-v` the `[[ ]]` is false, so the function returns 1 and `set -e` kills the
   script at the first `debug` call — before it logs anything or touches DNS. Cron runs
   it without `-v`, so it never did any work, and its log stayed empty. The 2026-07-14
   "set -e early exit" fix (#33) addressed `((errors++))` but missed this.
2. **The ISP changed the public IP** `50.47.181.194` → `50.106.25.46`. With DDNS dead, every
   DNS-only record stayed on the old IP.
3. **The Cloudflare DDNS API token had been revoked/deleted** (`Invalid API Token`), so even
   a working script couldn't update records.
4. **Google Nest port forwards to Mailcow were gone** (likely lost with the IP/modem
   change). Even with correct DNS, nothing reached port 25 on `.34`.

## Diagnosis

```bash
# 1. Public DNS vs actual public IP
dig +short A mail.woodhead.tech @1.1.1.1         # old IP?
curl -s https://api.ipify.org                    # current IP
dig +short MX woodhead.tech @1.1.1.1             # MX -> mail.woodhead.tech

# 2. DDNS state on thinkcentre1: stale cache file + empty log = silent death
ssh -i ~/.ssh/id_ansible root@192.168.86.29 \
  'cat /var/lib/ddns/current-ip; ls -l /var/lib/ddns; crontab -l | grep ddns;
   journalctl -t cloudflare-ddns --since -7d --no-pager | tail'

# 3. Reproduce the set -e bug in isolation (no network, no DNS changes)
bash -c 'set -euo pipefail; V=false; debug(){ [[ "$V" == true ]] && echo dbg; }; debug x; echo reached'; echo rc=$?
# -> rc=1, "reached" never printed

# 4. Token validity (read-only)
ssh -i ~/.ssh/id_ansible root@192.168.86.29 'set -a; . /etc/ddns/cloudflare.env; set +a;
  curl -s -H "Authorization: Bearer $CF_API_TOKEN" \
  https://api.cloudflare.com/client/v4/user/tokens/verify | jq -c "{success, status: .result.status, errors: [.errors[]?.message]}"'

# 5. Is ANY internet SMTP reaching Mailcow? The postfix container's docker log is
#    near-empty -- the real mail log is in Redis (what the Mailcow UI shows):
ssh -i ~/.ssh/id_ansible root@192.168.86.34 'cd /opt/mailcow-dockerized &&
  docker compose exec -T redis-mailcow sh -c "redis-cli \${REDISPASS:+-a \$REDISPASS} --no-auth-warning LRANGE POSTFIX_MAILLOG 0 3000"' \
  | grep -oE 'CONNECT from \[[0-9.]+\]' | grep -vE '\[(127|172|10|192\.168)\.' | sort | uniq -c | head
# Only acme-mailcow self-checks and zero external CONNECTs for 10+ days = port 25 not reaching .34.
```

Gotchas hit while diagnosing:
- `docker compose logs postfix-mailcow` is **not** the mail log on this host. Use Redis `POSTFIX_MAILLOG`.
- Testing ports against your own public IP from inside the LAN is meaningless: the Nest
  refuses hairpin for 443/25 while 80 answers (router UI). Use mxtoolbox or a real external email.
- A burst of bad-token calls triggers Cloudflare `Too many authentication failures` for
  ~15 min, which masks the real `Invalid API Token` error. Pause cron before testing tokens.

## Fix

```bash
# 1. Fix debug() so it always returns 0 (branch fix/ddns-debug-set-e)
#    debug() { if [[ "${VERBOSE}" == "true" ]]; then log "DEBUG: $*"; fi; }
scp -i ~/.ssh/id_ansible scripts/ddns/cloudflare-ddns.sh root@192.168.86.29:/usr/local/bin/cloudflare-ddns.new
ssh -i ~/.ssh/id_ansible root@192.168.86.29 \
  'cp -p /usr/local/bin/cloudflare-ddns /usr/local/bin/cloudflare-ddns.bak.$(date +%Y%m%d-%H%M%S) &&
   install -m 755 /usr/local/bin/cloudflare-ddns.new /usr/local/bin/cloudflare-ddns && rm /usr/local/bin/cloudflare-ddns.new'

# 2. Pause cron while the token is bad (stops the auth-failure lockout)
ssh -i ~/.ssh/id_ansible root@192.168.86.29 'crontab -l > /root/crontab.bak.$(date +%Y%m%d-%H%M%S);
  crontab -l | sed "s|^\(\*/5 .*cloudflare-ddns.*\)|# PAUSED: \1|" | crontab -'

# 3. New token: https://dash.cloudflare.com/profile/api-tokens -> Create Token ->
#    "Edit zone DNS" template, Zone Resources = woodhead.tech only. Save to Vaultwarden
#    item "Cloudflare DDNS token (homelab)". Install via stdin so it never hits argv:
read -rs T && printf '%s' "$T" | ssh -i ~/.ssh/id_ansible root@192.168.86.29 \
  'T=$(cat); sed -i "s|^CF_API_TOKEN=.*|CF_API_TOKEN=\"$T\"|" /etc/ddns/cloudflare.env'

# 4. Push the new IP once, verbosely, then re-enable cron
ssh -i ~/.ssh/id_ansible root@192.168.86.29 '/usr/local/bin/cloudflare-ddns -v; cat /var/lib/ddns/current-ip'
ssh -i ~/.ssh/id_ansible root@192.168.86.29 'crontab -l | sed "s|^# PAUSED: ||" | crontab -'
```

5. **Router port forwards** (Google Home app → Wi-Fi → Settings → Advanced networking →
   Port management), bound to the device by MAC:

| Device | MAC | Proto | Ports |
|---|---|---|---|
| mailserver `192.168.86.34` | `BC:24:11:87:81:8E` | TCP | 25, 465, 587, 993 (+4190 optional) |
| traefik `192.168.86.20` | `BC:24:11:B1:14:B6` | TCP | 80, 443 |
| wireguard `192.168.86.39` | `BC:24:11:43:C3:7A` | UDP | 51820 |

## Verification

```bash
# DNS on the new IP (TTL 300)
for n in mail vault wg nosuchhost; do echo "$n: $(dig +short A $n.woodhead.tech @1.1.1.1)"; done

# Updater healthy under cron: state file matches public IP, no ERROR lines
ssh -i ~/.ssh/id_ansible root@192.168.86.29 'cat /var/lib/ddns/current-ip; journalctl -t cloudflare-ddns --since -1h --no-pager | tail -3'

# Inbound SMTP from the internet: external CONNECTs appear in the Redis mail log within
# minutes of opening port 25 (spam bots, then real senders). Send a real test from Gmail:
ssh -i ~/.ssh/id_ansible root@192.168.86.34 'cd /opt/mailcow-dockerized &&
  docker compose exec -T dovecot-mailcow doveadm mailbox status -u bwoodwar@woodhead.tech messages INBOX'
# External check: https://mxtoolbox.com/SuperTool.aspx?action=smtp%3amail.woodhead.tech
```

Confirmed 2026-11-24: Gmail (`74.125.82.43`) connected over TLS 1.3 and delivered within a
minute of the forwards being restored; a freshly triggered GitHub device-verification
email arrived ~5 minutes later.

## Prevention / Mitigations

- `debug()` fixed to always return 0 — `fix/ddns-debug-set-e` (`504275e`, `ac9a4ca`).
- **Do not add `mail.woodhead.tech` to `CF_RECORD_NAMES`.** It has no A record of its own
  (it resolves via `*.woodhead.tech`); listing it makes every run fail "No A record found",
  skip the state-file write, and retry forever.
- **Add monitoring** (backlog): alert when `dig mail.woodhead.tech` != current public IP,
  and when `/var/lib/ddns/current-ip` is older than N days while the public IP differs.
  A blackbox SMTP probe from outside the LAN would have caught the dead port forward.
- Consider a dedicated `mail.woodhead.tech` A record (DNS-only) so MX doesn't depend on the wildcard.

## Notes

- Mailboxes: `bwoodwar@`, `alerts@`, `clawbot@`, `clawbot-0@`; alias `brandon@` → `bwoodwar@`.
- Mailcow sends outbound via Mailgun relay, so outbound looked fine throughout; only inbound broke.
- Related: `stale-arp-traefik-sso-outage.md` (also an aftershock of network changes).

# Domain Map

All `woodhead.tech` subdomains, their backends, ports, and authentication method.
TLS terminates at Traefik LXC (`192.168.86.20`). All certs are wildcard `*.woodhead.tech`
via Let's Encrypt DNS-01 (Cloudflare).

**Auth key:** `SSO` = Authentik forwardAuth required | `None` = publicly accessible | `Own` = service has its own login

---

## Infrastructure

| Subdomain | Backend IP | Port | Auth | Notes |
|-----------|-----------|------|------|-------|
| `proxmox.woodhead.tech` | 192.168.86.29 | 8006 | SSO | Proxmox web UI (any node) |
| `traefik.woodhead.tech` | localhost | -- | SSO | Traefik dashboard |
| `auth.woodhead.tech` | 192.168.86.28 | 9000 | Own | Authentik identity provider |
| `adguard.woodhead.tech` | 192.168.86.35 | 80 | SSO | AdGuard Home DNS + blocking |
| `unifi.woodhead.tech` | 192.168.86.43 | 8443 | SSO | UniFi Network Application |
| `step-ca.woodhead.tech` | 192.168.86.36 | 9000 | None | Step-CA SSH certificate authority |
| `mail.woodhead.tech` | 192.168.86.34 | 8080 | Own | Mailcow webmail + admin |
| `nas.woodhead.tech` | 192.168.86.40 | 443 | SSO | TrueNAS web UI |
| `guac.woodhead.tech` | 192.168.86.47 | 8080 | SSO | Apache Guacamole browser RDP |

## Monitoring & Observability

| Subdomain | Backend IP | Port | Auth | Notes |
|-----------|-----------|------|------|-------|
| `grafana.woodhead.tech` | 192.168.86.25 | 3000 | Own | Grafana dashboards |
| `prometheus.woodhead.tech` | 192.168.86.25 | 9090 | SSO | Prometheus metrics |
| `alertmanager.woodhead.tech` | 192.168.86.25 | 9093 | SSO | Alertmanager |
| `alertmind.woodhead.tech` | 192.168.86.25 | 8086 | SSO | AlertMind AI triage |

## AI

| Subdomain | Backend IP | Port | Auth | Notes |
|-----------|-----------|------|------|-------|
| `claw.woodhead.tech` | 192.168.86.26 | 18789 | None | OpenClaw AI agent |
| `claude-os.woodhead.tech` | 192.168.86.37 | 5173 | None | Claude OS frontend |
| `claude-os-api.woodhead.tech` | 192.168.86.37 | 8051 | None | Claude OS API |
| `ollama.woodhead.tech` | 192.168.86.42 | 11434 | SSO | Ollama LLM inference |

## Media

| Subdomain | Backend IP | Port | Auth | Notes |
|-----------|-----------|------|------|-------|
| `plex.woodhead.tech` | 192.168.86.23 | 32400 | Own | Plex Media Server |
| `jellyfin.woodhead.tech` | 192.168.86.24 | 8096 | Own | Jellyfin Media Server |
| `requests.woodhead.tech` | 192.168.86.22 | 5055 | SSO | Overseerr request portal |
| `sonarr.woodhead.tech` | 192.168.86.22 | 8989 | SSO | Sonarr (TV) |
| `radarr.woodhead.tech` | 192.168.86.22 | 7878 | SSO | Radarr (movies) |
| `bazarr.woodhead.tech` | 192.168.86.22 | 6767 | SSO | Bazarr (subtitles) |
| `prowlarr.woodhead.tech` | 192.168.86.22 | 9696 | SSO | Prowlarr (indexers) |
| `sabnzbd.woodhead.tech` | 192.168.86.22 | 8080 | SSO | SABnzbd (usenet; via Gluetun) |

## Apps

| Subdomain | Backend IP | Port | Auth | Notes |
|-----------|-----------|------|------|-------|
| `home.woodhead.tech` | 192.168.86.41 | 8123 | Own | Home Assistant |
| `recipes.woodhead.tech` | 192.168.86.21 | 80 | None | Gourmand recipe app |
| `alert.woodhead.tech` | 192.168.86.27 | 80 | None | Libby life alert |
| `scanner.woodhead.tech` | 192.168.86.32 | 3000 | SSO | SDR P25 scanner (rdio-scanner) |
| `pwnagotchi.woodhead.tech` | 192.168.86.38 | -- | None | Pwnagotchi (WireGuard only) |
| `tasks.woodhead.tech` | 192.168.86.33 | 8000 | None | Kanboard task manager |
| `ender5.woodhead.tech` | 192.168.86.136 | 80 | None | Klipper Ender 5 Pro (Mainsail) |
| `ender3.woodhead.tech` | 192.168.86.138 | 80 | None | Klipper Ender 3 (Mainsail) |

## Web & Content

| Subdomain | Backend IP | Port | Auth | Notes |
|-----------|-----------|------|------|-------|
| `woodhead.tech` | Cloudflare Pages | -- | None | Consulting site (not Traefik) |
| `lab.woodhead.tech` | 192.168.86.25 | 8083 | None | Homelab ops dashboard |
| `homelab.woodhead.tech` | 192.168.86.25 | 8084 | None | Homelab docs site |
| `docs.woodhead.tech` | 192.168.86.25 | 3080 | SSO | Internal docs (Docusaurus) |
| `resume.woodhead.tech` | 192.168.86.25 | 3081 | SSO | Resume site |
| `consulting.woodhead.tech` | 192.168.86.25 | 8085 | None | Consulting site (fallback container) |
| `v2mom.woodhead.tech` | 192.168.86.25 | 8087 | SSO | V2MOM planning dashboard |

## Customer Demos

| Subdomain | Backend IP | Port | Auth | Notes |
|-----------|-----------|------|------|-------|
| `skypups.woodhead.tech` | 192.168.86.25 | 8085 | SSO | Sky Pups Treats proposal (redirects to /proposals/skypups) |
| `tshirts-demo.woodhead.tech` | 54.221.225.53 | -- | None | T-Shirts ShopStack demo (AWS EC2 via wg1) |

---

## Port Forwarding (Google Nest → LAN)

| WAN Port | Destination | Protocol | Purpose |
|----------|------------|----------|---------|
| 80 | 192.168.86.20:80 | TCP | HTTP → Traefik |
| 443 | 192.168.86.20:443 | TCP | HTTPS → Traefik |
| 51820 | 192.168.86.39:51820 | UDP | WireGuard VPN (wg0) |
| 25 | 192.168.86.34:25 | TCP | SMTP inbound → Mailcow |
| 465 | 192.168.86.34:465 | TCP | SMTPS → Mailcow |
| 587 | 192.168.86.34:587 | TCP | SMTP Submission → Mailcow |
| 993 | 192.168.86.34:993 | TCP | IMAPS → Mailcow |

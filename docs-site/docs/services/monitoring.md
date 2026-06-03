---
sidebar_position: 2
title: Monitoring
---

# Monitoring Stack

LXC 205 | `192.168.86.25` | Prometheus :9090, Grafana :3000, Alertmanager :9093

## Components

| Service | Port | Purpose |
|---|---|---|
| Prometheus | 9090 | Metrics collection + TSDB (30-day retention) |
| Grafana | 3000 | Dashboards + visualization |
| Alertmanager | 9093 | Alert routing (Discord, Twilio SMS, HA Alexa) |
| Node Exporter | 9100 | Host metrics for the monitoring LXC |
| cAdvisor | 8080 | Docker container metrics |
| Blackbox Exporter | 9115 | HTTP/ICMP service probes |
| PVE Exporter | 9221 | Proxmox VE API metrics |
| NUT Exporter (tc3) | 9199 | UPS metrics for thinkcentre3 |
| NUT Exporter (tower1) | 9198 | UPS metrics for tower1 |
| NUT Exporter (zotac) | 9197 | UPS metrics for zotac |
| Dexcom Exporter | 9666 | Glucose CGM readings |
| Twilio Relay | 9667 | SMS webhook relay for glucose alerts |
| **Healer** | **9110** | **Auto-remediation webhook receiver** |
| Docs Site | 8081 | Docusaurus static site (docs.woodhead.tech) |
| Resume Site | 8082 | Hugo static site (resume.woodhead.tech) |
| Landing Site | 8083 | Service link tree (lab.woodhead.tech) |

## Deploy

```bash
make monitoring \
  DISCORD_WEBHOOK="..." \
  GRAFANA_PASSWORD="..." \
  PVE_USER=monitoring@pve \
  PVE_TOKEN_NAME=prometheus \
  PVE_TOKEN_VALUE="..."
```

## Dashboards

Auto-provisioned from `ansible/files/monitoring/grafana/dashboards/`:

- Proxmox VE (ID 10347)
- Docker Containers (ID 14282)
- Traefik 3.x (ID 17346)
- Blackbox Exporter (ID 7587)
- Dexcom Glucose (custom)
- Home (custom overview)

## Probe Coverage

Blackbox exporter uses four modules defined in `ansible/files/monitoring/blackbox/blackbox.yml`:

| Module | Accepts | Use case |
|---|---|---|
| `http_2xx` | 200–299 | Public services with no auth redirect |
| `http_2xx_or_3xx` | 200–399, no redirect follow | Authentik-gated services — 302 to auth = Traefik is healthy |
| `https_insecure` | 200–299, skip TLS verify | Self-signed certs (TrueNAS, Step-CA) |
| `icmp` | ICMP echo reply | Host reachability for Proxmox nodes + all LXCs |

**HTTP probes (internal):** Recipe site, Overseerr, Sonarr, Radarr, Prowlarr, Bazarr, SABnzbd, Plex, Grafana, Libby Alert, Kanboard, AdGuard, Home Assistant, Hermes, tv-kiosk Kodi bridge, Claude Code, Piboard, Klipper ×2

**HTTPS probes (external, 2xx):** resume.woodhead.tech, alert.woodhead.tech, scanner.woodhead.tech

**HTTPS probes (external, auth-gated 3xx ok):** grafana, traefik, docs, sonarr, radarr, request, kanboard, hermes, claude.woodhead.tech

**HTTPS insecure:** TrueNAS (192.168.86.40:443), Step-CA (192.168.86.36:9000/health)

**ICMP:** All 5 Proxmox nodes + 17 LXC containers

Intermittent devices (Piboard, Klipper, Home Assistant) have 90-day Alertmanager silences — they fire alerts when powered off which is expected behavior.

## Auto-Healer

The healer service (`/opt/healer/healer.py`) is a FastAPI webhook receiver that fires on `ServiceDown` and `HostUnreachable` alerts from Alertmanager and executes SSH remediation on the affected host.

**Key design decisions:**
- Rate-limited to 3 heals per service per hour — prevents restart loops
- All actions logged to SQLite at `/var/lib/healer/healer.db`
- Dedicated `id_healer` ed25519 keypair, separate from `id_ansible`
- Never heals: Ceph, TrueNAS, databases, Proxmox nodes, WireGuard

**Dashboard:** `http://192.168.86.25:9110/` — last 100 actions, color-coded outcomes

**JSON API:** `http://192.168.86.25:9110/actions?limit=100`

**Config:** `/etc/healer/config.yaml` — maps `alertname` + instance label to SSH host + shell command

Current remediation map:

| Alert | Instance | Action |
|---|---|---|
| ServiceDown | Sonarr | `docker restart sonarr` on arr-stack |
| ServiceDown | Radarr | `docker restart radarr` on arr-stack |
| ServiceDown | Prowlarr | `docker restart prowlarr` on arr-stack |
| ServiceDown | Bazarr | `docker restart bazarr` on arr-stack |
| ServiceDown | Overseerr | `docker restart overseerr` on arr-stack |
| ServiceDown | Plex | `systemctl restart plexmediaserver` on plex LXC |
| ServiceDown | Grafana | `docker compose restart grafana` on monitoring |
| ServiceDown | Traefik | `systemctl restart traefik` on traefik LXC |
| ServiceDown | Authentik | `docker compose restart server` on authentik LXC |
| ServiceDown | Hermes | `systemctl restart hermes-dashboard` on hermes LXC |
| ServiceDown | Kodi bridge | `systemctl restart kodi-bridge && kodi` on tv-kiosk |
| ServiceDown | Recipe site | `docker compose restart` on recipe-site LXC |

**Update the healer config (no restart needed for new rules — restart is needed):**
```bash
scp -i ~/.ssh/id_ansible \
  ansible/files/monitoring/healer/config.yaml \
  root@192.168.86.25:/etc/healer/config.yaml
ssh -i ~/.ssh/id_ansible root@192.168.86.25 'systemctl restart healer'
```

**Check healer logs:**
```bash
ssh -i ~/.ssh/id_ansible root@192.168.86.25 'journalctl -u healer -f'
```

**Add healer SSH key to a new LXC:**
```bash
HEALER_PUB="ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIObZRLAe0m3dYQ1wuvs1maA+6Fwj9RQ3/gHTQVy2qZAX healer@monitoring"
ssh -i ~/.ssh/id_ansible root@<new-lxc-ip> \
  "echo '$HEALER_PUB' >> /root/.ssh/authorized_keys"
```

## Alert Rules

Rules live in `ansible/files/monitoring/prometheus/rules/alerts.yml`. Hot-reload after editing:

```bash
scp -i ~/.ssh/id_ansible ansible/files/monitoring/prometheus/rules/alerts.yml \
  root@192.168.86.25:/opt/monitoring/prometheus/config/rules/alerts.yml
ssh -i ~/.ssh/id_ansible root@192.168.86.25 \
  'curl -s -X POST http://localhost:9090/-/reload'
```

Alert severity tiers:
- `critical` — immediate Discord DM, 1h repeat, triggers healer auto-remediation
- `warning` — Discord notification, 4h repeat
- `info` — dashboard only, no notification

## Alertmanager Config Update (without full redeploy)

`make monitoring` restarts everything and nukes the live Discord webhook. For config-only changes:

```bash
cd ~/Workspace/proxmox_kubernetes_cluster

# Alertmanager
scp -i ~/.ssh/id_ansible \
  ansible/files/monitoring/alertmanager/alertmanager.yml \
  root@192.168.86.25:/opt/monitoring/alertmanager/config/alertmanager.yml
ssh -i ~/.ssh/id_ansible root@192.168.86.25 \
  'curl -s -X POST http://localhost:9093/-/reload'

# Prometheus config or rules
scp -i ~/.ssh/id_ansible ansible/files/monitoring/prometheus/prometheus.yml \
  root@192.168.86.25:/opt/monitoring/prometheus/config/prometheus.yml
ssh -i ~/.ssh/id_ansible root@192.168.86.25 \
  'curl -s -X POST http://localhost:9090/-/reload'
```

## Dexcom Glucose Monitoring

Python exporter polling Dexcom Share API every 5 minutes.

**Alert thresholds:**

| Alert | Threshold | Delay | Severity |
|---|---|---|---|
| GlucoseCriticalLow | < 55 mg/dL | Immediate | Critical |
| GlucoseLow | 55–70 mg/dL | 5 min | Warning |
| GlucoseHigh | > 250 mg/dL | 15 min | Warning |
| GlucoseCriticalHigh | > 350 mg/dL | 5 min | Critical |
| DexcomStaleReading | No data 15 min | 5 min | Warning |

**Status:** Built, blocked on Dexcom Share credentials + Twilio account.

## Verify

```bash
curl http://192.168.86.25:9090/-/healthy    # Prometheus
curl http://192.168.86.25:3000/api/health   # Grafana
curl http://192.168.86.25:9110/health       # Healer
```

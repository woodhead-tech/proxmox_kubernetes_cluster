# Homelab Infrastructure Map
Generated: 2026-06-08 from commit `2116a6a`

> Re-generate with: `/infra-graph update` | Query with: `/infra-graph query <term>`

---

## Service Inventory

| Service | IP | VMID | Group | Role | always_on? |
|---------|-----|------|-------|------|-----------|
| traefik-gw | 192.168.86.20 | 200 | core | Reverse proxy ingress | yes |
| wireguard | 192.168.86.39 | 208 | core | VPN tunnel | yes |
| truenas | 192.168.86.40 | 300 (VM) | storage | NAS — ZFS pool, NFS exports | yes |
| authentik | 192.168.86.28 | 207 | security | SSO / identity provider | no |
| homeassistant | 192.168.86.41 | 301 (VM) | home | Smart home automation | no |
| zigbee2mqtt | 192.168.86.44 | 214 | home | Zigbee bridge + MQTT broker | no |
| libby-alert | 192.168.86.27 | 209 | home | Life-alert QR site | no |
| arr-stack | 192.168.86.22 | 202 | media | Sonarr/Radarr/Prowlarr/Bazarr/Overseerr/SABnzbd/Whisparr | no |
| plex-server | 192.168.86.23 | 203 | media | Plex streaming | no |
| monitoring-stack | 192.168.86.25 | 205 | observability | Prometheus + Grafana + Alertmanager + 8 static sites | no |
| recipe-site | 192.168.86.21 | 201 | apps | Recipe website (Go+SQLite) | no |
| kanboard | 192.168.86.33 | 211 | apps | Project management | no |
| claude-os | 192.168.86.37 | 215 | apps | AI memory/knowledge system | no |
| guacamole | 192.168.86.47 | 219 | apps | Browser-based remote desktop | no |
| mailserver | 192.168.86.34 | 212 | infra | Mailcow email server | no |
| adguard | 192.168.86.35 | 221 | infra | DNS (AdGuard Home) | no |
| step-ca | 192.168.86.36 | 222 | infra | SSH certificate authority | no |
| omada | 192.168.86.49 | 225 | infra | TP-Link Omada WiFi controller | no |
| pbs | 192.168.86.49:8007 | 223 | infra | Proxmox Backup Server | no |
| pwnagotchi | 192.168.86.38 | 216 | special (hw-bound) | WiFi learning device (RTL8188EUS) | no |
| talos-cp-0 | 192.168.86.101 | 400 (VM) | k8s | K8s control plane (tower1) | no |
| talos-worker-0 | 192.168.86.111 | 410 (VM) | k8s | K8s worker (thinkcentre2) | no |
| talos-worker-1 | 192.168.86.112 | 411 (VM) | k8s | K8s worker (thinkcentre3) | no |
| talos-worker-2 | 192.168.86.113 | 412 (VM) | k8s | K8s worker (zotac) | no |
| jellyfin-server | 192.168.86.24 | — | **ungrouped** | Jellyfin streaming | no |
| openclaw | 192.168.86.26 | — | **ungrouped** | OpenClaw AI agent | no |
| sdr-scanner | 192.168.86.32 | — | **ungrouped** | Trunk Recorder + rdio-scanner (SNO911 P25) | no |
| vaultwarden | 192.168.86.43 | — | **ungrouped** | Password manager (Bitwarden-compatible) | no |
| photos | 192.168.86.45 | — | **ungrouped** | Graduation photos upload app | no |
| piboard | 192.168.86.131 | — | standalone Pi | Waveshare 5" dashboard | no |
| klipper-ender5pro | 192.168.86.136 | — | standalone Pi | Ender 5 Pro (MainsailOS) | no |
| klipper-ender3 | 192.168.86.138 | — | standalone Pi | Ender 3 (MainsailOS) | no |
| netsvc1 | 192.168.86.207 | — | standalone | Secondary DNS + NTP + Ansible test target | no |

---

## Hub Nodes (most referenced)

Ranked by cross-file reference count.

| Rank | Node | References | Referenced By |
|------|------|-----------|--------------|
| 1 | **monitoring-stack** (192.168.86.25) | 15 | 12 Traefik routes (grafana, prometheus, alertmanager, docs, resume, homelab, consulting, landing, errors, v2mom, booth, alertmind, netmap) + Makefile deploy target + Prometheus scrapes all hosts |
| 2 | **traefik-gw** (192.168.86.20) | 14 | All 40+ Traefik dynamic configs route through it; every service deployment references it; dashboard.yml |
| 3 | **authentik** (192.168.86.28) | 18 | `authentik@file` middleware on 18 Traefik routes; auth.woodhead.tech + outpost path; required_by: [media, apps] group dependency |
| 4 | **arr-stack** (192.168.86.22) | 8 | 7 Traefik routes (overseerr, prowlarr, sonarr, radarr, bazarr, sabnzbd, whisparr) + setup-arr-stack.yml playbook |
| 5 | **truenas** (192.168.86.40) | 6 | storage group (always_on, required_by: media); NFS /media mount in arr-stack; nas.woodhead.tech Traefik route; setup-truenas.yml |
| 6 | **vaultwarden** (192.168.86.43) | 5 | K8s cert backup (certs-vault.sh); vault.woodhead.tech Traefik route; make certs-push/pull/check all depend on it |
| 7 | **wireguard** (192.168.86.39) | 4 | core group (always_on); gluetun in arr-stack routes downloads through it; WG_PRIVATE_KEY required by arr-stack deploy |
| 8 | **Makefile** | — | Every deployment operation goes through it; 50+ targets; entry point for the entire repo |
| 9 | **talos/_out/** | 5 | bootstrap.sh, recover-k8s.sh, certs-vault.sh, certs-check, kubeconfig target all read/write here |
| 10 | **adguard** (192.168.86.35) | 3 | DNS for all woodhead.tech subdomains |

---

## Service Group Dependency Order

```
core (always_on)
  └─ traefik-gw (.20), wireguard (.39)

storage (always_on, required_by: media)
  └─ truenas (.40)

security (required_by: media, apps)
  └─ authentik (.28)

home
  └─ homeassistant (.41), zigbee2mqtt (.44), libby-alert (.27)

media (depends_on: core, storage)
  └─ arr-stack (.22), plex-server (.23)

observability
  └─ monitoring-stack (.25)

apps (depends_on: security implied by Authentik middleware)
  └─ recipe-site (.21), kanboard (.33), claude-os (.37), guacamole (.47)

infra
  └─ mailserver (.34), adguard (.35), step-ca (.36), omada (.49), pbs (.49:8007)

special (hardware_bound — excluded from bulk ops)
  └─ pwnagotchi (.38)

k8s
  └─ talos-cp-0 (.101), talos-worker-0 (.111), talos-worker-1 (.112), talos-worker-2 (.113)

ungrouped (not in service_groups.yml)
  └─ jellyfin (.24), openclaw (.26), sdr-scanner (.32), vaultwarden (.43), photos (.45)
```

**Stop order** (safe sequence, must stop dependents first):
media → security → storage → core

---

## Makefile Target Chains

| Target | Calls Script | Playbook | Target Hosts | Env Vars Required | Destructive? |
|--------|-------------|----------|-------------|------------------|-------------|
| `traefik` | — | setup-traefik.yml | traefik-gw (.20) | CF_API_TOKEN | no |
| `arr-stack` | — | setup-arr-stack.yml | arr-stack (.22) | WG_PRIVATE_KEY | no |
| `plex` | — | setup-plex.yml | plex-server (.23) | — | no |
| `jellyfin` | — | setup-jellyfin.yml | jellyfin-server (.24) | — | no |
| `monitoring` | — | setup-monitoring.yml | monitoring-stack (.25) | DISCORD_WEBHOOK, GRAFANA_PASSWORD, PVE_PASSWORD | no |
| `openclaw` | — | setup-openclaw.yml | openclaw (.26) | — | no |
| `authentik` | — | setup-authentik.yml | authentik (.28) | — | no |
| `wireguard` | — | setup-wireguard.yml | wireguard (.39) | — | no |
| `vaultwarden` | — | setup-vaultwarden.yml | vaultwarden (.43) | VAULTWARDEN_ADMIN_TOKEN, SMTP_USER, SMTP_PASSWORD | no |
| `homeassistant` | — | setup-homeassistant.yml | homeassistant (.41) | HA_TOKEN (optional) | no |
| `truenas` | — | setup-truenas.yml | truenas (.40) | TRUENAS_* vars | no |
| `libby-alert` | — | setup-libby-alert.yml | libby-alert (.27) | DISCORD_WEBHOOK and/or TWILIO_* | no |
| `adguard` | — | setup-adguard.yml | adguard (.35) | — | no |
| `step-ca` | — | setup-step-ca.yml | step-ca (.36) | — | no |
| `kanboard` | — | setup-kanboard.yml | kanboard (.33) | — | no |
| `mailserver` | — | setup-mailserver.yml | mailserver (.34) | SMTP_* | no |
| `sdr` | — | setup-sdr.yml | sdr-scanner (.32) | — | no |
| `zigbee2mqtt` | — | setup-zigbee2mqtt.yml | zigbee2mqtt (.44) | — | no |
| `pwnagotchi` | — | setup-pwnagotchi.yml | pwnagotchi (.38) | — | no |
| `claude-os` | — | setup-claude-os.yml | claude-os (.37) | OPENAI_API_KEY (optional) | no |
| `watchdog` | — | setup-watchdog.yml | monitoring-stack (.25) | DISCORD_WEBHOOK | no |
| `alertmind` | — | setup-alertmind.yml | monitoring-stack (.25) | ANTHROPIC_API_KEY, DISCORD_WEBHOOK | no |
| `guacamole` | — | setup-guacamole.yml | guacamole (.47) | GUACAMOLE_* | no |
| `bootstrap` | bootstrap.sh | — | talos/_out/ + K8s VMs | CLUSTER_VIP, CONTROLPLANE_IPS, WORKER_IPS | yes |
| `recover-k8s` | recover-k8s.sh | — | all Talos VMs via Proxmox SSH | CLUSTER_VIP, CONTROLPLANE_IPS, WORKER_IPS | **YES — resets VMs** |
| `certs-push` | certs-vault.sh push | — | vaultwarden (.43) | BW_SESSION | no |
| `certs-pull` | certs-vault.sh pull | — | vaultwarden (.43) | BW_SESSION | no |
| `certs-check` | certs-vault.sh check | — | K8s cluster | — | no |
| `approve-csrs` | — | — | K8s API | — | no |
| `rejoin-worker` | rejoin-worker.sh | — | Proxmox node via SSH | NODE_IP | yes (qm stop) |
| `patch-proxmox` | — | patch-proxmox.yml | all proxmox nodes, serial | — | no |
| `patch-lxc` | — | patch-lxc.yml | all LXC containers | — | no |
| `patch-docker` | — | patch-docker.yml | all LXCs with Docker | — | brief downtime |
| `patch-pi` | — | patch-pi.yml | piboard, klipper hosts | — | no |
| `harden` | — | harden-proxmox.yml | all proxmox nodes | — | no |
| `destroy` | destroy.sh | — | all Terraform resources | — | **YES — destroys VMs** |
| `group-status` | — | group-status.yml | all proxmox nodes | — | no |
| `group-start` | — | group-start.yml | GROUP= members | GROUP= | no |
| `group-stop` | — | group-stop.yml | GROUP= members | GROUP= | no |

---

## Traefik Routes

All routes terminate TLS via Cloudflare DNS-01. All traffic enters through traefik-gw (192.168.86.20).

| Hostname | Backend | Auth (Authentik?) | Config File |
|----------|---------|------------------|-------------|
| adguard.woodhead.tech | 192.168.86.35:3000 | yes | adguard.yml |
| alertmanager.woodhead.tech | 192.168.86.25:9093 | yes | monitoring.yml |
| alertmind.woodhead.tech | 192.168.86.25:8086 | yes | alertmind.yml |
| alert.woodhead.tech | 192.168.86.27:8080 | **no** | libby-alert.yml |
| auth.woodhead.tech | 192.168.86.28:9000 | no (is the auth provider) | authentik.yml |
| bazarr.woodhead.tech | 192.168.86.22:6767 | yes | arr-stack.yml |
| booth.woodhead.tech | 192.168.86.25:8088 | **no** | booth.yml |
| claw.woodhead.tech | 192.168.86.26:18789 | yes | openclaw.yml |
| class2026.woodhead.tech | Cloudflare Pages (external) | **no** | graduation-site.yml |
| claude.woodhead.tech | 192.168.86.48:7681 | yes | claude-code.yml |
| claude-os.woodhead.tech | 192.168.86.37:5173 | **no** | claude-os.yml |
| claude-os-api.woodhead.tech | 192.168.86.37:8051 | **no** | claude-os.yml |
| consulting.woodhead.tech | 192.168.86.25:8085 | **no** | consulting-site.yml |
| docs.woodhead.tech | 192.168.86.25:8081 | **no** | docs-site.yml |
| ender3.woodhead.tech | 192.168.86.138:80 | **no** | klipper.yml |
| ender5.woodhead.tech | 192.168.86.136:80 | **no** | klipper.yml |
| grafana.woodhead.tech | 192.168.86.25:3000 | yes | monitoring.yml |
| guac.woodhead.tech | 192.168.86.47:8080 | yes | guacamole.yml |
| hermes.woodhead.tech | 192.168.86.51:9119 | yes | hermes.yml |
| home.woodhead.tech | 192.168.86.41:8123 | **no** (HA own auth) | homeassistant.yml |
| homelab.woodhead.tech | 192.168.86.25:8084 | **no** | homelab-site.yml |
| jellyfin.woodhead.tech | 192.168.86.24:8096 | **no** (Jellyfin own auth) | media-stack.yml |
| lab.woodhead.tech | 192.168.86.25:8083 | **no** | landing-site.yml |
| mail.woodhead.tech | 192.168.86.34:8080 | **no** (Mailcow own auth) | mailserver.yml |
| nas.woodhead.tech | 192.168.86.40 (https) | yes | truenas.yml |
| netmap.woodhead.tech | 192.168.86.25:8089 | yes | netmap.yml |
| pbs.woodhead.tech | 192.168.86.49:8007 (https) | yes | pbs.yml |
| plex.woodhead.tech | 192.168.86.23:32400 | **no** (Plex own auth) | media-stack.yml |
| prometheus.woodhead.tech | 192.168.86.25:9090 | yes | monitoring.yml |
| proxmox.woodhead.tech | 192.168.86.29:8006 (https) | yes | proxmox.yml |
| pwnagotchi.woodhead.tech | 192.168.86.38:8080 | **no** ⚠️ | pwnagotchi.yml |
| radarr.woodhead.tech | 192.168.86.22:7878 | yes | arr-stack.yml |
| recipes.woodhead.tech | 192.168.86.21:80 | **no** | recipe-site.yml |
| requests.woodhead.tech | 192.168.86.22:5055 | yes | arr-stack.yml |
| resume.woodhead.tech | 192.168.86.25:8082 | **no** | resume-site.yml |
| prowlarr.woodhead.tech | 192.168.86.22:9696 | yes | arr-stack.yml |
| sabnzbd.woodhead.tech | 192.168.86.22:8080 | yes | arr-stack.yml |
| scanner.woodhead.tech | 192.168.86.32:3000 | yes | sdr.yml |
| sonarr.woodhead.tech | 192.168.86.22:8989 | yes | arr-stack.yml |
| step-ca.woodhead.tech | 192.168.86.36:9000 (https) | **no** | step-ca.yml |
| tasks.woodhead.tech | 192.168.86.33:8000 | yes | kanboard.yml |
| traefik.woodhead.tech | dashboard (internal) | yes | dashboard.yml |
| v2mom.woodhead.tech | 192.168.86.25:8087 | yes | v2mom.yml |
| vault.woodhead.tech | 192.168.86.43:80 | yes (/admin only) | vaultwarden.yml |
| whisparr.woodhead.tech | 192.168.86.22:6969 | yes | arr-stack.yml |
| photos.woodhead.tech | 192.168.86.45:80 | **no** | photos.yml |

**Publicly accessible (no Authentik):** alert, booth, class2026, consulting, claude-os, claude-os-api, docs, ender3, ender5, home, homelab, jellyfin, klipper hosts, lab, mail, plex, **pwnagotchi** ⚠️, recipes, resume, step-ca, photos

---

## Docker Compose Port Map

| Service | LXC IP | Host Port | Container Port | Purpose |
|---------|--------|-----------|----------------|---------|
| prowlarr | .22 | 9696 | 9696 | Indexer manager |
| sonarr | .22 | 8989 | 8989 | TV shows |
| radarr | .22 | 7878 | 7878 | Movies |
| bazarr | .22 | 6767 | 6767 | Subtitles |
| overseerr | .22 | 5055 | 5055 | Request UI |
| sabnzbd | .22 | 8080 | 8080 | Usenet downloader (via gluetun network) |
| whisparr | .22 | 6969 | 6969 | Adult movie manager |
| authentik-postgres | .28 | 127.0.0.1:5432 | 5432 | Authentik DB (localhost only) |
| authentik-redis | .28 | 127.0.0.1:6379 | 6379 | Authentik cache (localhost only) |
| prometheus | .25 | 9090 | 9090 | Metrics scraper |
| grafana | .25 | 3000 | 3000 | Dashboards |
| alertmanager | .25 | 9093 | 9093 | Alert routing |
| node-exporter | .25 | 9100 | 9100 | Host metrics |
| cadvisor | .25 | 8080 | 8080 | Container metrics |
| blackbox-exporter | .25 | 9115 | 9115 | HTTP probe |
| docs-site | .25 | 8081 | 80 | docs.woodhead.tech |
| resume-site | .25 | 8082 | 80 | resume.woodhead.tech |
| landing/errors | .25 | 8083 | 80 | lab.woodhead.tech + catch-all errors |
| homelab-site | .25 | 8084 | 80 | homelab.woodhead.tech |
| consulting-site | .25 | 8085 | 80 | consulting.woodhead.tech |
| alertmind | .25 | 8086 | 8080 | alertmind.woodhead.tech |
| v2mom | .25 | 8087 | 80 | v2mom.woodhead.tech |
| booth | .25 | 8088 | 8080 | booth.woodhead.tech |
| netmap | .25 | 8089 | 80 | netmap.woodhead.tech |
| openclaw-gateway | .26 | 18789 | 18789 | AI agent API |
| openclaw-bridge | .26 | 18790 | 18790 | Discord/Slack integrations |
| libby-alert | .27 | 8080 | 8080 | alert.woodhead.tech |
| kanboard | .33 | 8000 | 80 | tasks.woodhead.tech |
| mailserver (Mailcow) | .34 | 8080 | 8080 | mail.woodhead.tech admin |
| adguard | .35 | 3000 | 3000 | DNS admin UI |
| step-ca | .36 | 9000 | 9000 | SSH CA API |
| rdio-scanner | .32 | 3000 | 3000 | scanner.woodhead.tech |
| vaultwarden | .43 | 80 | 80 | vault.woodhead.tech |
| mosquitto | .44 | 1883 | 1883 | MQTT broker for HA |
| zigbee2mqtt | .44 | 8080 | 8080 | Zigbee config UI |
| minecraft | — | 25565 | 25565 | Game server |
| guacamole | .47 | 8080 | 8080 | guac.woodhead.tech |

---

## Docker Compose Volume Map (Shared State)

| Volume Path | Used By | Type | Notes |
|-------------|---------|------|-------|
| `/media` | arr-stack (Sonarr, Radarr, Bazarr, Whisparr) | NFS mount from TrueNAS | **All arr services share this**; hardlinks require same filesystem |
| `/media/downloads` | arr-stack (SABnzbd + all *arrs) | NFS mount from TrueNAS | Hardlink path: downloads/ → library; must be same mount |
| `/opt/authentik/media` | authentik-server, authentik-worker | bind | Authentik uploads/branding |

**Coordination point:** All arr services (Sonarr, Radarr, Bazarr, Whisparr) must share `/media` and `/media/downloads` from the same NFS mount for hardlinks to work. If TrueNAS is down at arr-stack deploy time, the NFS mount fails and Docker Compose services crash on start.

---

## Ansible Playbook Targets

| Playbook | Target Hosts | Key Tasks | Files Deployed |
|----------|-------------|-----------|----------------|
| setup-traefik.yml | traefik-gw (.20) | Install Traefik binary + systemd, deploy dynamic configs | ansible/files/traefik/ |
| setup-arr-stack.yml | arr-stack (.22) | Docker Compose deploy, NFS mount /media, gluetun WireGuard | ansible/files/arr-stack/ |
| setup-plex.yml | plex-server (.23) | Docker Compose deploy, iGPU passthrough | ansible/files/plex/ |
| setup-jellyfin.yml | jellyfin-server (.24) | Docker Compose deploy, iGPU passthrough | ansible/files/ |
| setup-monitoring.yml | monitoring-stack (.25) | Docker Compose: Prometheus+Grafana+AM+static sites; Dexcom exporter | ansible/files/monitoring/ |
| setup-openclaw.yml | openclaw (.26) | Build + Docker Compose deploy | ansible/files/openclaw/ |
| setup-libby-alert.yml | libby-alert (.27) | Docker Compose, Twilio/Discord config | ansible/files/libby-alert/ |
| setup-authentik.yml | authentik (.28) | Docker Compose: server+worker+postgres+redis | ansible/files/authentik/ |
| setup-sdr.yml | sdr-scanner (.32) | Docker Compose: Trunk Recorder + rdio-scanner; RTL-SDR passthrough | ansible/files/sdr/ |
| setup-kanboard.yml | kanboard (.33) | Docker Compose | ansible/files/kanboard/ |
| setup-mailserver.yml | mailserver (.34) | Mailcow install + SMTP relay config | ansible/files/mailserver/ |
| setup-adguard.yml | adguard (.35) | AdGuard Home install, DNS config | ansible/files/ |
| setup-step-ca.yml | step-ca (.36) | Docker Compose, CA initialization | ansible/files/step-ca/ |
| setup-claude-os.yml | claude-os (.37) | Python venv + Flask app + Ollama (optional) | ansible/files/ |
| setup-pwnagotchi.yml | pwnagotchi (.38) | pwnagotchi install in venv + LXC thermal patch | ansible/files/ |
| setup-wireguard.yml | wireguard (.39) | WireGuard install + peers config | ansible/files/wireguard/ |
| setup-truenas.yml | truenas (.40) | TrueNAS REST API: ZFS pool, datasets, NFS shares | — |
| setup-homeassistant.yml | homeassistant (.41) | Traefik route + HA integration via REST API | — |
| setup-vaultwarden.yml | vaultwarden (.43) | Docker Compose + SMTP config | ansible/files/vaultwarden/ |
| setup-zigbee2mqtt.yml | zigbee2mqtt (.44) | Docker Compose: Mosquitto + zigbee2mqtt; USB dongle passthrough | ansible/files/zigbee2mqtt/ |
| setup-guacamole.yml | guacamole (.47) | Docker Compose: guacd + postgres + guacamole | ansible/files/guacamole/ |
| setup-watchdog.yml | monitoring-stack (.25) | Discord webhook watchdog | ansible/files/watchdog/ |
| setup-alertmind.yml | monitoring-stack (.25) | Alertmind AI triage container; ANTHROPIC_API_KEY | ansible/files/ |
| patch-proxmox.yml | proxmox (all 5 nodes) | apt upgrade, serial (one at a time) | — |
| patch-lxc.yml | lxc_services (all LXCs) | apt upgrade | — |
| patch-docker.yml | all LXC hosts | docker pull + compose up -d | — |
| group-start/stop/status.yml | proxmox (all) | qm start/stop/status per group | — |

---

## Scripts Inventory

| Script | Called By | Key CLIs | Env Vars | Destructive? |
|--------|-----------|----------|----------|-------------|
| bootstrap.sh | `make bootstrap` | talosctl (gen config, bootstrap, kubeconfig) | CLUSTER_VIP, CONTROLPLANE_IPS, WORKER_IPS, TALOS_VERSION | yes (gen config --force) |
| recover-k8s.sh | `make recover-k8s` | talosctl, ssh (qm reset via Proxmox), envsubst | CLUSTER_VIP, CONTROLPLANE_IPS, WORKER_IPS | **YES — qm reset on all Talos VMs** |
| certs-vault.sh | `make certs-push/pull/check` | bw (Bitwarden CLI), talosctl, kubectl | BW_SESSION (push/pull only) | no |
| rejoin-worker.sh | `make rejoin-worker` | ssh (qm stop/start on Proxmox), talosctl | NODE_IP | yes (qm stop) |
| find-talos-nodes.sh | `make find-nodes` | ssh (ARP probe via Proxmox) | CONTROLPLANE_IPS, WORKER_IPS | no |
| apply-k8s-base.sh | `make k8s-base`, `make k8s-base-metallb` | kubectl (apply, delete webhook) | KUBECONFIG, TALOSCONFIG | no |
| check-iso.sh | `make bootstrap` | — | — | no |
| destroy.sh | `make destroy` | terraform | — | **YES — destroys all VMs** |
| throttle-vms.sh | manual | — | — | no |

---

## Kubernetes Workloads

| Name | Namespace | Kind | Image | Notes |
|------|-----------|------|-------|-------|
| kubelet-csr-approver | kube-system | CronJob | bitnami/kubectl:latest | Runs every 5 min; auto-approves kubelet serving CSRs |
| kube-state-metrics | monitoring | Deployment | kube-state-metrics:v2.13.0 | Exports K8s object metrics to Prometheus |
| node-exporter | monitoring | DaemonSet | (prometheus node-exporter) | Host-level metrics on each K8s node |
| metallb (external) | metallb-system | Operator | metallb | LoadBalancer IP pool: 192.168.86.150–199 |
| ingress (commented out) | ingress-system | — | — | k8s-ingress.yml is disabled (commented) |

**Namespaces:** ingress-system, apps, monitoring, metallb-system, kube-system

---

## Cross-group Surprises

1. **monitoring-stack (observability) hosts 8+ public static sites**
   `ansible/files/traefik/dynamic/{docs,resume,homelab,consulting,landing,errors,v2mom,booth,netmap}.yml`
   Stopping or redeploying monitoring takes down docs.woodhead.tech, resume.woodhead.tech, consulting.woodhead.tech, homelab.woodhead.tech, and the landing/error pages — not just Grafana.

2. **arr-stack (media) → wireguard/gluetun (core)**
   `ansible/files/arr-stack/docker-compose.yml`
   All downloads route through a gluetun container that creates a WireGuard tunnel. WG_PRIVATE_KEY is required at deploy time. If the tunnel drops, SABnzbd stops downloading while all other web UIs remain accessible — silent partial failure.

3. **vaultwarden (ungrouped) → K8s cert backup dependency**
   `scripts/certs-vault.sh`
   The new certs-vault.sh workflow makes vaultwarden a dependency for K8s cert backup/restore. Vaultwarden is NOT in service_groups.yml so `make group-status` won't surface it, and it can be stopped without warning that K8s cert recovery will break.

4. **pwnagotchi (special) has a public Traefik route with no Authentik**
   `ansible/files/traefik/dynamic/pwnagotchi.yml`
   CLAUDE.md states pwnagotchi should only be accessible via WireGuard, but the Traefik route is publicly reachable with no auth middleware.

5. **monitoring-stack (observability) hosts alertmind (needs ANTHROPIC_API_KEY)**
   `ansible/files/traefik/dynamic/alertmind.yml`, `Makefile:335`
   alertmind is deployed via `make alertmind` which requires ANTHROPIC_API_KEY. A plain `make monitoring` redeployment won't include alertmind, leaving the alertmind.woodhead.tech route pointing at nothing.

6. **jellyfin, openclaw, sdr-scanner, vaultwarden, photos not in service_groups.yml**
   `ansible/vars/service_groups.yml`
   These services exist (inventory, Makefile targets, Traefik routes) but are invisible to `make group-status/start/stop`. They must be managed individually via Ansible or SSH.

7. **[RESOLVED] adguard IP (.35) conflicts with pxe-server IP in inventory**
   `ansible/inventory/hosts.yml` lines for adguard (.35) and pxe-server (.35)
   Both adguard and pxe-server were assigned 192.168.86.35 in hosts.yml. This has been resolved by moving pxe-server to .50.

8. **authentik (security group) required_by media AND apps groups, but authentik is not always_on**
   `ansible/vars/service_groups.yml`
   If authentik is stopped, all authentik@file-protected Traefik routes (18 routes) return 401/502. The security group has no `always_on: true` — nothing prevents stopping it while media and apps are running.

---

## Suggested Questions

1. **What breaks if monitoring-stack goes down?**
   → Grafana, Prometheus, Alertmanager, docs, resume, consulting, homelab, landing, errors, v2mom, booth, netmap, alertmind, netmap — 13 services go dark.

2. **Which services have no Authentik protection?**
   → alert, booth, class2026, consulting, claude-os, claude-os-api, docs, ender3, ender5, home, homelab, jellyfin, lab, mail, plex, **pwnagotchi** (⚠️ should be VPN-only), recipes, resume, step-ca, photos.

3. **What env vars do I need to deploy the full stack from scratch?**
   → CF_API_TOKEN (traefik), WG_PRIVATE_KEY (arr-stack), DISCORD_WEBHOOK (monitoring, libby-alert, watchdog), GRAFANA_PASSWORD + PVE_PASSWORD (monitoring), VAULTWARDEN_ADMIN_TOKEN + SMTP_USER + SMTP_PASSWORD (vaultwarden), ANTHROPIC_API_KEY (alertmind), CLUSTER_VIP + CONTROLPLANE_IPS + WORKER_IPS (K8s).

4. **Which services depend on TrueNAS being up?**
   → arr-stack (NFS /media mount — Sonarr, Radarr, Bazarr, Whisparr, SABnzbd all fail without it). Service group storage is `required_by: [media]` to enforce this.

5. **Why is vaultwarden not in service_groups.yml even though certs-vault.sh now depends on it?**
   → Gap introduced by PR #21 (certs-vault.sh). vaultwarden, jellyfin, openclaw, sdr-scanner, and photos are all untracked by the group lifecycle system.

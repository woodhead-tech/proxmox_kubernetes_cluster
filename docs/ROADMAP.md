# Roadmap

Future services and infrastructure planned for the Proxmox homelab.

## Planned Services

### NAS (TrueNAS Scale)

**Type**: Proxmox VM (not LXC -- needs direct disk access)
**Domain**: `nas.woodhead.tech`
**Why VM**: TrueNAS Scale needs direct disk passthrough for ZFS pool management.
LXC containers can't do raw disk passthrough safely.

**Requirements**:
- Dedicated disks (NOT on the Ceph pool) passed through to the VM
- Minimum 8GB RAM (more for ZFS ARC cache -- 1GB per TB of storage is ideal)
- 2-4 CPU cores
- Proxmox disk passthrough via `qm set <vmid> -scsi1 /dev/disk/by-id/<disk-id>`

**Shares**:
- SMB/NFS exports for media, backups, ISOs
- Media share mounted by Plex, Jellyfin, and ARR stack containers

**Terraform**: `terraform/vm-truenas.tf` (VM ID: 300)
**Traefik route**: `nas.woodhead.tech` -> TrueNAS web UI (:443)

**Notes**:
- TrueNAS Scale is Debian-based and includes built-in app support (K8s under the hood)
- However, we'll use it purely as a NAS -- apps run on our own K8s cluster or LXCs
- Consider separate network interface (VLAN) for storage traffic if bandwidth is a concern

---

### ARR Stack

**Type**: LXC container with Docker Compose (or K8s workloads)
**Domain**: `*.woodhead.tech` subdomains per service

**Services**:
| Service   | Purpose                          | Port  | Subdomain                   |
|-----------|----------------------------------|-------|-----------------------------|
| Prowlarr  | Indexer manager                  | 9696  | `prowlarr.woodhead.tech`    |
| Sonarr    | TV show management               | 8989  | `sonarr.woodhead.tech`      |
| Radarr    | Movie management                 | 7878  | `radarr.woodhead.tech`      |
| Bazarr    | Subtitle management              | 6767  | `bazarr.woodhead.tech`      |
| Lidarr    | Music management (optional)      | 8686  | `lidarr.woodhead.tech`      |
| Readarr   | Book management (optional)       | 8787  | `readarr.woodhead.tech`     |
| Overseerr | Request management (user-facing) | 5055  | `requests.woodhead.tech`    |
| SABnzbd   | Usenet downloader                | 8080  | `sabnzbd.woodhead.tech`     |

**Recommended approach**: Single LXC with Docker Compose. The ARR apps are tightly
coupled (they talk to each other via localhost) and benefit from shared filesystem
access to the media library. Docker Compose keeps them manageable as a unit.

**Requirements**:
- 2-4 CPU cores, 4GB RAM, 20GB disk (downloads go to NAS)
- NFS/SMB mount from TrueNAS for media storage
- VPN container (gluetun) for download clients if needed

**Terraform**: `terraform/lxc-arr.tf` (VM ID: 202)
**Traefik routes**: `ansible/files/traefik/dynamic/arr-stack.yml`

**Directory structure on NAS**:
```
/media/
├── downloads/
│   ├── complete/
│   └── incomplete/
├── movies/
├── tv/
├── music/
└── books/
```

---

### Home Assistant

**Type**: Proxmox VM (HAOS -- Home Assistant OS)
**Domain**: `home.woodhead.tech`
**Why VM**: Home Assistant OS (HAOS) is the recommended install method. It's a
purpose-built OS with addon support, automatic backups, and OTA updates. Running
as a container loses addon support and complicates USB device passthrough.

**Requirements**:
- 2 CPU cores, 2GB RAM, 32GB disk
- USB passthrough for Zigbee/Z-Wave dongles (if used):
  `qm set <vmid> -usb0 host=<vendor>:<product>`
- HAOS qcow2 image imported to Proxmox (not ISO -- it's a pre-built disk image)

**Installation**:
```bash
# Download HAOS for Proxmox
wget https://github.com/home-assistant/operating-system/releases/download/<version>/haos_ova-<version>.qcow2.xz

# Import to Proxmox
qm importdisk <vmid> haos_ova-<version>.qcow2 <storage>
```

**Terraform**: `terraform/vm-homeassistant.tf` (VM ID: 301)
**Traefik route**: `home.woodhead.tech` -> HA web UI (:8123)

**Notes**:
- HAOS manages its own updates -- don't put it behind package management
- Backup integration with TrueNAS (NFS share for HA backups)
- Consider a dedicated VLAN for IoT devices (security isolation)

---

### Plex Media Server

**Type**: LXC container (or K8s pod)
**Domain**: `plex.woodhead.tech`

**Requirements**:
- 2-4 CPU cores, 4GB RAM, 20GB disk (media on NAS)
- Hardware transcoding: Intel iGPU passthrough for Quick Sync
  - LXC: mount `/dev/dri` into the container
  - Add to LXC config: `lxc.mount.entry: /dev/dri dev/dri none bind,optional,create=dir`
  - Add `lxc.cgroup2.devices.allow: c 226:* rwm`
- NFS/SMB mount from TrueNAS for media library
- Plex Pass for hardware transcoding (optional but recommended)

**Terraform**: `terraform/lxc-plex.tf` (VM ID: 203)
**Traefik route**: `plex.woodhead.tech` -> Plex web UI (:32400)

**Notes**:
- Plex can also be accessed directly via app.plex.tv (remote access)
- Traefik route is for the local web UI
- GPU passthrough is the single most impactful optimization for transcoding

---

### Jellyfin

**Type**: LXC container (or K8s pod)
**Domain**: `jellyfin.woodhead.tech`

**Requirements**:
- Same as Plex (iGPU passthrough, NAS media mount)
- 2-4 CPU cores, 4GB RAM
- Fully open source -- no subscription needed for hardware transcoding

**Terraform**: `terraform/lxc-jellyfin.tf` (VM ID: 204)
**Traefik route**: `jellyfin.woodhead.tech` -> Jellyfin web UI (:8096)

**Notes**:
- Can run alongside Plex (same media library, different frontends)
- Better for sharing with family/friends (no Plex account required)
- DLNA support for smart TVs

---

### WireGuard VPN

**Type**: LXC container (lightweight tunnel endpoint)
**Domain**: `vpn.woodhead.tech` (for documentation; VPN uses UDP, not HTTP)
**Goal**: Secure remote access to the entire homelab LAN from anywhere.
Connect from laptop/phone while away and access all services as if on the
local network -- no port forwarding needed beyond the VPN port.

**Why WireGuard**: Modern, fast, minimal attack surface. Single UDP port,
kernel-level performance, simple config. Replaces clunky OpenVPN setups.

**Architecture**:
```
Phone/Laptop (remote)
    |
    | WireGuard tunnel (UDP 51820)
    |
    v
ISP Modem -> Google Nest (port forward UDP 51820)
    |
    v
WireGuard LXC (192.168.86.39)
    |
    | IP forwarding + masquerade
    |
    v
192.168.86.0/24 (full LAN access)
```

**Requirements**:
- 1 CPU core, 256 MB RAM, 2 GB disk (extremely lightweight)
- Port forward: UDP 51820 on Google Nest -> WireGuard LXC
- Static public IP or DDNS (already running for Cloudflare)
- IP forwarding enabled in the LXC (`net.ipv4.ip_forward=1`)

**Approach options**:
1. **Dedicated LXC** (VM ID 208, IP 192.168.86.39) -- cleanest isolation,
   own Terraform + Ansible like other services
2. **Run on Proxmox host directly** -- simplest, no LXC overhead, but
   mixes concerns with the hypervisor
3. **Run in existing LXC** (e.g., Traefik) -- fewer containers, but
   couples unrelated services

**Recommended: Dedicated LXC**. Follows the existing pattern and keeps the
VPN endpoint isolated. If the VPN LXC is compromised, other services are
unaffected (assuming firewall rules are added later).

**VPN subnet**: `10.10.0.0/24` (separate from LAN)
- `10.10.0.1` -- WireGuard server (LXC)
- `10.10.0.2` -- Brandon's laptop
- `10.10.0.3` -- Brandon's phone
- `10.10.0.4+` -- additional clients

**Implementation plan**:
1. `terraform/lxc-wireguard.tf` -- LXC container (VM ID 208, 192.168.86.39)
2. `ansible/playbooks/setup-wireguard.yml` -- Install WireGuard, generate
   server + client keys, configure interface, enable IP forwarding
3. Generate client configs (QR codes for phone, .conf files for laptop)
4. Port forward UDP 51820 on Google Nest -> 192.168.86.39
5. Traefik route not needed (WireGuard is UDP, not HTTP)

**Client setup**:
- macOS/Windows/Linux: official WireGuard app, import `.conf` file
- iOS/Android: WireGuard app, scan QR code from server

**DNS inside tunnel**: Clients use the LAN DNS (192.168.86.1) so
`*.woodhead.tech` resolves via hairpin NAT or split DNS. Alternatively,
set DNS to a Pi-hole/AdGuard instance in the future.

**Security notes**:
- Private keys generated on the server, never transmitted in plaintext
- Client configs contain pre-shared keys for post-quantum resistance
- Ansible playbook stores keys in `/etc/wireguard/` (mode 0600)
- Keys are injected via `--extra-vars` or generated at deploy time
- Consider AllowedIPs restrictions per client (e.g., phone only gets
  media services, not admin tools)

**Files**:
| File | Purpose |
|------|---------|
| `terraform/lxc-wireguard.tf` | LXC container (deployed) |
| `terraform/lxc-wireguard-variables.tf` | VM ID, IP variables |
| `ansible/playbooks/setup-wireguard.yml` | Install + configure WireGuard |
| `ansible/files/wireguard/wg0.conf.j2` | Server config template |
| `ansible/files/wireguard/client.conf.j2` | Client config template |

---

### Docusaurus Documentation Site

**Type**: Docker container on existing LXC or K8s pod
**Domain**: `docs.woodhead.tech`
**Goal**: Centralized documentation site for the homelab -- runbooks, architecture
diagrams, user guides, and operational procedures. Replaces the scattered markdown
files in the repo with a searchable, versioned, browsable site.

**Why Docusaurus**: React-based, Markdown-driven, built-in search, versioning,
and sidebar navigation. Deploys as a static site (nginx or K8s). Already familiar
from syssec-docs at work.

**Content to migrate**:
- `docs/ARCHITECTURE.md` -- network topology, resource allocation
- `docs/RUNBOOK.md` -- deployment walkthroughs per service
- `docs/PATCHING.md` -- update strategies
- `docs/ROADMAP.md` -- planned services
- Per-service user guides (ARR stack setup, Plex libraries, VPN client config)
- Operational playbooks (Ceph recovery, node failure, certificate rotation)

**Requirements**:
- Node.js build step (Docusaurus generates static HTML)
- Minimal runtime: nginx serving static files, or Kubernetes Deployment
- CI/CD: rebuild on push to docs branch (GitHub Actions or manual `make docs`)
- ~256MB RAM, 1 CPU core at runtime (static files)

**Deployment options**:
1. **K8s pod** (preferred) -- Dockerfile builds the site, Deployment serves it,
   Traefik IngressRoute routes `docs.woodhead.tech`
2. **Existing LXC** -- build locally, rsync static output to an nginx container
3. **Dedicated LXC** -- overkill for a static site

**Implementation plan**:
1. `docs-site/` directory in this repo (Docusaurus project)
2. Dockerfile: multi-stage build (node -> nginx)
3. K8s manifests or Docker Compose for deployment
4. Traefik route: `docs.woodhead.tech`
5. Migrate existing markdown content into Docusaurus structure
6. Makefile target: `make docs`

---

### Resume / Portfolio Site

**Type**: Static site (K8s pod or LXC container)
**Domain**: `resume.woodhead.tech`
**Goal**: Personal resume and portfolio site showcasing projects and experience.

**Options**:
1. **Static HTML/CSS** -- simple, fast, no framework overhead
2. **Hugo/Jekyll** -- Markdown-driven, theme ecosystem, easy to update
3. **React/Next.js** -- more interactive, heavier build

**Requirements**:
- Minimal: static file serving (nginx)
- ~256MB RAM, 1 CPU core
- Traefik route: `resume.woodhead.tech`

**Implementation plan**:
1. `resume-site/` directory in this repo (or separate repo)
2. Choose framework (Hugo recommended for simplicity + themes)
3. Dockerfile: multi-stage build -> nginx
4. K8s manifests or Docker Compose
5. Traefik route: `resume.woodhead.tech`
6. Makefile target: `make resume`

---

## IP Address Plan

Keeping track of allocated IPs to avoid conflicts:

| IP            | Service              | Type | VM ID |
|---------------|----------------------|------|-------|
| 192.168.86.1      | Gateway (Nest WiFi)  | Router | --  |
| 192.168.86.29-31  | Proxmox nodes (thinkcentre1–3) | Host | --    |
| 192.168.86.130    | tower1 (Proxmox node)  | Host | --    |
| 192.168.86.147    | zotac (Proxmox node)   | Host | --    |
| 192.168.86.20     | Traefik              | LXC  | 200   |
| 192.168.86.21     | Recipe site          | LXC  | 201   |
| 192.168.86.22     | ARR stack            | LXC  | 202   |
| 192.168.86.23     | Plex                 | LXC  | 203   |
| 192.168.86.24     | Jellyfin             | LXC  | 204   |
| 192.168.86.25     | Monitoring           | LXC  | 205   |
| 192.168.86.26     | OpenClaw             | LXC  | 206   |
| 192.168.86.28     | Authentik            | LXC  | 207   |
| 192.168.86.32     | SDR Scanner          | LXC  | 210   |
| 192.168.86.33     | Kanboard             | LXC  | 211   |
| 192.168.86.34     | Mailcow email        | LXC  | 212   |
| 192.168.86.35     | PXE boot server      | LXC  | 213   |
| 192.168.86.36     | Zigbee2MQTT          | LXC  | 214   |
| 192.168.86.37     | Claude OS            | LXC  | 215   |
| 192.168.86.38     | pwnagotchi           | LXC  | 216   |
| 192.168.86.39     | WireGuard VPN        | LXC  | 208   |
| 192.168.86.27     | Libby Alert          | LXC  | 209   |
| 192.168.86.40     | TrueNAS              | VM   | 300   |
| 192.168.86.41     | Home Assistant       | VM   | 301   |
| 192.168.86.131    | Piboard dashboard    | Pi   | --    |
| 192.168.86.138    | Klipper Ender 3      | Pi   | --    |
| 192.168.86.136    | Klipper Ender 5 Pro  | Pi   | --    |
| 192.168.86.100    | K8s API VIP          | VIP  | --    |
| 192.168.86.101    | K8s control plane    | VM   | 400   |
| 192.168.86.111-112| K8s workers          | VM   | 410+  |
| 192.168.86.150-199| MetalLB pool         | K8s  | --    |

---

### Authentik SSO

**Status**: DONE

**Type**: LXC 207 | `192.168.86.28` | Docker Compose
**Domain**: `auth.woodhead.tech`

Authentik replaced the originally planned Authelia. It provides domain-level forward auth
for all `*.woodhead.tech` subdomains via a single Traefik `forwardAuth` middleware (`authentik@file`).

**Current setup**:
- Single `woodhead-forward-auth` proxy provider in `forward_domain` mode covering `woodhead.tech`
- `admins` group — full access to all services (bwoodwar@gmail.com, lips42@gmail.com)
- Google OAuth source configured for login
- Outpost embedded in Authentik server container

**Files**:
| File | Purpose |
|------|---------|
| `terraform/lxc-authentik.tf` | LXC container (VM ID 207) |
| `ansible/playbooks/setup-authentik.yml` | Install + configure Authentik |
| `ansible/files/traefik/dynamic/authentik.yml` | Traefik forwardAuth middleware |

**Service protection** — add `middlewares: [authentik@file]` to any Traefik route to protect it:
| Service | Protected |
|---------|-----------|
| Sonarr, Radarr, Prowlarr, Bazarr | Yes |
| SABnzbd, Seerr | Yes |
| TrueNAS (`nas.woodhead.tech`) | Yes |
| SDR Scanner (`scanner.woodhead.tech`) | Yes |
| Grafana, docs, resume | Yes |
| Plex | No (uses Plex accounts) |

---

---

### Libby-Alert Glucose Graph

**Type**: Feature addition to existing libby-alert Go web server (LXC 209)
**Domain**: `libby.woodhead.tech` (existing)
**Goal**: Display a 3-hour rolling glucose chart on Libby's emergency info page
so anyone scanning the QR code (or visiting the site) can see recent readings.

**Architecture**:
```
Dexcom Share API -> dexcom-exporter (monitoring LXC 205)
    |
    v
Prometheus (192.168.86.25:9090)
    |
    | query_range (dexcom_glucose_value, last 3h)
    |
    v
libby-alert Go server (LXC 209, :8080)
    |
    | JSON API endpoint -> Chart.js line graph
    |
    v
Browser (libby.woodhead.tech)
```

**Implementation plan**:
1. Add a `/api/glucose` endpoint to the libby-alert Go server that queries
   Prometheus HTTP API: `query_range?query=dexcom_glucose_value&start=-3h`
2. Return JSON array of `{timestamp, value}` pairs
3. Add a Chart.js line graph to the frontend page (inline JS, no build step)
4. Color-code the chart zones: red (<70 low), green (70-180 normal), yellow (>180 high), red (>250 critical)
5. Auto-refresh every 5 minutes via `setInterval`
6. Graceful fallback if Prometheus is unreachable or no data (show "No recent data")

**Dependencies**:
- Dexcom monitoring stack deployed and scraping (blocked on Dexcom Share creds)
- Prometheus reachable from LXC 209 (same LAN, no firewall issues expected)

**Requirements**:
- No additional infrastructure -- runs on the existing libby-alert LXC
- Prometheus HTTP API access from libby-alert LXC (192.168.86.25:9090)
- Chart.js loaded from CDN or vendored

---

### Kanboard Task Queue (ClawBot)

**Status**: DONE

**Type**: LXC container with Docker Compose
**Domain**: `tasks.woodhead.tech`
**Goal**: Self-hosted Kanboard instance for leaving tasks that ClawBot (Claude Code
agent) can pick up and process autonomously. Enables asynchronous task delegation --
leave a card on the board before bed, ClawBot works it overnight.

**Why Kanboard**: Lightweight (PHP + SQLite), simple REST API, no heavy dependencies
(no Redis, no Postgres required). Easy for ClawBot to poll via API, parse task
descriptions, and update status. Kanban board UI for visual task management.

**Architecture**:
```
Brandon (browser / CLI)
    |
    | Create task card on Kanboard
    |
    v
Kanboard (tasks.woodhead.tech)
    |
    | REST API poll (GET /api, jsonrpc)
    |
    v
ClawBot (Claude Code agent, cron or long-running)
    |
    | Read task -> execute -> update card with results
    |
    v
Kanboard (task moved to Done, comment with output)
```

**Requirements**:
- 1 CPU core, 512MB RAM, 5GB disk (SQLite, minimal storage)
- PHP 8.x + Apache/nginx (official Kanboard Docker image handles this)
- Persistent volume for SQLite database + file attachments

**Implementation plan**:
1. `terraform/lxc-kanboard.tf` -- LXC container (allocate next VM ID + IP)
2. `ansible/playbooks/setup-kanboard.yml` -- Deploy Kanboard via Docker Compose
3. `ansible/files/kanboard/docker-compose.yml` -- Official Kanboard image + volume
4. Traefik dynamic route: `tasks.woodhead.tech` -> Kanboard (:80)
5. Authelia protection (admin-only access)
6. Create a "ClawBot" project with columns: Backlog, In Progress, Review, Done
7. Generate API token for ClawBot to authenticate

**ClawBot integration**:
- Python agent (`clawbot.py`) polls Kanboard JSON-RPC API every 5 minutes for tasks in Backlog
- Parses task title + description for instructions
- Moves card to In Progress, executes work, posts results as comment
- Moves card to Done (or Review if human check needed)
- Runs as macOS launchd agent, executes tasks via `claude -p --dangerously-skip-permissions`

**Kanboard API examples**:
```bash
# List tasks in Backlog column
curl -u clawbot:API_TOKEN -d '{"jsonrpc":"2.0","method":"getAllTasks","id":1,"params":{"project_id":1,"status_id":1}}' \
  https://tasks.woodhead.tech/jsonrpc.php

# Update task status
curl -u clawbot:API_TOKEN -d '{"jsonrpc":"2.0","method":"moveTaskPosition","id":1,"params":{"project_id":1,"task_id":42,"column_id":3,"position":1}}' \
  https://tasks.woodhead.tech/jsonrpc.php
```

**Files**:
| File | Purpose |
|------|---------|
| `terraform/lxc-kanboard.tf` | LXC container |
| `terraform/lxc-kanboard-variables.tf` | VM ID, IP variables |
| `ansible/playbooks/setup-kanboard.yml` | Install + configure Kanboard |
| `ansible/files/kanboard/docker-compose.yml` | Kanboard Docker stack |
| `ansible/files/traefik/dynamic/kanboard.yml` | Traefik route |

---

### Zigbee2MQTT (Zigbee Dongle on Zotac)

**Type**: LXC container on zotac (192.168.86.147)
**Domain**: none (internal service only)
**Goal**: Bridge the Zigbee USB dongle attached to zotac into Home Assistant via
Zigbee2MQTT + Mosquitto. USB passthrough can only go to a VM/LXC on the same
physical host as the USB device — the HA VM lives on thinkcentre1, so a dedicated
Zigbee2MQTT LXC on zotac is required.

**Architecture**:
```
Zigbee device (sensor/switch/bulb)
    |
    | Zigbee RF
    |
    v
USB Zigbee dongle (zotac, /dev/ttyUSB0 or /dev/ttyACM0)
    |
    | USB passthrough via cgroup rules in /etc/pve/lxc/<vmid>.conf
    |
    v
Zigbee2MQTT LXC (192.168.86.36, zotac)
    |
    | MQTT (192.168.86.36:1883)
    |
    v
Home Assistant VM (192.168.86.41, thinkcentre1)
    |
    | MQTT integration -> entities, automations
    |
    v
home.woodhead.tech
```

**USB passthrough for LXC** — add to `/etc/pve/lxc/<vmid>.conf` on zotac:
```
lxc.cgroup2.devices.allow: c <major>:<minor> rwm
lxc.mount.entry: /dev/ttyACM0 dev/ttyACM0 none bind,optional,create=file
```

Find the device major/minor: `ls -la /dev/ttyACM0` or `ls -la /dev/ttyUSB0` on zotac.

**Requirements**:
- 1 CPU core, 256MB RAM, 4GB disk
- LXC pinned to zotac (`node_name = "zotac"` in Terraform)
- USB device passthrough via cgroup rules (same pattern as SDR scanner LXC 210)
- Zigbee2MQTT + Mosquitto (MQTT broker) in Docker Compose
- Home Assistant MQTT integration pointed at LXC IP

**Zigbee2MQTT config** (`/opt/zigbee2mqtt/data/configuration.yaml`):
```yaml
homeassistant: true
mqtt:
  server: mqtt://localhost
serial:
  port: /dev/ttyACM0  # or /dev/ttyUSB0 — check after passthrough
```

**Home Assistant setup**:
1. Settings -> Devices & Services -> Add Integration -> MQTT
2. Broker: `192.168.86.36`, port `1883`
3. Devices auto-discovered via HA discovery topic

**Implementation plan**:
1. Identify dongle device path on zotac: `ls /dev/ttyACM* /dev/ttyUSB*`
2. `terraform/lxc-zigbee2mqtt.tf` -- LXC on zotac (VM ID 214, IP 192.168.86.36)
3. `ansible/playbooks/setup-zigbee2mqtt.yml` -- Docker Compose with Zigbee2MQTT + Mosquitto
4. USB passthrough cgroup rules in LXC config on zotac (same pattern as LXC 210 on pve2)
5. Configure Home Assistant MQTT integration
6. Pair Zigbee devices via Zigbee2MQTT web UI (port 8080)

**Files**:
| File | Purpose |
|------|---------|
| `terraform/lxc-zigbee2mqtt.tf` | LXC on zotac (VM ID 214) |
| `ansible/playbooks/setup-zigbee2mqtt.yml` | Install Zigbee2MQTT + Mosquitto |
| `ansible/files/zigbee2mqtt/docker-compose.yml` | Zigbee2MQTT + Mosquitto stack |

**Notes**:
- Zigbee2MQTT supports Sonoff Zigbee 3.0 USB Dongle Plus, HUSBZB-1, CC2652, ConBee II, and others
- Check dongle vendor ID: `lsusb` on zotac — needed to verify it's detected before starting LXC work
- No Traefik route needed; Zigbee2MQTT frontend (port 8080) can be accessed directly or left LAN-only
- Zigbee2MQTT preferred over ZHA (Home Assistant's built-in Zigbee) because it keeps the radio
  attached to a fixed LXC — if the HA VM is ever migrated to a different host, the bridge stays
  on zotac and HA just reconnects to the MQTT broker

---

### UPS Monitoring Dashboard

**Type**: Grafana dashboard + Prometheus alert rules (no new infrastructure)
**Goal**: Centralized visibility into UPS health across all Proxmox nodes so you
know at a glance if batteries are degrading, loads are unbalanced, or a UPS is
on battery power.

**What already exists**:
- 3 NUT exporters running on the monitoring LXC (Docker Compose):
  - `nut-exporter-tc3` (:9199) -> thinkcentre3 (192.168.86.31:3493)
  - `nut-exporter-tower1` (:9198) -> tower1 (192.168.86.130)
  - `nut-exporter-zotac` (:9197) -> zotac (192.168.86.147)
- Prometheus scrape job `nut` collecting metrics at `/ups_metrics`
- Metrics available: `ups_battery_charge`, `ups_battery_voltage`,
  `ups_load`, `ups_battery_runtime_seconds`, `ups_status`, `ups_input_voltage`,
  `ups_output_voltage`, `ups_temperature`

**Grafana dashboard** (`ansible/files/monitoring/grafana/dashboards/ups-monitoring.json`):
- Row per UPS (tc3, tower1, zotac) with:
  - Battery charge gauge (0-100%, color thresholds at 50%/80%)
  - Load percentage gauge (warn >70%, critical >90%)
  - Runtime remaining (minutes, with low threshold marker)
  - Input/output voltage graph (24h history)
  - Battery voltage graph (24h, detects degradation over time)
  - UPS status indicator (OL = online, OB = on battery, LB = low battery)
- Summary row at top with stat panels for all 3 UPS units

**Alert rules** (add to `ansible/files/monitoring/prometheus/rules/alerts.yml`):
- `UpsOnBattery` -- UPS status is OB (on battery) for >30s (critical)
- `UpsLowBattery` -- battery charge <50% (warning), <20% (critical)
- `UpsHighLoad` -- load >80% for 5 min (warning), >90% (critical)
- `UpsLowRuntime` -- runtime remaining <10 min (critical)
- `UpsExporterDown` -- NUT exporter unreachable for 2 min (warning)

**Implementation plan**:
1. Create Grafana dashboard JSON (`ups-monitoring.json`)
2. Add alert rules to `alerts.yml`
3. Redeploy monitoring stack (`make monitoring`)
4. Dashboard auto-provisions via Grafana provisioning config

**Requirements**:
- No new infrastructure -- everything runs on existing monitoring LXC (205)
- NUT exporters already deployed and scraping

---

### Email Server (woodhead.tech)

**Status**: DONE

**Type**: LXC container with Docker Compose
**Domain**: `mail.woodhead.tech`
**Goal**: Self-hosted email for the `woodhead.tech` domain. Enables sending/receiving
email from addresses like `brandon@woodhead.tech`, service notifications (ClawBot,
Alertmanager), and eliminates reliance on third-party email for homelab comms.

**Why self-hosted**: Full control over mailboxes, no per-user fees, custom aliases,
and a proper MX record for the domain. Service accounts (e.g., `clawbot@woodhead.tech`,
`alerts@woodhead.tech`) are free to create.

**Stack**: [Mailcow](https://mailcow.email/) (Postfix, Dovecot, Rspamd, SOGo, MariaDB, Redis)

**Requirements**:
- 2 CPU cores, 2-4GB RAM, 20GB disk (mailbox storage)
- DNS records on Cloudflare:
  - `MX` record: `woodhead.tech` -> `mail.woodhead.tech`
  - `A` record: `mail.woodhead.tech` -> public IP
  - `SPF`: `v=spf1 a mx ip4:<public-ip> -all`
  - `DKIM`: TXT record generated by the mail stack
  - `DMARC`: `v=DMARC1; p=quarantine; rua=mailto:postmaster@woodhead.tech`
  - `PTR` (reverse DNS): ISP must set this for deliverability -- check if possible
- Port forwards on router: TCP 25 (SMTP), 465 (SMTPS), 587 (submission), 993 (IMAPS)
- Let's Encrypt TLS via Traefik or standalone certbot

**Potential blockers**:
- Many residential ISPs block port 25 outbound/inbound. Verify with your ISP first.
  If blocked, use an SMTP relay (e.g., Mailgun, Amazon SES) for outbound delivery.
- Reverse DNS (PTR record) is typically set by the ISP, not Cloudflare. Without it,
  outbound mail may land in spam. Check if your ISP allows PTR configuration.

**Implementation plan**:
1. Verify ISP allows port 25 traffic (or plan for SMTP relay)
2. `terraform/lxc-mailserver.tf` -- LXC container (allocate next VM ID + IP)
3. `ansible/playbooks/setup-mailserver.yml` -- Deploy mail stack via Docker Compose
4. Configure Cloudflare DNS (MX, SPF, DKIM, DMARC)
5. Port forward SMTP/IMAP ports on router
6. Traefik route for webmail UI (if using Mailcow): `mail.woodhead.tech`
7. Create mailboxes: `brandon@woodhead.tech`, `clawbot@woodhead.tech`, `alerts@woodhead.tech`
8. Configure Alertmanager + ClawBot to send via local SMTP

**Notes**:
- ClamAV disabled to save RAM (~1GB reduction); Rspamd handles spam filtering
- Outbound mail relayed through Mailgun sandbox SMTP relay (ISP blocks port 25 outbound)

**Files**:
| File | Purpose |
|------|---------|
| `terraform/lxc-mailserver.tf` | LXC container |
| `terraform/lxc-mailserver-variables.tf` | VM ID, IP variables |
| `ansible/playbooks/setup-mailserver.yml` | Install + configure mail stack |
| `ansible/files/mailserver/docker-compose.yml` | Mail server Docker stack |
| `ansible/files/traefik/dynamic/mailserver.yml` | Traefik route (webmail UI) |

---

### Proxmox Backups via TrueNAS NFS

**Blocked on**: TrueNAS setup (NFS share must exist first)

**Plan**:
1. On TrueNAS: create a dataset (e.g., `tank/proxmox-backups`) and export it as NFS
   - Restrict access to the Proxmox subnet (`192.168.86.0/24`)
   - Use NFS v4, async writes for performance
2. On all Proxmox nodes: add NFS storage endpoint via `pvesm add nfs`
   - Storage ID: `truenas-backups`
   - Content type: `backup`
   - Mount point: `/mnt/pve/truenas-backups`
3. Create a cluster-wide backup job via Proxmox UI or `pvesh`:
   - Schedule: nightly (e.g., 02:00)
   - Mode: snapshot (zero downtime for running VMs)
   - Compression: zstd
   - Retention: 7 daily, 4 weekly
   - Target: `truenas-backups` storage
   - Scope: all VMs and LXCs across all nodes (thinkcentre1–3, tower1)

**Nodes to include**: thinkcentre1, thinkcentre2, thinkcentre3, tower1, zotac

**VMs/LXCs to back up** (currently none have backup jobs):
| ID  | Name                   | Node          |
|-----|------------------------|---------------|
| 200 | traefik                | thinkcentre1  |
| 201 | recipe-site            | thinkcentre1  |
| 202 | arr-stack              | thinkcentre2  |
| 203 | plex                   | thinkcentre2  |
| 204 | jellyfin               | thinkcentre3  |
| 205 | monitoring             | thinkcentre2  |
| 206 | openclaw               | thinkcentre3  |
| 207 | authentik              | thinkcentre1  |
| 208 | wireguard              | thinkcentre1  |
| 209 | libby-alert            | thinkcentre1  |
| 211 | kanboard               | thinkcentre1  |
| 300 | truenas                | tower1        |
| 301 | homeassistant          | thinkcentre1  |
| 400 | talos-proxmox-cp-0     | tower1        |
| 410 | talos-proxmox-worker-0 | tower1        |
| 411 | talos-proxmox-worker-1 | thinkcentre3  |

---

### Piboard Touchscreen Integration

**Status**: PLANNED (verify)

**Type**: Hardware + software — Waveshare 5-inch HDMI display (already installed on piboard Pi 3B)
**Goal**: Enable the resistive touchscreen on the Waveshare display so the piboard dashboard can respond to touch input. The display hardware supports touch via XPT2046 SPI, and SPI is already enabled in `deploy/setup-pi.sh` via `/boot/firmware/config.txt`.

**What to verify**:
1. Touch device appears: `ls /dev/input/event*` on the Pi — should see an XPT2046 device
2. Test raw touch: `evtest /dev/input/event0` (or whichever event node)
3. Chromium kiosk calibration: may need `xinput_calibrator` if touch coordinates are off
4. Consider interaction: tap to toggle full-screen, swipe for future panels, etc.

**Potential blockers**:
- XPT2046 overlay not loaded (add `dtoverlay=xpt2046,cs=0,penirq=17,speed=1000000,swapxy=0` to `/boot/firmware/config.txt`)
- Touch events not reaching Chromium (Chromium needs `--touch-events=enabled` flag)
- Coordinate calibration (calibration matrix in X11 `99-calibration.conf`)

**Implementation**:
1. SSH to Pi (`ssh pi@192.168.86.131`)
2. Check `dmesg | grep -i xpt2046` and `ls /dev/input/`
3. Add overlay if missing, reboot, re-verify
4. Add `--touch-events=enabled` to `deploy/piboard-kiosk.service` Chromium flags
5. Run `xinput_calibrator` via SSH with `DISPLAY=:0` to generate calibration config

---

### Grafana Cloud Paging / Alerting

**Status**: READY TO DEPLOY (grafana.net account created, API key stored in `scripts/secrets/grafana.env`)

**Type**: Monitoring integration — Grafana Cloud (grafana.net account)
**Goal**: Route critical homelab alerts (libby alerts, downed services, sensor failures) through Grafana Cloud's alerting and on-call paging infrastructure instead of raw Discord webhooks. Provides escalation policies, silences, acknowledgment, and mobile push/SMS paging.

**Scope**:
- Grafana Cloud connected to the self-hosted Prometheus at `192.168.86.25:9090` via Grafana Agent or remote_write
- Existing Alertmanager rules forwarded to Grafana Cloud Alerting (or replaced by Grafana managed alerts)
- PagerDuty/OpsGenie-style on-call routing for: Libby life alert triggers, service down (blackbox probe), enclosure temperature alerts, Dexcom glucose critical alerts

**Key decisions**:
- Push metrics to Grafana Cloud (remote_write from Prometheus) or run Grafana Agent on the monitoring LXC
- Use Grafana Alerting (cloud-managed) or keep Alertmanager and add a Grafana Cloud contact point
- API key stored in Ansible vault / secrets / gitignored env files (e.g. `scripts/secrets/grafana.env`) — never committed to git

**Implementation plan**:
1. Configure Grafana Agent on monitoring LXC (205) to scrape local Prometheus and ship to Grafana Cloud
2. Add Grafana Cloud data source to self-hosted Grafana (for cross-referencing local vs cloud)
3. Create Grafana Cloud alert rules mirroring current Alertmanager rules
4. Configure on-call routing: Discord for non-critical, mobile push/SMS for critical
5. Update `make monitoring` to inject Grafana Cloud credentials

---

### Gutgrinda Enclosure in Grafana

**Status**: PLANNED

**Type**: Monitoring addition — no new infrastructure
**Goal**: Grafana dashboard panels for Gutgrinda's enclosure (temperature, humidity, plug states) pulled from Home Assistant via the HA Prometheus integration.

**HA Prometheus integration**:
Enable in `configuration.yaml` (or `packages/beardie.yaml`):
```yaml
prometheus:
  namespace: homeassistant
  filter:
    include_entity_globs:
      - sensor.0xa4c13874d0343902_*
      - switch.gutgrinda_*
```
This exposes `GET /api/prometheus` on HA (port 8123). Add a Prometheus scrape job targeting `192.168.86.41:8123`.

**Dashboard panels**:
- Temperature gauge (95–115°F range, with color thresholds)
- Humidity gauge
- Basking lamp on/off state over time
- Ambient light on/off state over time
- Ceramic heater on/off state over time
- Alert history from `ALERTS{}` where alertname includes "Gutgrinda"

**Implementation plan**:
1. Add `prometheus:` config to `packages/beardie.yaml`, redeploy via `make beardie`
2. Add scrape job to `ansible/files/monitoring/prometheus/prometheus.yml`
3. Create Grafana dashboard JSON in `ansible/files/monitoring/grafana/dashboards/`
4. Redeploy monitoring: `make monitoring`

---

## Implementation Priority

1. **NAS** -- DONE (TrueNAS Scale 24.04, ZFS pool `tank` on 2TB Ceph RBD, NFS shares for media/backups/isos)
2. **Proxmox Backups** -- DONE (truenas-backups NFS storage added, nightly 02:00 snapshot job, 7-day retention)
3. **ARR stack** -- DONE (LXC with Docker Compose, NFS via Proxmox host bind-mount; gluetun WireGuard VPN killswitch for SABnzbd via PrivadoVPN)
4. **Plex / Jellyfin** -- DONE (LXCs with iGPU passthrough, NFS via Proxmox host bind-mount)
5. **Home Assistant** -- DONE (HAOS VM at 192.168.86.41, trusted_proxies configured, home.woodhead.tech via Traefik)
6. **Authentik SSO** -- DONE (deployed at auth.woodhead.tech; admins + media-users groups; access policy restricts admin services; Google OAuth source configured)
7. **WireGuard VPN** -- DONE (LXC, UDP 51820, split tunnel to LAN)
8. **Resource Balancing** -- DONE (tower1 added, Talos VMs redistributed across nodes)
9. **Piboard Dashboard** -- DONE (Raspberry Pi 3B + Waveshare 5" HDMI, Go + SSE + Prometheus)
10. **Klipper 3D Printing** -- DONE (Ender 5 Pro at ender5.woodhead.tech, Ender 3 at ender3.woodhead.tech; both Pi 3B running MainsailOS, routed via Traefik)
11. **Talos K8s Cluster** -- DONE (3-node cluster bootstrapped: CP at 192.168.86.143, workers at .144/.145; Flannel CNI; namespaces: ingress-system, apps, monitoring; configs in talos/_out/)
12. **SDR Scanner** -- DONE (LXC 210 on thinkcentre2, Trunk Recorder + rdio-scanner, RTL-SDR V4 USB passthrough, SNO911 P25 Phase II, scanner.woodhead.tech)
13. **Dexcom Glucose Monitoring** -- IN PROGRESS (Python exporter -> Prometheus -> Grafana dashboard; Alertmanager routes to Twilio SMS + Home Assistant Alexa; needs Dexcom Share credentials + Twilio account)
14. **Docusaurus Docs Site** -- DONE (docs.woodhead.tech; deployed on monitoring LXC; Traefik route + Authentik SSO)
15. **Resume Site** -- DONE (resume.woodhead.tech; Hugo static site deployed on monitoring LXC)
16. **Libby-Alert Glucose Graph** -- PLANNED (Chart.js glucose chart on libby.woodhead.tech; queries Prometheus for 3h of dexcom_glucose_value; blocked on Dexcom creds)
17. **Kanboard / ClawBot** -- DONE (tasks.woodhead.tech; Kanboard on LXC 211, ClawBot agent polls via JSON-RPC, Discord notifications with PR links, woodhead-tech GitHub account for PRs)
18. **UPS Monitoring Dashboard** -- DONE (Grafana dashboard + alert rules for NUT UPS metrics; 3 exporters scraping tc3/tower1/zotac; battery charge, load, runtime, voltage, status per UPS)
19. **Email Server** -- DONE (mail.woodhead.tech; Mailcow on LXC 212, Mailgun SMTP relay for outbound, inbound via port forwards, mailboxes: brandon@, clawbot@, clawbot-0@, alerts@)
20. **Zigbee2MQTT** -- DONE (LXC 214 on zotac at 192.168.86.36; SONOFF Zigbee Dongle Lite via USB passthrough; Zigbee2MQTT 2.10.1 + Mosquitto on :1883; HA connects via MQTT integration at 192.168.86.36:1883)
21. **pwnagotchi** -- DONE (LXC 216 on thinkcentre3 at 192.168.86.38; TP-Link TL-WN722N v2 RTL8188EUS USB WiFi in monitor mode via lxc.net.1.type=phys; bettercap + pwngrid + pwnagotchi Python AI; pwnagotchi.woodhead.tech)
22. **Legitimate SSL Certs** -- PLANNED (replace self-signed/wildcard certs with proper Let's Encrypt certs per service; evaluate cert-manager in K8s or Traefik ACME for LXC services; ensure all subdomains have valid TLS)
23. **Piboard Touchscreen** -- PLANNED (verify XPT2046 SPI touch on Waveshare 5" display; add `--touch-events=enabled` to Chromium kiosk flags; calibrate if needed)
24. **Grafana Cloud Paging** -- READY TO DEPLOY (grafana.net account created, API key stored in scripts/secrets/grafana.env; route critical alerts through grafana.net on-call; Grafana Agent on monitoring LXC ships metrics to cloud)
25. **Gutgrinda Enclosure in Grafana** -- PLANNED (enable HA Prometheus integration, scrape from monitoring LXC, Grafana dashboard for temp/humidity/plug states)

---

### Legitimate SSL Certificates

**Status**: PLANNED

**Type**: Configuration change (Traefik ACME + Let's Encrypt)
**Goal**: All `*.woodhead.tech` subdomains should present valid Let's Encrypt certificates
rather than relying on self-signed or wildcard certs that trigger browser warnings.

**Current state**: Traefik handles TLS termination via Let's Encrypt with Cloudflare DNS-01
challenge. The static config (`traefik.yml`) has ACME configured but several routes may
still serve self-signed certs or have cert resolver misconfigured.

**What to do**:
1. Audit all Traefik dynamic configs — ensure every `tls:` block references `certresolver: letsencrypt`
2. Verify Cloudflare API token has `Zone:DNS:Edit` permission for DNS-01 challenge
3. Check Traefik ACME storage (`/etc/traefik/acme.json`) is populated with valid certs for all subdomains
4. Test each subdomain: `curl -v https://<subdomain>.woodhead.tech` and check the cert
5. For K8s ingress routes, evaluate cert-manager with Let's Encrypt ClusterIssuer

**Requirements**:
- Cloudflare API token with DNS edit permissions (already needed for DDNS)
- Traefik ACME storage persisted across restarts (`/etc/traefik/acme.json`, chmod 600)
- All subdomains must be routable via Traefik before ACME challenge can complete

---

## Hardware Considerations

- **GPU passthrough**: Intel iGPU (Quick Sync) is shared between Plex and Jellyfin
  via `/dev/dri`. Only one node will have the iGPU available -- pin media LXCs
  to that node.
- **Disk passthrough**: TrueNAS needs dedicated disks, not Ceph volumes. Plan
  which physical disks go to Ceph vs NAS at Proxmox install time.
- **RAM budget**: With all services running, expect ~24-32GB total usage.
  Plan node RAM accordingly.
- **NAS on Ceph (known issue)**: TrueNAS VM currently uses a Ceph RBD for its data pool.
  Heavy write workloads (SABnzbd) overwhelm HDD OSDs and cause NFS hangs. See
  "NAS Migration" section above for the fix plan.

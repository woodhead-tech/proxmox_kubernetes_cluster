---
sidebar_position: 2
title: Architecture
---

# Architecture

Comprehensive architecture reference for the woodhead.tech Proxmox homelab.
Covers network topology, service dependencies, traffic flow, storage, DNS/TLS,
and resource allocation.

## Network Topology

```
                        +-----------+
                        |  Internet |
                        +-----+-----+
                              |
                        +-----+-----+
                        | ISP Modem |
                        +-----+-----+
                              |
                   +----------+----------+
                   | Google Nest WiFi    |
                   | Pro (router/mesh)   |
                   |     192.168.86.1    |
                   | NAT / DHCP / DNS /  |
                   | WiFi                |
                   +----------+----------+
                              |
                         192.168.86.0/24 (flat LAN)
                              |
          +----------+----------+----------+----------+
          |          |          |          |          |
    +-----+----+ +--+-------+ +--+------+ +--+-----+ +--+------+
    | Proxmox  | | Proxmox  | | Proxmox | | Proxmox| | Proxmox |
    | Node 1   | | Node 2   | | Node 3  | | Node 4 | | Node 5  |
    | .29      | | .30      | | .31     | | .130   | | .147    |
    | think-   | | think-   | | think-  | | tower1 | | zotac   |
    | centre1  | | centre2  | | centre3 | |        | |         |
    +-----+----+ +--+-------+ +--+------+ +--+-----+ +--+------+
          |          |          |          |          |
          +------- Ceph Storage Mesh (3-way replication) ------+
          |
          |   +----- VMs + LXCs distributed across nodes -----+
          |   |                                                |
     +----+---+----+   +----------+   +----------+   +--------+---+
     | Traefik     |   | Recipe   |   | ARR      |   | K8s Cluster|
     | LXC 200     |   | Site     |   | Stack    |   |            |
     | .86.20      |   | LXC 201  |   | LXC 202  |   | CP: .101   |
     | :80 :443    |   | .21 :80  |   | .22      |   | W1: .111   |
     +------+------+   +----------+   +----------+   | W2: .112   |
            |                                         | W3: .113   |
            |   +----------+   +----------+           | VIP: .100  |
            |   | Plex     |   | Jellyfin |           +------------+
            |   | LXC 203  |   | LXC 204  |
            |   | .23      |   | .24      |
            |   | :32400   |   | :8096    |
            |   | iGPU     |   | iGPU     |
            |   +----------+   +----------+
            |
            |   +----------+   +--------------+
            |   | TrueNAS  |   | Home         |
            |   | VM 300   |   | Assistant    |
            |   | .40      |   | VM 301       |
            |   | NFS:2049 |   | .41 :8123    |
            |   +----------+   +--------------+
            |
            |   +----------+   +----------+   +-----------+
            |   | Monitoring|   | OpenClaw |   | Authentik |
            |   | LXC 205  |   | LXC 206  |   | LXC 207   |
            |   | .25      |   | .26      |   | .28       |
            |   | :9090    |   | :18789   |   | :9091     |
            |   | :3000    |   +----------+   +----------+
            |   | :9093    |
            |   | -> Discord|   +-----------+   +-----------+
            |   | + Dexcom  |   | WireGuard |   | Libby     |
            |   |   glucose |   | LXC 208   |   | Alert     |
            |   +----------+   | .39       |   | LXC 209   |
            |                  | UDP:51820 |   | .27 :80   |
            |                  +-----------+   +-----------+
            |
            |   +----------+
            |   | SDR      |
            |   | Scanner  |
            |   | LXC 210  |
            |   | .32      |
            |   | :3000    |
            |   | RTL-SDR  |
            |   +----------+
            |
            |   +----------+   +----------+   +----------+
            |   | Kanboard |   | PXE      |   | Claude   |
            |   | LXC 211  |   | Server   |   | OS       |
            |   | .33      |   | LXC 213  |   | LXC 215  |
            |   | :8000    |   | .35      |   | .37      |
            |   +----------+   | TFTP/HTTP|   | :8051    |
            |                  +----------+   | :5173    |
            |                                 +----------+
            |
            |   +----------+
            |   | Zigbee   |
            |   | 2MQTT    |
            |   | LXC 214  |
            |   | .36      |
            |   | :8080    |
            |   | :1883    |
            |   | (zotac)  |
            |   +----------+
            |
          +------- Standalone Devices (not Proxmox-managed) -------+
          |                                                         |
     +----+----------+     +----------------+
     | Piboard       |     | Klipper        |  Raspberry Pi 3B
     | 192.168.86.131|     | Ender 5 Pro    |  MainsailOS + Klipper
     | :8080         |     | 192.168.86.136 |  Moonraker + Mainsail
     | Waveshare 5"  |     | :80 :7125      |  USB -> printer MCU
     +---------------+     +----------------+
```

## IP Address Allocation

| IP | Hostname | Type | VM ID | Purpose |
|---|---|---|---|---|
| 192.168.86.1 | nest-gateway | Router | -- | Google Nest WiFi Pro (NAT, DHCP, DNS) |
| 192.168.86.29 | pve1 (thinkcentre1) | Host | -- | Proxmox node 1 |
| 192.168.86.30 | pve2 (thinkcentre2) | Host | -- | Proxmox node 2 |
| 192.168.86.31 | pve3 (thinkcentre3) | Host | -- | Proxmox node 3 |
| 192.168.86.130 | tower1 | Host | -- | Proxmox node 4 |
| 192.168.86.147 | zotac | Host | -- | Proxmox node 5 |
| 192.168.86.20 | traefik | LXC | 200 | Reverse proxy, TLS termination |
| 192.168.86.21 | recipe-site | LXC | 201 | Go + SQLite recipe app |
| 192.168.86.22 | arr-stack | LXC | 202 | Docker: Sonarr, Radarr, etc. |
| 192.168.86.23 | plex | LXC | 203 | Plex Media Server + iGPU |
| 192.168.86.24 | jellyfin | LXC | 204 | Jellyfin Media Server + iGPU |
| 192.168.86.25 | monitoring | LXC | 205 | Prometheus, Grafana, Alertmanager |
| 192.168.86.26 | openclaw | LXC | 206 | OpenClaw AI agent framework |
| 192.168.86.27 | libby-alert | LXC | 209 | Libby life alert QR site + alerts |
| 192.168.86.28 | authentik | LXC | 207 | Identity provider (Authentik SSO, OIDC) |
| 192.168.86.32 | sdr | LXC | 210 | SDR scanner (Trunk Recorder + rdio-scanner) |
| 192.168.86.33 | kanboard | LXC | 211 | Kanboard project management + ClawBot agent |
| 192.168.86.34 | mailserver | LXC | 212 | Mailcow email server (Mailgun relay) |
| 192.168.86.35 | adguard | LXC | 221 | DNS (AdGuard Home) |
| 192.168.86.36 | step-ca | LXC | 222 | Step-CA SSH certificate authority |
| 192.168.86.37 | claude-os | LXC | 215 | Claude OS AI memory/MCP server |
| 192.168.86.38 | pwnagotchi | LXC | 216 | Pwnagotchi passive WiFi capture (pve3, RTL8188EUS) |
| 192.168.86.39 | wireguard | LXC | 208 | WireGuard VPN tunnel (UDP 51820) |
| 192.168.86.44 | zigbee2mqtt | LXC | 214 | Zigbee2MQTT + Mosquitto (on zotac) |
| 192.168.86.50 | pxe-server | LXC | 213 | PXE boot server (proxy-DHCP + TFTP + HTTP) |
| 192.168.86.51 | static-sites | LXC | 227 | Static web properties (docs, resume, consulting, etc.) |
| 192.168.86.40 | truenas | VM | 300 | NAS, ZFS, NFS/SMB shares |
| 192.168.86.41 | homeassistant | VM | 301 | Home Assistant OS, smart home |
| 192.168.86.131 | piboard | Pi | -- | Raspberry Pi 3B monitoring dashboard |
| 192.168.86.136 | klipper-ender5pro | Pi | -- | Klipper 3D printer (Ender 5 Pro) |
| 192.168.86.138 | klipper-ender3 | Pi | -- | Klipper 3D printer (Ender 3) |
| 192.168.86.100 | k8s-vip | VIP | -- | Kubernetes API endpoint |
| 192.168.86.101 | talos-cp-0 | VM | 400 | K8s control plane (Talos Linux) |
| 192.168.86.111-113 | talos-worker-* | VM | 410-412 | K8s workers (Talos Linux, 3 nodes) |
| 192.168.86.150-199 | metallb-pool | K8s | -- | MetalLB LoadBalancer IPs |
| 192.168.86.200-254 | dhcp-pool | DHCP | -- | Dynamic client addresses |

## Traffic Flow: External

An external request to `https://recipes.woodhead.tech`:

```
1. CLIENT                  DNS query: recipes.woodhead.tech
       |
       v
2. CLOUDFLARE DNS          Returns public IP (WAN) via A record
       |                   (Updated every 5 min by DDNS)
       v
3. ISP MODEM               Passes traffic to Google Nest
       |
       v
4. GOOGLE NEST             Receives on public IP :443
       |                   Port forward: :443 -> 192.168.86.20:443
       v
5. TRAEFIK (192.168.86.20) Terminates TLS (wildcard *.woodhead.tech cert)
       |                   Matches route: Host(`recipes.woodhead.tech`)
       |                   Proxies to backend: http://192.168.86.21:80
       v
6. RECIPE SITE (192.168.86.21) Nginx :80 -> Go app :8080
       |                   Returns HTML response
       v
7. TRAEFIK                 Wraps response in TLS, sends back
       |
       v
8. GOOGLE NEST             Reverse NAT: 192.168.86.20 -> public IP
       |
       v
9. CLIENT                  Receives HTTPS response with valid cert
```

**Port forwarding (Google Nest -> LAN):**

| WAN Port | Destination | Protocol | Purpose |
|---|---|---|---|
| 80 | 192.168.86.20:80 | TCP | HTTP -> Traefik |
| 443 | 192.168.86.20:443 | TCP | HTTPS -> Traefik |
| 51820 | 192.168.86.39:51820 | UDP | WireGuard VPN tunnel |

## Traffic Flow: Internal

Internal clients resolve `*.woodhead.tech` via Cloudflare DNS (upstream from Google Nest). The Nest supports hairpin NAT, so traffic loops back to Traefik without leaving the network.

```
1. CLIENT (192.168.86.x)   DNS query: recipes.woodhead.tech
       |
       v
2. GOOGLE NEST DNS          Forwards to upstream (8.8.8.8 / 1.1.1.1)
       |                   Returns public IP from Cloudflare
       v
3. CLIENT                  Connects to public IP :443
       |
       v
4. GOOGLE NEST             Hairpin NAT: public IP -> 192.168.86.20:443
       |
       v
5. TRAEFIK (192.168.86.20) Terminates TLS, routes to backend
       |
       v
6. RECIPE SITE (192.168.86.21) Responds directly on LAN
```

:::note
Unlike a dedicated firewall with local DNS overrides, internal requests still depend on external DNS resolution. Services are unreachable during internet outages unless clients have static hosts file entries.
:::

## DNS Resolution

```
                    +-------------------+
                    |  External Client  |
                    +--------+----------+
                             |
                    +--------v----------+
                    |   Cloudflare DNS  |  Authoritative for woodhead.tech
                    |   (free tier)     |  A record: *.woodhead.tech -> public IP
                    +-------------------+  Updated by DDNS every 5 min


                    +-------------------+
                    |  Internal Client  |
                    +--------+----------+
                             |
                    +--------v----------+
                    | Google Nest DNS   |  Forwards to upstream resolvers
                    |  (192.168.86.1:53)|
                    +-------------------+
```

- **Registrar:** Squarespace (nameservers pointed to Cloudflare)
- **Authoritative DNS:** Cloudflare (free tier)
- **DDNS updates:** Cron script on Proxmox node (every 5 min)
- **Internal resolution:** Google Nest forwards to upstream DNS; hairpin NAT loops traffic back to Traefik

## TLS Certificate Flow

Traefik handles all TLS termination using Let's Encrypt certificates obtained via Cloudflare DNS-01 challenges.

```
1. TRAEFIK detects new route requiring TLS
       |
       v
2. Requests cert from LET'S ENCRYPT
       |  Challenge type: DNS-01
       v
3. TRAEFIK creates TXT record via CLOUDFLARE API
       |  _acme-challenge.woodhead.tech = <token>
       v
4. LET'S ENCRYPT validates TXT record
       |  Verifies domain ownership
       v
5. Certificate issued
       |  Wildcard: *.woodhead.tech
       |  Stored: /etc/traefik/acme.json (0600)
       |  Auto-renewal: 30 days before expiry
       v
6. TRAEFIK applies cert to all matching routes
```

**Why DNS-01?** Supports wildcard certs, works before port forwarding is configured, works with internal-only IPs, and Cloudflare free tier supports it.

## Service Dependency Graph

**Hard dependencies (service won't function without):**
- All services -> Google Nest gateway (routing, DHCP, DNS)
- All external access -> Traefik (TLS, routing)
- Protected services -> Authentik (forwardAuth SSO, OIDC)
- Remote VPN access -> WireGuard (UDP 51820 port forward required)
- ARR stack media storage -> TrueNAS (NFS at `/media`)
- Plex/Jellyfin media library -> TrueNAS (NFS at `/media`, read-only)
- Plex/Jellyfin transcoding -> iGPU (`/dev/dri` passthrough from Proxmox host)

**Soft dependencies (service works but with reduced functionality):**
- Monitoring without PVE token: Proxmox metrics unavailable
- Monitoring without Dexcom credentials: glucose exporter starts but can't poll API
- Monitoring without Twilio credentials: glucose SMS alerts silently fail
- Piboard without Prometheus: dashboard shows "connection lost" overlay
- Services without Traefik: accessible via direct IP:port (no TLS)

## Boot Order

| Order | Service | VM ID | Delay | Why |
|---|---|---|---|---|
| 1 | TrueNAS | 300 | 30s | NFS shares must be ready before consumers |
| 2 | Home Assistant | 301 | 15s | Smart home should always be running |
| auto | All LXCs | 200-210 | -- | Start on boot, no ordering constraint |
| manual | K8s Cluster | 400+ | -- | Bootstrapped via `make bootstrap` |

## Storage Architecture

```
+-- Proxmox Node -----------------------------------------+
|                                                          |
|  Physical Disks:                                         |
|  +----------+  +----------+  +----------+  +----------+ |
|  |   sda    |  |   sdb    |  |   sdc    |  |   sdd    | |
|  | Proxmox  |  | Ceph OSD |  | TrueNAS  |  | TrueNAS  | |
|  | OS +     |  |          |  | data 1   |  | data 2   | |
|  | local-lvm|  |          |  | (pass-   |  | (pass-   | |
|  +----------+  +----------+  |  through)|  |  through) | |
|                               +----------+  +----------+ |
+----------------------------------------------------------+
```

| Storage | Type | Used By |
|---|---|---|
| local-lvm | LVM (SSD) | TrueNAS OS, HAOS, all LXC disks |
| ceph-pool | Ceph (3x) | K8s control plane, K8s workers |
| Passthrough | Physical | TrueNAS ZFS data pool |

## Resource Allocation

### CPU & Memory

| Service | Cores | RAM (MB) | Notes |
|---|---|---|---|
| TrueNAS | 4 | 8192 | ZFS ARC cache |
| Home Assistant | 2 | 2048 | USB passthrough |
| K8s Control Plane | 2 | 4096 | Per node |
| K8s Workers | 4 | 8192 | Per node, 3 nodes |
| Traefik LXC | 1 | 256 | Lightweight proxy |
| Monitoring LXC | 2 | 2048 | Prometheus, Grafana, exporters |
| ARR Stack LXC | 2 | 4096 | 7 Docker containers |
| Plex / Jellyfin LXC | 2 | 2048 | iGPU passthrough |
| Authentik LXC | 2 | 2048 | Postgres + Redis + server + worker |
| SDR Scanner LXC | 2 | 2048 | Trunk Recorder + rdio-scanner |
| WireGuard LXC | 1 | 256 | Kernel WireGuard |
| Kanboard LXC | 1 | 512 | Kanboard + SQLite |
| PXE Server LXC | 1 | 256 | dnsmasq + nginx |
| Zigbee2MQTT LXC | 1 | 512 | Zigbee2MQTT + Mosquitto |
| Claude OS LXC | 4 | 4096 | FastAPI + Redis + RQ + Vite |
| Pwnagotchi LXC | 1 | 1024 | bettercap + pwnagotchi Python |

### Total Budget

| Resource | Total | Notes |
|---|---|---|
| CPU | ~36 cores | Shared across 5 Proxmox nodes |
| RAM | ~47.25 GB | TrueNAS benefits from more (ZFS ARC) |
| local-lvm | ~146 GB | OS disks for VMs + all LXCs |
| ceph-pool | ~250 GB raw | K8s VMs (3x replication) |

## Traefik Routing Table

| Subdomain | Backend | Port | Status |
|---|---|---|---|
| recipes.woodhead.tech | 192.168.86.21 | 80 | Active |
| prowlarr.woodhead.tech | 192.168.86.22 | 9696 | Active (Authentik SSO) |
| sonarr.woodhead.tech | 192.168.86.22 | 8989 | Active (Authentik SSO) |
| radarr.woodhead.tech | 192.168.86.22 | 7878 | Active (Authentik SSO) |
| bazarr.woodhead.tech | 192.168.86.22 | 6767 | Active (Authentik SSO) |
| requests.woodhead.tech | 192.168.86.22 | 5055 | Active (Authentik SSO) |
| sabnzbd.woodhead.tech | 192.168.86.22 | 8080 | Active (Authentik SSO) |
| plex.woodhead.tech | 192.168.86.23 | 32400 | Active |
| jellyfin.woodhead.tech | 192.168.86.24 | 8096 | Active |
| nas.woodhead.tech | 192.168.86.40 | 443 | Active (Authentik SSO) |
| home.woodhead.tech | 192.168.86.41 | 8123 | Active |
| grafana.woodhead.tech | 192.168.86.25 | 3000 | Active |
| prometheus.woodhead.tech | 192.168.86.25 | 9090 | Active (Authentik SSO) |
| alertmanager.woodhead.tech | 192.168.86.25 | 9093 | Active |
| docs.woodhead.tech | 192.168.86.25 | 8081 | Active |
| resume.woodhead.tech | 192.168.86.25 | 8082 | Active |
| woodhead.tech / www.woodhead.tech | 192.168.86.25 | 8083 | Active |
| homelab.woodhead.tech | 192.168.86.25 | 8084 | Active |
| scanner.woodhead.tech | 192.168.86.32 | 3000 | Active (Authentik SSO) |
| auth.woodhead.tech | 192.168.86.28 | 9000 | Active |
| claw.woodhead.tech | 192.168.86.26 | 18789 | Active |
| alert.woodhead.tech | 192.168.86.27 | 8080 | Active |
| mail.woodhead.tech | 192.168.86.34 | 8080 | Active |
| tasks.woodhead.tech | 192.168.86.33 | 8000 | Active |
| ender5.woodhead.tech | 192.168.86.136 | 80 | Active |
| ender3.woodhead.tech | 192.168.86.138 | 80 | Active |
| traefik.woodhead.tech | localhost | -- | Active (Authentik SSO) |
| claude-os.woodhead.tech | 192.168.86.37 | 5173 | Active |
| claude-os-api.woodhead.tech | 192.168.86.37 | 8051 | Active |
| pwnagotchi.woodhead.tech | 192.168.86.38 | 8080 | Active |

## Terraform Resource Map

| Resource | File | Type | ID |
|---|---|---|---|
| `proxmox_virtual_environment_container.traefik` | lxc-traefik.tf | LXC | 200 |
| `proxmox_virtual_environment_container.recipe_site` | lxc-recipe-site.tf | LXC | 201 |
| `proxmox_virtual_environment_container.arr` | lxc-arr.tf | LXC | 202 |
| `proxmox_virtual_environment_container.plex` | lxc-plex.tf | LXC | 203 |
| `proxmox_virtual_environment_container.jellyfin` | lxc-jellyfin.tf | LXC | 204 |
| `proxmox_virtual_environment_container.monitoring` | lxc-monitoring.tf | LXC | 205 |
| `proxmox_virtual_environment_container.openclaw` | lxc-openclaw.tf | LXC | 206 |
| `proxmox_virtual_environment_container.authelia` | lxc-authelia.tf | LXC | 207 |
| `proxmox_virtual_environment_container.wireguard` | lxc-wireguard.tf | LXC | 208 |
| `proxmox_virtual_environment_container.libby_alert` | lxc-libby-alert.tf | LXC | 209 |
| `proxmox_virtual_environment_container.sdr` | lxc-sdr.tf | LXC | 210 |
| `proxmox_virtual_environment_container.kanboard` | lxc-kanboard.tf | LXC | 211 |
| `proxmox_virtual_environment_container.mailserver` | lxc-mailserver.tf | LXC | 212 |
| `proxmox_virtual_environment_container.pxe` | lxc-pxe.tf | LXC | 213 |
| `proxmox_virtual_environment_container.zigbee2mqtt` | lxc-zigbee2mqtt.tf | LXC | 214 |
| `proxmox_virtual_environment_container.claude_os` | lxc-claude-os.tf | LXC | 215 |
| `proxmox_virtual_environment_container.pwnagotchi` | lxc-pwnagotchi.tf | LXC | 216 |
| `proxmox_virtual_environment_vm.truenas` | vm-truenas.tf | VM | 300 |
| `proxmox_virtual_environment_vm.homeassistant` | vm-homeassistant.tf | VM | 301 |
| `proxmox_virtual_environment_vm.controlplane[*]` | control-plane.tf | VM | 400+ |
| `proxmox_virtual_environment_vm.worker[*]` | workers.tf | VM | 410+ |

**Provider:** [bpg/proxmox](https://registry.terraform.io/providers/bpg/proxmox-virtual-environment) ~0.66.0

## Service Group Management

Services are organized into logical groups that can be started and stopped as a unit. Node location is discovered at runtime via the Proxmox cluster API — no node is hardcoded.

| Group | VMIDs | RAM | Always On | Notes |
|---|---|---|---|---|
| `core` | 200 (traefik), 208 (wireguard) | ~512MB | Yes | Stop refused |
| `storage` | 300 (truenas) | ~16GB | Yes | Stop refused; required by `media` |
| `security` | 207 (authentik) | ~2GB | No | Required by `media`, `apps` |
| `home` | 301 (homeassistant), 214 (zigbee2mqtt), 209 (libby-alert) | ~2.7GB | No | |
| `media` | 202 (arr-stack), 203 (plex), 204 (jellyfin) | ~8GB | No | Depends on `core`, `storage` |
| `observability` | 205 (monitoring), 206 (openclaw) | ~4GB | No | |
| `apps` | 201 (recipe-site), 211 (kanboard), 215 (claude-os) | ~6.5GB | No | |
| `infra` | 212 (mailserver), 213 (pxe) | ~3.5GB | No | |
| `sdr` | 210 (sdr) | ~2GB | No | RTL-SDR USB passthrough |
| `special` | 216 (pwnagotchi) | ~1GB | No | Hardware-bound; excluded from bulk ops |
| `k8s` | 400 (talos-cp-0), 410 (worker-0), 411 (worker-1) | ~20GB | No | Drain workers before stop |

**Max potential savings:** ~42GB RAM when all non-`core`, non-`storage` groups are stopped.

### Usage

```bash
make group-status                 # Show live status of all groups
make group-start GROUP=<name>     # Start a group
make group-stop GROUP=<name>      # Stop a group
```

### Safety Rules

- **`always_on`** (`core`, `storage`) — stop is refused unconditionally
- **Dependency blocking** — stop is blocked if a dependent group is running; operator must stop dependents first, no cascading
- **Dependency warnings** — start emits a warning (non-blocking) if `depends_on` groups have stopped members
- **`hardware_bound`** (`special`) — excluded from bulk ops; manage individual members via `pct`/`qm` on the host node directly
- **K8s group** — workers are drained via `kubectl drain` before VMs stop; control plane starts first on start

:::note
Stop is never cascaded. `make group-stop GROUP=storage` will fail while `media` is running — stop `media` first, then `storage`.
:::

### Implementation

| File | Purpose |
|---|---|
| `ansible/vars/service_groups.yml` | Group definitions, dependency graph, `proxmox_node_map` |
| `ansible/playbooks/group-status.yml` | Read-only status query |
| `ansible/playbooks/group-start.yml` | Start with dependency warnings |
| `ansible/playbooks/group-stop.yml` | Stop with dependency blocking |

Node discovery uses `pvesh get /cluster/resources` on `pve1`. The `proxmox_node_map` in `service_groups.yml` translates Proxmox node hostnames (e.g., `thinkcentre2`) to Ansible inventory names (e.g., `pve2`).

## Backup Strategy

| What | Where | Method | Frequency |
|---|---|---|---|
| Proxmox VMs | TrueNAS /pool/backups | Proxmox backup job -> NFS | Weekly |
| Home Assistant | TrueNAS /pool/backups/ha | Built-in snapshots -> NFS | Daily |
| ARR stack configs | TrueNAS /pool/backups | Backup /opt/arr/ directory | Weekly |
| Traefik certs | Included in LXC backup | acme.json auto-renews if lost | -- |
| K8s state | etcd (on control plane disk) | Velero (future) | -- |
| Recipe site DB | Included in LXC backup | SQLite file in /opt/ | Weekly |

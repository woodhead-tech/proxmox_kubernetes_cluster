# Architecture

Comprehensive architecture reference for the woodhead.tech Proxmox homelab.
Covers network topology, service dependencies, traffic flow, storage, DNS/TLS,
and resource allocation.

## Table of Contents

- [Network Topology](#network-topology)
- [IP Address Allocation](#ip-address-allocation)
- [Traffic Flow: External](#traffic-flow-external)
- [Traffic Flow: Internal](#traffic-flow-internal)
- [DNS Resolution](#dns-resolution)
- [TLS Certificate Flow](#tls-certificate-flow)
- [Service Dependency Graph](#service-dependency-graph)
- [Boot Order](#boot-order)
- [Storage Architecture](#storage-architecture)
- [Resource Allocation](#resource-allocation)
- [Terraform Resource Map](#terraform-resource-map)
- [Traefik Routing Table](#traefik-routing-table)
- [ARR Stack Internal Architecture](#arr-stack-internal-architecture)
- [Kubernetes Cluster](#kubernetes-cluster)
- [VLAN Segmentation (Project Popeye)](#vlan-segmentation-project-popeye----in-progress)
- [Firewall Rules](#firewall-rules)
- [Backup Strategy](#backup-strategy)
- [Service Group Management](#service-group-management)

---

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
          +-------------------+-------------------+-------------------+-------------------+
          |                   |                   |                   |                   |
    +-----+------+    +------+------+    +-------+-------+    +-----+------+    +-------+------+
    | Proxmox    |    | Proxmox    |    | Proxmox       |    | Proxmox    |    | Proxmox      |
    | Node 1     |    | Node 2     |    | Node 3        |    | tower1     |    | zotac        |
    | 192.168.86 |    | 192.168.86 |    | 192.168.86    |    | 192.168.86 |    | 192.168.86   |
    | .29        |    | .30        |    | .31           |    | .130       |    | .147         |
    +-----+------+    +------+------+    +-------+-------+    +-----+------+    +-------+------+
          |                   |                   |                   |                   |
          +------------------ Ceph Storage Mesh (replication across nodes) -----------------+
          |
          |   +----- VMs + LXCs distributed across nodes -----+
          |   |                                                |
     +----+---+----+   +----------+   +----------+   +--------+---+
     | Traefik     |   | Recipe   |   | ARR      |   | K8s Cluster|
     | LXC 200     |   | Site     |   | Stack    |   |            |
     | .86.20      |   | LXC 201  |   | LXC 202  |   | CP: .101   |
     | :80 :443    |   | .21 :80  |   | .22      |   | W1: .111   |
     +------+------+   +----------+   +----------+   | W2: .112   |
            |                                         | VIP: .100  |
            |   +----------+   +----------+           +------------+
            |   | Plex     |   | Jellyfin |
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
            |   +----------+   +----------+
            |   | Kanboard |   | Mail-    |
            |   | LXC 211  |   | server   |
            |   | .33      |   | LXC 212  |
            |   | :8000    |   | .34      |
            |   +----------+   | :8080    |
            |                  | SMTP:25  |
            |                  +----------+
            |
          +------- Standalone Devices (not Proxmox-managed) -------+
          |                                                         |
     +----+----------+     +----------------+     +----------------+
     | Piboard       |     | Klipper        |     | Klipper        |
     | 192.168.86.131|     | Ender 5 Pro    |     | Ender 3        |  Raspberry Pi 3B
     | :8080         |     | 192.168.86.136 |     | 192.168.86.138 |  MainsailOS + Klipper
     | Waveshare 5"  |     | :80 :7125      |     | :80 :7125      |
     +---------------+     +----------------+     +----------------+
            |
    +-------+-------+
    | Traefik       |
    | Routes:       |
    |  recipes.*    +---> 192.168.86.21:80
    |  sonarr.*     +---> 192.168.86.22:8989
    |  radarr.*     +---> 192.168.86.22:7878
    |  prowlarr.*   +---> 192.168.86.22:9696
    |  bazarr.*     +---> 192.168.86.22:6767
    |  requests.*   +---> 192.168.86.22:5055
    |  sabnzbd.*    +---> 192.168.86.22:8080
    |  whisparr.*   +---> 192.168.86.22:6969
    |  qbittorrent.*+--> 192.168.86.22:8090
    |  flaresolverr.+--> 192.168.86.22:8191
    |  nas.*        +---> 192.168.86.40:443
    |  home.*       +---> 192.168.86.41:8123
    |  claw.*       +---> 192.168.86.26:18789
    |  alert.*      +---> 192.168.86.27:80
    |  auth.*       +---> 192.168.86.28:9091
    |  grafana.*    +---> 192.168.86.25:3000
    |  prometheus.* +---> 192.168.86.25:9090
    |  scanner.*    +---> 192.168.86.32:3000
    |  tasks.*      +---> 192.168.86.33:8000
    |  mail.*       +---> 192.168.86.34:8080
    |  docs.*       +---> 192.168.86.25:3080
    |  consulting.* +---> 192.168.86.25:8085
    |  ender3.*     +---> 192.168.86.138:80
    |  traefik.*    +---> dashboard (local)
    +---------------+
```

---

## IP Address Allocation

| IP              | Hostname         | Type   | VM ID | Purpose                             |
|-----------------|------------------|--------|-------|-------------------------------------|
| 192.168.86.1        | nest-gateway     | Router | --    | Google Nest WiFi Pro (NAT, DHCP, DNS)|
| 192.168.86.29      | pve1             | Host   | --    | Proxmox node 1                      |
| 192.168.86.30      | pve2             | Host   | --    | Proxmox node 2                      |
| 192.168.86.31      | pve3             | Host   | --    | Proxmox node 3 (optional)           |
| 192.168.86.130     | tower1           | Host   | --    | Proxmox node 4 (tower)              |
| 192.168.86.147     | zotac            | Host   | --    | Proxmox node 5 (Zotac mini PC)      |
| 192.168.86.20      | traefik          | LXC    | 200   | Reverse proxy, TLS termination      |
| 192.168.86.35      | adguard          | LXC    | 221   | AdGuard Home DNS + ad blocking      |
| 192.168.86.21      | recipe-site      | LXC    | 201   | Go + SQLite recipe app              |
| 192.168.86.22      | arr-stack        | LXC    | 202   | Docker: Sonarr, Radarr, etc.        |
| 192.168.86.23      | plex             | LXC    | 203   | Plex Media Server + iGPU            |
| 192.168.86.24      | (free)           | --     | --    | was jellyfin (decommissioned)       |
| 192.168.86.25      | monitoring       | LXC    | 205   | Prometheus, Grafana, Alertmanager, Healer (auto-remediation) |
| 192.168.86.26      | (free)           | --     | --    | was openclaw (decommissioned)       |
| 192.168.86.27      | libby-alert      | LXC    | 209   | Libby life alert QR site + alerts   |
| 192.168.86.28      | authentik        | LXC    | 207   | Identity provider (Authentik SSO, OIDC)    |
| 192.168.86.33      | kanboard         | LXC    | 211   | Kanboard task queue                 |
| 192.168.86.34      | mailserver       | LXC    | 212   | Mailcow email (woodhead.tech)       |
| 192.168.86.36      | step-ca          | LXC    | 222   | Step-CA SSH certificate authority   |
| 192.168.86.37      | claude-os        | LXC    | 215   | Claude OS AI memory system (paused) |
| 192.168.86.38      | pwnagotchi       | LXC    | 216   | Pwnagotchi WiFi (on pve3)           |
| 192.168.86.39      | wireguard        | LXC    | 208   | WireGuard VPN (wg0 remote + wg1 ShopStack) |
| 192.168.86.40      | truenas          | VM     | 300   | NAS, ZFS, NFS/SMB (direct SATA passthrough on tower1) |
| 192.168.86.41      | homeassistant    | VM     | 301   | Home Assistant OS + Zigbee2MQTT     |
| 192.168.86.42      | (free)           | --     | --    | was ollama (decommissioned — iGPU too slow) |
| 192.168.86.43      | (free)           | --     | --    | was unifi (decommissioned)          |
| 192.168.86.44      | zigbee2mqtt      | LXC    | 214   | Zigbee2MQTT + Mosquitto (on zotac)  |
| 192.168.86.45      | hermes           | LXC    | 224   | Hermes AI agent (Discord gateway, claude-opus-4-6) |
| 192.168.86.46      | tv-kiosk         | LXC    | 225   | Kodi media center (living room TV, on zotac, /dev/dri passthrough) |
| 192.168.86.47      | guacamole        | LXC    | 219   | Apache Guacamole browser-based RDP  |
| 192.168.86.48      | claude-code      | LXC    | 220   | Claude Code + ttyd web terminal (claude.woodhead.tech) |
| 192.168.86.49      | pbs              | LXC    | 223   | Proxmox Backup Server (pbs-tc3 datastore) |
| 192.168.86.131     | piboard          | Pi     | --    | Raspberry Pi 3B monitoring dashboard|
| 192.168.86.136     | klipper-ender5pro| Pi     | --    | Klipper 3D printer (Ender 5 Pro)    |
| 192.168.86.137     | ubuntu-laptop    | Client | --    | Ubuntu laptop (workstation)         |
| 192.168.86.138     | klipper-ender3   | Pi     | --    | Klipper 3D printer (Ender 3)        |
| 192.168.86.173     | cachy            | Client | --    | Lenovo Legion Go (CachyOS/KDE, primary dev machine) |
| 192.168.86.100     | k8s-vip          | VIP    | --    | Kubernetes API endpoint             |
| 192.168.86.101     | talos-cp-0       | VM     | 400   | K8s control plane (tower1)          |
| 192.168.86.111     | talos-worker-0   | VM     | 410   | K8s worker (tower1)                 |
| 192.168.86.112     | talos-worker-1   | VM     | 411   | K8s worker (thinkcentre3)           |
| 192.168.86.113     | talos-worker-2   | VM     | 412   | K8s worker (zotac)                  |
| 192.168.86.150-199 | metallb-pool     | K8s    | --    | MetalLB LoadBalancer IPs            |
| 192.168.86.200-254 | dhcp-pool        | DHCP   | --    | Dynamic client addresses            |

---

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

Configure via Google Home app > WiFi > Settings > Advanced Networking > Port Management.

| WAN Port | Destination           | Protocol | Purpose               |
|----------|-----------------------|----------|-----------------------|
| 80       | 192.168.86.20:80      | TCP      | HTTP -> Traefik       |
| 443      | 192.168.86.20:443     | TCP      | HTTPS -> Traefik      |
| 51820    | 192.168.86.39:51820   | UDP      | WireGuard VPN tunnel  |
| 25       | 192.168.86.34:25      | TCP      | SMTP inbound -> Mailcow |
| 465      | 192.168.86.34:465     | TCP      | SMTPS -> Mailcow      |
| 587      | 192.168.86.34:587     | TCP      | SMTP Submission -> Mailcow |
| 993      | 192.168.86.34:993     | TCP      | IMAPS -> Mailcow      |

---

## Traffic Flow: Internal

Internal clients resolve `*.woodhead.tech` via AdGuard Home (`192.168.86.35`),
which has split-horizon DNS rewrites: `*.woodhead.tech` and `woodhead.tech`
resolve directly to Traefik (`192.168.86.20`) without leaving the LAN.

```
1. CLIENT (192.168.86.x)   DNS query: recipes.woodhead.tech
       |
       v
2. GOOGLE NEST DNS          Forwards to AdGuard (192.168.86.35)
       |
       v
3. ADGUARD HOME             Rewrite: *.woodhead.tech -> 192.168.86.20
       |                   (split-horizon; no WAN roundtrip)
       v
4. CLIENT                  Connects directly to 192.168.86.20:443
       |
       v
5. TRAEFIK (192.168.86.20) Terminates TLS, routes to backend
       |
       v
6. RECIPE SITE (192.168.86.21) Responds directly on LAN
```

Split-horizon rewrites live in `/opt/adguardhome/data/AdGuardHome.yaml`
under `filtering.rewrites`. Internal services remain reachable during
internet outages (DNS resolves locally; TLS certs are cached by Traefik).

---

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
                    | Google Nest DNS   |  Forwards all queries to AdGuard
                    |  (192.168.86.1:53)|
                    +--------+----------+
                             |
                    +--------v----------+
                    | AdGuard Home      |  Split-horizon rewrites:
                    | (192.168.86.35)   |  *.woodhead.tech -> 192.168.86.20
                    |                   |  Upstream: Cloudflare + Google DoH
                    |                   |  (for non-rewritten queries)
                    +-------------------+
```

**DNS record management:**
- **Registrar:** Squarespace (nameservers pointed to Cloudflare)
- **Authoritative DNS:** Cloudflare (free tier)
- **DDNS updates:** Cron script on Proxmox node (every 5 min)
- **Internal resolution:** AdGuard split-horizon rewrites `*.woodhead.tech` to `192.168.86.20` (Traefik)
- **AdGuard upstreams:** `https://dns.cloudflare.com/dns-query` + `https://dns.google/dns-query` (DoH)

---

## TLS Certificate Flow

Traefik handles all TLS termination using Let's Encrypt certificates
obtained via Cloudflare DNS-01 challenges.

```
1. TRAEFIK detects new route requiring TLS
       |
       v
2. Requests cert from LET'S ENCRYPT
       |  Challenge type: DNS-01
       |  Resolver: "cloudflare"
       v
3. TRAEFIK creates TXT record via CLOUDFLARE API
       |  _acme-challenge.woodhead.tech = <token>
       |  Uses CF_DNS_API_TOKEN from environment
       v
4. LET'S ENCRYPT validates TXT record
       |  Queries public resolvers (1.1.1.1, 8.8.8.8)
       |  Verifies domain ownership
       v
5. Certificate issued
       |  Wildcard: *.woodhead.tech
       |  Stored: /etc/traefik/acme.json (0600)
       |  Auto-renewal: 30 days before expiry
       v
6. TRAEFIK applies cert to all matching routes
       |  Hot-reload, no restart needed
```

**Why DNS-01?**
- Supports wildcard certs (`*.woodhead.tech`) -- one cert for all subdomains
- Works before port forwarding is configured
- Works with internal-only IPs (no HTTP validation needed)
- Cloudflare free tier supports it

---

## Service Dependency Graph

```
    Google Nest WiFi Pro (192.168.86.1)
    Router, NAT, DHCP, DNS, WiFi
    (physical device, not managed by Proxmox)
              |
              +-- 192.168.86.0/24 (flat LAN)
              |
    +---------+---------+--------------+
    |         |         |              |
    v         v         v              v
+--------+ +--------+ +----------+ +--------+
|TrueNAS | |Traefik | |K8s       | |Home    |
|(storage)| |(routing)| |Cluster  | |Asst    |
+---+----+ +---+----+ +----+-----+ +--------+
    |          |            |
    |   +------+------+    |
    |   |      |      |    |
    v   v      v      v    v
+-------+-+ +------+ +----------+
|ARR Stack| |Recipe| |K8s Pods  |
|(media)  | |Site  | |(future)  |
+----+----+ +------+ +----------+
     |
+----v-----------+
| Monitoring     |  Scrapes all services via
| (Prometheus)   |  PVE Exporter, Blackbox,
| (observes all) |  Traefik metrics, K8s exporters
|                |  Alerts -> Discord via Alertmanager
+-------+--------+
        |
        | Prometheus API (/api/v1/query)
        |
+-------v--------+
| Piboard        |  Raspberry Pi 3B (standalone)
| (dashboard)    |  Polls Prometheus every 20s
| 192.168.86.131 |  SSE -> Chromium kiosk (localhost)
+----------------+
     |
NFS mount (/media, read-write)
     |
+----v-------+ +------------+
| Plex       | | Jellyfin   |
| (media)    | | (media)    |
+------------+ +------------+
     |              |
NFS mount (/media, read-only)
```

**Hard dependencies (service won't function without):**
- All services -> Google Nest gateway (routing, DHCP, DNS)
- All external access -> Traefik (TLS, routing)
- Protected services -> Authentik (forwardAuth SSO, OIDC)
- Remote VPN access -> WireGuard (UDP 51820 port forward required)
- ARR stack media storage -> TrueNAS (NFS at `/media`)
- Plex/Jellyfin media library -> TrueNAS (NFS at `/media`, read-only)
- Plex/Jellyfin transcoding -> iGPU (`/dev/dri` passthrough from Proxmox host)

**Soft dependencies (service works but with reduced functionality):**
- ARR stack without TrueNAS: uses local `/media` directory (no NAS)
- Plex/Jellyfin without TrueNAS: no media to serve
- Plex/Jellyfin without iGPU: falls back to software transcoding (CPU-heavy)
- Protected services without Authentik: accessible via direct IP:port only (Traefik blocks)
- Services without Traefik: accessible via direct IP:port (no TLS, no subdomain)
- K8s without MetalLB: ClusterIP services only (no external access)
- Monitoring without PVE token: Proxmox metrics unavailable (all other scrapes still work)
- Monitoring without Discord webhook: alerts fire but no notifications sent
- Monitoring without Dexcom credentials: glucose exporter starts but can't poll API
- Monitoring without Twilio credentials: glucose SMS alerts silently fail
- Monitoring without K8s manifests: K8s metrics unavailable (deploy kube-state-metrics later)
- Piboard without Prometheus: dashboard shows "connection lost" overlay (reconnects via SSE)
- Piboard without Blackbox Exporter: service tiles show unknown status (Prometheus still reachable)

---

## Boot Order

Proxmox starts VMs in this order after a host reboot. LXC containers start
in parallel after the host is ready.

| Order | Service              | VM ID | Delay  | Why                                        |
|-------|----------------------|-------|--------|--------------------------------------------|
| 1     | TrueNAS              | 300   | 30s    | NFS shares must be ready before consumers   |
| 2     | Home Assistant       | 301   | 15s    | Smart home should always be running         |
| auto  | Traefik LXC          | 200   | --     | Starts on boot, no ordering constraint      |
| auto  | Recipe Site LXC      | 201   | --     | Starts on boot                              |
| auto  | ARR Stack LXC        | 202   | --     | Starts on boot, NFS mount may retry         |
| auto  | Plex LXC             | 203   | --     | Starts on boot, iGPU node pinned            |
| auto  | Jellyfin LXC         | 204   | --     | Starts on boot, iGPU node pinned            |
| auto  | Monitoring LXC       | 205   | --     | Starts on boot, scrapes all services        |
| auto  | OpenClaw LXC         | 206   | --     | Starts on boot, AI agent framework          |
| auto  | Authentik LXC        | 207   | --     | Starts on boot, SSO gateway                 |
| auto  | WireGuard LXC        | 208   | --     | Starts on boot, VPN tunnel                  |
| auto  | Libby Alert LXC      | 209   | --     | Starts on boot, Go web app + alert service  |
| auto  | SDR Scanner LXC      | 210   | --     | Starts on boot, privileged, RTL-SDR USB     |
| auto  | Kanboard LXC         | 211   | --     | Starts on boot, task queue for ClawBot      |
| auto  | Mailserver LXC       | 212   | --     | Starts on boot, Mailcow email stack         |
| auto  | AdGuard LXC          | 213   | --     | Starts on boot, AdGuard Home DNS + blocking |
| auto  | Zigbee2MQTT LXC      | 214   | --     | Starts on boot, Zigbee bridge (on zotac)    |
| auto  | Step-CA LXC          | --    | --     | Starts on boot, SSH certificate authority   |
| auto  | UniFi LXC            | --    | --     | Starts on boot, UniFi Network Application   |
| auto  | Claude OS LXC        | 215   | --     | Starts on boot, AI memory system            |
| auto  | Pwnagotchi LXC       | 216   | --     | Starts on boot, USB WiFi dongle (on pve3)   |
| auto  | Ollama LXC           | 217   | --     | Starts on boot, local LLM inference (iGPU)  |
| auto  | Guacamole LXC        | 219   | --     | Starts on boot, browser-based RDP gateway   |
| auto  | Dev Desktop LXC      | 220   | --     | Starts on boot, Claude Code + ttyd web terminal |
| auto  | TV Kiosk LXC         | 225   | --     | Starts on boot, Kodi media center (living room TV) |
| manual| K8s Cluster          | 400+  | --     | Bootstrapped via `make bootstrap`           |

---

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
|  |          |  |          |  |  through)|  |  through) | |
|  +----+-----+  +----+-----+  +----+-----+  +----+-----+ |
|       |              |              |              |      |
+-------+--------------+--------------+--------------+------+
        |              |              |              |
   +----v----+    +----v----+    +----v--------------v----+
   |local-lvm|    |ceph-pool|    |  TrueNAS ZFS Pool     |
   |         |    |         |    |  (mirror or RAIDZ1)    |
   | TrueNAS |    | K8s CP  |    |                        |
   |  (OS)   |    | K8s     |    |  pool/media            |
   |   (OS)  |    | Workers |    |   +-- downloads/       |
   | HAOS    |    |         |    |   +-- movies/          |
   | Traefik |    |         |    |   +-- tv/              |
   | Recipe  |    |         |    |   +-- music/           |
   | ARR     |    |         |    |   +-- books/           |
   +---------+    +---------+    |                        |
                                 |  pool/backups          |
                                 |   +-- proxmox/         |
                                 |   +-- homeassistant/   |
                                 +------------------------+
```

**Storage assignments:**

| Storage      | Type       | Used By                                        |
|--------------|------------|-------------------------------------------------|
| local-lvm    | LVM (SSD)  | TrueNAS OS, HAOS, all LXC disks                 |
| ceph-pool    | Ceph (3x)  | K8s control plane, K8s workers                  |
| Passthrough  | Physical   | TrueNAS ZFS data pool (via `qm set -scsi1`)    |

**NFS exports (TrueNAS -> LAN):**

| Export Path            | Mount Point  | Consumer        | Access    |
|------------------------|--------------|-----------------|-----------|
| /mnt/pool/media        | /media       | ARR Stack LXC   | Read/write|
| /mnt/pool/media        | /media       | Plex LXC        | Read-only |
| /mnt/pool/media        | /media       | Jellyfin LXC    | Read-only |
| /mnt/pool/backups      | --           | Proxmox, HA     | Read/write|

---

## Resource Allocation

### CPU & Memory

| Service           | Cores | RAM (MB) | CPU Type | Notes                          |
|-------------------|-------|----------|----------|--------------------------------|
| TrueNAS           | 4     | 8192     | host     | ZFS ARC cache (~1GB per TB)     |
| Home Assistant    | 2     | 2048     | host     | USB passthrough support         |
| K8s Control Plane | 2     | 4096     | x86-64   | Per node, default 1 node        |
| K8s Workers       | 4     | 8192     | x86-64   | Per node, default 2 nodes       |
| Traefik LXC       | 1     | 256      | --       | Lightweight reverse proxy       |
| Recipe Site LXC   | 1     | 2048     | --       | Go binary + SQLite (2GB for Go compilation) |
| Plex LXC          | 2     | 2048     | --       | iGPU passthrough for Quick Sync |
| Jellyfin LXC      | 2     | 2048     | --       | iGPU passthrough for VAAPI      |
| Monitoring LXC    | 2     | 2048     | --       | Prometheus, Grafana, exporters  |
| OpenClaw LXC      | 2     | 2048     | --       | AI agent gateway + CLI          |
| Authentik LXC     | 2     | 2048     | --       | Identity provider (Postgres + Redis + server + worker)|
| WireGuard LXC     | 1     | 256      | --       | Kernel WireGuard, privileged LXC|
| Libby Alert LXC   | 1     | 512      | --       | Docker: Go web server, SMS/Discord alerts|
| SDR Scanner LXC   | 2     | 2048     | --       | Trunk Recorder + rdio-scanner, privileged (USB) |
| Kanboard LXC      | 1     | 512      | --       | PHP + SQLite (lightweight)      |
| Mailserver LXC    | 2     | 3072     | --       | Mailcow stack (Postfix, Dovecot, Rspamd, MariaDB) |
| ARR Stack LXC     | 2     | 4096     | --       | 7 Docker containers             |
| Ollama LXC        | 4     | 8192     | --       | Local LLM inference, iGPU passthrough (thinkcentre1) |

### Disk

| Service           | Size   | Storage     | Format    | Notes                       |
|-------------------|--------|-------------|-----------|-----------------------------|
| TrueNAS (OS)      | 16 GB  | local-lvm   | raw       | OS only                     |
| TrueNAS (data)    | varies | passthrough | ZFS       | Physical disks for pool     |
| Home Assistant    | 32 GB  | local-lvm   | qcow2     | HAOS + addons + database    |
| K8s CP            | 50 GB  | ceph-pool   | raw       | etcd + system               |
| K8s Workers       | 100 GB | ceph-pool   | raw       | Container images + volumes  |
| Traefik LXC       | 4 GB   | local-lvm   | --        | Binary + certs + configs    |
| Recipe Site LXC   | 8 GB   | local-lvm   | --        | Go toolchain + app + SQLite DB |
| Plex LXC          | 8 GB   | local-lvm   | --        | Plex binary + DB (media on NAS) |
| Jellyfin LXC      | 8 GB   | local-lvm   | --        | Jellyfin binary + DB (media on NAS) |
| Monitoring LXC    | 20 GB  | local-lvm   | --        | Prometheus TSDB (30-day retention)  |
| OpenClaw LXC      | 20 GB  | local-lvm   | --        | Source build + Docker images + workspace |
| Authentik LXC     | 8 GB   | local-lvm   | --        | Docker + Postgres data + media + certs   |
| WireGuard LXC     | 2 GB   | local-lvm   | --        | WireGuard tools + configs                |
| Libby Alert LXC   | 8 GB   | local-lvm   | --        | Docker + Go binary + config              |
| SDR Scanner LXC   | 20 GB  | local-lvm   | --        | Docker + recordings + Trunk Recorder |
| Kanboard LXC      | 5 GB   | local-lvm   | --        | Docker + SQLite DB + attachments |
| Mailserver LXC    | 20 GB  | local-lvm   | --        | Docker + Mailcow + mailbox storage |
| ARR Stack LXC     | 20 GB  | local-lvm   | --        | Docker + configs (media on NAS) |
| Ollama LXC        | 40 GB  | local-lvm   | --        | Ollama binary + model storage (llama3 ~5GB) |

### Standalone Devices (not Proxmox-managed)

| Device            | Cores | RAM (MB) | Disk   | Notes                              |
|-------------------|-------|----------|--------|------------------------------------|
| Piboard (Pi 3B)   | 4     | 1024     | 32 GB  | Waveshare 5" HDMI, Chromium kiosk  |
| Klipper Ender 5 Pro (Pi 3B) | 4 | 1024 | 16 GB | MainsailOS, USB to printer MCU  |
| Klipper Ender 3 (Pi 3B) | 4 | 1024 | 16 GB | MainsailOS, USB to printer MCU    |
| Lenovo Legion Go  | --    | --       | --     | CachyOS; .173 (primary dev machine) |
| Ubuntu Laptop     | --    | --       | --     | Ubuntu 24.04; .137                  |
| UniHiker K10      | 1     | 512      | 8 GB   | House assistant (VAD + STT proxy → Ollama .42 → Claude API) |

### Total resource budget (all services running)

| Resource | Total       | Notes                                      |
|----------|-------------|--------------------------------------------|
| CPU      | ~31 cores   | Shared across Proxmox nodes                |
| RAM      | ~42.75 GB   | TrueNAS benefits from more (ZFS ARC)       |
| local-lvm| ~171 GB     | OS disks for VMs + all LXCs                |
| ceph-pool| ~250 GB raw | K8s VMs (3x replication = ~750 GB physical) |

### Resource Balancing

Each Proxmox node has 4 physical cores and 7.6 GB RAM (i5-7500T, no hyperthreading).
All nodes are overcommitted -- this works because most services idle, but concurrent
spikes cause swapping. Proxmox resource balancing mitigates this.

**Memory ballooning (VMs only):** The balloon driver lets Proxmox reclaim unused
RAM dynamically. Each VM has a ceiling (max RAM) and a floor (minimum guaranteed).
The hypervisor adjusts between them based on host memory pressure. LXC containers
don't support ballooning -- their memory is hard-limited by cgroups.

| VM | Ceiling | Floor (balloon) | Shares | Rationale |
|----|---------|-----------------|--------|-----------|
| TrueNAS | 8192 MB | 4096 MB | 1500 | ZFS ARC is greedy but elastic |
| K8s CP | 4096 MB | 2048 MB | 1200 | etcd + apiserver steady state ~1.5GB |
| K8s Workers | 8192 MB | 4096 MB | 1000 | Pod workloads vary |
| Home Assistant | 2048 MB | 1024 MB | 800 | Mostly idle automations |

> **Note:** The Shares column reflects target priority weights. Proxmox `shares`
> maps to the `ivshmem` parameter which requires `root@pam` authentication -- it
> cannot be set via Terraform with API token auth. Set manually if desired:
> `qm set <vmid> -shares <value>`

**CPU units (VMs + LXCs):** CFS scheduler weight for CPU time distribution under
contention. Higher weight = more CPU time when cores are contested. Idle services
consume no CPU regardless of weight.

| Service | Type | Units | Tier |
|---------|------|-------|------|
| Traefik | LXC | 2048 | Critical |
| TrueNAS | VM | 1500 | High |
| K8s CP | VM | 1200 | High |
| Authentik | LXC | 1200 | High |
| K8s Workers | VM | 1024 | Normal |
| ARR, Plex, Jellyfin | LXC | 1024 | Normal |
| Monitoring, OpenClaw | LXC | 800 | Low |
| Home Assistant | VM | 800 | Low |
| Recipe Site, WireGuard, Libby Alert | LXC | 512 | Minimal |

**Per-node overcommit ratios:**

| Node | Allocated Cores | Allocated RAM | Physical | Overcommit |
|------|----------------|---------------|----------|------------|
| thinkcentre1 | 12 | ~16 GB | 4c / 7.6G | 3x CPU, 2.1x RAM |
| thinkcentre2 | 10 | ~16 GB | 4c / 7.6G | 2.5x CPU, 2.1x RAM |
| thinkcentre3 | 8 | ~12 GB | 4c / 7.6G | 2x CPU, 1.6x RAM |

---

## Terraform Resource Map

| Resource                                          | File                        | Type | ID  |
|---------------------------------------------------|-----------------------------|------|-----|
| `proxmox_virtual_environment_container.traefik`   | lxc-traefik.tf              | LXC  | 200 |
| `proxmox_virtual_environment_container.recipe_site`| lxc-recipe-site.tf         | LXC  | 201 |
| `proxmox_virtual_environment_container.arr`       | lxc-arr.tf                  | LXC  | 202 |
| `proxmox_virtual_environment_container.plex`      | lxc-plex.tf                 | LXC  | 203 |
| `proxmox_virtual_environment_container.jellyfin`  | lxc-jellyfin.tf             | LXC  | 204 |
| `proxmox_virtual_environment_container.monitoring`| lxc-monitoring.tf           | LXC  | 205 |
| `proxmox_virtual_environment_container.openclaw`  | lxc-openclaw.tf             | LXC  | 206 |
| `proxmox_virtual_environment_container.authelia`  | lxc-authelia.tf (authentik stack) | LXC  | 207 |
| `proxmox_virtual_environment_container.wireguard` | lxc-wireguard.tf            | LXC  | 208 |
| `proxmox_virtual_environment_container.libby_alert`| lxc-libby-alert.tf         | LXC  | 209 |
| `proxmox_virtual_environment_container.sdr`       | lxc-sdr.tf                  | LXC  | 210 |
| `proxmox_virtual_environment_container.kanboard`  | lxc-kanboard.tf             | LXC  | 211 |
| `proxmox_virtual_environment_container.mailserver` | lxc-mailserver.tf          | LXC  | 212 |
| `proxmox_virtual_environment_container.ollama`    | lxc-ollama.tf               | LXC  | 217 |
| `proxmox_virtual_environment_container.guacamole` | lxc-guacamole.tf            | LXC  | 219 |
| `proxmox_virtual_environment_container.dev_desktop`| lxc-dev-desktop.tf         | LXC  | 220 |
| `proxmox_virtual_environment_file.lxc_ssh_fix`    | lxc-ssh-hook.tf             | File | --  |
| `proxmox_virtual_environment_vm.truenas`          | vm-truenas.tf               | VM   | 300 |
| `proxmox_virtual_environment_vm.homeassistant`    | vm-homeassistant.tf         | VM   | 301 |
| `proxmox_virtual_environment_download_file.haos_image` | vm-homeassistant.tf    | File | --  |
| `proxmox_virtual_environment_vm.controlplane[*]`  | control-plane.tf           | VM   | 400+|
| `proxmox_virtual_environment_vm.worker[*]`        | workers.tf                 | VM   | 410+|

**Provider:** [bpg/proxmox](https://registry.terraform.io/providers/bpg/proxmox-virtual-environment) ~0.66.0

**Variable files:**
- `variables.tf` -- Proxmox connection, network, K8s cluster sizing
- `lxc-variables.tf` -- LXC storage, SSH key, per-service IPs/VMIDs
- `vm-truenas-variables.tf` -- TrueNAS ISO, sizing
- `vm-homeassistant-variables.tf` -- HAOS image URL, sizing

**Terraform state notes:**
- Terraform state (`terraform.tfstate`) is gitignored. In state: traefik, recipe_site, authelia, wireguard, libby_alert, sdr, zigbee2mqtt, claude_os, pwnagotchi, ollama, lxc_ssh_fix.
- Not in state (VM disk import hangs): truenas (300), homeassistant (301), controlplane (400), K8s workers (410–412). Use `-target` for LXC-only applies.
- Not in state (deployed manually or pre-terraform): arr (202), plex (203), jellyfin (204), monitoring (205), openclaw (206), kanboard (211), mailserver (212), pxe (213).

**Hookscript restriction:**
The `lxc-ssh-hook.tf` snippet uploads to Proxmox as a file resource. Wiring it as a hookscript on an LXC (`hook_script_file_id`) requires `root@pam` authentication — the Terraform API token (non-root) gets a 403. Set hookscripts manually via SSH: `pct set <vmid> --hookscript local:snippets/lxc-ssh-fix.sh`.

---

## Traefik Routing Table

All routes terminate TLS at Traefik and proxy plaintext HTTP to backends.
Certificates are wildcard (`*.woodhead.tech`) via Let's Encrypt DNS-01.

| Subdomain              | Backend              | Port  | Config File           | Status    |
|------------------------|----------------------|-------|-----------------------|-----------|
| recipes.woodhead.tech  | 192.168.86.21        | 80    | recipe-site.yml       | Active    |
| prowlarr.woodhead.tech | 192.168.86.22        | 9696  | arr-stack.yml         | Active (Authentik SSO) |
| sonarr.woodhead.tech   | 192.168.86.22        | 8989  | arr-stack.yml         | Active (Authentik SSO) |
| radarr.woodhead.tech   | 192.168.86.22        | 7878  | arr-stack.yml         | Active (Authentik SSO) |
| bazarr.woodhead.tech   | 192.168.86.22        | 6767  | arr-stack.yml         | Active (Authentik SSO) |
| requests.woodhead.tech | 192.168.86.22        | 5055  | arr-stack.yml         | Active (Authentik SSO) |
| sabnzbd.woodhead.tech  | 192.168.86.22        | 8080  | arr-stack.yml         | Active (Authentik SSO) |
| whisparr.woodhead.tech | 192.168.86.22        | 6969  | arr-stack.yml         | Active (Authentik SSO) |
| qbittorrent.woodhead.tech | 192.168.86.22     | 8090  | arr-stack.yml         | Active (Authentik SSO) |
| flaresolverr.woodhead.tech | 192.168.86.22    | 8191  | arr-stack.yml         | Active (Authentik SSO) |
| plex.woodhead.tech     | 192.168.86.23        | 32400 | media-stack.yml       | Active    |
| jellyfin.woodhead.tech | 192.168.86.24        | 8096  | media-stack.yml       | Active    |
| nas.woodhead.tech      | 192.168.86.40        | 443   | media-stack.yml       | Active (Authentik SSO) |
| home.woodhead.tech     | 192.168.86.41        | 8123  | homeassistant.yml     | Active    |
| grafana.woodhead.tech  | 192.168.86.25        | 3000  | monitoring.yml        | Active    |
| prometheus.woodhead.tech| 192.168.86.25       | 9090  | monitoring.yml        | Active (Authentik SSO) |
| alertmanager.woodhead.tech| 192.168.86.25     | 9093  | monitoring.yml        | Active (Authentik SSO) |
| claw.woodhead.tech     | 192.168.86.26        | 18789 | openclaw.yml          | Active    |
| alert.woodhead.tech    | 192.168.86.27        | 80    | libby-alert.yml       | Active    |
| auth.woodhead.tech     | 192.168.86.28        | 9000  | authentik.yml         | Active    |
| ender5.woodhead.tech   | 192.168.86.136       | 80    | klipper.yml           | Active    |
| ender3.woodhead.tech   | 192.168.86.138       | 80    | klipper.yml           | Active    |
| scanner.woodhead.tech  | 192.168.86.32        | 3000  | sdr.yml               | Active (Authentik SSO) |
| tasks.woodhead.tech    | 192.168.86.33        | 8000  | kanboard.yml          | Active    |
| mail.woodhead.tech     | 192.168.86.34        | 8080  | mailserver.yml        | Active    |
| docs.woodhead.tech     | 192.168.86.25        | 3080  | docs-site.yml         | Active (Authentik SSO) |
| resume.woodhead.tech   | 192.168.86.25        | 3081  | resume-site.yml       | Active (Authentik SSO) |
| consulting.woodhead.tech | 192.168.86.25      | 8085  | consulting-site.yml   | Active    |
| adguard.woodhead.tech  | 192.168.86.35        | 80    | adguard.yml           | Active (Authentik SSO) |
| proxmox.woodhead.tech  | 192.168.86.29        | 8006  | proxmox.yml           | Active (Authentik SSO) |
| traefik.woodhead.tech  | localhost (dashboard) | --    | dashboard.yml         | Active (Authentik SSO) |
| guac.woodhead.tech     | 192.168.86.47        | 8080  | guacamole.yml         | Active (Authentik SSO) |
| alertmind.woodhead.tech| 192.168.86.25        | 8086  | alertmind.yml         | Active (Authentik SSO) |
| step-ca.woodhead.tech  | 192.168.86.36        | 9000  | step-ca.yml           | Active (HTTPS passthrough, no SSO) |
| ollama.woodhead.tech   | 192.168.86.42        | 11434 | ollama.yml            | Active (Authentik SSO) |
| claude-os.woodhead.tech| 192.168.86.37        | 5173  | claude-os.yml         | Active    |
| claude-os-api.woodhead.tech | 192.168.86.37   | 8051  | claude-os.yml         | Active    |
| unifi.woodhead.tech    | 192.168.86.43        | 8443  | unifi.yml             | Active (Authentik SSO) |
| lab.woodhead.tech      | 192.168.86.25        | 8083  | landing-site.yml      | Active    |
| homelab.woodhead.tech  | 192.168.86.25        | 8084  | homelab-site.yml      | Active    |
| v2mom.woodhead.tech    | 192.168.86.25        | 8087  | v2mom.yml             | Active (Authentik SSO) |
| skypups.woodhead.tech  | 192.168.86.25        | 8085  | skypups.yml           | Active (Authentik SSO, demo) |
| *.woodhead.tech        | K8s VIP (192.168.86.100) | 80 | k8s-ingress.yml      | Commented |

Routes are in `ansible/files/traefik/dynamic/`. Uncomment as you deploy each service.
Traefik watches the directory and hot-reloads -- no restart needed.

---

## ARR Stack Internal Architecture

All ARR services run as Docker containers inside a single LXC (192.168.86.22).
They communicate via Docker's internal DNS (container names).

```
+-- ARR Stack LXC (192.168.86.22) ----------------------------------------+
|                                                                           |
|  Docker Compose Network (bridge)                                          |
|                                                                           |
|  +----------+  +---------+  +---------+  +---------+  +----------+      |
|  | Prowlarr |  | Sonarr  |  | Radarr  |  | Bazarr  |  | Whisparr |      |
|  | :9696    |  | :8989   |  | :7878   |  | :6767   |  | :6969    |      |
|  +----+-----+  +----+----+  +----+----+  +----+----+  +----+-----+      |
|       |              |            |            |             |            |
|       +--- Prowlarr syncs indexers to Sonarr/Radarr/Whisparr             |
|            Bazarr connects to Sonarr/Radarr for subtitles                 |
|                                                                           |
|  +-----------+   +-------------+                                          |
|  | Overseerr |   | FlareSolverr|  Cloudflare bypass proxy                 |
|  | :5055     |   | :8191       |  Used by Prowlarr for CF-protected        |
|  | request   |   |             |  indexers (e.g., XXXClub)                |
|  | portal    |   +-------------+                                          |
|  +-----------+                                                            |
|                                                                           |
|  +----------+     +----------+  +-------------+                          |
|  | Gluetun  |<--->| SABnzbd  |  | qBittorrent |                          |
|  | (VPN)    |     | :8080    |  | :8090       |  Both share Gluetun's    |
|  | :8080    |     |          |  |             |  network namespace.       |
|  | :8090    |     +----------+  +-------------+  All torrent + usenet    |
|  +----------+                                     traffic exits via VPN.  |
|       |                                                                   |
|       +--- PrivadoVPN WireGuard (WIREGUARD_ENDPOINT_IP=45.38.15.158)     |
|            Private key in /opt/arr/gluetun/wireguard_private_key (never  |
|            committed to git)                                              |
|                                                                           |
|  Shared volume: /media (NFS from TrueNAS 192.168.86.40)                 |
|  +----------------------------------------------------------+            |
|  | /media/downloads/complete    <-- SABnzbd/qBittorrent out  |            |
|  | /media/downloads/incomplete  <-- in-progress downloads    |            |
|  | /media/movies/               <-- Radarr library           |            |
|  | /media/tv/                   <-- Sonarr library           |            |
|  | /media/adult/                <-- Whisparr library         |            |
|  | /media/music/                <-- Lidarr (future)          |            |
|  | /media/books/                <-- Readarr (future)         |            |
|  +----------------------------------------------------------+            |
|                                                                           |
|  All containers run as PUID=1000, PGID=1000 (arrstack user)             |
|  LinuxServer.io images (except Whisparr: hotio), TZ=America/Chicago      |
+---------------------------------------------------------------------------+
```

**Service configuration order:**
1. Prowlarr -- Add indexers (Usenet + torrent); add FlareSolverr proxy for CF-protected indexers
2. SABnzbd -- Configure Usenet server credentials; add category `whisparr`
3. Sonarr -- Connect to Prowlarr + SABnzbd, add TV libraries
4. Radarr -- Connect to Prowlarr + SABnzbd, add movie libraries
5. Bazarr -- Connect to Sonarr + Radarr for subtitle downloads
6. Overseerr -- Connect to Sonarr + Radarr for user requests
7. Whisparr -- Connect to Prowlarr (fullSync), SABnzbd + qBittorrent; root folder `/media/adult`
8. Gluetun -- Configure VPN provider credentials (PrivadoVPN WireGuard)

---

## Kubernetes Cluster

Talos Linux is an immutable, API-driven Kubernetes OS. No SSH access --
all management is through `talosctl` and `kubectl`.

```
+-- Kubernetes Cluster (talos-proxmox) ---+
|                                          |
|  API VIP: 192.168.86.100:6443            |
|                                          |
|  +-- Control Plane (192.168.86.101) --+ |
|  |   Talos Linux v1.9.0               | |
|  |   etcd, kube-apiserver              | |
|  |   kube-scheduler, kube-controller   | |
|  |   2 cores, 4GB RAM, 50GB (Ceph)    | |
|  +------------------------------------+ |
|                                          |
|  +-- Worker 0 (192.168.86.111) -------+ |
|  |   Talos Linux v1.9.0               | |
|  |   kubelet, kube-proxy (tower1)     | |
|  |   4 cores, 8GB RAM, 100GB (Ceph)   | |
|  +------------------------------------+ |
|                                          |
|  +-- Worker 1 (192.168.86.112) -------+ |
|  |   (same as Worker 0, pve3)         | |
|  +------------------------------------+ |
|                                          |
|  +-- Worker 2 (192.168.86.113) -------+ |
|  |   (same as Worker 0, zotac)        | |
|  +------------------------------------+ |
|                                          |
|  Namespaces: ingress-system, apps,       |
|              monitoring, metallb-system   |
|                                          |
|  MetalLB: L2 mode                        |
|  IP Pool: 192.168.86.150 - 192.168.86.199|
|                                          |
+------------------------------------------+
```

**Scaling:** Update `terraform.tfvars` (counts + IPs), then `make apply && make bootstrap`.

---

## WiFi / Network Architecture

Google Nest WiFi Pro mesh serves as the network router and WiFi access point.
It handles NAT, DHCP, DNS forwarding, and WiFi for all clients.

```
ISP Modem/ONT
    |
    +-- Google Nest WiFi Pro (192.168.86.1)
            |  Router mode (default)
            |  NAT, DHCP, DNS forwarding, WiFi
            |
            +-- Primary unit (wired to ISP modem + switch)
            +-- Satellite(s) (wireless mesh backhaul)
            |
            +-- [Switch] -- Proxmox nodes, wired devices
            |
            WiFi + wired clients on 192.168.86.0/24
```

**Port forwarding**: Google Home app > WiFi > Settings > Advanced Networking >
Port Management. Forward 80/443 to Traefik LXC (192.168.86.20).

**DDNS**: Cloudflare DDNS script runs on a Proxmox node via cron (every 5 min).

**Limitation**: Google Nest does not support VLANs or multiple SSIDs per VLAN.
All clients land on the same flat 192.168.86.0/24 network. This is fine
for current use -- no services require VLAN segmentation to function.

---

## VLAN Segmentation (Project Popeye -- In Progress)

Network migration from flat 192.168.86.0/24 to segmented VLANs is underway.
Codename "Project Popeye" (named after the house).

**Status:** VLANs created on Dell X1026 switch. Awaiting OPNsense hardware
(Topton N100) and TP-Link Omada APs before cutting over.

### Hardware

| Component | Model | IP | Notes |
|-----------|-------|-----|-------|
| Managed Switch | Dell Networking X1026 | 192.168.86.210 | 24-port GbE, 802.1Q, mgmt via x1026 wrapper on tc1 |
| Firewall (planned) | Topton N100 4x 2.5GbE | TBD | OPNsense + Suricata IDS/IPS |
| AP - Basement | TP-Link EAP670 (planned) | TBD | WiFi 6, multi-SSID, near homelab rack |
| AP - 1st Floor | TP-Link EAP245 (planned) | TBD | Multi-SSID, wired via MoCA |
| AP - 3rd Floor | TP-Link EAP245 (planned) | TBD | Multi-SSID, wired via MoCA |
| AP - Garage | Google Nest (reuse) | TBD | Wireless bridge, IoT VLAN only |

### VLAN Design

| VLAN | Subnet | Purpose | SSID |
|------|--------|---------|------|
| 1 | 192.168.1.0/24 | Management (switch, APs, OPNsense) | -- (wired) |
| 10 | 192.168.10.0/24 | Trusted LAN (personal devices) | "Popeye" |
| 20 | 192.168.20.0/24 | Servers (Proxmox, LXCs, VMs, MetalLB) | -- (wired) |
| 30 | 192.168.30.0/24 | IoT (ESP32, 3D printers, Zigbee, smart devices) | "Popeye-IoT" |
| 40 | 192.168.40.0/24 | Guest WiFi | "Popeye-Guest" |
| 50 | 192.168.50.0/24 | DMZ (Traefik, Mailcow, WireGuard) | -- (wired) |
| 99 | 192.168.99.0/24 | Lab (pwnagotchi, offensive tools) | -- (wired) |

### Dell X1026 Port Map (Target)

| Port | Mode | VLANs Tagged | Untagged | Device |
|------|------|-------------|----------|--------|
| 1 | Trunk | 1,10,20,30,40,50,99 | 1 | OPNsense LAN |
| 2-5 | Trunk | 1,20 | 20 | Proxmox nodes (4x ThinkCentre) |
| 6 | Trunk | 1,20 | 20 | Proxmox node 5 (zotac) |
| 7 | Trunk | 1,10,30,40 | 1 | AP1 - Basement (EAP670) |
| 8 | Trunk | 1,10,30,40 | 1 | AP2 - 1st Floor (EAP245, via MoCA) |
| 9 | Trunk | 1,10,30,40 | 1 | AP3 - 3rd Floor (EAP245, via MoCA) |
| 10 | -- | -- | -- | (unused -- garage AP is wireless) |
| 11-12 | Access | -- | 20 | TrueNAS, Raspberry Pis |
| 13-14 | Access | -- | 10 | Wired workstations |
| 15 | Access | -- | 30 | Wired IoT |
| 16 | Access | -- | 99 | Pwnagotchi/Lab |
| 17-22 | Access | -- | 20 | Future servers / expansion |
| 23 | Access | -- | 1 | Management access (laptop) |
| 24 | Trunk | all | 1 | Mirror/debug uplink |

### Inter-VLAN Firewall Rules (OPNsense -- planned)

```
Trusted (10) ---> Servers (20)              ALLOW   (access Plex, Grafana, HA)
Trusted (10) ---> IoT (30)                  ALLOW   (manage 3D printers, ESP32)
IoT (30) -------> HA on Servers (20:8123)   ALLOW   (smart home control + MQTT)
IoT (30) -------> Internet                  ALLOW   (OTA updates, NTP)
IoT (30) -------> everything else           DENY    (isolate compromised devices)
Guest (40) -----> Internet                  ALLOW   (internet only)
Guest (40) -----> ALL RFC1918               DENY    (full isolation)
Lab (99) -------> Internet                  ALLOW   (updates)
Lab (99) -------> ALL RFC1918               DENY    (full isolation)
DMZ (50) -------> Internet                  ALLOW   (ACME, mail relay)
DMZ (50) -------> Servers (20)              ALLOW   (Traefik -> backends)
WAN ------------> DMZ (50)                  ALLOW   (HTTP/S, SMTP/IMAP, WireGuard)
```

### Physical Topology (House "Popeye")

130-year-old house, 3 floors + detached garage. MoCA backhaul between
basement, 1st floor (living room), and 3rd floor (attic).

- **Basement:** Homelab rack (Proxmox nodes, Dell X1026, OPNsense), MoCA endpoint
- **1st Floor:** Zotac (Zigbee hub), MoCA hub, EAP245 AP
- **3rd Floor (Attic):** Home office (Brandon), Ender's bedroom, MoCA endpoint, EAP245 AP
- **Garage (detached):** Motorcycle workshop, 3D print lab, Google Nest wireless bridge

### Migration Phases

| Phase | Description | Status |
|-------|-------------|--------|
| 0 | Prep: VLANs on switch, order hardware | **In Progress** |
| 1 | Parallel infrastructure: OPNsense + Omada APs alongside Nest | Pending |
| 2 | Service migration: move LXCs to VLAN 20 one at a time | Pending |
| 3 | Client migration: personal devices to new SSIDs | Pending |
| 4 | Cutover: disable Google Nest routing | Pending |
| 5 | Hardening: Suricata IPS, GeoIP blocking, CrowdSec | Pending |

---

## Firewall Rules

### Port Forwarding (Google Nest WiFi Pro -- current)

Configured via Google Home app. Will be replaced by OPNsense NAT rules in Phase 2.

| WAN Port | Destination | Protocol | Purpose |
|----------|-------------|----------|---------|
| 80 | 192.168.86.20:80 | TCP | HTTP -> Traefik |
| 443 | 192.168.86.20:443 | TCP | HTTPS -> Traefik |
| 51820 | 192.168.86.39:51820 | UDP | WireGuard VPN tunnel |
| 25 | 192.168.86.34:25 | TCP | SMTP inbound -> Mailcow |
| 465 | 192.168.86.34:465 | TCP | SMTPS -> Mailcow |
| 587 | 192.168.86.34:587 | TCP | SMTP Submission -> Mailcow |
| 993 | 192.168.86.34:993 | TCP | IMAPS -> Mailcow |

### IDS/IPS (OPNsense + Suricata -- planned)

- WAN interface: Inline IPS mode (ET Open ruleset)
- Inter-VLAN: IDS mode initially (log lateral movement, tune before blocking)
- GeoIP blocking on WAN inbound
- CrowdSec plugin for collaborative threat intelligence

---

## Backup Strategy

| What                | Where                        | Method                          | Frequency  |
|---------------------|------------------------------|---------------------------------|------------|
| Proxmox VMs         | TrueNAS /pool/backups        | Proxmox backup job -> NFS       | Weekly     |
| Home Assistant      | TrueNAS /pool/backups/ha     | Built-in snapshots -> NFS       | Daily      |
| ARR stack configs   | TrueNAS /pool/backups        | Backup /opt/arr/ directory      | Weekly     |
| Traefik certs       | Included in LXC backup       | acme.json auto-renews if lost   | --         |
| K8s state           | etcd (on control plane disk)  | Velero (future)                | --         |
| TrueNAS config      | TrueNAS self                 | Config export (JSON)            | After changes |
| Recipe site DB      | Included in LXC backup       | SQLite file in /opt/            | Weekly     |

**Offsite (recommended future):** Replicate TrueNAS backups to cloud storage
or rotate USB drives.

---

## Service Group Management

Services are organized into logical groups that can be started and stopped as a unit. Node location is discovered at runtime via the Proxmox cluster API — no node is hardcoded.

| Group | VMIDs | RAM | Always On | Notes |
|-------|-------|-----|-----------|-------|
| `core` | 200 (traefik), 208 (wireguard) | ~512MB | Yes | Stop refused |
| `storage` | 300 (truenas) | ~16GB | Yes | Stop refused; required by `media` |
| `security` | 207 (authentik) | ~2GB | No | Required by `media`, `apps` |
| `home` | 301 (homeassistant), 214 (zigbee2mqtt), 209 (libby-alert) | ~2.7GB | No | |
| `media` | 202 (arr-stack), 203 (plex), 204 (jellyfin) | ~8GB | No | Depends on `core`, `storage` |
| `observability` | 205 (monitoring) | ~4GB | No | Includes healer auto-remediation service |
| `apps` | 201 (recipe-site), 211 (kanboard), 215 (claude-os), 220 (claude-code), 224 (hermes), 225 (tv-kiosk) | ~18GB | No | |
| `infra` | 212 (mailserver), 213 (adguard) | ~3.5GB | No | |
| `sdr` | 210 (sdr) | ~2GB | No | RTL-SDR USB passthrough |
| `special` | 216 (pwnagotchi) | ~1GB | No | Hardware-bound; excluded from bulk ops |
| `k8s` | 400 (talos-cp-0), 410 (worker-0), 411 (worker-1), 412 (worker-2) | ~28GB | No | Drain workers before stop |

**Max potential savings:** ~42GB RAM when all non-`core`, non-`storage` groups are stopped.

### Usage

```bash
make group-status                   # Show live status of all groups
make group-start GROUP=<name>       # Start a group
make group-stop GROUP=<name>        # Stop a group
```

### Safety Rules

- **`always_on`** (`core`, `storage`) — stop is refused unconditionally
- **Dependency blocking** — stop is blocked if a dependent group is running (e.g., `make group-stop GROUP=storage` fails while `media` is running); operator must stop dependents first, no cascading
- **Dependency warnings** — start emits a warning (non-blocking) if `depends_on` groups have stopped members
- **`hardware_bound`** (`special`) — excluded from bulk ops; manage individual members via `pct`/`qm` on the host node directly
- **K8s group** — workers are drained via `kubectl drain --ignore-daemonsets --delete-emptydir-data` before VMs are shut down; control plane starts first on start

### Implementation Files

| File | Purpose |
|------|---------|
| `ansible/vars/service_groups.yml` | Group definitions: VMIDs, types, dependency graph, `proxmox_node_map` |
| `ansible/playbooks/group-status.yml` | Read-only status query against cluster API |
| `ansible/playbooks/group-start.yml` | Start group with dependency warnings |
| `ansible/playbooks/group-stop.yml` | Stop group with dependency blocking |

Node discovery queries `pvesh get /cluster/resources --type vm` on `pve1`. The `proxmox_node_map` in `service_groups.yml` translates Proxmox node hostnames (e.g., `thinkcentre2`) to Ansible inventory names (e.g., `pve2`).

---

## Operations Notes

### NAS Migration (in progress — 2026)

TrueNAS VM 300 at `192.168.86.40` is being migrated from a Ceph RBD-backed VM to
dedicated hardware. New machine: AM4 Ryzen 7 5700 build (arrived 2026-05-22).

**Current state:** TrueNAS still running as VM on tower1 (VMID 300, `.40`). During
hardware transit the NAS was temporarily reachable at `.149`; final IP stays `.40`
so no config changes are needed on consumers (arr-stack, Plex, Jellyfin, Proxmox backups).

**Post-migration cleanup:** Remove `osd.0` (Samsung 860 QVO SSD, thinkcentre1 — first to
go) and `osd.5` (Seagate ST2000DM008 SMR HDD, tower1) from Ceph cluster once NAS
data is on dedicated hardware and Ceph-backed TrueNAS disk is freed.

### Ceph Phase 0 Stabilization

The Ceph cluster has known instability due to SMR HDDs (osd.3, osd.5) and a QLC SSD
(osd.0). Phase 0 measures are in place to bridge to the NAS migration:

| Measure | Detail |
|---------|--------|
| 3-monitor quorum | thinkcentre1/2/3; no mon on tower1 or zotac |
| osd.0 suicide timeout | 600s (prevents rapid-restart crash cascade) |
| osd.2 CRUSH frozen | `osd_crush_update_on_start=false` — prevents auto-move on reboot |
| ARR stack halted | SABnzbd write storms were the primary cascade trigger; arr-stack stopped until NAS migration |

**OSD status summary:**
- `osd.0` SSD thinkcentre1 — 5-crash history; first to remove post-migration
- `osd.1` SSD thinkcentre2 — was nearfull at 86%, recovered after osd.0 rebalance
- `osd.2` SSD thinkcentre3 — CRUSH placement frozen, stable
- `osd.3` HDD thinkcentre3 — SMR, D-state cascade trigger
- `osd.5` HDD tower1 — SMR (Seagate ST2000DM008), second to remove post-migration
- `osd.4` — REMOVED (repurposed as `backup-hdd` dir storage on tower1)

Full operational runbook: `docs/RUNBOOK.md` and `homelab-admin` skill `references/ceph.md`.

---

## Automation Toolchain

```
+-- Local Machine (macOS) ----+
|                              |
|  Makefile (orchestration)    |
|       |                      |
|       +-- Terraform          |  Provisions VMs + LXCs on Proxmox
|       |   (bpg/proxmox)     |  State: terraform/terraform.tfstate
|       |                      |
|       +-- Ansible            |  Configures services inside VMs/LXCs
|       |   (playbooks)        |  Inventory: ansible/inventory/hosts.yml
|       |                      |
|       +-- talosctl           |  Manages Talos Linux (no SSH)
|       |                      |  Config: talos/_out/talosconfig
|       |                      |
|       +-- kubectl            |  Manages K8s workloads
|       |                      |  Config: talos/_out/kubeconfig
|       |                      |
|       +-- Scripts            |  Bootstrap, destroy, DDNS, K8s base
|                              |
+------------------------------+
```

## Smart Home Device Mapping

### Linkind Plug Serial → Device Mapping

| Matter Serial | Commissioning Code | HA Device ID | Role |
|---|---|---|---|
| `00005795737` | `3016-351-2379` | `a5477bf1...` | Basking lamp |
| `00005806904` | `2201-851-2373` | `8be2197e...` | Ambient light |
| `00005795754` | `1016-521-2372` | `aa9590f7...` | Ceramic heater |
| `00005807765` | *(check sticker)* | `98adc57d...` | Living room lamp |

Manufacturer reports as "Leedarson" in Home Assistant (Linkind OEM). All four are in the **Choppy's Enclosure** area (enclosure devices) or **Living Room** area (living room lamp).

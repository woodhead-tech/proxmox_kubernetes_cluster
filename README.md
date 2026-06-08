# Proxmox Kubernetes Cluster

Homelab infrastructure for [woodhead.tech](https://woodhead.tech) -- a Talos Linux Kubernetes cluster, LXC services, and automated DNS/TLS on Proxmox VE.

## Architecture

```
ISP Modem/ONT
    |
[Google Nest WiFi Pro] (192.168.86.1) -- NAT, DHCP, DNS, WiFi
    |
    192.168.86.0/24 (flat LAN)
    |
    +-- Traefik LXC (192.168.86.20)  <-- ports 80/443 forwarded here
    |       |
    |       +-- Recipe Site LXC (192.168.86.21)
    |       +-- ARR Stack LXC (192.168.86.22) -- Sonarr, Radarr, Prowlarr, etc.
    |       +-- Monitoring LXC (192.168.86.25) -- Prometheus, Grafana, Alertmanager
    |       +-- OpenClaw LXC (192.168.86.26) -- AI agent gateway
    |       +-- Libby Alert LXC (192.168.86.27) -- life alert QR site + SMS/Discord
    |       +-- Authentik LXC (192.168.86.28) -- identity provider (SSO, OIDC, forwardAuth)
    |       +-- SDR Scanner LXC (192.168.86.32) -- Trunk Recorder + rdio-scanner
    |       +-- Kanboard LXC (192.168.86.33) -- project management
    |       +-- Mailserver LXC (192.168.86.34) -- Mailcow email server
    |       +-- step-ca LXC (192.168.86.36) -- SSH certificate authority
    |       +-- Claude OS LXC (192.168.86.37) -- AI memory system (claude-os.woodhead.tech)
    |       +-- pwnagotchi LXC (192.168.86.38) -- WiFi learning device (pwnagotchi.woodhead.tech)
    |       +-- Zigbee2MQTT LXC (192.168.86.44) -- Zigbee USB bridge for Home Assistant
    |       +-- PXE Boot Server LXC (192.168.86.50) -- proxy-DHCP + TFTP + HTTP
    |       +-- static-sites LXC (192.168.86.51) -- static web properties (docs, resume, consulting, etc.)
    |       +-- K8s VIP (192.168.86.100)
    |
    +-- WireGuard LXC (192.168.86.39) -- VPN tunnel (UDP 51820)
    |
    +-- TrueNAS VM (192.168.86.40) -- NFS media storage for ARR/Plex/Jellyfin
    +-- K8s Cluster (192.168.86.101, 192.168.86.111-113)
    |
    +-- Standalone Devices (not Proxmox-managed)
        +-- Piboard Pi 3B (192.168.86.131) -- monitoring dashboard kiosk
        +-- Klipper Ender 5 Pro (192.168.86.136) -- MainsailOS 3D printer
        +-- Klipper Ender 3 (192.168.86.138) -- MainsailOS 3D printer
```

- **Proxmox VE 8.x** -- 5-node cluster with Ceph storage
- **Talos Linux** -- immutable, API-driven Kubernetes OS (no SSH)
- **Terraform** (bpg/proxmox provider) -- provisions VMs and LXC containers
- **Ansible** -- configures Proxmox hosts, Traefik, and services
- **Traefik** -- reverse proxy + TLS termination (Let's Encrypt via Cloudflare DNS-01)
- **Cloudflare** -- DNS authority for woodhead.tech (free tier, DDNS-friendly API)

Default K8s topology: 1 control plane + 2 workers. Configurable via `terraform.tfvars`.

## Prerequisites

- Proxmox VE 8.x cluster with Ceph storage
- Cloudflare account (free) with woodhead.tech DNS
- API token for Proxmox (User > API Tokens)
- Local tools:
  - [Terraform](https://developer.hashicorp.com/terraform/install) >= 1.5
  - [talosctl](https://www.talos.dev/v1.9/introduction/getting-started/#talosctl)
  - [kubectl](https://kubernetes.io/docs/tasks/tools/)
  - [Ansible](https://docs.ansible.com/ansible/latest/installation_guide/)

## Quick Start

See [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) for the full system architecture, network flows, and dependency graphs.
See [docs/RUNBOOK.md](docs/RUNBOOK.md) for the step-by-step deployment guide.

```bash
# 1. Configure
cp terraform/terraform.tfvars.example terraform/terraform.tfvars
vim terraform/terraform.tfvars
vim ansible/inventory/hosts.yml

# 2. Proxmox base setup + DDNS
make setup
make prepare
make ddns

# 3. Create all infrastructure
make init && make apply

# 4. Configure services
make traefik
make recipe-site
make arr-stack

# 5. Bootstrap Kubernetes
export CLUSTER_VIP="192.168.86.100"
export CONTROLPLANE_IPS="192.168.86.101"
export WORKER_IPS="192.168.86.111,192.168.86.112,192.168.86.113"
make bootstrap

# 6. Verify
export KUBECONFIG=talos/_out/kubeconfig
kubectl get nodes
curl https://recipes.woodhead.tech

# 7. Harden
make harden
```

## Makefile Targets

| Target              | Phase | Description                                    |
|---------------------|-------|------------------------------------------------|
| `setup`             | 0     | Verify/configure Proxmox hosts (run once)      |
| `prepare`           | 0     | Download Talos ISO to Proxmox                  |
| `prepare-truenas`   | 0     | Download TrueNAS Scale ISO to Proxmox          |
| `ddns`              | 1     | Deploy Cloudflare DDNS updater                 |
| `init`              | --    | Initialize Terraform providers                 |
| `plan`              | --    | Preview all Terraform changes                  |
| `apply`             | --    | Create/update all VMs + LXCs                   |
| `apply-truenas`     | --    | Create TrueNAS NAS VM only                     |
| `apply-homeassistant`| --   | Create Home Assistant VM (downloads HAOS image) |
| `plan-lxc`          | --    | Preview LXC changes only                       |
| `apply-lxc`         | --    | Create/update LXC containers only              |
| `traefik`           | 2     | Configure Traefik reverse proxy                |
| `recipe-site`       | 3     | Deploy recipe site into its LXC                |
| `arr-stack`         | 3     | Deploy ARR media stack into its LXC            |
| `plex`              | 3     | Deploy Plex Media Server with iGPU passthrough |
| `jellyfin`          | 3     | Deploy Jellyfin Media Server with iGPU         |
| `monitoring`        | 3     | Deploy monitoring stack (Prometheus, Grafana)  |
| `openclaw`          | 3     | Deploy OpenClaw AI agent framework             |
| `authelia`          | 3     | Deploy Authelia SSO gateway (requires password)|
| `wireguard`         | 3     | Deploy WireGuard VPN tunnel for remote access  |
| `libby-alert`       | 3     | Deploy Libby life alert site (requires Twilio + Discord creds)|
| `kanboard`          | 3     | Deploy Kanboard project management              |
| `mailserver`        | 3     | Deploy Mailcow email server (Mailgun relay)      |
| `sdr`               | 3     | Deploy SDR scanner stack (Trunk Recorder)        |
| `pxe`               | 3     | Deploy PXE boot server (proxy-DHCP + TFTP)       |
| `zigbee2mqtt`       | 3     | Deploy Zigbee2MQTT + Mosquitto on zotac          |
| `claude-os`         | 3     | Deploy Claude OS AI memory system                |
| `pwnagotchi`        | 3     | Deploy pwnagotchi WiFi learning device           |
| `bootstrap`         | 4     | Generate Talos configs and bootstrap K8s       |
| `kubeconfig`        | 4     | Fetch kubeconfig from running cluster          |
| `health`            | 4     | Check K8s cluster health via talosctl          |
| `k8s-base`          | 4     | Apply base K8s manifests (namespaces)          |
| `k8s-base-metallb`  | 4     | Apply base manifests + MetalLB                 |
| `docs-build`        | --    | Build Docusaurus docs site                       |
| `docs-dev`          | --    | Start Docusaurus dev server (hot reload)         |
| `resume-build`      | --    | Build Hugo resume site                           |
| `patch-proxmox`     | --    | Patch Proxmox VE hosts (serial, one at a time) |
| `patch-lxc`         | --    | Patch Debian packages on all LXC containers    |
| `patch-docker`      | --    | Pull latest Docker images, restart all stacks  |
| `patch-pi`          | --    | Patch Raspberry Pi devices                       |
| `harden`            | 5     | Security hardening (SSH, firewall, fail2ban)   |
| `destroy`           | --    | Tear down K8s VMs and clean configs            |
| `clean`             | --    | Remove generated Talos configs only            |

## Project Structure

```
.
├── Makefile                              # Workflow orchestration
├── docs/
│   ├── RUNBOOK.md                        # Step-by-step deployment guide
│   ├── ROADMAP.md                        # Future services + IP plan
│   ├── PATCHING.md                       # Patching plan for all components
│   ├── TRUENAS-SETUP.md                  # TrueNAS install + NFS config guide
│   └── HOMEASSISTANT-SETUP.md            # HAOS install + smart home config guide
├── terraform/
│   ├── versions.tf                       # Provider config (bpg/proxmox)
│   ├── variables.tf                      # K8s VM variables
│   ├── lxc-variables.tf                  # LXC container variables
│   ├── control-plane.tf                  # Talos CP VM definitions
│   ├── workers.tf                        # Talos worker VM definitions
│   ├── lxc-traefik.tf                    # Traefik reverse proxy LXC
│   ├── lxc-recipe-site.tf               # Recipe site LXC
│   ├── lxc-arr.tf                        # ARR media stack LXC (Docker)
│   ├── lxc-plex.tf                       # Plex Media Server LXC
│   ├── lxc-jellyfin.tf                   # Jellyfin Media Server LXC
│   ├── lxc-monitoring.tf                 # Monitoring stack LXC (Docker)
│   ├── lxc-openclaw.tf                  # OpenClaw AI agent LXC (Docker)
│   ├── lxc-authelia.tf                  # Authentik identity provider LXC (Docker)
│   ├── lxc-wireguard.tf                 # WireGuard VPN tunnel LXC
│   ├── lxc-libby-alert.tf               # Libby life alert LXC (Docker)
│   ├── lxc-sdr.tf                       # SDR scanner LXC
│   ├── lxc-kanboard.tf                  # Kanboard project management LXC
│   ├── lxc-mailserver.tf                # Mailcow email server LXC
│   ├── lxc-pxe-server.tf               # PXE boot server LXC
│   ├── lxc-zigbee2mqtt.tf              # Zigbee2MQTT LXC (zotac)
│   ├── lxc-claude-os.tf                # Claude OS AI memory system LXC
│   ├── lxc-pwnagotchi.tf               # pwnagotchi WiFi learning device LXC
│   ├── lxc-ssh-hook.tf                  # Proxmox hookscript: fix Debian 12.12 SSH socket
│   ├── vm-truenas.tf                     # TrueNAS Scale NAS VM
│   ├── vm-truenas-variables.tf           # TrueNAS variables
│   ├── vm-homeassistant.tf               # Home Assistant OS VM
│   ├── vm-homeassistant-variables.tf     # Home Assistant variables
│   ├── outputs.tf                        # Infrastructure outputs
│   └── terraform.tfvars.example          # Configuration template
├── talos/
│   ├── talconfig.yaml                    # Cluster topology reference
│   └── patches/
│       ├── controlplane.yaml             # CP-specific Talos patches
│       └── worker.yaml                   # Worker-specific Talos patches
├── ansible/
│   ├── ansible.cfg
│   ├── inventory/hosts.yml               # Multi-group inventory
│   ├── playbooks/
│   │   ├── setup-proxmox-base.yml        # Proxmox verification + base config
│   │   ├── prepare-proxmox.yml           # Download Talos ISO
│   │   ├── prepare-truenas.yml           # Download TrueNAS ISO
│   │   ├── setup-ddns.yml                # Deploy DDNS updater
│   │   ├── setup-traefik.yml             # Configure Traefik
│   │   ├── setup-recipe-site.yml         # Deploy recipe site
│   │   ├── setup-arr-stack.yml           # Deploy ARR media stack (Docker)
│   │   ├── setup-plex.yml               # Deploy Plex + iGPU passthrough
│   │   ├── setup-jellyfin.yml           # Deploy Jellyfin + iGPU passthrough
│   │   ├── setup-monitoring.yml          # Deploy monitoring stack (Docker)
│   │   ├── setup-openclaw.yml           # Deploy OpenClaw AI agent (Docker)
│   │   ├── setup-authentik.yml          # Deploy Authentik identity provider (Docker)
│   │   ├── setup-wireguard.yml          # Deploy WireGuard VPN tunnel
│   │   ├── setup-libby-alert.yml        # Deploy Libby life alert site (Docker)
│   │   ├── setup-kanboard.yml           # Deploy Kanboard
│   │   ├── setup-sdr.yml               # Deploy SDR scanner
│   │   ├── setup-mailserver.yml         # Deploy Mailcow email server
│   │   ├── setup-pxe-server.yml        # Deploy PXE boot server
│   │   ├── setup-zigbee2mqtt.yml       # Deploy Zigbee2MQTT + Mosquitto
│   │   ├── setup-claude-os.yml         # Deploy Claude OS AI memory system
│   │   ├── setup-pwnagotchi.yml        # Deploy pwnagotchi + bettercap + pwngrid
│   │   ├── patch-proxmox.yml              # Patch Proxmox VE hosts
│   │   ├── patch-lxc.yml                 # Patch Debian packages on LXCs
│   │   ├── patch-docker.yml              # Update Docker images on all stacks
│   │   ├── patch-pi.yml                 # Patch Raspberry Pi devices
│   │   └── harden-proxmox.yml            # Security hardening
│   └── files/
│       ├── arr-stack/
│       │   └── docker-compose.yml        # ARR stack Docker Compose
│       ├── openclaw/
│       │   └── docker-compose.yml        # OpenClaw AI agent Docker Compose
│       ├── authelia/
│       │   ├── docker-compose.yml        # Authelia SSO Docker Compose
│       │   ├── configuration.yml         # Authelia server + access control config
│       │   └── users_database.yml        # File-based user database template
│       ├── kanboard/
│       │   └── docker-compose.yml        # Kanboard Docker Compose
│       ├── mailserver/
│       │   └── docker-compose.override.yml # Mailcow override config
│       ├── wireguard/
│       │   ├── wg0.conf.j2              # Server config Jinja2 template
│       │   └── client.conf.j2           # Client config Jinja2 template
│       ├── monitoring/
│       │   ├── docker-compose.yml        # Monitoring stack Docker Compose
│       │   ├── prometheus/
│       │   │   ├── prometheus.yml        # Scrape targets config
│       │   │   └── rules/alerts.yml      # Alert rules
│       │   ├── alertmanager/
│       │   │   └── alertmanager.yml      # Alert routing (Discord/Slack)
│       │   ├── blackbox/
│       │   │   └── blackbox.yml          # HTTP/ICMP probe modules
│       │   └── grafana/provisioning/     # Auto-provisioned datasources + dashboards
│       └── traefik/
│           ├── traefik.yml               # Traefik static config
│           └── dynamic/
│               ├── recipe-site.yml       # Route: recipes.woodhead.tech
│               ├── arr-stack.yml         # Routes: sonarr/radarr/prowlarr.*
│               ├── media-stack.yml       # Routes: plex/jellyfin/nas.*
│               ├── homeassistant.yml     # Route: home.woodhead.tech
│               ├── monitoring.yml         # Routes: grafana/prometheus/alertmanager.*
│               ├── openclaw.yml          # Route: claw.woodhead.tech
│               ├── authelia.yml         # Route: auth.woodhead.tech + forwardAuth middleware
│               ├── kanboard.yml          # Route: tasks.woodhead.tech
│               ├── mailserver.yml        # Route: mail.woodhead.tech
│               ├── sdr.yml              # Route: scanner.woodhead.tech
│               ├── docs-site.yml        # Route: docs.woodhead.tech
│               ├── resume-site.yml      # Route: resume.woodhead.tech
│               ├── landing-site.yml     # Route: woodhead.tech landing page
│               ├── klipper.yml          # Routes: ender5/ender3.woodhead.tech
│               ├── truenas.yml          # Route: nas.woodhead.tech
│               ├── k8s-ingress.yml       # Route: *.woodhead.tech -> K8s
│               └── dashboard.yml         # Route: traefik.woodhead.tech
├── docs-site/                            # Docusaurus docs site source
├── resume-site/                          # Hugo resume site source
├── k8s/
│   └── base/
│       ├── namespace.yml                 # Base namespaces
│       ├── monitoring/                   # K8s monitoring exporters
│       │   ├── kube-state-metrics.yml    # Cluster state metrics + RBAC
│       │   └── node-exporter-daemonset.yml # Host metrics for Talos nodes
│       └── metallb/                      # MetalLB LoadBalancer support
│           ├── namespace.yml
│           ├── ip-pool.yml               # IP range: 192.168.86.150-199
│           └── metallb-install.yml       # Installation reference
└── scripts/
    ├── bootstrap.sh                      # Talos config gen + cluster bootstrap
    ├── destroy.sh                        # Teardown with confirmation
    ├── apply-k8s-base.sh                 # Apply base K8s manifests
    └── ddns/
        ├── cloudflare-ddns.sh            # DDNS updater script
        └── cloudflare.env.example        # Cloudflare credentials template
```

## Adding New Services

### New LXC Service

1. Create `terraform/lxc-<name>.tf` with a `proxmox_virtual_environment_container` resource
2. Add variables to `terraform/lxc-variables.tf`
3. Add Traefik route in `ansible/files/traefik/dynamic/<name>.yml`
4. Create Ansible playbook in `ansible/playbooks/setup-<name>.yml`
5. Add host to `ansible/inventory/hosts.yml` under `lxc_services`
6. Run `make apply` then `make traefik`

### New K8s Workload

1. Add manifests to `k8s/<app>/`
2. Uncomment the K8s catch-all route in `ansible/files/traefik/dynamic/k8s-ingress.yml`
3. Run `make traefik` to update routing

## Scaling K8s

Update `terraform.tfvars`:
```hcl
controlplane_count = 3
controlplane_ips   = ["192.168.86.101", "192.168.86.102", "192.168.86.103"]

worker_count = 5
worker_ips   = ["192.168.86.111", "192.168.86.112", "192.168.86.113", "192.168.86.114", "192.168.86.115"]
```

Then `make apply` and `make bootstrap`.

## Roadmap

See [docs/ROADMAP.md](docs/ROADMAP.md) for full details, IP plan, and hardware considerations.

| Service          | Type | Status      | Subdomain                  |
|------------------|------|-------------|----------------------------|
| TrueNAS Scale    | VM   | Ready       | `nas.woodhead.tech`        |
| ARR Stack        | LXC  | Ready       | `sonarr/radarr/prowlarr.*` |
| Plex             | LXC  | Ready       | `plex.woodhead.tech`       |
| Jellyfin         | LXC  | Ready       | `jellyfin.woodhead.tech`   |
| Home Assistant   | VM   | Ready       | `home.woodhead.tech`       |
| Monitoring       | LXC  | Ready       | `grafana.woodhead.tech`    |
| OpenClaw         | LXC  | Ready       | `claw.woodhead.tech`       |
| Authentik SSO    | LXC  | Ready       | `auth.woodhead.tech`       |
| WireGuard VPN    | LXC  | Ready       | UDP 51820 (not HTTP)       |
| Libby Alert      | LXC  | Ready       | `alert.woodhead.tech`      |
| SDR Scanner      | LXC  | Ready       | `scanner.woodhead.tech`    |
| Kanboard         | LXC  | Ready       | `tasks.woodhead.tech`      |
| Email Server     | LXC  | Ready       | `mail.woodhead.tech`       |
| Docusaurus       | LXC  | Ready       | `docs.woodhead.tech`       |
| Resume Site      | LXC  | Ready       | `resume.woodhead.tech`     |
| PXE Boot Server  | LXC  | Ready       | LAN-only (no subdomain)    |
| Zigbee2MQTT      | LXC  | Ready       | LAN-only (MQTT :1883)      |
| Claude OS        | LXC  | Ready       | `claude-os.woodhead.tech`  |
| pwnagotchi       | LXC  | Ready       | `pwnagotchi.woodhead.tech` |

Traefik routes for all planned services are stubbed out in `ansible/files/traefik/dynamic/` -- uncomment as you deploy each service.

## Migrating to kubeadm

If Talos doesn't fit your needs, the Terraform VM configs can be reused with a standard Ubuntu/Debian cloud image. Swap the `cdrom` block for a `clone` from a cloud-init template and add Ansible roles for kubeadm setup.

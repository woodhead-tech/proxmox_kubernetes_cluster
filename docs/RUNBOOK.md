# Deployment Runbook

Step-by-step guide to deploy the full Proxmox homelab infrastructure from scratch.

## Prerequisites

Install these on your local machine (Mac):

```bash
# Terraform
brew install terraform

# Ansible
brew install ansible

# talosctl
brew install siderolabs/tap/talosctl

# kubectl
brew install kubectl

# htpasswd (for Traefik dashboard password)
brew install httpd  # Provides htpasswd
```

## Phase 0: Proxmox Base Setup

### 0.1 Install Proxmox VE

1. Download Proxmox VE 8.x ISO from https://www.proxmox.com/en/downloads
2. Flash to USB with `dd` or Balena Etcher
3. Install on each node (2-3 nodes)
4. Set static IPs during install:
   - Node 1: `192.168.86.29`
   - Node 2: `192.168.86.30`
   - Node 3: `192.168.86.31` (optional)
5. Access web UI at `https://192.168.86.29:8006`

### 0.2 Create Proxmox Cluster

On node 1 (via web UI or SSH):
```bash
pvecm create homelab
```

On node 2 (and 3):
```bash
pvecm add 192.168.86.29
```

### 0.3 Repository Setup (Handled by Ansible)

The `make setup` playbook automatically switches from the enterprise repos (which require a paid subscription) to the free no-subscription community repos. You don't need to do this manually -- just be aware that `apt update` will fail until `make setup` runs if you haven't done this step.

If you want to do it manually before running Ansible:
```bash
# Remove enterprise repos
rm /etc/apt/sources.list.d/pve-enterprise.list
rm /etc/apt/sources.list.d/ceph.list

# Add community repos
echo "deb http://download.proxmox.com/debian/pve bookworm pve-no-subscription" > /etc/apt/sources.list.d/pve-no-subscription.list
echo "deb http://download.proxmox.com/debian/ceph-reef bookworm no-subscription" > /etc/apt/sources.list.d/ceph-no-subscription.list

apt update
```

### 0.4 Configure Ceph

Via the Proxmox web UI (Datacenter > Ceph):
1. Install Ceph on each node
2. Create OSDs from available disks on each node
3. Create a pool named `ceph-pool` (default size 3 for 3 nodes, or size 2 for 2 nodes)

Verify from SSH:
```bash
ceph status
ceph osd pool ls  # Should show "ceph-pool"
```

### 0.5 Create API Token

Via Proxmox web UI:
1. Datacenter > Permissions > API Tokens
2. User: `root@pam`
3. Token ID: `terraform`
4. Uncheck "Privilege Separation" (gives full permissions)
5. Save the token -- you'll need it for `terraform.tfvars`

Format: `root@pam!terraform=xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx`

### 0.6 Run Base Setup Playbook

Update the inventory with your node IPs:
```bash
vim ansible/inventory/hosts.yml
```

Run the setup:
```bash
make setup
```

This verifies Proxmox version, Ceph health, network bridge, and downloads the Debian 12 LXC template.

---

## Phase 1: Cloudflare DNS + DDNS

### 1.1 Create Cloudflare Account

1. Sign up at https://dash.cloudflare.com/sign-up (free tier)
2. Click "Add a Site" and enter `woodhead.tech`
3. Select the **Free** plan

### 1.2 Transfer DNS from Squarespace

1. Cloudflare will show you 2 nameserver addresses (e.g., `ada.ns.cloudflare.com`)
2. Go to https://account.squarespace.com/domains/managed/woodhead.tech
3. Under DNS settings, change the nameservers to the Cloudflare ones
4. Wait for propagation (can take up to 24 hours, usually faster)

Verify:
```bash
dig woodhead.tech NS
# Should return Cloudflare nameservers
```

### 1.3 Create DNS Records in Cloudflare

In the Cloudflare dashboard for woodhead.tech:
1. Add A record: `woodhead.tech` -> your current public IP
2. Add A record: `*.woodhead.tech` -> your current public IP
3. Set both to **DNS only** (gray cloud) -- NOT proxied
4. TTL: 5 minutes (for DDNS updates)

### 1.4 Create Cloudflare API Token

1. My Profile > API Tokens > Create Token
2. Use the "Edit zone DNS" template
3. Zone Resources: Include > Specific Zone > `woodhead.tech`
4. Save the token

### 1.5 Note Zone ID and Record Info

1. On the woodhead.tech Overview page, the Zone ID is in the right sidebar
2. You'll need it for the DDNS env file

### 1.6 Configure DDNS

```bash
# Copy the example env file
cp scripts/ddns/cloudflare.env.example scripts/ddns/cloudflare.env

# Edit with your Cloudflare credentials
vim scripts/ddns/cloudflare.env
```

Fill in:
- `CF_API_TOKEN` - the API token from step 1.4
- `CF_ZONE_ID` - from step 1.5
- `CF_RECORD_NAMES` - `woodhead.tech,*.woodhead.tech`

### 1.7 Deploy DDNS

```bash
make ddns
```

This installs the script on the first Proxmox node and sets up a cron job every 5 minutes. Verify in syslog:
```bash
ssh root@192.168.86.29 "journalctl -t cloudflare-ddns --no-pager -n 20"
```

---

## Phase 2: Terraform Configuration

### 2.1 Configure terraform.tfvars

```bash
cp terraform/terraform.tfvars.example terraform/terraform.tfvars
vim terraform/terraform.tfvars
```

Key values to update:
- `proxmox_endpoint` - your Proxmox URL (e.g., `https://192.168.86.29:8006`)
- `proxmox_api_token` - from Phase 0.4
- `proxmox_node` - node name (usually `pve` or `pve1`)
- `ssh_public_key` - your SSH public key (cat `~/.ssh/id_ed25519.pub`)
- Network IPs - adjust to match your subnet
- Domain settings

### 2.2 Download ISOs

Download service ISOs before creating VMs:
```bash
make prepare           # Talos ISO
make prepare-truenas   # TrueNAS Scale ISO
```

### 2.3 Initialize and Apply

```bash
# Download providers
make init

# Review what will be created
make plan

# Create everything (VMs + LXC containers)
make apply
```

This creates:
- 1 TrueNAS NAS VM (ID 300)
- 1 Home Assistant VM (ID 301)
- 1 control plane VM (ID 400)
- 2 worker VMs (IDs 410, 411)
- 1 Traefik LXC (ID 200)
- 1 Recipe site LXC (ID 201)
- 1 ARR stack LXC (ID 202)
- 1 Plex LXC (ID 203)
- 1 Jellyfin LXC (ID 204)
- 1 Monitoring LXC (ID 205)
- 1 OpenClaw LXC (ID 206)
- 1 Authelia LXC (ID 207)
- 1 WireGuard LXC (ID 208)
- 1 Libby Alert LXC (ID 209)

Or create infrastructure piecemeal:
```bash
make apply-truenas   # TrueNAS VM only
make apply-lxc       # LXC containers only
```

---

## Phase 3: Traefik Reverse Proxy

### 3.1 Generate Dashboard Password

```bash
htpasswd -nb admin your-secure-password-here
```

Copy the output and update `ansible/files/traefik/dynamic/dashboard.yml`:
- Replace `admin:$$apr1$$PLACEHOLDER$$REPLACE_WITH_HTPASSWD_HASH`
- Double all `$` signs (YAML escaping)

### 3.2 Deploy Traefik

```bash
make traefik
```

Pass the Cloudflare API token:
```bash
cd ansible && ansible-playbook playbooks/setup-traefik.yml \
  --extra-vars "cf_api_token=your-cloudflare-api-token"
```

### 3.3 Configure Port Forwarding

In the Google Home app (WiFi > Settings > Advanced Networking > Port Management):
- Forward port 80 -> `192.168.86.20:80`
- Forward port 443 -> `192.168.86.20:443`

### 3.4 Verify

```bash
# Should get Traefik 404 (no routes matched yet for this host)
curl -k https://192.168.86.20

# After recipe site is deployed, should work:
curl https://recipes.woodhead.tech
```

---

## Phase 4: Recipe Site

### 4.1 Deploy

```bash
make recipe-site
```

This copies and runs the install script from `~/WORKSPACE/recipes/site/deploy/install-recipe-site.sh` inside the LXC.

### 4.2 Verify

```bash
# Direct access (internal)
curl http://192.168.86.21:80

# Via Traefik (external)
curl https://recipes.woodhead.tech
```

### 4.3 Configure GitHub Webhook

In the recipes repo on GitHub (Settings > Webhooks > Add webhook):
1. Payload URL: `https://recipes.woodhead.tech/webhook`
2. Content type: `application/json`
3. Secret: SSH into the LXC and get it: `cat /opt/recipe-site/.webhook-secret`
4. Events: Just the push event

---

## Phase 5: TrueNAS Scale NAS

VM 300 (truenas) is already provisioned with two virtual disks:
- `scsi0`: 16 GiB local-lvm — OS disk
- `scsi1`: 2 TiB Ceph RBD — data disk (3x replicated across the Ceph cluster)

The TrueNAS ISO is downloaded and attached. The steps below are the remaining
manual tasks; all post-install configuration is automated via Ansible.

### 5.1 Download TrueNAS ISO (already done — skip if VM exists)

```bash
make prepare-truenas
make apply-truenas
```

### 5.2 Install TrueNAS via Proxmox Console

1. Open Proxmox web UI -> VM 300 (truenas) -> Console
2. Follow the TrueNAS Scale installer
3. When asked which disk to install on, select `/dev/sda` (16 GiB) — **not** `/dev/sdb`
4. Set a root password — you will need it in step 5.3
5. Reboot when prompted; remove the ISO boot entry if the installer does not do so automatically

### 5.3 Verify Network

After reboot, the console shows the assigned IP. Verify:
```bash
curl http://192.168.86.40/api/v2.0/system/info
```

If the IP is wrong, configure it through the TrueNAS console menu:
- Network -> Interfaces -> edit -> Static IP: `192.168.86.40/24`
- Default gateway: `192.168.86.1`
- DNS: `8.8.8.8`
- Save and apply

### 5.4 Run Ansible Post-Install Configuration

```bash
make truenas TRUENAS_PASSWORD=<root-password-from-step-5.2>
```

This runs `ansible/playbooks/setup-truenas.yml` which:
- Creates ZFS pool `tank` on `/dev/sdb` (the 2 TiB Ceph RBD disk)
- Creates datasets with LZ4 compression: `tank/media` (movies/tv/music/downloads), `tank/backups`, `tank/isos`
- Enables and starts the NFS service
- Creates NFS shares accessible from `192.168.86.0/24`

### 5.5 Add NFS Storage to Proxmox

Via Proxmox web UI: **Datacenter > Storage > Add > NFS** — repeat for each:

| ID                | Server          | Share               | Content          |
|-------------------|-----------------|---------------------|------------------|
| `truenas-backups` | `192.168.86.40` | `/mnt/tank/backups` | VZDump backup    |
| `truenas-isos`    | `192.168.86.40` | `/mnt/tank/isos`    | ISO image        |

### 5.6 Create Proxmox Backup Job

**Datacenter > Backup > Add:**
- Storage: `truenas-backups`
- Schedule: `0 2 * * *` (nightly at 2:00 AM)
- Selection mode: All
- Compression: LZO
- Mode: Snapshot

### 5.7 Mount NFS Media in Service LXCs (optional)

ARR stack, Plex, and Jellyfin LXCs access `/mnt/tank/media` over NFS. Pass the
`nfs_server` extra-var when deploying those services:
```bash
cd ansible && ansible-playbook playbooks/setup-arr-stack.yml \
  --extra-vars "nfs_server=192.168.86.40 nfs_share=/mnt/tank/media"
```

---

## Phase 6: ARR Media Stack

### 6.1 Deploy

The ARR stack requires a PrivadoVPN WireGuard private key for the SABnzbd VPN killswitch.
Download a WireGuard `.conf` from my.privado.io and copy the `PrivateKey` value:

```bash
make arr-stack WG_PRIVATE_KEY=<privado_wireguard_private_key>
```

The key is written to `/opt/arr/gluetun/wireguard_private_key` on the LXC and never committed to git.

If TrueNAS NFS is ready, pass the mount details too:
```bash
cd ansible && ansible-playbook playbooks/setup-arr-stack.yml \
  --extra-vars "wg_private_key=<key> nfs_server=192.168.86.40 nfs_share=/mnt/pool/media"
```

### 6.2 Configure Services

Access each service via its web UI:
| Service   | URL                             | First step                      |
|-----------|---------------------------------|---------------------------------|
| Prowlarr  | `http://192.168.86.22:9696`     | Add indexers                    |
| SABnzbd   | `http://192.168.86.22:8080`     | Configure Usenet server         |
| Sonarr    | `http://192.168.86.22:8989`     | Connect to Prowlarr + SABnzbd  |
| Radarr    | `http://192.168.86.22:7878`     | Connect to Prowlarr + SABnzbd  |
| Bazarr    | `http://192.168.86.22:6767`     | Connect to Sonarr + Radarr     |
| Seerr     | `http://192.168.86.22:5055`     | Connect to Sonarr + Radarr     |

### 6.3 Gluetun VPN Killswitch

SABnzbd runs inside gluetun's network namespace (PrivadoVPN WireGuard). If the VPN drops, SABnzbd loses connectivity — intentional killswitch behavior.

**Always recreate both containers together** when restarting gluetun, or SABnzbd's network namespace goes stale:
```bash
cd /opt/arr && docker compose up -d --force-recreate gluetun sabnzbd
```

To rotate the WireGuard key:
```bash
printf '%s' 'NEW_PRIVATE_KEY' > /opt/arr/gluetun/wireguard_private_key
docker compose up -d --force-recreate gluetun sabnzbd
```

### 6.5 Enable Traefik Routes (Optional)

To expose ARR services externally, uncomment the routes in
`ansible/files/traefik/dynamic/arr-stack.yml` and redeploy:
```bash
make traefik
```

---

## Phase 7: Plex and Jellyfin

Both media servers share the TrueNAS NFS media library. They use Intel
Quick Sync (iGPU) for hardware transcoding via `/dev/dri` passthrough.

### 7.1 Deploy Plex

```bash
make plex
```

With NFS media:
```bash
cd ansible && ansible-playbook playbooks/setup-plex.yml \
  --extra-vars "nfs_server=192.168.86.40 nfs_share=/mnt/pool/media"
```

Without GPU passthrough (software transcoding only):
```bash
cd ansible && ansible-playbook playbooks/setup-plex.yml \
  --extra-vars "gpu_passthrough=false"
```

Configure at `http://192.168.86.23:32400/web`:
1. Sign in with your Plex account
2. Add libraries: `/media/movies`, `/media/tv`, `/media/music`
3. Enable hardware transcoding (Settings > Transcoder, requires Plex Pass)

### 7.2 Deploy Jellyfin

```bash
make jellyfin
```

With NFS media:
```bash
cd ansible && ansible-playbook playbooks/setup-jellyfin.yml \
  --extra-vars "nfs_server=192.168.86.40 nfs_share=/mnt/pool/media"
```

Configure at `http://192.168.86.24:8096`:
1. Create admin account
2. Add libraries: `/media/movies`, `/media/tv`, `/media/music`
3. Enable VAAPI transcoding (Dashboard > Playback > Transcoding > `/dev/dri/renderD128`)

### 7.3 Enable Traefik Routes (Optional)

Uncomment routes in `ansible/files/traefik/dynamic/media-stack.yml` and:
```bash
make traefik
```

### 7.4 GPU Sharing Note

Both Plex and Jellyfin can share the same iGPU (`/dev/dri`). Intel Quick
Sync handles multiple transcoding sessions concurrently. Both LXCs must
run on the same Proxmox node that has the iGPU.

---

## Phase 8: Home Assistant

See [docs/HOMEASSISTANT-SETUP.md](HOMEASSISTANT-SETUP.md) for the full setup guide.

### 8.1 Create the VM

Unlike other VMs, HAOS uses a pre-built disk image instead of an ISO installer.
Terraform handles the image download and VM creation in one step:

```bash
make apply-homeassistant
```

This downloads the HAOS qcow2 image to Proxmox, decompresses it, and creates the
VM with the image imported as the boot disk. No separate ISO download needed.

### 8.2 First Boot

1. Open Proxmox web UI -> VM 301 (homeassistant) -> Console
2. HAOS boots automatically (no install wizard)
3. Wait 2-3 minutes for initial setup
4. The console shows the web UI URL

### 8.3 Configure

1. Access web UI at `http://192.168.86.41:8123`
2. Complete the onboarding wizard (create admin account, set location)
3. Set static IP: Settings -> System -> Network -> `192.168.86.41/24`

### 8.4 USB Passthrough (Optional)

For Zigbee/Z-Wave dongles:
```bash
# On Proxmox host, find your dongle's vendor:product ID
lsusb

# Pass it through to the VM
qm set 301 -usb0 host=<vendor>:<product>
```

Then in HA: Settings -> Devices & Services -> Add ZHA or Z-Wave JS integration.

### 8.5 Enable Traefik Route (Optional)

Uncomment the route in `ansible/files/traefik/dynamic/homeassistant.yml` and redeploy:
```bash
make traefik
```

---

## Phase 9: Kubernetes Cluster

### 9.1 Download Talos ISO

```bash
make prepare
```

### 9.2 Bootstrap

```bash
export CLUSTER_VIP="192.168.86.100"
export CONTROLPLANE_IPS="192.168.86.101"
export WORKER_IPS="192.168.86.111,192.168.86.112"
make bootstrap
```

> **SeaBIOS + Talos ISO caveat:** These VMs use SeaBIOS (not OVMF/UEFI). Talos writes an MBR bootloader to disk during installation, which SeaBIOS will prefer over the IDE CD-ROM even when the Proxmox boot order lists `ide2` first. If you need to boot from the ISO (e.g. for re-bootstrap), you must wipe the first ~100 MB of each VM's disk before starting:
> ```bash
> # Stop the VM first, then on the Proxmox node that hosts it:
> rbd map thinkCentreCeph/vm-400-disk-0
> DEV=$(rbd showmapped | grep vm-400-disk-0 | awk '{print $5}')
> dd if=/dev/zero of=$DEV bs=1M count=100
> rbd unmap $DEV
> ```
> Also note: in maintenance mode (no config applied), Talos nodes obtain IPs via DHCP rather than the static IPs in `terraform.tfvars`. Scan for port 50000 across the subnet to find them, then use those DHCP IPs for `talosctl apply-config --insecure`.

### 9.3 Verify

```bash
export KUBECONFIG=talos/_out/kubeconfig
kubectl get nodes
# Should show 3 nodes in Ready state
```

### 9.4 Apply Base Manifests

```bash
# Without MetalLB
make k8s-base

# With MetalLB (for LoadBalancer services)
make k8s-base-metallb
```

### 9.5 Enable K8s Routing in Traefik

Once K8s has an ingress controller, uncomment the routes in `ansible/files/traefik/dynamic/k8s-ingress.yml` and redeploy:
```bash
make traefik
```

---

## Phase 10: Monitoring Stack

### 10.1 Create the LXC

```bash
make apply-lxc
```

This creates the monitoring LXC (VM ID 205, 192.168.86.25) along with any other LXCs.

### 10.2 Create Proxmox API Token for PVE Exporter

Via Proxmox web UI:
1. Datacenter > Permissions > Users > Add
   - User: `monitoring@pve`, Realm: `Proxmox VE authentication server`
2. Datacenter > Permissions > Roles > Add
   - Select `PVEAuditor` (read-only access)
3. Datacenter > Permissions > Add > User Permission
   - Path: `/`, User: `monitoring@pve`, Role: `PVEAuditor`
4. Datacenter > Permissions > API Tokens > Add
   - User: `monitoring@pve`, Token ID: `prometheus`
   - Uncheck "Privilege Separation"
5. Save the token value

### 10.3 Create Discord Webhook

1. Create a Discord server (or use existing)
2. Create a `#homelab-alerts` channel
3. Channel Settings > Integrations > Webhooks > New Webhook
4. Name it "Alertmanager" and select the `#homelab-alerts` channel
5. Copy the webhook URL (format: `https://discord.com/api/webhooks/<id>/<token>`)

### 10.4 Deploy Monitoring Stack

Basic deployment (configure credentials later):
```bash
make monitoring
```

With all credentials (recommended):
```bash
make monitoring \
  DISCORD_WEBHOOK="https://discord.com/api/webhooks/YOUR_ID/YOUR_TOKEN" \
  GRAFANA_PASSWORD="your-secure-password" \
  PVE_USER=monitoring@pve \
  PVE_TOKEN_NAME=prometheus \
  PVE_TOKEN_VALUE="YOUR_TOKEN_VALUE"
```

### 10.5 Enable Traefik Metrics

Redeploy Traefik to add the Prometheus metrics entrypoint:
```bash
make traefik
```

This adds a `:8082` metrics endpoint that Prometheus scrapes for request data.

### 10.6 Grafana Dashboards

Five dashboards are auto-provisioned from JSON files in `ansible/files/monitoring/grafana/dashboards/`:

| Dashboard | Source ID | Purpose |
|-----------|-----------|---------|
| Proxmox VE | 10347 | Host/VM/LXC resource metrics (via PVE Exporter) |
| Docker Containers | 14282 | Container CPU, memory, network (via cAdvisor) |
| Traefik 3.x | 17346 | Request rate, latency, errors |
| Blackbox Exporter | 7587 | Service uptime, response time |
| Dexcom Glucose | custom | CGM glucose level, trend, 24h history |

These load automatically on first boot -- no manual import needed. To add more,
download the JSON from grafana.com, replace `${DS_PROMETHEUS}` with `Prometheus`,
and place the file in the dashboards directory. Redeploy:
```bash
make monitoring
```

For the Kubernetes cluster overview dashboard (ID `315`), import manually after
bootstrapping K8s (it requires kube-state-metrics data to be useful).

### 10.7 Traefik Routes

Monitoring routes are pre-configured in `ansible/files/traefik/dynamic/monitoring.yml`:
- `grafana.woodhead.tech` -> :3000 (open)
- `prometheus.woodhead.tech` -> :9090 (behind Authelia 2FA)
- `alertmanager.woodhead.tech` -> :9093 (behind Authelia 2FA)

These are deployed automatically by `make traefik`. No uncommenting needed.

### 10.8 Deploy K8s Exporters (Optional)

After the K8s cluster is bootstrapped:
```bash
kubectl apply -f k8s/base/monitoring/kube-state-metrics.yml
kubectl apply -f k8s/base/monitoring/node-exporter-daemonset.yml
```

Then uncomment the K8s scrape configs in `ansible/files/monitoring/prometheus/prometheus.yml` and restart the stack:
```bash
ssh root@192.168.86.25 "cd /opt/monitoring && docker compose restart prometheus"
```

### 10.9 Verify

```bash
# Prometheus healthy
curl http://192.168.86.25:9090/-/healthy

# Grafana healthy
curl http://192.168.86.25:3000/api/health

# Check scrape targets (all jobs should be "up")
curl -s http://192.168.86.25:9090/api/v1/targets | jq '.data.activeTargets[] | {job: .labels.job, health: .health}'

# Test Discord alerting (should appear in #homelab-alerts within 30s)
curl -X POST http://192.168.86.25:9093/api/v1/alerts \
  -H 'Content-Type: application/json' \
  -d '[{"labels":{"alertname":"TestAlert","severity":"warning"},"annotations":{"description":"Test alert from homelab"}}]'

# Traefik routes (after make traefik)
curl -I https://grafana.woodhead.tech
```

### 10.10 Dexcom Glucose Monitoring

The monitoring stack includes a Dexcom CGM exporter that polls the Dexcom Share API
and exposes glucose readings as Prometheus metrics. Alert rules notify via Discord,
Twilio SMS, and Home Assistant Alexa announcements.

**Prerequisites:**
- Wife enables "Share" in the Dexcom app and adds you as a follower
- Twilio account with SMS-capable phone number
- Home Assistant Alexa Media Player integration (for voice announcements)

**Deploy with Dexcom credentials:**
```bash
make monitoring \
  DEXCOM_USERNAME=your-dexcom-username \
  DEXCOM_PASSWORD=your-dexcom-password
```

**Configure Twilio SMS (edit on the LXC):**
```bash
ssh root@192.168.86.25
vi /opt/monitoring/dexcom-exporter/twilio.env
# Set: TWILIO_ACCOUNT_SID, TWILIO_AUTH_TOKEN, TWILIO_FROM_NUMBER, SMS_TO_NUMBER
cd /opt/monitoring && docker compose restart twilio-relay
```

**Configure Home Assistant Alexa webhook:**
1. In HA, create an automation triggered by webhook (e.g., `glucose-alert`)
2. Action: Alexa Media Player > Notify > Announce on desired Echo device
3. Pass the webhook URL to the monitoring deploy:
```bash
make monitoring HA_GLUCOSE_WEBHOOK=http://192.168.86.41:8123/api/webhook/glucose-alert
```

**Alert thresholds:**

| Alert | Threshold | Delay | Severity |
|-------|-----------|-------|----------|
| GlucoseCriticalLow | < 55 mg/dL | Immediate | Critical |
| GlucoseLow | 55-70 mg/dL | 5 min | Warning |
| GlucoseHigh | > 250 mg/dL | 15 min | Warning |
| GlucoseCriticalHigh | > 350 mg/dL | 5 min | Critical |
| DexcomStaleReading | No data 15 min | 5 min | Warning |

**Verify:**
```bash
curl -s http://192.168.86.25:9666/metrics | grep dexcom_glucose
```

---

## Phase 10b: SDR Scanner

### 10b.1 Deploy

The SDR scanner decodes Snohomish County SNO911 P25 Phase II trunked radio
using an RTL-SDR V4 USB dongle attached to thinkcentre2 (pve2).

**Prerequisites:**
- RTL-SDR V4 plugged into thinkcentre2 USB port
- LXC 210 created via Terraform (or already exists — import if needed)

```bash
# If LXC doesn't exist yet, create it
cd terraform && terraform apply -target=proxmox_virtual_environment_container.sdr

# If LXC already exists but isn't in state, import it first
cd terraform && terraform import proxmox_virtual_environment_container.sdr thinkcentre2/210

# Deploy the stack (USB passthrough + Docker + Traefik route)
make sdr
```

**Note:** The LXC must be privileged for USB device passthrough. `make sdr` configures
cgroup rules on pve2 for USB access and restarts the LXC. The Traefik route is deployed
with Authentik forward auth — no separate Authentik application is needed since the
domain-level `woodhead-forward-auth` provider covers all `*.woodhead.tech` subdomains.

If the LXC is recreated, re-run `make sdr` to reapply USB passthrough rules.

### 10b.2 Verify

```bash
# Check containers are running
ssh -i ~/.ssh/id_ansible root@192.168.86.32 "docker ps"

# Check trunk-recorder is decoding (expect 4-10 msgs/sec from SNO911 control channel)
ssh -i ~/.ssh/id_ansible root@192.168.86.32 "docker logs trunk-recorder --tail 10"

# Check rdio-scanner web UI
curl -s -o /dev/null -w "%{http_code}" http://192.168.86.32:3000/

# Traefik + Authentik route (expect 302 redirect to auth.woodhead.tech)
curl -I https://scanner.woodhead.tech
```

---

## Phase 11: Authentik Identity Provider

### 11.1 Deploy

```bash
make authentik
```

This installs Docker, generates cryptographic secrets (JWT, session, storage encryption),
hashes the admin password with argon2id, and starts Authelia.

### 11.2 Configure

1. Access at `http://192.168.86.28:9000`
2. Log in with `admin account created during initial setup
3. Register a TOTP device (Authy, Google Authenticator, etc.)

### 11.3 Protect Services

Authelia acts as a forwardAuth middleware for Traefik. Services with
`middlewares: [authelia@file]` in their Traefik dynamic config require
authentication before access. Prometheus and Alertmanager are protected by default.

### 11.4 Enable Traefik Route

The route at `ansible/files/traefik/dynamic/authelia.yml` (`auth.woodhead.tech`)
is already active. Redeploy Traefik if needed:
```bash
make traefik
```

---

## Phase 12: WireGuard VPN

See [docs/WIREGUARD-MANGO.md](WIREGUARD-MANGO.md) for connecting a GL-iNet Mango travel router.

### 12.1 Deploy

```bash
make wireguard
```

This installs WireGuard, enables IP forwarding, generates server + client keypairs
with preshared keys, templates `wg0.conf`, and starts the tunnel.

### 12.2 Configure Port Forwarding

In the Google Home app (WiFi > Settings > Advanced Networking > Port Management):
- Forward UDP port 51820 -> `192.168.86.39:51820`

### 12.3 Client Setup

Client configs are generated on the LXC at `/etc/wireguard/clients/` and fetched
to `ansible/files/wireguard/clients/` locally. Import the `.conf` file into the
WireGuard app on your phone/laptop.

### 12.4 Verify

```bash
# Check tunnel status on server
ssh root@192.168.86.39 "wg show"

# Test from client: ping the WireGuard server
ping 10.0.0.1
```

---

## Phase 13: Libby Alert

### 13.1 Create the LXC

```bash
make apply-lxc
```

This creates the libby-alert LXC (VM ID 209, 192.168.86.27).

### 13.2 Set SSH Hookscript (Required for Debian 12.12)

Debian 12.12 uses systemd socket activation for sshd, which only binds to IPv6 by default.
Proxmox provides a hookscript (`lxc-ssh-fix.sh`) that runs post-start to fix this.

The hookscript file is managed by Terraform, but setting it on the LXC requires `root@pam`
auth (the API token gets a 403). Set it manually:

```bash
# Verify the snippet was uploaded
ssh root@192.168.86.29 "ls /var/lib/vz/snippets/"
# Should show: lxc-ssh-fix.sh

# Make it executable and attach to the LXC
ssh root@192.168.86.29 "chmod +x /var/lib/vz/snippets/lxc-ssh-fix.sh && pct set 209 --hookscript local:snippets/lxc-ssh-fix.sh"

# Restart the LXC to trigger the hook
ssh root@192.168.86.29 "pct reboot 209"
```

Verify SSH is now reachable:
```bash
ssh root@192.168.86.27
```

### 13.3 Deploy

```bash
make libby-alert \
  TWILIO_ACCOUNT_SID="..." \
  TWILIO_AUTH_TOKEN="..." \
  TWILIO_FROM="..." \
  TWILIO_TO="..." \
  DISCORD_WEBHOOK="..."
```

### 13.4 Enable Traefik Route

Uncomment the route in `ansible/files/traefik/dynamic/libby-alert.yml` and redeploy:
```bash
make traefik
```

### 13.5 Verify

```bash
# Direct
curl http://192.168.86.27

# Via Traefik
curl https://alert.woodhead.tech
```

---

## Phase 14: Piboard Dashboard (Raspberry Pi)

The piboard is a standalone Go dashboard that queries Prometheus and displays
service health, Proxmox node metrics, and alert counts on a Raspberry Pi 3B
with a Waveshare 5-inch HDMI display (800x480). Not managed by Proxmox.

### 14.1 Flash Raspberry Pi OS

1. Download Raspberry Pi OS Lite (64-bit or 32-bit for Pi 3B)
2. Flash to SD card with Raspberry Pi Imager
3. Enable SSH and configure WiFi during imaging
4. Boot the Pi, note its IP address

### 14.2 Build and Deploy Piboard

```bash
cd piboard

# Build for ARMv7 (Raspberry Pi 3B)
make build-pi

# Deploy binary + config to the Pi
make deploy PI_HOST=192.168.86.131
```

This copies the `piboard` binary, `config.yaml`, and systemd service file to the Pi.

### 14.3 Run Setup Script

The setup script installs X11, Chromium, configures auto-login, kiosk mode,
and Waveshare display settings:

```bash
ssh bwoodwar@192.168.86.131
sudo bash /tmp/deploy/setup-pi.sh
```

This:
- Installs Openbox, Chromium, xinit, and dependencies
- Configures auto-login on tty1 with `.bash_profile` launching `startx`
- Sets Waveshare HDMI timing in `/boot/firmware/config.txt`
- Creates the `piboard` systemd service
- Reboots into kiosk mode

### 14.4 Add to Ansible Inventory

The Pi is already in `ansible/inventory/hosts.yml` under the `raspberry_pi` group:
```yaml
raspberry_pi:
  hosts:
    piboard:
      ansible_host: 192.168.86.131
      ansible_user: bwoodwar
```

### 14.5 Verify

```bash
# Check piboard service
ssh bwoodwar@192.168.86.131 "sudo systemctl status piboard"

# Check the dashboard API
curl http://192.168.86.131:8080/api/health

# The Waveshare display should show the dashboard in Chromium kiosk mode
```

### 14.6 Configuration

Edit `piboard/config.yaml` to adjust:
- `prometheus_url` -- Prometheus endpoint (default: `http://192.168.86.25:9090`)
- `poll_interval` -- How often to poll Prometheus (default: `20s`)
- `services` -- List of monitored services (matched against Blackbox Exporter targets)
- `proxmox_nodes` -- List of Proxmox nodes with PVE Exporter `id` labels

---

## Phase 15: Security Hardening

### 15.1 Verify SSH Key Access

Before running this, make sure you can SSH with keys:
```bash
ssh root@192.168.86.29  # Should work without password
```

### 15.2 Apply Hardening

```bash
make harden
```

This disables SSH password auth, installs fail2ban, and enables the Proxmox firewall.

---

## Day-2 Operations

### Adding a New LXC Service

1. Create a new Terraform file: `terraform/lxc-<service>.tf`
2. Add variables to `terraform/lxc-variables.tf`
3. Add a Traefik route: `ansible/files/traefik/dynamic/<service>.yml`
4. Create an Ansible playbook: `ansible/playbooks/setup-<service>.yml`
5. Add the host to `ansible/inventory/hosts.yml`
6. Run `make apply` then `make traefik`

### Updating Traefik Routes

Edit files in `ansible/files/traefik/dynamic/` and run:
```bash
make traefik
```
Traefik watches the dynamic config directory, so changes take effect within seconds.

### Checking DDNS Status

```bash
ssh root@192.168.86.29 "journalctl -t cloudflare-ddns --no-pager -n 20"
ssh root@192.168.86.29 "cat /var/lib/ddns/current-ip"
```

### Rebuilding K8s Cluster

The recipe site and Traefik LXC are independent of K8s:
```bash
make destroy   # Only destroys K8s VMs (LXCs are unaffected)
make apply     # Recreate VMs
make bootstrap # Re-bootstrap cluster
```

If re-bootstrapping without destroying/recreating the VMs (e.g. recovering from lost talosconfig), you must wipe the VM disks first — see "Talos VMs won't boot from ISO (SeaBIOS)" in the Troubleshooting section.

### Scaling K8s

Update `terraform.tfvars`:
```hcl
controlplane_count = 3
controlplane_ips   = ["192.168.86.101", "192.168.86.102", "192.168.86.103"]
```
Then: `make apply` and `make bootstrap`

---

## Troubleshooting

### Terraform can't connect to Proxmox
- Verify API token: `curl -k -H "Authorization: PVEAPIToken=root@pam!terraform=TOKEN" https://192.168.86.29:8006/api2/json/version`
- Check `proxmox_insecure = true` in tfvars if using self-signed certs

### DDNS not updating
- Check cron: `ssh root@192.168.86.29 "crontab -l"`
- Check logs: `ssh root@192.168.86.29 "journalctl -t cloudflare-ddns"`
- Test manually: `ssh root@192.168.86.29 "/usr/local/bin/cloudflare-ddns -v"`

### Traefik not getting certificates
- Check Cloudflare API token permissions (Zone:DNS:Edit)
- Check Traefik logs: `ssh root@192.168.86.20 "journalctl -u traefik --no-pager -n 50"`
- Verify DNS propagation: `dig recipes.woodhead.tech`

### Talos nodes stuck in maintenance
- Check talosctl: `TALOSCONFIG=talos/_out/talosconfig talosctl dmesg --nodes 192.168.86.101`
- Verify Proxmox console: check the VM serial console in Proxmox web UI

### Talos VMs won't boot from ISO (SeaBIOS)
These VMs use SeaBIOS. Talos writes an MBR bootloader to disk on first install; SeaBIOS will always prefer it over the CD-ROM regardless of the Proxmox boot order setting.

**Fix:** Wipe the disk before booting from ISO. SSH to the Proxmox node hosting the VM, stop the VM, then:
```bash
rbd map thinkCentreCeph/vm-<VMID>-disk-0
DEV=$(rbd showmapped | grep vm-<VMID>-disk-0 | awk '{print $5}')
dd if=/dev/zero of=$DEV bs=1M count=100
rbd unmap $DEV
```
Set boot order to `ide2` only in Proxmox, then start the VM. It will boot from the Talos ISO into maintenance mode.

**Finding nodes in maintenance mode:** Nodes get DHCP IPs (not their static .101/.111/.112) until a config is applied. Find them by scanning for port 50000:
```bash
for i in $(seq 1 254); do (nc -z -w 1 192.168.86.$i 50000 2>/dev/null && echo "192.168.86.$i") & done; wait
```
Apply config to the DHCP IP with `--insecure`, then immediately flip the Proxmox boot order back to `scsi0` before the node reboots from disk.

### Recipe site not reachable
- Check service: `ssh root@192.168.86.21 "systemctl status recipe-site"`
- Check nginx: `ssh root@192.168.86.21 "systemctl status nginx"`
- Check Traefik route: `curl -I https://recipes.woodhead.tech`

### SSH refused on a new Debian 12.12 LXC (IPv6-only binding)
Debian 12.12 uses systemd socket activation (`ssh.socket`) which binds sshd to `:::22` (IPv6) only.
Proxmox LXC containers can't reach IPv6-only services via the veth bridge, so `ssh root@<ip>` gets refused.

Fix via `pct exec` from the Proxmox host:
```bash
pct exec <vmid> -- bash -c "
  systemctl stop ssh.socket
  systemctl disable ssh.socket
  echo 'ListenAddress 0.0.0.0' >> /etc/ssh/sshd_config
  systemctl restart ssh
"
```

Or trigger the hookscript by rebooting the LXC (if hookscript is attached):
```bash
pct reboot <vmid>
```

The Ansible playbooks for affected LXCs (libby-alert, authelia) include this fix as the first task,
so re-running the playbook also resolves it.

### Stale ARP entry causing TCP connection refusals
If `ping` works but SSH (or other TCP) is refused with `Connection refused`, a stale ARP entry
may be routing traffic to the wrong MAC address (a different LAN device).

Diagnose:
```bash
# On the Proxmox host
ip neigh show | grep <ip>
# If MAC doesn't match the LXC's MAC (visible in Proxmox UI or pct config <vmid>), it's stale
```

Fix on Proxmox host:
```bash
ip neigh del <ip> dev vmbr0
ping -c1 <ip>  # Forces ARP re-resolution
```

Fix on local machine (requires sudo):
```bash
sudo ip neigh replace <ip> dev <interface> lladdr <correct-mac>
```

The LXC's correct MAC is shown in the Proxmox web UI under the network interface settings,
or via `pct config <vmid> | grep hwaddr`.

### Talos worker missing from cluster / port 50000 RST

**Symptom:** `kubectl get nodes` shows fewer workers than expected. The missing node's
VM is running in Proxmox but `nc -z <ip> 50000` returns RST (connection refused) or
the node got a random DHCP address instead of its configured static IP.

**Cause:** A previous Talos installation on the Ceph RBD disk confuses the boot sequence.
The disk may have stale configs or a partial install. The ISO boots but the node either:
- Loads the old config from disk, tries to use a static IP that DHCP doesn't assign
- Boots from disk instead of ISO, with apid not starting cleanly

**Key diagnostic: Talos maintenance mode is slow.** Even on a clean ISO boot, port 50000
takes 10–13 minutes to open due to Ceph I/O during kernel module loading.

**Fix — automated:**
```bash
make check-iso                              # confirm ISO version matches talconfig.yaml
make rejoin-worker NODE_IP=192.168.86.113   # wipe, restart, wait, apply-config
```

**Fix — manual steps the automation performs:**
```bash
# 1. Stop the VM
ssh -i ~/.ssh/id_ansible root@192.168.86.147 'qm stop 412'

# 2. Wipe the first 10 MiB of the Ceph disk (clears partition table / bootloader)
ssh -i ~/.ssh/id_ansible root@192.168.86.147 '
  DEV=$(rbd --conf /etc/pve/ceph.conf --keyring /etc/pve/priv/ceph.client.admin.keyring \
        --id admin device map thinkCentreCeph/vm-412-disk-0)
  dd if=/dev/zero of=$DEV bs=1M count=10 status=progress
  rbd --conf /etc/pve/ceph.conf --keyring /etc/pve/priv/ceph.client.admin.keyring \
      --id admin device unmap $DEV
'

# 3. Start the VM and find its DHCP IP (it won't be .113 yet)
ssh -i ~/.ssh/id_ansible root@192.168.86.147 'qm start 412'
# Watch the ARP table until IPv4 appears:
ssh -i ~/.ssh/id_ansible root@192.168.86.147 \
  'watch -n5 "ip neigh show dev vmbr0 | grep bc:24:11:d8:4b:15"'

# 4. Wait for port 50000 to open (can take ~10 min), then apply config
until nc -z -w 3 <DHCP_IP> 50000; do sleep 10; done
talosctl apply-config --insecure --nodes <DHCP_IP> \
  --file talos/_out/worker-2.yaml

# 5. Node installs Talos v1.9.0 to disk, reboots, comes up at .113
watch -n5 kubectl --kubeconfig talos/_out/kubeconfig get nodes -o wide
```

**After rejoin, verify:**
```bash
kubectl --kubeconfig talos/_out/kubeconfig get nodes -o wide
# Expect: all 4 nodes (1 control-plane + 3 workers) showing Ready

talosctl --talosconfig talos/_out/talosconfig health
```

**ISO mismatch note:** The node may boot a newer Talos ISO (e.g. v1.12.5) than the
cluster (v1.9.0). This is harmless — the machine config contains
`installer: ghcr.io/siderolabs/installer:v1.9.0`, so the node self-installs the correct
version on first apply-config. `make check-iso` will warn you about the mismatch upfront.

---

### Authelia showing Bad Gateway
Authelia v4.38 removed the `authelia healthcheck` CLI and deprecated the `AUTHELIA_JWT_SECRET_FILE`
environment variable.

Health check fix (in `ansible/files/authelia/docker-compose.yml`):
```yaml
# Old (broken in v4.38+):
test: ["CMD", "authelia", "healthcheck"]

# New:
test: ["CMD-SHELL", "wget -q --spider http://localhost:9091/api/health || exit 1"]
```

JWT secret env var rename:
```yaml
# Old (deprecated, logs warning):
AUTHELIA_JWT_SECRET_FILE=/secrets/jwt

# New:
AUTHELIA_IDENTITY_VALIDATION_RESET_PASSWORD_JWT_SECRET_FILE=/secrets/jwt
```

After fixing, redeploy: `make authentik`

---

### Healer not auto-remediating

**Symptom:** ServiceDown alert fires to Discord but the container doesn't restart.

1. Check healer is running:
   ```bash
   ssh -i ~/.ssh/id_ansible root@192.168.86.25 'systemctl status healer && curl -s http://localhost:9110/health'
   ```

2. Check healer logs for the alert receipt and outcome:
   ```bash
   ssh -i ~/.ssh/id_ansible root@192.168.86.25 'journalctl -u healer --since "10 min ago"'
   ```

3. Check action history in the dashboard: `http://192.168.86.25:9110/`
   - `rate_limited` — healer tried 3+ times this hour, stopped to avoid a loop
   - `failed` / `timeout` — SSH to the target host failed; check that the healer key is present
   - `dry_run` — `HEALER_DRY_RUN=true` is set in the systemd unit; remove it

4. Verify healer SSH key is on the target LXC:
   ```bash
   ssh -i ~/.ssh/id_ansible root@<target-ip> 'grep healer@monitoring /root/.ssh/authorized_keys'
   ```
   If missing, add it:
   ```bash
   HEALER_PUB="ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIObZRLAe0m3dYQ1wuvs1maA+6Fwj9RQ3/gHTQVy2qZAX healer@monitoring"
   ssh -i ~/.ssh/id_ansible root@<target-ip> "echo '$HEALER_PUB' >> /root/.ssh/authorized_keys"
   ```

5. Check if a rule exists for this alert+instance in `/etc/healer/config.yaml`:
   ```bash
   ssh -i ~/.ssh/id_ansible root@192.168.86.25 'cat /etc/healer/config.yaml'
   ```

---

### TV Kiosk (Kodi) showing no signal

The display sleeps or X crashes. From any machine on the LAN:

1. Wake the display via Kodi event server:
   ```bash
   ssh -i ~/.ssh/id_ansible root@192.168.86.46 \
     'kodi-send --host=127.0.0.1 --port=9777 --action="Select"'
   ```

2. If that doesn't work, restart the kodi service:
   ```bash
   ssh -i ~/.ssh/id_ansible root@192.168.86.46 'systemctl restart kodi'
   ```

3. Verify the HTTP bridge is up (needed for Kore remote app):
   ```bash
   curl -s http://192.168.86.46:8080/jsonrpc \
     -H "Content-Type: application/json" \
     -d '{"jsonrpc":"2.0","method":"JSONRPC.Ping","id":1}'
   # Expected: {"id":1,"jsonrpc":"2.0","result":"pong"}
   ```

4. If bridge is down: `ssh root@192.168.86.46 'systemctl restart kodi-bridge'`

5. If Kodi log shows `Loading skin file: DialogConfirm.xml` on repeat — ALSA audio failed.
   Dismiss with `kodi-send --action="Select"` then check ALSA:
   ```bash
   ssh root@192.168.86.46 'aplay -l'
   ```

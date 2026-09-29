# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Overview

Infrastructure-as-Code for a homelab on Proxmox VE. It provisions a Talos Linux Kubernetes cluster, LXC containers, and VMs (TrueNAS, Home Assistant) with Traefik as the central reverse proxy, Cloudflare DDNS, and Authentik SSO (replaced the originally-planned Authelia). Domain: `woodhead.tech`.

## Key Commands

All workflow is driven by `make`. Run `make help` or read the Makefile for the full target list.

**Infrastructure (Terraform):**
```bash
make init       # terraform init
make plan       # terraform plan
make apply      # terraform apply (creates all VMs + LXCs)
make destroy    # destroy all VMs (prompts for confirmation)
```

**Service Deployment (Ansible):**
```bash
make setup      # Configure Proxmox base (run once)
make prepare    # Download ISOs to Proxmox
make traefik    # Deploy Traefik (requires CF_API_TOKEN env var)
make monitoring DISCORD_WEBHOOK=... GRAFANA_PASSWORD=... PVE_PASSWORD=... DEXCOM_USERNAME=... DEXCOM_PASSWORD=...
# NOTE: alertmind is NOT included in 'make monitoring' — deploy it separately:
make alertmind ANTHROPIC_API_KEY=sk-ant-... DISCORD_WEBHOOK=...
make authelia AUTHELIA_ADMIN_PASSWORD=...
make arr-stack
make openclaw
make wireguard
make ddns       # Deploy Cloudflare DDNS updater
```

**Kubernetes (Talos):**
```bash
# Set env vars before bootstrapping:
export CLUSTER_VIP="192.168.86.100"
export CONTROLPLANE_IPS="192.168.86.101"
export WORKER_IPS="192.168.86.111,192.168.86.112"

make bootstrap      # Generate Talos configs + init cluster (destructive, one-time)
make kubeconfig     # Fetch kubeconfig to talos/_out/kubeconfig
make health         # Check cluster node/pod health
make k8s-base       # Apply base namespaces
make k8s-base-metallb  # Apply base + MetalLB IP pool
make clean          # Delete generated talos/_out/ configs only
```

**Day-2 Operations:**
```bash
make patch-proxmox  # Patch Proxmox hosts (serial, one at a time)
make patch-lxc      # Patch Debian packages on all LXCs
make patch-docker   # Pull latest images + restart all Docker stacks
make patch-pi       # Patch Raspberry Pi devices (piboard, etc.)
```

**Accessing the cluster:**
```bash
export KUBECONFIG=talos/_out/kubeconfig
kubectl get nodes
talosctl --talosconfig talos/_out/talosconfig health
```

## Deployment Order

Changes must follow this dependency order:

1. `setup` + `prepare` — Proxmox base config + ISOs
2. `ddns` — Cloudflare DDNS (needed before TLS certs resolve)
3. `init` → `apply` — Terraform creates all infrastructure
4. Service playbooks (`traefik`, `arr-stack`, `monitoring`, etc.)
5. `bootstrap` → `kubeconfig` → `k8s-base` — Talos K8s cluster

Traefik must be running before any HTTP/HTTPS service is reachable. The K8s cluster depends on its VMs already existing from step 3.

## Architecture

**Network (192.168.86.0/24):**
- Proxmox nodes: `.29` (thinkcentre1), `.30` (thinkcentre2), `.31` (thinkcentre3), `.130` (tower1) — 4-node cluster, shared Ceph
- Traefik LXC: `.20` (single ingress for all services)
- Service LXCs: `.21`–`.26`, `.28`, `.32`, `.39`, `.58`, `.61`, `.62` (ARR stack, Plex, Jellyfin, monitoring, Authentik, OpenClaw, SDR scanner, WireGuard, wger, Mealie, Yarnl)
- TrueNAS VM: `.40` (on tower1, 16GB RAM) | Home Assistant VM: `.41`
- K8s VIP: `.100` | control plane: `.101` (tower1) | workers: `.111` (thinkcentre2), `.112` (thinkcentre3)
- Piboard (Pi 3B): `.131` (standalone monitoring dashboard, not Proxmox-managed)
- Klipper Ender 5 Pro (Pi 3B): `.136` (MainsailOS, 3D printer control, WiFi)
- MetalLB pool: `.150`–`.199`

**Talos/K8s:** Immutable OS, API-driven. Config lives in `talos/talconfig.yaml` (reference) and `talos/patches/`. Generated secrets/configs go to `talos/_out/` (gitignored).

**Traefik routing:** Static config in `ansible/files/traefik/traefik.yml`; per-service routes in `ansible/files/traefik/dynamic/*.yml`. TLS via Let's Encrypt + Cloudflare DNS challenge. Authentik `forwardAuth` middleware applied to protected routes — check the specific service's `dynamic/*.yml` for its `middlewares:` list rather than assuming a service is public.

## Homelab Ground Truth (read before debugging reachability)

- **recipe-site is retired** (decommissioned 2026-08-20, was VMID 201/`.21`) — replaced by **Mealie** (`.61`, `recipes.woodhead.tech`), **wger** (`.58`), and **Yarnl** (`.62`). All three sit behind **Authentik** (`ansible/files/traefik/dynamic/{mealie,wger,yarnl}.yml`).
- Before reasoning about whether a service exists, is public, or sits behind Authentik: check the live Traefik dynamic config and Ansible inventory — don't assume from memory or from other docs in this repo (`docs/RUNBOOK.md`, `ARCHITECTURE.md`, `INFRA_MAP.md` still describe the pre-2026-08-20 Authelia/recipe-site state and are stale; the dynamic Traefik configs and this file are ground truth).
- **Split-horizon DNS**: none since AdGuard (LXC 221) was decommissioned 2026-09-29. `*.woodhead.tech` resolves to the public IP via the router; use an `/etc/hosts` override per machine until a replacement resolver exists (tracked in Kanboard). Old config is in PBS `ct/221`. See `docs/runbooks/router-dns-not-forwarding-to-adguard.md` for history.
- **Debugging "site can't be reached"**: work down the layers in order and show evidence at each before moving to the next: (1) client DNS resolution (router, no split-horizon), (2) Traefik router match, (3) Authentik forward-auth, (4) backend container health via SSH/`docker compose ps`. Never bypass DNS (`curl --resolve`, `/etc/hosts`) to "prove" a layer works — that hides the actual failure.

**Monitoring stack:** Prometheus + Grafana + Alertmanager deployed via Docker Compose on a dedicated LXC. Discord webhook alerts. PVE exporter for Proxmox metrics. Dexcom glucose exporter polls Dexcom Share API, alerts via Twilio SMS + Home Assistant Alexa. Dashboards auto-provisioned from `ansible/files/monitoring/`.

**SDR Scanner:** Trunk Recorder + rdio-scanner on LXC 210 (192.168.86.32, thinkcentre2). RTL-SDR V4 USB passthrough decodes SNO911 P25 Phase II radio. Web UI at scanner.woodhead.tech. Deploy via `make sdr`.

**Piboard:** Go dashboard on a Raspberry Pi 3B (192.168.86.131) with a Waveshare 5" HDMI display. Polls Prometheus via HTTP API, streams status via SSE to a Chromium kiosk. Source in `piboard/`, deployed via `make deploy PI_HOST=...` from the piboard directory. Patched via `make patch-pi`.

## Configuration Files

Before first use, copy and edit:
```bash
cp terraform/terraform.tfvars.example terraform/terraform.tfvars
# Also update: ansible/inventory/hosts.yml
```

IPs in `terraform/terraform.tfvars` and `ansible/inventory/hosts.yml` must be kept in sync — Terraform sets IPs via `ipconfig0`, Ansible uses them for SSH targeting.

## Sensitive / Gitignored Files

- `terraform/terraform.tfvars` — Proxmox API token, SSH keys, cluster topology
- `talos/_out/` — Generated Talos configs containing cluster secrets
- `ansible/files/wireguard/clients/` — WireGuard private keys
- `.env` files — API tokens and credentials

## Tool Dependencies

Local tools required: `terraform >= 1.5`, `talosctl` (matching cluster version), `kubectl`, `ansible`. Terraform provider: `bpg/proxmox ~> 0.66.0`.

## Docs

Detailed reference in `docs/`:
- `ARCHITECTURE.md` — network flows, resource allocation per node
- `RUNBOOK.md` — step-by-step deployment walkthrough
- `PATCHING.md` — update strategy for each layer
- `ROADMAP.md` — planned services and IP allocations

# Makefile - Workflow orchestration for Proxmox homelab infrastructure
#
# Full lifecycle for a Talos Kubernetes cluster + LXC services on Proxmox.
# Domain: woodhead.tech | DNS: Cloudflare | TLS: Let's Encrypt via Traefik
#
# Deploy order (from fresh Proxmox):
#   make setup          - Verify Proxmox base config
#   make prepare        - Download Talos, TrueNAS ISOs
#   make ddns           - Deploy DDNS updater
#   make init           - Initialize Terraform
#   make apply          - Create all VMs + LXC containers
#   make traefik        - Configure Traefik reverse proxy
#   make recipe-site    - Deploy recipe site
#   make arr-stack      - Deploy ARR media stack
#   make monitoring     - Deploy monitoring stack
#   make openclaw       - Deploy OpenClaw AI agent
#   make authentik      - Deploy Authentik identity provider
#   make wireguard      - Deploy WireGuard VPN tunnel
#   make homeassistant  - Deploy Traefik route + trusted_proxies config for HAOS
#   make bootstrap      - Bootstrap Talos K8s cluster
#   make k8s-base       - Apply base K8s manifests
#   make sdr            - Deploy SDR scanner (Trunk Recorder + rdio-scanner)
#   make minecraft      - Deploy Minecraft server (PaperMC) for Annie
#   make harden         - Security hardening

.PHONY: setup prepare prepare-truenas ddns init plan apply \
        apply-truenas apply-homeassistant apply-lxc plan-lxc \
        traefik recipe-site arr-stack plex jellyfin monitoring openclaw authentik wireguard homeassistant beardie truenas sdr pxe mailserver zigbee2mqtt claude-os pwnagotchi \
        bootstrap kubeconfig health k8s-base harden \
        patch-proxmox patch-lxc patch-docker patch-pi destroy clean help \
        docs-build docs-dev resume-build consulting-build consulting alertmind \
        group-status group-start group-stop

TERRAFORM_DIR := terraform
TALOS_DIR := talos
ANSIBLE_DIR := ansible
SCRIPTS_DIR := scripts
K8S_DIR := k8s
TALOS_OUT := $(TALOS_DIR)/_out

# Load environment overrides if available
-include .env

help: ## Show this help
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | \
		awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-15s\033[0m %s\n", $$1, $$2}'

# ===== Phase 0: Proxmox Base Setup =====

setup: ## Verify and configure Proxmox hosts (run once after fresh install)
	cd $(ANSIBLE_DIR) && ansible-playbook playbooks/setup-proxmox-base.yml

prepare: ## Download Talos ISO to Proxmox host
	cd $(ANSIBLE_DIR) && ansible-playbook playbooks/prepare-proxmox.yml

prepare-truenas: ## Download TrueNAS Scale ISO to Proxmox host
	cd $(ANSIBLE_DIR) && ansible-playbook playbooks/prepare-truenas.yml

# ===== Phase 1: DDNS =====

ddns: ## Deploy Cloudflare DDNS updater to Proxmox host
	cd $(ANSIBLE_DIR) && ansible-playbook playbooks/setup-ddns.yml

# ===== Terraform (VMs + LXCs) =====

init: ## Initialize Terraform providers
	cd $(TERRAFORM_DIR) && terraform init

plan: ## Preview all Terraform changes (VMs + LXCs)
	cd $(TERRAFORM_DIR) && terraform plan

apply: ## Create/update all infrastructure (VMs + LXCs)
	cd $(TERRAFORM_DIR) && terraform apply

apply-truenas: ## Create TrueNAS NAS VM only (pass through data disks separately)
	cd $(TERRAFORM_DIR) && terraform apply \
		-target=proxmox_virtual_environment_vm.truenas

apply-homeassistant: ## Create Home Assistant VM (HAOS image must be pre-downloaded)
	cd $(TERRAFORM_DIR) && terraform apply \
		-target=proxmox_virtual_environment_vm.homeassistant

plan-lxc: ## Preview LXC container changes only
	cd $(TERRAFORM_DIR) && terraform plan \
		-target=proxmox_virtual_environment_container.traefik \
		-target=proxmox_virtual_environment_container.recipe_site \
		-target=proxmox_virtual_environment_container.arr \
		-target=proxmox_virtual_environment_container.plex \
		-target=proxmox_virtual_environment_container.jellyfin \
		-target=proxmox_virtual_environment_container.monitoring \
		-target=proxmox_virtual_environment_container.openclaw \
		-target=proxmox_virtual_environment_container.authelia \
		-target=proxmox_virtual_environment_container.wireguard \
		-target=proxmox_virtual_environment_container.libby_alert \
		-target=proxmox_virtual_environment_container.kanboard \
		-target=proxmox_virtual_environment_container.mailserver \
		-target=proxmox_virtual_environment_container.pxe \
		-target=proxmox_virtual_environment_container.zigbee2mqtt \
		-target=proxmox_virtual_environment_container.claude_os \
		-target=proxmox_virtual_environment_container.pwnagotchi

apply-lxc: ## Create/update LXC containers only
	cd $(TERRAFORM_DIR) && terraform apply \
		-target=proxmox_virtual_environment_container.traefik \
		-target=proxmox_virtual_environment_container.recipe_site \
		-target=proxmox_virtual_environment_container.arr \
		-target=proxmox_virtual_environment_container.plex \
		-target=proxmox_virtual_environment_container.jellyfin \
		-target=proxmox_virtual_environment_container.monitoring \
		-target=proxmox_virtual_environment_container.openclaw \
		-target=proxmox_virtual_environment_container.authelia \
		-target=proxmox_virtual_environment_container.wireguard \
		-target=proxmox_virtual_environment_container.libby_alert \
		-target=proxmox_virtual_environment_container.kanboard \
		-target=proxmox_virtual_environment_container.mailserver \
		-target=proxmox_virtual_environment_container.pxe \
		-target=proxmox_virtual_environment_container.zigbee2mqtt \
		-target=proxmox_virtual_environment_container.claude_os \
		-target=proxmox_virtual_environment_container.pwnagotchi

# ===== Phase 2-3: LXC Services =====

traefik: ## Configure Traefik reverse proxy in its LXC
	@# Source Cloudflare token from DDNS env file (same token used for DNS-01 ACME)
	@if [ ! -f $(SCRIPTS_DIR)/ddns/cloudflare.env ]; then \
		echo "Error: scripts/ddns/cloudflare.env not found. Run 'make ddns' first."; \
		exit 1; \
	fi
	. $(SCRIPTS_DIR)/ddns/cloudflare.env && cd $(ANSIBLE_DIR) && \
		ansible-playbook playbooks/setup-traefik.yml \
		--extra-vars "cf_api_token=$$CF_API_TOKEN acme_email=admin@woodhead.tech"

recipe-site: ## Deploy recipe site into its LXC
	cd $(ANSIBLE_DIR) && ansible-playbook playbooks/setup-recipe-site.yml

arr-stack: ## Deploy ARR media stack (Sonarr, Radarr, Prowlarr, etc.) into its LXC
	@if [ -z "$(WG_PRIVATE_KEY)" ]; then \
		echo "Error: WireGuard private key required"; \
		echo "Usage: make arr-stack WG_PRIVATE_KEY=<key>"; \
		exit 1; \
	fi
	cd $(ANSIBLE_DIR) && ansible-playbook playbooks/setup-arr-stack.yml \
		--extra-vars "wg_private_key=$(WG_PRIVATE_KEY)"

plex: ## Deploy Plex Media Server into its LXC (with iGPU passthrough)
	cd $(ANSIBLE_DIR) && ansible-playbook playbooks/setup-plex.yml

jellyfin: ## Deploy Jellyfin Media Server into its LXC (with iGPU passthrough)
	cd $(ANSIBLE_DIR) && ansible-playbook playbooks/setup-jellyfin.yml

monitoring: ## Deploy monitoring stack (Prometheus, Grafana, Alertmanager, Dexcom) into its LXC
	@# Usage: make monitoring DISCORD_WEBHOOK=https://... GRAFANA_PASSWORD=... PVE_USER=monitoring@pve PVE_TOKEN_NAME=prometheus PVE_TOKEN_VALUE=...
	@# Dexcom: make monitoring DEXCOM_USERNAME=user DEXCOM_PASSWORD=pass HA_GLUCOSE_WEBHOOK=http://192.168.86.41:8123/api/webhook/<id>
	@# Gutgrinda: make monitoring HA_TOKEN=<long-lived-token>  (writes /etc/prometheus/ha_token for HA scrape)
	cd $(ANSIBLE_DIR) && ansible-playbook playbooks/setup-monitoring.yml \
		$(if $(DISCORD_WEBHOOK),--extra-vars "discord_webhook=$(DISCORD_WEBHOOK)") \
		$(if $(GRAFANA_PASSWORD),--extra-vars "grafana_password=$(GRAFANA_PASSWORD)") \
		$(if $(PVE_USER),--extra-vars "pve_user=$(PVE_USER) pve_token_name=$(PVE_TOKEN_NAME) pve_token_value=$(PVE_TOKEN_VALUE)") \
		$(if $(DEXCOM_USERNAME),--extra-vars "dexcom_username=$(DEXCOM_USERNAME) dexcom_password=$(DEXCOM_PASSWORD)") \
		$(if $(HA_GLUCOSE_WEBHOOK),--extra-vars "ha_glucose_webhook=$(HA_GLUCOSE_WEBHOOK)") \
		$(if $(HA_TOKEN),--extra-vars "ha_token=$(HA_TOKEN)")

openclaw: ## Deploy OpenClaw AI agent framework into its LXC
	cd $(ANSIBLE_DIR) && ansible-playbook playbooks/setup-openclaw.yml

authentik: ## Deploy Authentik identity provider into its LXC
	cd $(ANSIBLE_DIR) && ansible-playbook playbooks/setup-authentik.yml

wireguard: ## Deploy WireGuard VPN tunnel into its LXC
	cd $(ANSIBLE_DIR) && ansible-playbook playbooks/setup-wireguard.yml

wireguard-shopstack: ## One-time: set up ShopStack management hub (wg1, 10.99.0.0/24, port 51821)
	cd $(ANSIBLE_DIR) && ansible-playbook playbooks/setup-wireguard-shopstack.yml

shopstack-add-peer: ## Register a customer spoke with the hub. Usage: make shopstack-add-peer CLIENT=tshirts-demo WG_IP=10.99.0.2
	@test -n "$(CLIENT)" || (echo "Usage: make shopstack-add-peer CLIENT=<name> WG_IP=<ip>"; exit 1)
	@test -n "$(WG_IP)"  || (echo "Usage: make shopstack-add-peer CLIENT=<name> WG_IP=<ip>"; exit 1)
	cd $(ANSIBLE_DIR) && ansible-playbook playbooks/add-shopstack-peer.yml \
		--extra-vars "peer_name=$(CLIENT) peer_ip=$(WG_IP)"

shopstack-ssh: ## SSH to a customer via WireGuard. Usage: make shopstack-ssh CLIENT=tshirts-demo
	@test -n "$(CLIENT)" || (echo "Usage: make shopstack-ssh CLIENT=<name>"; exit 1)
	ssh -i ~/.ssh/id_ansible admin@$(shell grep -A2 "$(CLIENT):" ~/Workspace/shopstack/ansible/inventory/customers/$(CLIENT).yml | grep ansible_host | awk '{print $$2}')

homeassistant: ## Deploy Traefik route for Home Assistant (post-onboarding config via HA_TOKEN=)
	cd $(ANSIBLE_DIR) && ansible-playbook playbooks/setup-homeassistant.yml \
		$(if $(HA_TOKEN),--extra-vars "ha_token=$(HA_TOKEN)")

beardie: ## Deploy Gutgrinda enclosure automation to HAOS (GUTGRINDA_DISCORD_WEBHOOK= HA_TOKEN= optional)
	cd $(ANSIBLE_DIR) && ansible-playbook playbooks/setup-homeassistant.yml --tags packages

truenas: ## Configure TrueNAS Scale via REST API (post-install: ZFS pool, datasets, NFS shares)
	@if [ -z "$(TRUENAS_PASSWORD)" ]; then \
		echo "Error: TRUENAS_PASSWORD is required."; \
		echo "Usage: make truenas TRUENAS_PASSWORD=your-root-password"; \
		exit 1; \
	fi
	cd $(ANSIBLE_DIR) && ansible-playbook playbooks/setup-truenas.yml \
		--extra-vars "truenas_password=$(TRUENAS_PASSWORD)"

libby-alert: ## Deploy Libby life alert QR website into its LXC
	@if [ -z "$(DISCORD_WEBHOOK)" ] && ([ -z "$(TWILIO_SID)" ] || [ -z "$(TWILIO_TOKEN)" ] || [ -z "$(TWILIO_FROM)" ] || [ -z "$(ALERT_PHONES)" ]); then \
		echo "Error: provide DISCORD_WEBHOOK and/or all Twilio vars (TWILIO_SID, TWILIO_TOKEN, TWILIO_FROM, ALERT_PHONES)"; \
		exit 1; \
	fi
	cd $(ANSIBLE_DIR) && ansible-playbook playbooks/setup-libby-alert.yml \
		--extra-vars "twilio_account_sid=$(TWILIO_SID) twilio_auth_token=$(TWILIO_TOKEN) \
		twilio_from_number=$(TWILIO_FROM) alert_phone_numbers=$(ALERT_PHONES) \
		$(if $(DISCORD_WEBHOOK),discord_webhook=$(DISCORD_WEBHOOK)) \
		$(if $(COOLDOWN),alert_cooldown_minutes=$(COOLDOWN))"

minecraft: ## Deploy Minecraft Java Edition server (PaperMC) for Annie
	cd $(ANSIBLE_DIR) && ansible-playbook playbooks/setup-minecraft.yml \
		$(if $(RCON_PASSWORD),--extra-vars "rcon_password=$(RCON_PASSWORD)") \
		$(if $(OPS),--extra-vars "ops=$(OPS)")

adguard: ## Deploy AdGuard Home DNS server into its LXC
	cd $(ANSIBLE_DIR) && ansible-playbook playbooks/setup-adguard.yml

step-ca: ## Deploy Smallstep step-ca SSH Certificate Authority into its LXC
	cd $(ANSIBLE_DIR) && ansible-playbook playbooks/setup-step-ca.yml

kanboard: ## Deploy Kanboard project management into its LXC
	cd $(ANSIBLE_DIR) && ansible-playbook playbooks/setup-kanboard.yml

sdr: ## Deploy SDR scanner stack (Trunk Recorder + rdio-scanner) for SNO911 fire/EMS
	cd $(ANSIBLE_DIR) && ansible-playbook playbooks/setup-sdr.yml

pxe: ## Deploy PXE boot server (proxy-DHCP + TFTP + HTTP for LAN network installs)
	cd $(ANSIBLE_DIR) && ansible-playbook playbooks/setup-pxe.yml

zigbee2mqtt: ## Deploy Zigbee2MQTT + Mosquitto on zotac (Zigbee USB dongle bridge for Home Assistant)
	cd $(ANSIBLE_DIR) && ansible-playbook playbooks/setup-zigbee2mqtt.yml

pwnagotchi: ## Deploy pwnagotchi WiFi learning device (LXC 216 on pve3, RTL8188EUS dongle)
	cd $(ANSIBLE_DIR) && ansible-playbook playbooks/setup-pwnagotchi.yml \
		$(if $(WEB_PASSWORD),--extra-vars "web_password=$(WEB_PASSWORD)")

claude-os: ## Deploy Claude OS AI memory system (OpenAI: OPENAI_API_KEY=sk-..., local: INSTALL_OLLAMA=true)
	cd $(ANSIBLE_DIR) && ansible-playbook playbooks/setup-claude-os.yml \
		$(if $(OPENAI_API_KEY),--extra-vars "openai_api_key=$(OPENAI_API_KEY)") \
		$(if $(INSTALL_OLLAMA),--extra-vars "install_ollama=$(INSTALL_OLLAMA)")

mailserver: ## Deploy Mailcow email server (Mailgun relay for outbound)
	@if [ -z "$(MAILGUN_USER)" ] || [ -z "$(MAILGUN_PASSWORD)" ]; then \
		echo "Warning: No Mailgun credentials provided. Outbound relay will not be configured."; \
		echo "Usage: make mailserver MAILGUN_USER=postmaster@mg.woodhead.tech MAILGUN_PASSWORD=<key>"; \
	fi
	cd $(ANSIBLE_DIR) && ansible-playbook playbooks/setup-mailserver.yml \
		$(if $(MAILGUN_USER),--extra-vars "mailgun_user=$(MAILGUN_USER) mailgun_password=$(MAILGUN_PASSWORD)")

# ===== Documentation =====

docs-build: ## Build the Docusaurus docs site (static output in docs-site/build/)
	cd docs-site && npm ci && npm run build

docs-dev: ## Start Docusaurus dev server (hot reload)
	cd docs-site && npm start

resume-build: ## Build the Hugo resume site (static output in resume-site/public/)
	cd resume-site && hugo --minify

consulting-build: ## Build the Astro consulting site (static output in consulting-site/dist/)
	cd consulting-site && npm ci && npm run build

consulting: ## Deploy consulting site to monitoring LXC
	cd $(ANSIBLE_DIR) && ansible-playbook playbooks/setup-consulting-site.yml

alertmind: ## Deploy alertmind AI alert triage (ANTHROPIC_API_KEY= DISCORD_WEBHOOK= SLACK_WEBHOOK= TWILIO_ACCOUNT_SID= TWILIO_AUTH_TOKEN= WHATSAPP_FROM= WHATSAPP_TO=)
	@if [ -z "$(ANTHROPIC_API_KEY)" ]; then \
		echo "Error: ANTHROPIC_API_KEY is required"; \
		echo "Usage: make alertmind ANTHROPIC_API_KEY=sk-ant-... DISCORD_WEBHOOK=https://..."; \
		exit 1; \
	fi
	cd $(ANSIBLE_DIR) && ansible-playbook playbooks/setup-alertmind.yml \
		--extra-vars "anthropic_api_key=$(ANTHROPIC_API_KEY)" \
		$(if $(DISCORD_WEBHOOK),--extra-vars "discord_webhook_url=$(DISCORD_WEBHOOK)") \
		$(if $(SLACK_WEBHOOK),--extra-vars "slack_webhook_url=$(SLACK_WEBHOOK)") \
		$(if $(TWILIO_ACCOUNT_SID),--extra-vars "twilio_account_sid=$(TWILIO_ACCOUNT_SID)") \
		$(if $(TWILIO_AUTH_TOKEN),--extra-vars "twilio_auth_token=$(TWILIO_AUTH_TOKEN)") \
		$(if $(WHATSAPP_FROM),--extra-vars "whatsapp_from=$(WHATSAPP_FROM)") \
		$(if $(WHATSAPP_TO),--extra-vars "whatsapp_to=$(WHATSAPP_TO)")

# ===== Phase 4: Talos K8s Cluster =====

bootstrap: ## Generate Talos configs and bootstrap the cluster
	chmod +x $(SCRIPTS_DIR)/bootstrap.sh
	./$(SCRIPTS_DIR)/bootstrap.sh

kubeconfig: ## Fetch kubeconfig from the running cluster
	@if [ ! -f "$(TALOS_OUT)/talosconfig" ]; then \
		echo "Error: No talosconfig found. Run 'make bootstrap' first."; \
		exit 1; \
	fi
	TALOSCONFIG=$(TALOS_OUT)/talosconfig talosctl kubeconfig $(TALOS_OUT)/kubeconfig --force
	@echo "Kubeconfig written to $(TALOS_OUT)/kubeconfig"

health: ## Check cluster health
	@if [ ! -f "$(TALOS_OUT)/talosconfig" ]; then \
		echo "Error: No talosconfig found. Run 'make bootstrap' first."; \
		exit 1; \
	fi
	TALOSCONFIG=$(TALOS_OUT)/talosconfig talosctl health

k8s-base: ## Apply base K8s manifests (namespaces, optional MetalLB)
	chmod +x $(SCRIPTS_DIR)/apply-k8s-base.sh
	./$(SCRIPTS_DIR)/apply-k8s-base.sh

k8s-base-metallb: ## Apply base K8s manifests with MetalLB
	chmod +x $(SCRIPTS_DIR)/apply-k8s-base.sh
	./$(SCRIPTS_DIR)/apply-k8s-base.sh --with-metallb

# ===== Patching =====

patch-proxmox: ## Patch Proxmox VE hosts (serial, one at a time)
	cd $(ANSIBLE_DIR) && ansible-playbook playbooks/patch-proxmox.yml

patch-lxc: ## Patch Debian packages on all LXC containers
	cd $(ANSIBLE_DIR) && ansible-playbook playbooks/patch-lxc.yml

patch-docker: ## Pull latest Docker images and restart all stacks
	cd $(ANSIBLE_DIR) && ansible-playbook playbooks/patch-docker.yml

patch-pi: ## Patch Raspberry Pi devices (piboard dashboard, etc.)
	cd $(ANSIBLE_DIR) && ansible-playbook playbooks/patch-pi.yml

# ===== Phase 5: Security =====

harden: ## Apply security hardening to Proxmox hosts
	cd $(ANSIBLE_DIR) && ansible-playbook playbooks/harden-proxmox.yml

# ===== Teardown =====

destroy: ## Tear down VMs and clean generated configs
	chmod +x $(SCRIPTS_DIR)/destroy.sh
	./$(SCRIPTS_DIR)/destroy.sh

clean: ## Remove generated Talos configs (does not destroy VMs)
	rm -rf $(TALOS_OUT)
	@echo "Cleaned generated configs."

# ===== Service Group Management =====

group-status: ## Show running status of all service groups
	cd $(ANSIBLE_DIR) && ansible-playbook playbooks/group-status.yml

group-start: ## Start a service group: make group-start GROUP=media
	@if [ -z "$(GROUP)" ]; then echo "Usage: make group-start GROUP=<name>"; exit 1; fi
	cd $(ANSIBLE_DIR) && ansible-playbook playbooks/group-start.yml \
		--extra-vars "target_group=$(GROUP)"

group-stop: ## Stop a service group: make group-stop GROUP=media
	@if [ -z "$(GROUP)" ]; then echo "Usage: make group-stop GROUP=<name>"; exit 1; fi
	cd $(ANSIBLE_DIR) && ansible-playbook playbooks/group-stop.yml \
		--extra-vars "target_group=$(GROUP)"

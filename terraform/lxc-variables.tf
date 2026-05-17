# lxc-variables.tf - Variables for LXC container provisioning

# --- LXC Storage ---
# LXC containers use local storage (faster, no Ceph overhead for lightweight services)
variable "lxc_storage" {
  description = "Proxmox storage for LXC container disks"
  type        = string
  default     = "local-lvm"
}

variable "debian_template" {
  description = "Debian LXC template file ID (e.g., local:vztmpl/debian-12-standard_12.7-1_amd64.tar.zst)"
  type        = string
  default     = "local:vztmpl/debian-12-standard_12.7-1_amd64.tar.zst"
}

# --- SSH Key ---
variable "ssh_public_key" {
  description = "SSH public key to inject into LXC containers for Ansible access"
  type        = string
  default     = ""
}

# --- Node Assignments ---
# Distribute LXC containers across Proxmox cluster nodes.
# Keys must match the container names used in each lxc-*.tf file.
variable "node_assignments" {
  description = "Map of container name to Proxmox node for multi-node distribution"
  type        = map(string)
  default     = {}
}

# --- Traefik LXC ---
variable "traefik_vmid" {
  description = "VM ID for the Traefik reverse proxy LXC"
  type        = number
  default     = 200
}

variable "traefik_ip" {
  description = "Static IP for the Traefik LXC"
  type        = string
  default     = "192.168.86.20"
}

# --- Recipe Site LXC ---
variable "recipe_site_vmid" {
  description = "VM ID for the recipe site LXC"
  type        = number
  default     = 201
}

variable "recipe_site_ip" {
  description = "Static IP for the recipe site LXC"
  type        = string
  default     = "192.168.86.21"
}

# --- ARR Stack LXC ---
variable "arr_vmid" {
  description = "VM ID for the ARR media management stack LXC"
  type        = number
  default     = 202
}

variable "arr_ip" {
  description = "Static IP for the ARR stack LXC"
  type        = string
  default     = "192.168.86.22"
}

variable "arr_cores" {
  description = "CPU cores for the ARR stack (runs multiple Docker containers)"
  type        = number
  default     = 2
}

variable "arr_memory" {
  description = "Memory in MB for the ARR stack"
  type        = number
  default     = 4096
}

variable "arr_disk_size" {
  description = "Disk size in GB for the ARR stack (configs + temp downloads, media on NAS)"
  type        = number
  default     = 20
}

# --- Plex LXC ---
variable "plex_vmid" {
  description = "VM ID for the Plex Media Server LXC"
  type        = number
  default     = 203
}

variable "plex_ip" {
  description = "Static IP for the Plex LXC"
  type        = string
  default     = "192.168.86.23"
}

variable "plex_cores" {
  description = "CPU cores for Plex (iGPU handles transcoding, CPU for metadata/scanning)"
  type        = number
  default     = 2
}

variable "plex_memory" {
  description = "Memory in MB for Plex"
  type        = number
  default     = 2048
}

variable "plex_disk_size" {
  description = "Disk size in GB for Plex (metadata + thumbnails, media on NAS)"
  type        = number
  default     = 8
}

# --- Jellyfin LXC ---
variable "jellyfin_vmid" {
  description = "VM ID for the Jellyfin Media Server LXC"
  type        = number
  default     = 204
}

variable "jellyfin_ip" {
  description = "Static IP for the Jellyfin LXC"
  type        = string
  default     = "192.168.86.24"
}

variable "jellyfin_cores" {
  description = "CPU cores for Jellyfin (iGPU handles transcoding)"
  type        = number
  default     = 2
}

variable "jellyfin_memory" {
  description = "Memory in MB for Jellyfin"
  type        = number
  default     = 2048
}

variable "jellyfin_disk_size" {
  description = "Disk size in GB for Jellyfin (metadata + cache, media on NAS)"
  type        = number
  default     = 8
}

# --- Monitoring Stack LXC ---
variable "monitoring_vmid" {
  description = "VM ID for the monitoring stack LXC (Prometheus, Grafana, Alertmanager)"
  type        = number
  default     = 205
}

variable "monitoring_ip" {
  description = "Static IP for the monitoring stack LXC"
  type        = string
  default     = "192.168.86.25"
}

variable "monitoring_cores" {
  description = "CPU cores for the monitoring stack (Prometheus query engine + Grafana rendering)"
  type        = number
  default     = 2
}

variable "monitoring_memory" {
  description = "Memory in MB for the monitoring stack (Prometheus TSDB + Grafana + exporters)"
  type        = number
  default     = 2048
}

variable "monitoring_disk_size" {
  description = "Disk size in GB for the monitoring stack (Prometheus TSDB, 30-day retention)"
  type        = number
  default     = 20
}

# --- OpenClaw LXC ---
variable "openclaw_vmid" {
  description = "VM ID for the OpenClaw AI agent framework LXC"
  type        = number
  default     = 206
}

variable "openclaw_ip" {
  description = "Static IP for the OpenClaw LXC"
  type        = string
  default     = "192.168.86.26"
}

variable "openclaw_cores" {
  description = "CPU cores for OpenClaw (Node.js gateway + CLI)"
  type        = number
  default     = 2
}

variable "openclaw_memory" {
  description = "Memory in MB for OpenClaw (Node.js runtime + LLM API calls)"
  type        = number
  default     = 2048
}

variable "openclaw_disk_size" {
  description = "Disk size in GB for OpenClaw (source build + Docker images + workspace)"
  type        = number
  default     = 20
}

# --- Authelia SSO LXC ---
variable "authelia_vmid" {
  description = "VM ID for the Authelia SSO gateway LXC"
  type        = number
  default     = 207
}

variable "authelia_ip" {
  description = "Static IP for the Authelia LXC"
  type        = string
  default     = "192.168.86.28"
}

# --- WireGuard VPN LXC ---
variable "wireguard_vmid" {
  description = "VM ID for the WireGuard VPN tunnel LXC"
  type        = number
  default     = 208
}

variable "wireguard_ip" {
  description = "Static IP for the WireGuard LXC"
  type        = string
  default     = "192.168.86.39"
}

# --- Libby Alert LXC ---
variable "libby_alert_vmid" {
  description = "VM ID for the Libby life alert website LXC"
  type        = number
  default     = 209
}

variable "libby_alert_ip" {
  description = "Static IP for the Libby alert LXC"
  type        = string
  default     = "192.168.86.27"
}

variable "libby_alert_root_password" {
  description = "Temporary root password for console access during initial setup"
  type        = string
  default     = ""
  sensitive   = true
}

# --- SDR Scanner LXC ---
variable "sdr_vmid" {
  description = "VM ID for the SDR scanner LXC (Trunk Recorder + rdio-scanner)"
  type        = number
  default     = 210
}

variable "sdr_ip" {
  description = "Static IP for the SDR scanner LXC (must be on thinkcentre2)"
  type        = string
  default     = "192.168.86.32"
}

# --- Kanboard LXC ---
variable "kanboard_vmid" {
  description = "VM ID for the Kanboard project management LXC"
  type        = number
  default     = 211
}

variable "kanboard_ip" {
  description = "Static IP for the Kanboard LXC"
  type        = string
  default     = "192.168.86.33"
}

variable "kanboard_root_password" {
  description = "Temporary root password for console access during initial setup"
  type        = string
  default     = ""
  sensitive   = true
}

# --- Mailserver LXC ---
variable "mailserver_vmid" {
  description = "VM ID for the Mailcow email server LXC"
  type        = number
  default     = 212
}

variable "mailserver_ip" {
  description = "Static IP for the Mailcow email server LXC"
  type        = string
  default     = "192.168.86.34"
}

variable "mailserver_cores" {
  description = "CPU cores for Mailcow (Postfix, Dovecot, Rspamd, SOGo, MariaDB, Redis)"
  type        = number
  default     = 2
}

variable "mailserver_memory" {
  description = "Memory in MB for Mailcow (recommend 2048-4096)"
  type        = number
  default     = 3072
}

variable "mailserver_disk_size" {
  description = "Disk size in GB for Mailcow (mailbox storage + MariaDB)"
  type        = number
  default     = 20
}

variable "mailserver_root_password" {
  description = "Temporary root password for console access during initial setup"
  type        = string
  default     = ""
  sensitive   = true
}

# --- PXE Boot Server LXC ---
variable "pxe_vmid" {
  description = "VM ID for the PXE boot server LXC (dnsmasq + nginx)"
  type        = number
  default     = 213
}

variable "pxe_ip" {
  description = "Static IP for the PXE boot server LXC"
  type        = string
  default     = "192.168.86.35"
}

variable "pxe_cores" {
  description = "CPU cores for the PXE server (file serving is lightweight)"
  type        = number
  default     = 1
}

variable "pxe_memory" {
  description = "Memory in MB for the PXE server (dnsmasq + nginx are tiny)"
  type        = number
  default     = 512
}

variable "pxe_disk_size" {
  description = "Disk size in GB for the PXE server (kernel + initramfs + airootfs per ISO)"
  type        = number
  default     = 8
}

# --- Zigbee2MQTT LXC ---
variable "zigbee2mqtt_vmid" {
  description = "VM ID for the Zigbee2MQTT LXC (must live on zotac with the USB dongle)"
  type        = number
  default     = 214
}

variable "zigbee2mqtt_ip" {
  description = "Static IP for the Zigbee2MQTT LXC"
  type        = string
  default     = "192.168.86.36"
}

# --- Claude OS LXC ---
variable "claude_os_vmid" {
  description = "VM ID for the Claude OS LXC"
  type        = number
  default     = 215
}

variable "claude_os_ip" {
  description = "Static IP for the Claude OS LXC"
  type        = string
  default     = "192.168.86.37"
}

variable "claude_os_cores" {
  description = "CPU cores for Claude OS (Python API + Node.js frontend + optional Ollama)"
  type        = number
  default     = 4
}

variable "claude_os_memory" {
  description = "Memory in MB for Claude OS (2GB min for OpenAI, 4GB+ for local Ollama lite)"
  type        = number
  default     = 4096
}

variable "claude_os_disk_size" {
  description = "Disk size in GB for Claude OS (repo + venv + SQLite DB + optional Ollama models)"
  type        = number
  default     = 20
}

# --- Pwnagotchi LXC ---
variable "pwnagotchi_vmid" {
  description = "VM ID for the Pwnagotchi LXC (must be on pve3 where WiFi dongle is attached)"
  type        = number
  default     = 216
}

variable "pwnagotchi_ip" {
  description = "Static IP for the Pwnagotchi LXC"
  type        = string
  default     = "192.168.86.38"
}

# --- Ollama LXC ---
variable "ollama_vmid" {
  description = "VM ID for the Ollama LXC"
  type        = number
  default     = 217
}

variable "ollama_ip" {
  description = "Static IP for the Ollama LXC"
  type        = string
  default     = "192.168.86.42"
}

variable "ollama_cores" {
  description = "CPU cores for Ollama (handles inference if GPU is unavailable)"
  type        = number
  default     = 4
}

variable "ollama_memory" {
  description = "Memory in MB for Ollama (8GB+ recommended for Llama 3)"
  type        = number
  default     = 8192
}

variable "ollama_disk_size" {
  description = "Disk size in GB for Ollama (models are large; 40GB+ recommended)"
  type        = number
  default     = 40
}

# --- Domain ---
variable "domain" {
  description = "Base domain name for services"
  type        = string
  default     = "woodhead.tech"
}

variable "acme_email" {
  description = "Email address for Let's Encrypt ACME registration"
  type        = string
  default     = ""
}

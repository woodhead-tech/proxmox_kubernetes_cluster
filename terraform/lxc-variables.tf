# lxc-variables.tf - Variables for LXC container provisioning

# --- Arch Linux Template ---
variable "arch_template" {
  description = "Arch Linux LXC template file ID"
  type        = string
  default     = "local:vztmpl/archlinux-base_20260420-1_amd64.tar.zst"
}

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
  default     = "192.168.86.50"
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

# --- Guacamole LXC ---
variable "guacamole_vmid" {
  description = "VM ID for the Guacamole remote desktop gateway LXC"
  type        = number
  default     = 219
}

variable "guacamole_ip" {
  description = "IP address for the Guacamole LXC"
  type        = string
  default     = "192.168.86.47"
}

variable "guacamole_root_password" {
  description = "Root password for the Guacamole LXC"
  type        = string
  default     = ""
  sensitive   = true
}

# --- Vaultwarden LXC ---
variable "vaultwarden_vmid" {
  description = "VM ID for the Vaultwarden password manager LXC"
  type        = number
  default     = 226
}

variable "vaultwarden_ip" {
  description = "Static IP for the Vaultwarden LXC"
  type        = string
  default     = "192.168.86.43"
}

variable "vaultwarden_root_password" {
  description = "Root password for the Vaultwarden LXC"
  type        = string
  default     = ""
  sensitive   = true
}

# --- Dev Desktop LXC ---
variable "dev_desktop_vmid" {
  description = "VM ID for the dev desktop LXC (Arch + XFCE + xRDP)"
  type        = number
  default     = 220
}

variable "dev_desktop_ip" {
  description = "IP address for the dev desktop LXC"
  type        = string
  default     = "192.168.86.48"
}

variable "dev_desktop_root_password" {
  description = "Root password for the dev desktop LXC"
  type        = string
  default     = ""
  sensitive   = true
}

# --- AdGuard Home LXC ---
variable "adguard_vmid" {
  description = "VM ID for the AdGuard Home DNS LXC"
  type        = number
  default     = 221
}

variable "adguard_ip" {
  description = "Static IP for the AdGuard Home LXC"
  type        = string
  default     = "192.168.86.35"
}

# --- Step-CA LXC ---
variable "step_ca_vmid" {
  description = "VM ID for the Step-CA SSH certificate authority LXC"
  type        = number
  default     = 222
}

variable "step_ca_ip" {
  description = "Static IP for the Step-CA LXC"
  type        = string
  default     = "192.168.86.36"
}

# --- Photos LXC ---
variable "photos_vmid" {
  description = "VM ID for the graduation photos upload app LXC"
  type        = number
  default     = 218
}

variable "photos_ip" {
  description = "Static IP for the photos LXC"
  type        = string
  default     = "192.168.86.45"
}

variable "photos_root_password" {
  description = "Root password for the photos LXC"
  type        = string
  default     = ""
  sensitive   = true
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


# --- Omada Controller ---
variable "omada_vmid" {
  description = "VM ID for the Omada WiFi Controller LXC"
  type        = number
  default     = 225
}

variable "omada_ip" {
  description = "Static IP for the Omada Controller LXC"
  type        = string
  default     = "192.168.86.49"
}

variable "omada_root_password" {
  description = "Temporary root password for console access during initial setup"
  type        = string
  default     = ""
  sensitive   = true
}

# --- Static Sites LXC ---
variable "static_sites_vmid" {
  description = "VM ID for the static sites LXC (docs, resume, homelab, consulting, landing, v2mom)"
  type        = number
  default     = 228
}

variable "static_sites_ip" {
  description = "Static IP for the static sites LXC"
  type        = string
  default     = "192.168.86.51"
}

variable "static_sites_root_password" {
  description = "Temporary root password for console access during initial setup"
  type        = string
  default     = ""
  sensitive   = true
}

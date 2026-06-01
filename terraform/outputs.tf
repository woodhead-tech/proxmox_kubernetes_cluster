# outputs.tf - Useful outputs after VM creation

output "controlplane_vm_ids" {
  description = "VM IDs of control plane nodes"
  value       = proxmox_virtual_environment_vm.controlplane[*].vm_id
}

output "controlplane_names" {
  description = "Names of control plane nodes"
  value       = proxmox_virtual_environment_vm.controlplane[*].name
}

output "worker_vm_ids" {
  description = "VM IDs of worker nodes"
  value       = proxmox_virtual_environment_vm.worker[*].vm_id
}

output "worker_names" {
  description = "Names of worker nodes"
  value       = proxmox_virtual_environment_vm.worker[*].name
}

output "controlplane_ips" {
  description = "Control plane node IPs (from variables)"
  value       = var.controlplane_ips
}

output "worker_ips" {
  description = "Worker node IPs (from variables)"
  value       = var.worker_ips
}

output "cluster_vip" {
  description = "Kubernetes API VIP"
  value       = var.cluster_vip
}

output "cluster_endpoint" {
  description = "Kubernetes API endpoint URL"
  value       = "https://${var.cluster_vip}:6443"
}

# --- LXC Outputs ---

output "traefik_ip" {
  description = "Traefik reverse proxy LXC IP"
  value       = var.traefik_ip
}

output "traefik_vmid" {
  description = "Traefik LXC VM ID"
  value       = proxmox_virtual_environment_container.traefik.vm_id
}

output "recipe_site_ip" {
  description = "Recipe site LXC IP"
  value       = var.recipe_site_ip
}

output "recipe_site_vmid" {
  description = "Recipe site LXC VM ID"
  value       = proxmox_virtual_environment_container.recipe_site.vm_id
}

output "arr_ip" {
  description = "ARR stack LXC IP"
  value       = var.arr_ip
}

output "arr_vmid" {
  description = "ARR stack LXC VM ID"
  value       = proxmox_virtual_environment_container.arr.vm_id
}

output "plex_ip" {
  description = "Plex Media Server LXC IP"
  value       = var.plex_ip
}

output "plex_vmid" {
  description = "Plex LXC VM ID"
  value       = proxmox_virtual_environment_container.plex.vm_id
}

output "monitoring_ip" {
  description = "Monitoring stack LXC IP"
  value       = var.monitoring_ip
}

output "monitoring_vmid" {
  description = "Monitoring stack LXC VM ID"
  value       = proxmox_virtual_environment_container.monitoring.vm_id
}

output "authelia_ip" {
  description = "Authelia SSO gateway LXC IP"
  value       = var.authelia_ip
}

output "authelia_vmid" {
  description = "Authelia LXC VM ID"
  value       = proxmox_virtual_environment_container.authelia.vm_id
}

output "wireguard_ip" {
  description = "WireGuard VPN tunnel LXC IP"
  value       = var.wireguard_ip
}

output "wireguard_vmid" {
  description = "WireGuard LXC VM ID"
  value       = proxmox_virtual_environment_container.wireguard.vm_id
}

output "adguard_ip" {
  description = "AdGuard Home DNS LXC IP"
  value       = var.adguard_ip
}

output "adguard_vmid" {
  description = "AdGuard Home LXC VM ID"
  value       = proxmox_virtual_environment_container.adguard.vm_id
}

output "step_ca_ip" {
  description = "Step-CA SSH CA LXC IP"
  value       = var.step_ca_ip
}

output "step_ca_vmid" {
  description = "Step-CA LXC VM ID"
  value       = proxmox_virtual_environment_container.step_ca.vm_id
}

output "domain" {
  description = "Base domain for services"
  value       = var.domain
}

# --- TrueNAS Outputs ---

output "truenas_ip" {
  description = "TrueNAS NAS IP (configured inside TrueNAS)"
  value       = var.truenas_ip
}

output "truenas_vmid" {
  description = "TrueNAS NAS VM ID"
  value       = proxmox_virtual_environment_vm.truenas.vm_id
}

# --- Home Assistant Outputs ---

output "homeassistant_ip" {
  description = "Home Assistant IP (configured inside HAOS)"
  value       = var.homeassistant_ip
}

output "homeassistant_vmid" {
  description = "Home Assistant VM ID"
  value       = proxmox_virtual_environment_vm.homeassistant.vm_id
}


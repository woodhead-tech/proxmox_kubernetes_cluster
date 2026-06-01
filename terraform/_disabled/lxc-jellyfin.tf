# lxc-jellyfin.tf - Jellyfin Media Server LXC container
#
# Jellyfin is a fully open-source media server (no subscription needed
# for hardware transcoding, unlike Plex Pass). Shares the same TrueNAS
# media library as Plex -- you can run both side by side.
#
# Hardware transcoding uses Intel Quick Sync via /dev/dri passthrough
# (configured by the Ansible playbook on the Proxmox host).
#
# Good for sharing with family/friends since Jellyfin doesn't require
# account creation on a third-party service (no Plex account needed).
#
# Media is stored on TrueNAS and mounted via NFS at /media.
# Jellyfin config lives on the LXC disk at /var/lib/jellyfin.

resource "proxmox_virtual_environment_container" "jellyfin" {
  node_name   = lookup(var.node_assignments, "jellyfin", var.proxmox_node)
  vm_id       = var.jellyfin_vmid
  description = "Jellyfin Media Server - open source streaming for ${var.domain}"
  tags        = ["service", "media", "jellyfin"]

  unprivileged  = true
  started       = true
  start_on_boot = true

  operating_system {
    template_file_id = var.debian_template
    type             = "debian"
  }

  cpu {
    cores = var.jellyfin_cores
    units = 1024  # Normal -- transcoding uses iGPU, not CPU
  }

  memory {
    dedicated = var.jellyfin_memory
  }

  disk {
    datastore_id = var.lxc_storage
    size         = var.jellyfin_disk_size
  }

  network_interface {
    name   = "eth0"
    bridge = var.network_bridge
  }

  # Static IP, DNS, and SSH key for Ansible access
  initialization {
    hostname = "jellyfin"

    ip_config {
      ipv4 {
        address = "${var.jellyfin_ip}/${var.network_subnet}"
        gateway = var.network_gateway
      }
    }

    dns {
      servers = var.nameservers
    }

    user_account {
      keys = var.ssh_public_key != "" ? [var.ssh_public_key] : []
    }
  }

  # Nesting for device access
  features {
    nesting = true
  }

  lifecycle {
    # Proxmox returns dns.domain = " " (a space) when unset; provider bug.
    ignore_changes = [
      initialization[0].dns[0].domain,
    ]
  }
}

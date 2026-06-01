# lxc-adguard.tf - AdGuard Home DNS LXC container
#
# Network-wide DNS with ad blocking and local DNS overrides.
# Replaces the router's default DNS for all LAN clients.

resource "proxmox_virtual_environment_container" "adguard" {
  node_name   = lookup(var.node_assignments, "adguard", var.proxmox_node)
  vm_id       = var.adguard_vmid
  description = "AdGuard Home DNS - network-wide ad blocking for ${var.domain}"
  tags        = ["infrastructure", "dns", "adguard"]

  unprivileged  = true
  started       = true
  start_on_boot = true

  operating_system {
    template_file_id = var.debian_template
    type             = "debian"
  }

  cpu {
    cores = 1
    units = 1500
  }

  memory {
    dedicated = 256
  }

  disk {
    datastore_id = var.lxc_storage
    size         = 4
  }

  network_interface {
    name   = "eth0"
    bridge = var.network_bridge
  }

  initialization {
    hostname = "adguard"

    ip_config {
      ipv4 {
        address = "${var.adguard_ip}/${var.network_subnet}"
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

  features {
    nesting = true
  }

  lifecycle {
    ignore_changes = [
      initialization[0].dns[0].domain,
    ]
  }
}

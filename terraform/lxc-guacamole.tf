# lxc-guacamole.tf - Apache Guacamole browser-based remote desktop gateway
#
# Lightweight LXC running Docker Compose with guacamole + guacd + postgres.
# Provides browser-based RDP/VNC/SSH to all homelab hosts via guac.woodhead.tech.
# Protected by Authentik SSO.

resource "proxmox_virtual_environment_container" "guacamole" {
  node_name   = lookup(var.node_assignments, "guacamole", var.proxmox_node)
  vm_id       = var.guacamole_vmid
  description = "Apache Guacamole browser-based remote desktop gateway"
  tags        = ["service", "guacamole"]

  unprivileged  = true
  started       = true
  start_on_boot = true

  operating_system {
    template_file_id = var.debian_template
    type             = "debian"
  }

  cpu {
    cores = 2
    units = 512
  }

  memory {
    dedicated = 1024
  }

  disk {
    datastore_id = var.lxc_storage
    size         = 10
  }

  network_interface {
    name   = "eth0"
    bridge = var.network_bridge
  }

  initialization {
    hostname = "guacamole"

    ip_config {
      ipv4 {
        address = "${var.guacamole_ip}/${var.network_subnet}"
        gateway = var.network_gateway
      }
    }

    dns {
      servers = var.nameservers
    }

    user_account {
      keys     = var.ssh_public_key != "" ? [var.ssh_public_key] : []
      password = var.guacamole_root_password
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

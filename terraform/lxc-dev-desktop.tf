# lxc-dev-desktop.tf - Remote dev desktop LXC (XFCE + xRDP)
#
# Placed on tower1 — most available RAM in the cluster (AMD Ryzen 7, 31GB total).
# Accessible via xRDP directly on LAN, or via Guacamole at guac.woodhead.tech.

resource "proxmox_virtual_environment_container" "dev_desktop" {
  node_name   = lookup(var.node_assignments, "dev-desktop", "tower1")
  vm_id       = var.dev_desktop_vmid
  description = "Remote dev desktop — XFCE + xRDP, accessible via Guacamole"
  tags        = ["service", "desktop"]

  unprivileged  = true
  started       = true
  start_on_boot = true

  operating_system {
    template_file_id = var.arch_template
    type             = "archlinux"
  }

  cpu {
    cores = 4
    units = 1024
  }

  memory {
    dedicated = 4096
  }

  disk {
    datastore_id = var.lxc_storage
    size         = 30
  }

  network_interface {
    name   = "eth0"
    bridge = var.network_bridge
  }

  initialization {
    hostname = "dev-desktop"

    ip_config {
      ipv4 {
        address = "${var.dev_desktop_ip}/${var.network_subnet}"
        gateway = var.network_gateway
      }
    }

    dns {
      servers = var.nameservers
    }

    user_account {
      keys     = var.ssh_public_key != "" ? [var.ssh_public_key] : []
      password = var.dev_desktop_root_password
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

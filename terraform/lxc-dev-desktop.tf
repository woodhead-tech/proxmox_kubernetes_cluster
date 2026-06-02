# lxc-dev-desktop.tf - Claude Code LXC with ttyd web terminal
#
# Placed on tower1 — most available RAM in the cluster (AMD Ryzen 7, 31GB total).
# Accessible via browser at claude.woodhead.tech (Traefik + Authentik).

resource "proxmox_virtual_environment_container" "dev_desktop" {
  node_name   = lookup(var.node_assignments, "dev-desktop", "tower1")
  vm_id       = var.dev_desktop_vmid
  description = "Claude Code LXC — ttyd web terminal at claude.woodhead.tech"
  tags        = ["service", "claude"]

  unprivileged  = true
  started       = true
  start_on_boot = true

  operating_system {
    template_file_id = "local:vztmpl/debian-12-standard_12.12-1_amd64.tar.zst"
    type             = "debian"
  }

  cpu {
    cores = 4
    units = 1024
  }

  memory {
    dedicated = 2048
  }

  disk {
    datastore_id = var.lxc_storage
    size         = 20
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

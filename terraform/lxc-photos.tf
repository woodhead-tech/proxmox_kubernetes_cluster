# lxc-photos.tf - Graduation photos upload app LXC container
#
# Go web app for event photo uploads with live WebSocket gallery.
# Runs at photos.woodhead.tech, no auth (QR code is the gate).
# 2 cores / 2GB RAM for image processing worker pool.

resource "proxmox_virtual_environment_container" "photos" {
  node_name   = lookup(var.node_assignments, "photos", "thinkcentre1")
  vm_id       = var.photos_vmid
  description = "Graduation photos upload app"
  tags        = ["service", "photos"]

  unprivileged  = true
  started       = true
  start_on_boot = true

  operating_system {
    template_file_id = var.debian_template
    type             = "debian"
  }

  cpu {
    cores = 2
    units = 1024
  }

  memory {
    dedicated = 2048
  }

  disk {
    datastore_id = var.lxc_storage
    size         = 32
  }

  network_interface {
    name   = "eth0"
    bridge = var.network_bridge
  }

  initialization {
    hostname = "photos"

    ip_config {
      ipv4 {
        address = "${var.photos_ip}/${var.network_subnet}"
        gateway = var.network_gateway
      }
    }

    dns {
      servers = var.nameservers
    }

    user_account {
      keys     = var.ssh_public_key != "" ? [var.ssh_public_key] : []
      password = var.photos_root_password
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

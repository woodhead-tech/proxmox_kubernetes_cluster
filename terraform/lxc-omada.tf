# lxc-omada.tf - TP-Link Omada Software Controller LXC
#
# Runs the Omada Software Controller for managing TP-Link EAP access points.
# Provides centralized AP management: SSID/VLAN assignment, firmware updates,
# client monitoring, and mesh backhaul configuration.
#
# Part of Project Popeye network migration.
# Nesting enabled for Docker-in-LXC support.

resource "proxmox_virtual_environment_container" "omada" {
  node_name   = lookup(var.node_assignments, "omada", var.proxmox_node)
  vm_id       = var.omada_vmid
  description = "TP-Link Omada WiFi Controller"
  tags        = ["service", "omada", "network"]

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
    hostname = "omada"

    ip_config {
      ipv4 {
        address = "${var.omada_ip}/${var.network_subnet}"
        gateway = var.network_gateway
      }
    }

    dns {
      servers = var.nameservers
    }

    user_account {
      keys     = var.ssh_public_key != "" ? [var.ssh_public_key] : []
      password = var.omada_root_password
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

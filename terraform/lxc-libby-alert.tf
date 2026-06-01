# lxc-libby-alert.tf - Libby life alert QR website LXC container
#
# Single LXC running Docker Compose with the libby-alert Go web server.
# Serves Libby's emergency info at alert.woodhead.tech and fires
# SMS + Discord alerts when the QR code is scanned.
#
# Nesting enabled for Docker-in-LXC support.
# Twilio credentials and webhook URLs are injected via Ansible --extra-vars.

resource "proxmox_virtual_environment_container" "libby_alert" {
  node_name   = lookup(var.node_assignments, "libby_alert", var.proxmox_node)
  vm_id       = var.libby_alert_vmid
  description = "Libby life alert QR website"
  tags        = ["service", "libby-alert"]

  unprivileged  = true
  started       = true
  start_on_boot = true

  operating_system {
    template_file_id = var.debian_template
    type             = "debian"
  }

  cpu {
    cores = 1
    units = 512
  }

  memory {
    dedicated = 512
  }

  disk {
    datastore_id = var.lxc_storage
    size         = 8
  }

  network_interface {
    name   = "eth0"
    bridge = var.network_bridge
  }

  initialization {
    hostname = "libby-alert"

    ip_config {
      ipv4 {
        address = "${var.libby_alert_ip}/${var.network_subnet}"
        gateway = var.network_gateway
      }
    }

    dns {
      servers = var.nameservers
    }

    user_account {
      keys     = var.ssh_public_key != "" ? [var.ssh_public_key] : []
      password = var.libby_alert_root_password
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

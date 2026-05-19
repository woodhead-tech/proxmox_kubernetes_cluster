# lxc-unifi.tf - UniFi Network Application LXC container
#
# Runs the UniFi Network Application (Java) + MongoDB via Docker Compose.
# Manages all UniFi APs at unifi.woodhead.tech, protected by Authentik.
#
# Resource sizing: UniFi is a Java app backed by MongoDB — it needs real RAM.
# 2GB is the practical minimum; MongoDB alone wants ~512MB.
#
# Nesting enabled for Docker-in-LXC support.

resource "proxmox_virtual_environment_container" "unifi" {
  node_name   = lookup(var.node_assignments, "unifi", var.proxmox_node)
  vm_id       = var.unifi_vmid
  description = "UniFi Network Application — WiFi controller"
  tags        = ["service", "unifi", "network"]

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
    dedicated = 2048
  }

  disk {
    datastore_id = var.lxc_storage
    size         = 15
  }

  network_interface {
    name   = "eth0"
    bridge = var.network_bridge
  }

  initialization {
    hostname = "unifi"

    ip_config {
      ipv4 {
        address = "${var.unifi_ip}/${var.network_subnet}"
        gateway = var.network_gateway
      }
    }

    dns {
      servers = var.nameservers
    }

    user_account {
      keys     = var.ssh_public_key != "" ? [var.ssh_public_key] : []
      password = var.unifi_root_password
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

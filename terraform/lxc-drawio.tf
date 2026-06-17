# lxc-drawio.tf - draw.io self-hosted diagramming app
#
# Single LXC running the official jgraph/drawio Docker image via Compose.
# Stateless — no persistent volumes needed.
# Routed via Traefik at draw.woodhead.tech, protected by Authentik SSO.
#
# Nesting enabled for Docker-in-LXC support.

resource "proxmox_virtual_environment_container" "drawio" {
  node_name   = lookup(var.node_assignments, "drawio", var.proxmox_node)
  vm_id       = var.drawio_vmid
  description = "draw.io self-hosted diagramming app"
  tags        = ["service", "drawio"]

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
    hostname = "drawio"

    ip_config {
      ipv4 {
        address = "${var.drawio_ip}/${var.network_subnet}"
        gateway = var.network_gateway
      }
    }

    dns {
      servers = var.nameservers
    }

    user_account {
      keys     = var.ssh_public_key != "" ? [var.ssh_public_key] : []
      password = var.drawio_root_password
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

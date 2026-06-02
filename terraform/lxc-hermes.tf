# lxc-hermes.tf - Hermes autonomous AI agent (Nous Research)
#
# Accessible at hermes.woodhead.tech behind Authentik SSO.
# Uses external LLM provider (Anthropic/OpenRouter) — no local GPU needed.

resource "proxmox_virtual_environment_container" "hermes" {
  node_name   = lookup(var.node_assignments, "hermes", "thinkcentre1")
  vm_id       = var.hermes_vmid
  description = "Hermes autonomous AI agent — hermes.woodhead.tech"
  tags        = ["service", "ai"]

  unprivileged  = true
  started       = true
  start_on_boot = true

  operating_system {
    template_file_id = "local:vztmpl/debian-12-standard_12.12-1_amd64.tar.zst"
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
    size         = 15
  }

  network_interface {
    name   = "eth0"
    bridge = var.network_bridge
  }

  initialization {
    hostname = "hermes"

    ip_config {
      ipv4 {
        address = "${var.hermes_ip}/${var.network_subnet}"
        gateway = var.network_gateway
      }
    }

    dns {
      servers = var.nameservers
    }

    user_account {
      keys     = var.ssh_public_key != "" ? [var.ssh_public_key] : []
      password = "Hermes2026!"
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

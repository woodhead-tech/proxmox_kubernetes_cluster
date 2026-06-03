# lxc-vaultwarden.tf - Vaultwarden (self-hosted Bitwarden-compatible) LXC
#
# Lightweight password manager server. Vaultwarden is a single Go binary with
# SQLite — no external DB required. Admin panel at vault.woodhead.tech/admin is
# protected by Authentik; the main API/web vault uses Vaultwarden's own auth
# so Bitwarden clients (browser ext, mobile, desktop) work unimpeded.
#
# After terraform apply:
#   make vaultwarden
# Then complete initial setup at https://vault.woodhead.tech/admin

resource "proxmox_virtual_environment_container" "vaultwarden" {
  node_name   = lookup(var.node_assignments, "vaultwarden", "thinkcentre1")
  vm_id       = var.vaultwarden_vmid
  description = "Vaultwarden self-hosted password manager"
  tags        = ["service", "vaultwarden", "security"]

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
    size         = 4
  }

  network_interface {
    name   = "eth0"
    bridge = var.network_bridge
  }

  initialization {
    hostname = "vaultwarden"

    ip_config {
      ipv4 {
        address = "${var.vaultwarden_ip}/${var.network_subnet}"
        gateway = var.network_gateway
      }
    }

    dns {
      servers = var.nameservers
    }

    user_account {
      keys     = var.ssh_public_key != "" ? [var.ssh_public_key] : []
      password = var.vaultwarden_root_password
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

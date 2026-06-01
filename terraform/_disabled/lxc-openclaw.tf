# lxc-openclaw.tf - OpenClaw AI agent framework LXC container
#
# Single LXC running Docker Compose with OpenClaw:
#   - openclaw-gateway (API server, session management, tool execution)
#   - openclaw-cli (interactive terminal, shares gateway network)
#
# OpenClaw is built from source (no published Docker image).
# The Ansible playbook handles git clone + docker build.
#
# Nesting is enabled for Docker-in-LXC support.
# LLM API keys are injected via Ansible --extra-vars (not stored in git).

resource "proxmox_virtual_environment_container" "openclaw" {
  node_name   = lookup(var.node_assignments, "openclaw", var.proxmox_node)
  vm_id       = var.openclaw_vmid
  description = "OpenClaw AI agent framework - gateway + CLI"
  tags        = ["service", "openclaw", "ai"]

  unprivileged  = true
  started       = true
  start_on_boot = true

  operating_system {
    template_file_id = var.debian_template
    type             = "debian"
  }

  cpu {
    cores = var.openclaw_cores
    units = 800  # Low -- bursty but not latency-critical
  }

  memory {
    dedicated = var.openclaw_memory
  }

  disk {
    datastore_id = var.lxc_storage
    size         = var.openclaw_disk_size
  }

  network_interface {
    name   = "eth0"
    bridge = var.network_bridge
  }

  # Static IP, DNS, and SSH key for Ansible access
  initialization {
    hostname = "openclaw"

    ip_config {
      ipv4 {
        address = "${var.openclaw_ip}/${var.network_subnet}"
        gateway = var.network_gateway
      }
    }

    dns {
      servers = var.nameservers
    }

    user_account {
      keys = var.ssh_public_key != "" ? [var.ssh_public_key] : []
    }
  }

  # Nesting required for Docker-in-LXC
  features {
    nesting = true
  }

  lifecycle {
    # Proxmox returns dns.domain = " " (a space) when unset; provider bug.
    ignore_changes = [
      initialization[0].dns[0].domain,
    ]
  }
}

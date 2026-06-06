# lxc-ollama.tf - Ollama LLM Inference LXC container
#
# Ollama serves local large language models (LLMs) via a REST API.
# Hardware acceleration uses the Proxmox host's GPU (Intel iGPU or NVIDIA).
#
# GPU passthrough requires the LXC to run on a Proxmox node with the 
# physical hardware. Pin this container to that node using node_assignments.

resource "proxmox_virtual_environment_container" "ollama" {
  node_name   = lookup(var.node_assignments, "ollama", var.proxmox_node)
  vm_id       = var.ollama_vmid
  description = "Ollama - Local LLM Inference for ${var.domain}"
  tags        = ["service", "ai", "ollama"]

  unprivileged  = true
  started       = true
  start_on_boot = true

  operating_system {
    template_file_id = var.debian_template
    type             = "debian"
  }

  cpu {
    cores = var.ollama_cores
    units = 1024
  }

  memory {
    dedicated = var.ollama_memory
  }

  disk {
    datastore_id = var.lxc_storage
    size         = var.ollama_disk_size
  }

  network_interface {
    name   = "eth0"
    bridge = var.network_bridge
  }

  # Static IP, DNS, and SSH key for Ansible access
  initialization {
    hostname = "ollama"

    ip_config {
      ipv4 {
        address = "${var.ollama_ip}/${var.network_subnet}"
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

  # Nesting and device access for GPU passthrough
  features {
    nesting = true
  }

  lifecycle {
    ignore_changes = [
      initialization[0].dns[0].domain,
    ]
  }
}

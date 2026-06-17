# lxc-immich.tf - Immich self-hosted photo/video library LXC container
#
# Runs the full Immich Docker Compose stack:
#   immich-server, immich-machine-learning, redis, postgres (pgvecto-rs)
#
# Machine learning inference is CPU-heavy; 4 cores + 6GB RAM is the minimum.
# Photos/videos are stored at /opt/immich/photos (bind mount, not Docker volume).
# Place on tower1 — it has the most available RAM in the cluster.
#
# Nesting enabled for Docker-in-LXC support.
# Deploy after terraform apply: make immich

resource "proxmox_virtual_environment_container" "immich" {
  node_name   = lookup(var.node_assignments, "immich", var.proxmox_node)
  vm_id       = var.immich_vmid
  description = "Immich self-hosted photo/video library"
  tags        = ["service", "immich", "photos"]

  unprivileged  = true
  started       = true
  start_on_boot = true

  operating_system {
    template_file_id = var.debian_template
    type             = "debian"
  }

  cpu {
    cores = 4
    units = 512
  }

  memory {
    # 6144MB for immich-server + machine-learning + postgres + redis
    dedicated = 6144
  }

  disk {
    datastore_id = var.lxc_storage
    # 32GB: OS + Docker images + model cache (~3GB for ML models) + metadata
    size = 32
  }

  network_interface {
    name   = "eth0"
    bridge = var.network_bridge
  }

  initialization {
    hostname = "immich"

    ip_config {
      ipv4 {
        address = "${var.immich_ip}/${var.network_subnet}"
        gateway = var.network_gateway
      }
    }

    dns {
      servers = var.nameservers
    }

    user_account {
      keys     = var.ssh_public_key != "" ? [var.ssh_public_key] : []
      password = var.immich_root_password
    }
  }

  features {
    # Required for Docker-in-LXC
    nesting = true
  }

  lifecycle {
    ignore_changes = [
      initialization[0].dns[0].domain,
    ]
  }
}

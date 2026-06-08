# lxc-static-sites.tf - Static sites LXC container
#
# Dedicated LXC for all public-facing static web properties.
# Splits static sites off monitoring-stack to reduce blast radius:
# a monitoring redeploy no longer takes down docs, resume, consulting, etc.
#
# Services migrated from monitoring-stack (192.168.86.25):
#   docs-site      (port 8081)  → docs.woodhead.tech
#   resume-site    (port 8082)  → resume.woodhead.tech
#   landing-site   (port 8083)  → lab.woodhead.tech
#   homelab-site   (port 8084)  → homelab.woodhead.tech
#   consulting-site(port 8085)  → consulting.woodhead.tech
#   v2mom-site     (port 8087)  → v2mom.woodhead.tech
#
# After migration, remove these services from ansible/files/monitoring/docker-compose.yml.
#
# VMID: 228 | IP: 192.168.86.51 | Group: apps

resource "proxmox_virtual_environment_container" "static_sites" {
  node_name   = lookup(var.node_assignments, "static-sites", var.proxmox_node)
  vm_id       = var.static_sites_vmid
  description = "Static web sites (docs, resume, homelab, consulting, landing, v2mom)"
  tags        = ["service", "static-sites", "web"]

  unprivileged  = true
  started       = true
  start_on_boot = true

  operating_system {
    template_file_id = var.debian_template
    type             = "debian"
  }

  cpu {
    cores = 1
    units = 256
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
    hostname = "static-sites"

    ip_config {
      ipv4 {
        address = "${var.static_sites_ip}/${var.network_subnet}"
        gateway = var.network_gateway
      }
    }

    dns {
      servers = var.nameservers
    }

    user_account {
      keys     = var.ssh_public_key != "" ? [var.ssh_public_key] : []
      password = var.static_sites_root_password
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

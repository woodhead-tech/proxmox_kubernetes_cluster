# lxc-sdr.tf - SDR (Software Defined Radio) scanner LXC
#
# Runs Trunk Recorder (P25 Phase II decoder) + rdio-scanner (web UI)
# for Snohomish County SNO911 trunked radio system.
#
# Must live on thinkcentre2 where the RTL-SDR V4 dongle is physically attached.
# The LXC is privileged so Docker can access USB devices inside the container.
#
# After `terraform apply`, run: make sdr
# USB passthrough is configured post-provision via Ansible (adds cgroup rules to
# /etc/pve/lxc/<vmid>.conf on the Proxmox host, then restarts the LXC).

resource "proxmox_virtual_environment_container" "sdr" {
  node_name   = "thinkcentre2"
  vm_id       = var.sdr_vmid
  description = "SDR scanner - Trunk Recorder + rdio-scanner for SNO911"
  tags        = ["service", "sdr", "scanner"]

  unprivileged  = false   # privileged required for USB device passthrough in Docker
  started       = true
  start_on_boot = true

  operating_system {
    template_file_id = var.debian_template
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
    size         = 20
  }

  network_interface {
    name   = "eth0"
    bridge = var.network_bridge
  }

  initialization {
    hostname = "sdr"

    ip_config {
      ipv4 {
        address = "${var.sdr_ip}/${var.network_subnet}"
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

  lifecycle {
    ignore_changes = [
      initialization[0].dns[0].domain,
    ]
  }
}

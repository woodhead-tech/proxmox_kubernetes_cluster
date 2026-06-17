# lxc-pxe.tf - PXE boot server LXC container
#
# Serves network boot for LAN devices (e.g. Lenovo Legion Go).
# Runs dnsmasq (proxy-DHCP + TFTP) and nginx (HTTP squashfs serving).
# Does not replace the router's DHCP server — proxy-DHCP mode only.

resource "proxmox_virtual_environment_container" "pxe" {
  node_name   = lookup(var.node_assignments, "pxe", var.proxmox_node)
  vm_id       = var.pxe_vmid
  description = "PXE boot server - dnsmasq (proxy-DHCP/TFTP) + nginx (HTTP ISO serving)"
  tags        = ["infrastructure", "pxe", "netboot"]

  unprivileged  = true
  started       = true
  start_on_boot = true

  features {
    nesting = true
  }

  operating_system {
    template_file_id = var.debian_template
    type             = "debian"
  }

  cpu {
    cores = var.pxe_cores
    units = 512
  }

  memory {
    dedicated = var.pxe_memory
  }

  disk {
    datastore_id = var.lxc_storage
    size         = var.pxe_disk_size
  }

  network_interface {
    name   = "eth0"
    bridge = var.network_bridge
  }

  initialization {
    hostname = "pxe"

    ip_config {
      ipv4 {
        address = "${var.pxe_ip}/${var.network_subnet}"
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

# lxc-dns.tf - Split-horizon DNS LXC (dnsmasq)
#
# Replaces the decommissioned AdGuard LXC. Answers *.woodhead.tech with the
# Traefik LAN IP so LAN clients (and containers like Seerr) skip the public IP,
# which the router cannot hairpin. Everything else forwards upstream.
# Reuses VMID 221 / 192.168.86.35 from the old AdGuard container.

resource "proxmox_virtual_environment_container" "dns" {
  node_name   = lookup(var.node_assignments, "dns", var.proxmox_node)
  vm_id       = var.dns_vmid
  description = "dnsmasq split-horizon DNS for ${var.domain}"
  tags        = ["infrastructure", "dns"]

  unprivileged  = true
  started       = true
  start_on_boot = true

  operating_system {
    template_file_id = var.debian_template
    type             = "debian"
  }

  cpu {
    cores = 1
    units = 1500
  }

  memory {
    dedicated = 256
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
    hostname = "dns"

    ip_config {
      ipv4 {
        address = "${var.dns_ip}/${var.network_subnet}"
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

  # Debian 12 systemd in an unprivileged LXC needs nesting (create warned without).
  features {
    nesting = true
  }

  lifecycle {
    # Container was created by a run that errored (nesting warning) and then
    # imported; the import cannot read these back, so ignore them to avoid a rebuild.
    ignore_changes = [
      initialization,
      operating_system,
      network_interface,
      tags,
      unprivileged,
    ]
  }
}

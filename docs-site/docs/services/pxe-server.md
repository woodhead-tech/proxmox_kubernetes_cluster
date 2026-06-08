---
sidebar_position: 12
title: PXE Server
---

# PXE Server

LXC 213 | `192.168.86.50` | Port 69 (TFTP), 80 (HTTP)

Network boot server for bare-metal and VM installations across the LAN. Runs proxy-DHCP mode so it coexists with the Google Nest DHCP server — no network reconfiguration needed.

## Architecture

- **Proxy-DHCP**: Listens for DHCP discovery packets and injects PXE boot options without replacing the existing DHCP server
- **TFTP**: Serves the PXE bootloader (`pxelinux.0` / iPXE) to booting clients
- **HTTP**: Serves OS images, kickstart/preseed configs, and iPXE chain scripts for larger file transfers

```
Client (F12 / PXE boot)
    |  DHCP broadcast
    v
Google Nest (192.168.86.1)     PXE Server (192.168.86.50)
    |  Issues IP lease          |  Proxy-DHCP: sends PXE boot options
    +----> Client <-----------+
                |
                |  TFTP request: pxelinux.0 / ipxe.efi
                v
          PXE Server :69
                |
                |  HTTP: boot menu, kernel, initrd, ISO
                v
          PXE Server :80
                |
                v
          OS installer
```

## Supported Boot Targets

Configured via `ansible/files/pxe/` (iPXE scripts and boot menu):

- Debian / Ubuntu net installers
- Talos Linux (for cluster re-provisioning)
- Rescue environments

## Deploy

```bash
# Provision the LXC
make apply-lxc

# Deploy PXE server
make pxe
```

## Verify

```bash
# Service status
ssh root@192.168.86.50 'systemctl status dnsmasq nginx'

# Test TFTP connectivity
tftp 192.168.86.50 -c get pxelinux.0 /dev/null && echo "TFTP OK"
```

## Troubleshooting

- **Client not seeing PXE option**: Proxy-DHCP requires the client to respond to both the DHCP server and the proxy offer. Some network stacks ignore the proxy offer — try enabling PXE in the firmware settings.
- **Boot loops**: Verify the iPXE chain script points to a valid kernel/initrd path served by HTTP.
- **Slow downloads**: Large ISO images are served via HTTP (port 80), not TFTP. Confirm the HTTP service is running and the image path is correct.

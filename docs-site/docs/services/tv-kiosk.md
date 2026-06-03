---
sidebar_position: 10
title: TV Kiosk (Kodi)
---

# TV Kiosk

LXC 225 | `192.168.86.46` | Kodi :8080 (HTTP bridge) | Living room TV via HDMI

Privileged Debian 12 LXC on the Zotac node running Kodi 20.1 (Nexus). Drives the
living room TV via HDMI using `/dev/dri` passthrough from the Zotac's Intel Celeron
N3150 iGPU. PlexKodiConnect links it to the local Plex server.

## Hardware Notes

The Zotac (192.168.86.147) has an Intel Celeron N3150 (Braswell/Cherrytrail). This
chip does **not** support VM GPU passthrough via IOMMU — IOMMU groups are empty even
with `intel_iommu=on`. LXC device passthrough is used instead, which does not
require IOMMU.

HDMI-CEC is not supported by the N3150 i915 driver without a
[Pulse-Eight USB-CEC adapter](https://www.pulse-eight.com/p/104/usb-hdmi-cec-adapter).
Use the Kore phone app for remote control.

## LXC Config

Key settings in `/etc/pve/lxc/225.conf` on the Zotac:

```
unprivileged: 0                               # privileged — required for DRM access
lxc.cgroup2.devices.allow: c 226:1 rwm       # /dev/dri/card1 (iGPU, appears as card1 in LXC)
lxc.cgroup2.devices.allow: c 226:128 rwm     # /dev/dri/renderD128
lxc.cgroup2.devices.allow: c 116:* rwm       # /dev/snd/* (ALSA audio)
lxc.cgroup2.devices.allow: c 4:7 rwm         # /dev/tty7
lxc.mount.entry: /dev/dri dev/dri none bind,optional,create=dir
lxc.mount.entry: /dev/snd dev/snd none bind,optional,create=dir
lxc.mount.entry: /dev/tty7 dev/tty7 none bind,optional,create=file
lxc.mount.entry: /dev/input dev/input none bind,optional,create=dir
```

The iGPU appears as `card1` inside the LXC (not `card0`). A symlink is created at
startup: `ln -sf /dev/dri/card1 /dev/dri/card0` so X11 can find it.

## Services

| Service | Managed by | Purpose |
|---|---|---|
| `kodi.service` | systemd | Runs xinit → Xorg → openbox → kodi on vt7 |
| `kodi-bridge.service` | systemd | Python HTTP→TCP bridge, exposes JSON-RPC on :8080 |

### Why a bridge?

Kodi 20.1 (Debian) has its JSON-RPC TCP server on `127.0.0.1:9090` only. The HTTP
web server on port 8080 (Chorus2) does not start reliably in this package version.
The bridge (`/usr/local/bin/kodi-http-bridge.py`) converts inbound HTTP POST requests
on `0.0.0.0:8080` to raw TCP JSON-RPC calls on `localhost:9090`, making Kode/Kore
remote apps work normally.

## Remote Control

**Kore app (recommended):**
1. Install Kore (official Kodi remote, Android/iOS)
2. Add host: `192.168.86.46`, port `8080`, no username/password

**Wake display if blank:**
```bash
ssh -i ~/.ssh/id_ansible root@192.168.86.46 \
  'kodi-send --host=127.0.0.1 --port=9777 --action="Select"'
```

**Dismiss stuck dialog (audio sink error on startup):**
```bash
ssh -i ~/.ssh/id_ansible root@192.168.86.46 \
  'kodi-send --host=127.0.0.1 --port=9777 --action="Select"'
```

**Send a notification to the TV:**
```bash
curl -s http://192.168.86.46:8080/jsonrpc \
  -H "Content-Type: application/json" \
  -d '{"jsonrpc":"2.0","method":"GUI.ShowNotification","id":1,"params":{"title":"Title","message":"Message","displaytime":5000}}'
```

## PlexKodiConnect

PKC 3.12.6 is installed at `/root/.kodi/addons/plugin.video.plexkodiconnect/`.

Config at `/root/.kodi/userdata/addon_data/plugin.video.plexkodiconnect/settings.xml`:

| Setting | Value |
|---|---|
| `ipaddress` | `192.168.86.23` |
| `port` | `32400` |
| `myplexlogin` | `false` (local server, not plex.tv) |
| `https` | `false` |
| `plex_machineidentifier` | `bb71a4246befd1bf67a268c8be41bdb69b37b287` |

The Plex server at 192.168.86.23 is **unclaimed** (not linked to plex.tv account).
Local connections require no auth token. PKC connects directly.

## Xorg Config

Explicit Xorg config at `/etc/X11/xorg.conf.d/10-modesetting.conf` forces the
modesetting driver to use `PCI:0:2:0` (the N3150 iGPU). Without this, X tries to
open `/dev/dri/card0` which doesn't exist — the card appears as `card1` inside the LXC.

## Display Blanking

DPMS is disabled in `/home/kodi/.xinitrc` so the TV never sleeps:

```bash
xset s off
xset -dpms
xset s noblank
```

## Startup Sequence

1. `kodi.service` → runs `/usr/local/bin/start-kodi-tv.sh`
2. Script: symlinks `card0 → card1`, sleeps 3s (allows ALSA to settle), then `xinit`
3. `xinit` starts Xorg on vt7, then launches `.xinitrc`
4. `.xinitrc`: disables DPMS, starts openbox, starts `kodi --standalone`
5. `kodi-bridge.service` waits for TCP socket on `localhost:9090` then starts HTTP server

## Logs

```bash
# Kodi service + X11
ssh -i ~/.ssh/id_ansible root@192.168.86.46 'journalctl -u kodi -f'
ssh -i ~/.ssh/id_ansible root@192.168.86.46 'cat /var/log/Xorg.0.log'
ssh -i ~/.ssh/id_ansible root@192.168.86.46 'cat /root/.kodi/temp/kodi.log | tail -50'

# HTTP bridge
ssh -i ~/.ssh/id_ansible root@192.168.86.46 'journalctl -u kodi-bridge -f'
```

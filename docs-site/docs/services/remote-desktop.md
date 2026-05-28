---
sidebar_position: 11
title: Remote Desktop
---

# Remote Desktop

**Guacamole** — LXC 219 | `192.168.86.47` | [guac.woodhead.tech](https://guac.woodhead.tech) (Authentik SSO)

**Dev Desktop** — LXC 220 | `192.168.86.48` | RDP port 3389 | Arch Linux + XFCE4 + xRDP

Browser-based remote access to the homelab dev desktop. Guacamole proxies RDP over HTTPS — no VPN or RDP client needed from any browser.

## Architecture

```
Browser (any device)
    |  HTTPS
    v
Traefik (guac.woodhead.tech)
    |  Authentik SSO check
    v
Guacamole LXC (192.168.86.47:8080)
    |  guacd protocol
    v
Dev Desktop LXC (192.168.86.48:3389)
    |  xRDP + XFCE4
    v
Desktop session (Arch Linux)
```

**Guacamole stack** (Docker Compose on LXC 219):
- `guacamole/guacamole:1.5.5` — web UI + session manager
- `guacamole/guacd:1.5.5` — protocol proxy daemon (RDP/VNC/SSH)
- `postgres:15-alpine` — connection/user database

**Dev Desktop** (LXC 220 on tower1):
- Arch Linux, 4 vCPU, 4GB RAM, 30GB disk
- XFCE4 desktop environment
- xRDP on port 3389
- Dev tools: Go 1.23.4, Python, Docker, git, zsh, neovim, yay (AUR)
- User: `bwoodwar` (wheel + docker groups)

## Accessing from a Browser

1. Go to [guac.woodhead.tech](https://guac.woodhead.tech) — Authentik SSO login
2. Default Guacamole admin: `guacadmin` / `guacadmin` (**change this**)
3. Click **Dev Desktop (Arch)** from the home screen
4. Enter password when prompted (RDP credentials for `bwoodwar`)
5. XFCE4 desktop loads in the browser tab

**Keyboard shortcuts in Guacamole:**
- `Ctrl+Alt+Shift` — toggle Guacamole sidebar (clipboard, zoom, input settings)
- Clipboard sync: paste text into the Guacamole sidebar clipboard field, then paste inside the desktop session

## Accessing via Native RDP (LAN only)

Direct RDP is faster than Guacamole for heavy use on the local network.

```bash
# From any RDP client (Remmina, Windows Remote Desktop, FreeRDP)
Host:     192.168.86.48
Port:     3389
Username: bwoodwar
```

Via FreeRDP CLI:
```bash
xfreerdp /u:bwoodwar /v:192.168.86.48:3389 /cert-ignore /dynamic-resolution
```

## SSH Access

```bash
ssh -i ~/.ssh/id_ansible bwoodwar@192.168.86.48
```

## Dev Tooling

| Tool | Version / Location |
|------|--------------------|
| Go | 1.23.4 at `/usr/local/go` |
| Python | System Python (Arch) |
| Docker | Via `docker` + `docker compose` |
| yay (AUR) | `/usr/bin/yay` |
| zsh | Default shell |
| neovim | `/usr/bin/nvim` |
| Claude Code | `claude` (npm global) |

Claude Code config and skills are synced from the primary dev machine. Re-run `~/personal_configs/claude/mcp-setup.sh` to wire MCPs after first login.

## Deploy / Redeploy

```bash
# Redeploy dev desktop (Arch Linux packages + user + xRDP)
make dev-desktop DEV_USER_PASSWORD=<password>

# Redeploy Guacamole (Docker Compose stack)
make guacamole GUAC_POSTGRES_PASSWORD=<password>
```

### Arch Linux pacman note

The LXC kernel does not support Landlock sandbox. `DisableSandbox` must be present in the `[options]` section of `/etc/pacman.conf` (not appended at end of file):

```bash
sed -i '/^\[options\]/a DisableSandbox' /etc/pacman.conf
```

Python must also be pre-installed before Ansible can connect:
```bash
ssh -i ~/.ssh/id_ansible root@192.168.86.130 \
  'pct exec 220 -- bash -c "pacman -Sy --noconfirm python"'
```

## Adding Connections in Guacamole

New RDP/VNC/SSH targets can be added without redeploying anything.

1. Log in as `guacadmin` at [guac.woodhead.tech](https://guac.woodhead.tech)
2. Top-right menu → **Settings** → **Connections** → **New Connection**
3. Protocol: RDP
4. Hostname: target IP, Port: 3389
5. Under **Authentication**: username + password (or leave blank to prompt on connect)
6. Save — connection appears on the home screen immediately

## Maintenance

**Check stack health:**
```bash
ssh -i ~/.ssh/id_ansible root@192.168.86.47 \
  'cd /opt/guacamole && docker compose ps'
```

**View Guacamole logs:**
```bash
ssh -i ~/.ssh/id_ansible root@192.168.86.47 \
  'cd /opt/guacamole && docker compose logs --tail=50 guacamole'
```

**Restart stack:**
```bash
ssh -i ~/.ssh/id_ansible root@192.168.86.47 \
  'cd /opt/guacamole && docker compose restart'
```

**Check xRDP on dev desktop:**
```bash
ssh -i ~/.ssh/id_ansible bwoodwar@192.168.86.48 \
  'sudo systemctl status xrdp xrdp-sesman'
```

**Change bwoodwar RDP password:**
```bash
ssh -i ~/.ssh/id_ansible bwoodwar@192.168.86.48 'passwd'
```

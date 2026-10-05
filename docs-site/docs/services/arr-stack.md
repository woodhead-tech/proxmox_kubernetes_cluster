---
sidebar_position: 3
title: ARR Stack
---

# ARR Media Stack

LXC 202 | `192.168.86.22` | Docker Compose

## Services

| Service | Port | Subdomain | Purpose |
|---|---|---|---|
| Prowlarr | 9696 | prowlarr.woodhead.tech | Indexer manager |
| Sonarr | 8989 | sonarr.woodhead.tech | TV show management |
| Radarr | 7878 | radarr.woodhead.tech | Movie management |
| Bazarr | 6767 | bazarr.woodhead.tech | Subtitle management |
| Seerr | 5055 | requests.woodhead.tech | User request portal |
| SABnzbd | 8080 | sabnzbd.woodhead.tech | Usenet downloader (via VPN) |
| LazyLibrarian | 5299 | lazylibrarian.woodhead.tech | Ebook/audiobook search + download, imports into Calibre |
| Calibre-Web | 8083 | books.woodhead.tech | Ebook library browser + OPDS feed for e-readers |
| Gluetun | -- | -- | WireGuard VPN killswitch for SABnzbd |

All services run as PUID=1000, PGID=1000 using LinuxServer.io images.

## Deploy

```bash
make arr-stack WG_PRIVATE_KEY=<privado_wireguard_private_key>
```

WireGuard key: download a `.conf` from my.privado.io and copy the `PrivateKey` field. The key is written to `/opt/arr/gluetun/wireguard_private_key` on the LXC and never committed to git.

## VPN Killswitch

SABnzbd runs inside gluetun's network namespace. All download traffic exits through PrivadoVPN WireGuard. If the VPN drops, SABnzbd loses connectivity entirely.

When restarting gluetun, always recreate SABnzbd at the same time — they share a network namespace:
```bash
docker compose up -d --force-recreate gluetun sabnzbd
```

## Configuration Order

1. Prowlarr — Add indexers
2. SABnzbd — Configure Usenet server
3. Sonarr — Connect to Prowlarr + SABnzbd
4. Radarr — Connect to Prowlarr + SABnzbd
5. Bazarr — Connect to Sonarr + Radarr
6. Seerr — Connect to Sonarr + Radarr
7. LazyLibrarian — Point downloaders at `gluetun:8080` (SABnzbd) / `gluetun:8090` (qBittorrent), add book-category indexers from Prowlarr, set the library destination to `/books/calibre-library` and the calibredb path to `/usr/bin/calibredb` (installed by the universal-calibre mod)
8. Calibre-Web — First login `admin` / `admin123` (change it immediately), set the library path to `/books/calibre-library`, enable the OPDS feed

## Media Directory

```
/media/
├── downloads/
│   ├── complete/
│   └── incomplete/
├── movies/
├── tv/
├── music/
└── books/
    └── calibre-library/   # Calibre metadata.db + books (LazyLibrarian writes, Calibre-Web reads)
```

NFS mounted from TrueNAS (192.168.86.40).

## Ebooks

LazyLibrarian grabs books through the same SABnzbd/qBittorrent clients (inside gluetun's network namespace, so use the hostname `gluetun`, not `localhost`) and imports finished files into the Calibre library with `calibredb`. Calibre-Web serves that library; e-readers connect to `https://books.woodhead.tech/opds` using their Calibre-Web username and password (this path skips Authentik SSO because reader apps cannot follow an SSO redirect).

---
sidebar_position: 3
title: Network Migration (Project Popeye)
description: VLAN segmentation migration plan - OPNsense + Omada APs
---

# Homelab Network Migration Plan — "Project Popeye"

## Context

The current network is a flat 192.168.86.0/24 behind a Google Nest WiFi Pro with no VLANs, no firewall rules, no IDS/IPS, and limited WiFi coverage across a 130-year-old, 4-section house ("Popeye") plus a detached garage. The goal is to replace this with a properly segmented, security-focused network with full coverage — without spending Unifi money.

**Why now:** The homelab has grown to 18+ containers, 5 Proxmox nodes, IoT devices, and externally-exposed services (Mailcow, Plex, WireGuard). A flat network with consumer gear is a liability for someone running this much infrastructure.

---

## Recommended Solution: OPNsense + TP-Link Omada APs

### Hardware Shopping List

| Component | Model | Cost | Notes |
|-----------|-------|------|-------|
| Firewall | Topton N100 4x 2.5GbE mini PC | ~$130 | Fanless, 15W TDP, handles Suricata at 1Gbps |
| Switch | Dell X-2160 (owned) | $0 | 24-port GbE managed, VLAN-capable |
| AP - Basement | TP-Link EAP670 (AX5400) | ~$120 | Primary AP, multi-SSID, near homelab rack |
| AP - 1st Floor | TP-Link EAP245 (AC1750) | ~$60 | Multi-SSID, covers living/dining/kitchen, wired via MoCA |
| AP - 3rd Floor | TP-Link EAP245 (AC1750) | ~$60 | Multi-SSID, covers home office + Ender's room, wired via MoCA |
| AP - Garage | Google Nest (reuse) | $0 | Single-VLAN (IoT 30), wireless mesh backhaul from 1st floor AP |
| PoE Injectors (x3) | TP-Link TL-POE150S | ~$45 | One per Omada AP |

**Total: ~$415** (slightly over $400 target, but all zones get proper multi-SSID coverage)

**Garage connectivity:** A Google Nest unit in the garage operates as a wireless bridge — connecting wirelessly to the 1st floor network and serving a local WiFi SSID for the 3D printers. Since the Nest can't do VLAN tagging, it'll bridge traffic onto IoT VLAN 30 by being connected (wirelessly) to the IoT SSID from the 1st floor Omada AP. The 3D printers then connect to the Nest's local SSID which bridges to the Omada's IoT network. Bandwidth is low (Klipper/Mainsail is mostly small API calls and gcode), so wireless backhaul is fine.

**Future upgrades (when budget allows):**
- Cat6 or MoCA run to garage for wired backhaul (~$25-80)
- Replace Nest in garage with EAP225-Outdoor (~$70) — gains weatherproofing + multi-SSID
- Add a PoE switch (e.g., TP-Link TL-SG1005P, ~$30) to eliminate injectors

**To hit $400 flat:** Drop one EAP245 (skip 3rd floor Omada) and reuse a Nest unit there on Trusted VLAN 10 only. Saves $60 but Ender's ESP32 devices would need to reach down to the 1st floor IoT SSID. Not recommended given the old construction between floors.

**Chosen approach:** Spend the extra $15 over budget for full multi-SSID on all 3 floors. The Nest goes to the garage where single-VLAN (IoT) is sufficient.

---

## House Layout & AP Placement

```
                    POPEYE - 130 year old house
                    (plaster/lath walls, high RF attenuation)
                    MoCA backhaul: Basement ↔ Living Room ↔ Ender's Room

┌─────────────────────────────────────────────────────────┐
│  3RD FLOOR (ATTIC)                                      │
│  ┌────────────────────┐  ┌───────────────────────────┐  │
│  │  Ender's Bedroom   │  │  Brandon's Home Office    │  │
│  │  [Laptop, IoT,     │  │  [Mac workstation]        │  │
│  │   ESP32 devices]   │  │                           │  │
│  │  ⊞ MoCA endpoint   │  │                           │  │
│  └────────────────────┘  └───────────────────────────┘  │
│            ◆ AP3 (EAP245, Omada)                         │
│            (multi-SSID: Trusted + IoT + Guest)          │
│            (wired via MoCA)                             │
└─────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────┐
│  1ST FLOOR                                              │
│  ┌──────────────┐  ┌──────────────┐ ┌───────────────┐  │
│  │  Living Room │  │  Dining Room │ │ Kitchen + Bath │  │
│  │  [Zotac PC]  │  │              │ │               │  │
│  │  [Zigbee     │  │              │ │               │  │
│  │   antenna]   │  │              │ │               │  │
│  │  ⊞ MoCA hub  │  │              │ │               │  │
│  └──────────────┘  └──────────────┘ └───────────────┘  │
│            ◆ AP2 (EAP245, Omada)                        │
│            (central hallway/ceiling, wired via MoCA)    │
└─────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────┐
│  BASEMENT                                               │
│  ┌────────────┐ ┌──────────┐ ┌────────┐ ┌───────────┐  │
│  │  Master BR │ │ Spare BR │ │Libby's │ │ HOMELAB   │  │
│  │  + Ensuite │ │(→future  │ │ Office │ │ [Proxmox] │  │
│  │            │ │ master)  │ │[Laptop]│ │ [Switch]  │  │
│  │            │ │          │ │[IoT]   │ │ [OPNsense]│  │
│  └────────────┘ └──────────┘ └────────┘ └───────────┘  │
│                                    ◆ AP1 (EAP670)       │
│                                    (near homelab rack)  │
│         ┌── OPNsense + Dell X-2160 + MoCA endpoint ─┐  │
└─────────────────────────────────────────────────────────┘

         ~~~ 30-50ft gap, no MoCA/coax ~~~

┌─────────────────────────────────────────────────────────┐
│  DETACHED GARAGE                                        │
│  ┌──────────────────────┐  ┌─────────────────────────┐  │
│  │  Motorcycle Workshop │  │  Ender's 3D Print Lab   │  │
│  │  (Brandon)           │  │  [Klipper/Mainsail]     │  │
│  │                      │  │  [Ender 3, Ender 5 Pro] │  │
│  └──────────────────────┘  └─────────────────────────┘  │
│            ◆ AP4 (Google Nest, reuse as wireless bridge) │
│            (IoT VLAN 30 only — 3D printers)             │
│            (wireless backhaul to 1st floor Omada AP)    │
└─────────────────────────────────────────────────────────┘
```

**Why 4 APs:** 130-year-old construction means plaster-over-lath or brick interior walls, possibly horsehair insulation, thick floor joists. RF attenuation between floors is severe (easily -15 to -20dB per floor). Each section needs dedicated coverage.

---

## VLAN Design

| VLAN | Subnet | Purpose | SSID |
|------|--------|---------|------|
| 1 | 192.168.1.0/24 | Management (switch, APs, OPNsense LAN) | — (wired only) |
| 10 | 192.168.10.0/24 | Trusted LAN (personal devices) | "Popeye" |
| 20 | 192.168.20.0/24 | Servers (Proxmox, LXCs, VMs, MetalLB) | — (wired only) |
| 30 | 192.168.30.0/24 | IoT (Zigbee bridge, 3D printers, smart devices) | "Popeye-IoT" |
| 40 | 192.168.40.0/24 | Guest WiFi | "Popeye-Guest" |
| 50 | 192.168.50.0/24 | DMZ (Traefik, Mailcow frontend, WireGuard) | — (wired only) |
| 99 | 192.168.99.0/24 | Lab (pwnagotchi, offensive tools) | — (wired only) |

**WiFi SSIDs per AP:**
- Omada APs (Basement + 1st Floor + 3rd Floor) broadcast all SSIDs: Popeye (VLAN 10), Popeye-IoT (VLAN 30), Popeye-Guest (VLAN 40)
- Nest reuse (Garage): Single SSID "Popeye-IoT" on VLAN 30 only (wireless backhaul, no hardline)
- Guest WiFi coverage: All 3 floors via Omada APs. Garage guests use 1st floor bleed-through (acceptable).
- Ender's ESP32 devices connect to "Popeye-IoT" on 3rd floor AP (proper coverage, no floor bleed-through needed)

---

## Firewall Rules (OPNsense)

**Device-to-VLAN assignments:**
- Trusted (10): Brandon's Mac, Libby's laptop, Ender's laptop, cell phones (family)
- Servers (20): Proxmox nodes, LXCs, VMs, TrueNAS, Zotac (Zigbee2MQTT hub), MetalLB pool
- IoT (30): ESP32 devices, 3D printers (Klipper), Zigbee end-devices, smart home gadgets
- Guest (40): Visitor devices only
- DMZ (50): Traefik, Mailcow frontend, WireGuard endpoint
- Lab (99): Pwnagotchi, offensive tools

**ESP32 / mDNS note:** ESP32 devices use mDNS for discovery. Install the Avahi mDNS reflector plugin on OPNsense if you want Trusted (10) devices to discover ESP32s on IoT (30) directly. Otherwise, route all ESP32 control through Home Assistant (Servers VLAN 20, which has explicit IoT access).

**Inter-VLAN policy: Default deny, explicit allow.**

Key rules:
- Trusted (10) → Servers (20): Allow (access Plex, Grafana, Home Assistant, etc.)
- Trusted (10) → IoT (30): Allow (manage 3D printers, Klipper UI, ESP32 web interfaces)
- IoT (30) → Home Assistant (20, port 8123/1883): Allow
- IoT (30) → Internet: Allow (ESP32 OTA updates, NTP, MQTT cloud if any)
- IoT (30) → everything else: Deny
- Guest (40) → Internet: Allow
- Guest (40) → RFC1918: Deny
- Lab (99) → Internet: Allow
- Lab (99) → RFC1918: Deny
- DMZ (50) → Internet: Allow (Mailcow relay, Let's Encrypt ACME)
- DMZ (50) → Servers (20): Allow (Traefik → backend services)
- WAN → DMZ (50): Allow HTTP/S, SMTP/IMAP, WireGuard

**IDS/IPS (Suricata):**
- WAN interface: Inline IPS mode (ET Open ruleset)
- Inter-VLAN: IDS mode initially (log lateral movement, don't block until tuned)
- GeoIP blocking on WAN (block inbound from countries with no expected traffic)

---

## Migration Plan (Phased, No Downtime)

### Phase 0: Prep (1 evening)
- Document all current IPs/MACs/port-forwards
- Order hardware (OPNsense mini PC, APs, PoE injectors)
- Pre-configure Dell X-2160 VLANs (don't change port assignments yet)
- Install OPNsense on mini PC offline; configure VLANs, DHCP pools, firewall rules
- Use GL.iNet Mango (owned) as a test client to validate VLAN isolation — connect it to each SSID/VLAN and verify reachability rules before migrating real devices

### Phase 1: Parallel Infrastructure (1 weekend)
- Connect OPNsense WAN to ISP modem (Google Nest stays operational)
- Connect OPNsense LAN trunk to Dell switch (tagged port)
- Add VLAN-aware bridge to Proxmox nodes (vmbr1) alongside existing vmbr0
- Verify OPNsense routes traffic correctly on new subnets
- Deploy Omada Controller as LXC on Proxmox
- Mount and configure APs (adopt into Omada Controller, create SSIDs)

### Phase 2: Service Migration (3-4 evenings)
- Move LXC/VM interfaces to server VLAN (20) one at a time, test each
- Update Traefik backends to new IPs
- Move MetalLB pool to 192.168.20.150-199
- Migrate WireGuard to OPNsense native (eliminate standalone WireGuard LXC)
- Update Cloudflare DDNS to OPNsense (native os-ddclient plugin)
- Move port forwards to OPNsense NAT rules
- Verify Mailcow, Plex, external access all work through OPNsense

### Phase 3: Client Migration (1 evening)
- Connect personal devices to "Popeye" SSID (VLAN 10)
- Move IoT devices to "Popeye-IoT" SSID (VLAN 30)
- Move 3D printers (garage) to IoT VLAN via garage AP
- Verify Home Assistant still reaches Zigbee coordinator and printers
- Test inter-VLAN rules (IoT can't reach workstations, guests can't reach LAN)

### Phase 4: Cutover (1 evening)
- Disable Google Nest WiFi DHCP and routing
- Remove Nest from network (or repurpose as dumb AP on Guest VLAN for extra coverage)
- Remove all references to 192.168.86.0/24
- Enable Suricata IPS on WAN
- Enable Suricata IDS on inter-VLAN

### Phase 5: Hardening (ongoing)
- Tune Suricata false positives (1-2 weeks of IDS logging before going full IPS)
- Set up alerting (OPNsense → Slack webhook or email on IDS hits)
- Configure OPNsense backup (config.xml export to Git repo or NAS)
- Add CrowdSec plugin for collaborative threat intelligence
- GeoIP blocking on WAN inbound

---

## Existing Wiring: MoCA Network

MoCA (Multimedia over Coax) adapters already provide wired backhaul to 3 locations:
- **Basement** (homelab) — switch and all Proxmox nodes live here
- **Living Room** — Zotac mini PC (Zigbee antenna hub)
- **Ender's Room (3rd floor)** — personal laptop + IoT devices

**MoCA implications for this plan:**
- MoCA adapters are typically unmanaged (no VLAN awareness). They pass Ethernet frames transparently, which means you CAN trunk tagged VLAN traffic over them if needed — but confirm your specific MoCA adapters support jumbo/tagged frames (most MoCA 2.0+ adapters do, since they just bridge at Layer 2).
- The living room and 3rd floor already have wired connectivity without running new cable.
- APs at those locations can be wired back to the Dell switch via MoCA.
- The Zotac (Zigbee hub) in the living room stays on Servers VLAN (20) since it runs Zigbee2MQTT.

**Garage connectivity (decided: wireless bridge):**
The garage has no coax or Ethernet run. A Google Nest unit operates as a wireless bridge — it connects to the 1st floor Omada AP's "Popeye-IoT" SSID and rebroadcasts locally for the 3D printers. This is adequate for Klipper/Mainsail traffic (small gcode uploads, API status checks).

**Future upgrade:** Run outdoor-rated Cat6 in conduit (~$25) for full-speed wired backhaul when convenient. This would also allow replacing the Nest with a proper Omada AP.

---

## Dell X-2160 Port Map

| Port | Mode | VLANs Tagged | Untagged | Device |
|------|------|-------------|----------|--------|
| 1 | Trunk | 1,10,20,30,40,50,99 | 1 | OPNsense LAN |
| 2-5 | Trunk | 1,20 | 20 | Proxmox nodes (4x) |
| 6 | Trunk | 1,20 | 20 | Proxmox node 5 (zotac) |
| 7 | Trunk | 1,10,30,40 | 1 | AP1 - Basement (EAP670, Omada) |
| 8 | Trunk | 1,10,30,40 | 1 | AP2 - 1st Floor (EAP245, Omada) |
| 9 | Trunk | 1,10,30,40 | 1 | AP3 - 3rd Floor (EAP245, Omada, via MoCA) |
| 10 | — | — | — | (unused — garage AP is wireless via Nest bridge) |
| 11-12 | Access | — | 20 | TrueNAS, Raspberry Pis |
| 13-14 | Access | — | 10 | Wired workstations |
| 15 | Access | — | 30 | Wired IoT (if any) |
| 16 | Access | — | 99 | Pwnagotchi/Lab |
| 17-22 | Access | — | 20 | Future servers / expansion |
| 23 | Access | — | 1 | Management access (laptop) |
| 24 | Trunk | all | 1 | Mirror/debug uplink |

---

## Verification

After migration is complete, verify:

1. **Connectivity**: Each VLAN can reach the internet; devices get DHCP from OPNsense
2. **Isolation**: Guest (40) cannot ping any RFC1918 address; IoT (30) cannot reach Trusted (10) or Servers (20) except Home Assistant
3. **External access**: Cloudflare → OPNsense → Traefik → services work (test Plex, Mailcow, recipes site)
4. **WireGuard**: Remote VPN connects and can reach Trusted (10) + Servers (20)
5. **IDS/IPS**: Generate test traffic (curl known-bad signatures from ET Open test URLs); verify Suricata alerts in OPNsense logs
6. **WiFi coverage**: Walk-test all 4 zones with phone; verify signal strength >-65dBm in each area
7. **3D printers**: Klipper/Mainsail accessible from Trusted VLAN; print jobs complete successfully
8. **Home Assistant**: Zigbee devices respond; automations trigger correctly
9. **DNS**: Internal resolution via OPNsense Unbound; external via Cloudflare; DDNS updates on WAN IP change
10. **Failover**: Unplug OPNsense WAN, verify no LAN disruption (services still reachable internally)

---

## Summary

| Requirement | Solution | Met? |
|-------------|----------|------|
| VLAN segmentation | 7 VLANs, Dell X-2160 trunking, OPNsense inter-VLAN firewall | Yes |
| Better WiFi coverage | 3x Omada APs (basement + 1st + 3rd floor) + Nest bridge (garage) | Yes |
| IDS/IPS + firewall | OPNsense + Suricata (inline IPS on WAN, IDS on LAN) | Yes |
| Unified management | OPNsense (network/security) + Omada Controller (WiFi) — 2 UIs | Mostly |
| Budget | ~$415 (slightly over, but all floors get full multi-SSID) | Close |

**Timeline:** 2-3 weekends at homelab pace, zero downtime with phased approach.

**Key advantages:**
- MoCA provides wired backhaul to 1st and 3rd floor APs without new cable runs
- Google Nest reuse as wireless bridge to garage costs $0
- Dell X-2160 already owned eliminates switch cost
- OPNsense is free software on a $130 mini PC — beats any commercial router/firewall at this price

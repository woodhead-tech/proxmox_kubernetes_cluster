#!/usr/bin/env python3
"""Read-only Prometheus exporter for Google Nest Wifi / Nest Wifi Pro.

Polls the unauthenticated local API (http://<point>/api/v1/status) that every Nest
point serves on the LAN. Nothing is ever written to the router - Google exposes no
local write API; settings stay in the Google Home app.

Also runs an optional L2 loop detector: a raw AF_PACKET listener that counts frames
arriving with THIS host's own source MAC. That is the symptom of a switching loop
(e.g. Nest points with MoCA wired backhaul + wireless mesh reflecting frames back),
the same thing Proxmox logs as "received packet ... with own address as source".

Stdlib only (no pip deps). Metrics on :9668/metrics.

Env:
  NEST_SEEDS          comma list of known point IPs (default 192.168.86.1)
  NEST_SUBNET         /24 prefix to scan for points (default 192.168.86)
  DISCOVERY_INTERVAL  seconds between LAN scans for new points (default 600)
  FORGET_AFTER        seconds a missing point keeps reporting nest_up=0 (default 86400)
  LOOP_IFACE          interface for the loop detector, "" disables (default eth0)
  LISTEN_PORT         default 9668
"""
import json
import logging
import os
import socket
import struct
import threading
import time
import urllib.request
from concurrent.futures import ThreadPoolExecutor
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

logging.basicConfig(level=logging.INFO, format="%(asctime)s [%(levelname)s] %(message)s")
log = logging.getLogger("nest-exporter")

SEEDS = [s.strip() for s in os.environ.get("NEST_SEEDS", "192.168.86.1").split(",") if s.strip()]
SUBNET = os.environ.get("NEST_SUBNET", "192.168.86")
DISCOVERY_INTERVAL = int(os.environ.get("DISCOVERY_INTERVAL", "600"))
FORGET_AFTER = int(os.environ.get("FORGET_AFTER", "86400"))
LOOP_IFACE = os.environ.get("LOOP_IFACE", "eth0")
PORT = int(os.environ.get("LISTEN_PORT", "9668"))

# ip -> {"last_seen": ts, "role": str, "model": str}; guarded by LOCK
POINTS = {}
LOCK = threading.Lock()
STATE = {"discovery_ts": 0.0, "discovery_ok": 0, "loop_enabled": 0, "loop_frames": 0}


def fetch_status(ip, timeout=4.0, retries=1):
    """Return the parsed status JSON, or None if this IP is not a Nest point.

    The router's API is sometimes slow (1-3s+ measured from every LAN host), so polls
    use a generous timeout and one retry before a point is reported down.
    """
    for attempt in range(retries + 1):
        try:
            with urllib.request.urlopen(f"http://{ip}/api/v1/status", timeout=timeout) as r:
                d = json.load(r)
            return d if "system" in d and "modelId" in d.get("system", {}) else None
        except Exception:
            if attempt == retries:
                return None
    return None


def remember(ip, d):
    s = d.get("system", {})
    with LOCK:
        POINTS[ip] = {"last_seen": time.time(), "role": s.get("groupRole", "unknown"),
                      "model": s.get("modelId", "unknown")}


def discover():
    """Sweep the /24 for Nest points; IPs move via DHCP, so this runs periodically."""
    ips = [f"{SUBNET}.{i}" for i in range(1, 255)]
    with ThreadPoolExecutor(max_workers=64) as ex:
        results = list(ex.map(lambda ip: (ip, fetch_status(ip, 3.0, 0)), ips))
    found = [(ip, d) for ip, d in results if d]
    for ip, d in found:
        remember(ip, d)
    STATE["discovery_ts"], STATE["discovery_ok"] = time.time(), 1
    log.info("discovery: %d Nest point(s): %s", len(found), ", ".join(ip for ip, _ in found))


def discovery_loop():
    for ip in SEEDS:  # seeds first so the router shows up before the first full sweep finishes
        d = fetch_status(ip)
        if d:
            remember(ip, d)
    while True:
        try:
            discover()
        except Exception as e:  # never let discovery kill the exporter
            STATE["discovery_ok"] = 0
            log.warning("discovery failed: %s", e)
        time.sleep(DISCOVERY_INTERVAL)


def loop_detector():
    """Count received frames whose source MAC is our own (L2 loop / reflection)."""
    try:
        with open(f"/sys/class/net/{LOOP_IFACE}/address") as f:
            own = bytes.fromhex(f.read().strip().replace(":", ""))
        sock = socket.socket(socket.AF_PACKET, socket.SOCK_RAW, socket.ntohs(0x0003))
        sock.bind((LOOP_IFACE, 0))
    except Exception as e:
        log.warning("loop detector disabled (%s): %s", LOOP_IFACE, e)
        return
    STATE["loop_enabled"] = 1
    log.info("loop detector listening on %s (own MAC %s)", LOOP_IFACE, own.hex(":"))
    PACKET_OUTGOING = 4  # our own transmissions; anything else with our src MAC came back in
    while True:
        try:
            frame, addr = sock.recvfrom(65535)
        except Exception as e:
            log.warning("loop detector recv error: %s", e)
            time.sleep(1)
            continue
        if len(frame) >= 12 and addr[2] != PACKET_OUTGOING and frame[6:12] == own:
            STATE["loop_frames"] += 1


def esc(v):
    return str(v).replace("\\", "\\\\").replace('"', '\\"').replace("\n", " ")


def render():
    """Poll every known point now (concurrently) and build the exposition text."""
    now = time.time()
    with LOCK:
        for ip in [ip for ip, p in POINTS.items() if now - p["last_seen"] > FORGET_AFTER]:
            del POINTS[ip]  # gone for a day: stop reporting it
        known = dict(POINTS)
    t0 = time.time()
    with ThreadPoolExecutor(max_workers=8) as ex:
        statuses = dict(zip(known, ex.map(fetch_status, known)))
    out = []

    def metric(name, help_, typ, samples):
        out.append(f"# HELP {name} {help_}\n# TYPE {name} {typ}")
        out.extend(f"{name}{{{','.join(f'{k}=\"{esc(v)}\"' for k, v in lbl.items())}}} {val}"
                   for lbl, val in samples)

    up, info, wired, uptime, chan, wan, wan_eth, led = ([] for _ in range(8))
    for ip, d in statuses.items():
        p = known[ip]
        if d:
            remember(ip, d)
            s, m, w, sw = d.get("system", {}), d.get("meshInfo", {}), d.get("wan", {}), d.get("software", {})
            p = {"role": s.get("groupRole", p["role"]), "model": s.get("modelId", p["model"])}
        base = {"ip": ip, "role": p["role"]}
        up.append((dict(base, model=p["model"]), 1 if d else 0))
        if not d:
            continue
        # labels deliberately exclude serial/hardwareId
        info.append((dict(base, model=p["model"], firmware=sw.get("softwareVersion", ""),
                          mesh_interface=m.get("mesh-interface", ""),
                          led=s.get("ledAnimation", "")), 1))
        wired.append((base, 1 if s.get("lan0Link") else 0))
        uptime.append((base, s.get("uptime", 0)))
        if m.get("mesh-channel") is not None:
            chan.append((base, m["mesh-channel"]))
        led.append((base, 1 if s.get("ledAnimation") == "CONNECTED" else 0))
        if p["role"] == "root":  # only the router has a meaningful WAN
            wan.append((base, 1 if w.get("online") else 0))
            wan_eth.append((base, 1 if w.get("ethernetLink") else 0))

    metric("nest_up", "1 if the point answered its local status API", "gauge", up)
    metric("nest_info", "Static info per point (value always 1)", "gauge", info)
    metric("nest_wired", "1 if the point's Ethernet port has link (wired backhaul / uplink)", "gauge", wired)
    metric("nest_uptime_seconds", "Point uptime in seconds", "gauge", uptime)
    metric("nest_mesh_channel", "Wi-Fi channel the mesh runs on", "gauge", chan)
    metric("nest_connected", "1 if the point LED state is CONNECTED", "gauge", led)
    metric("nest_wan_online", "1 if the router reports its WAN online", "gauge", wan)
    metric("nest_wan_ethernet_link", "1 if the router WAN port has link", "gauge", wan_eth)
    metric("nest_points_known", "Nest points currently tracked", "gauge", [({}, len(known))])
    metric("nest_discovery_last_success_timestamp_seconds", "Last completed LAN sweep", "gauge",
           [({}, STATE["discovery_ts"])])
    metric("nest_loop_detector_enabled", "1 if the own-source-MAC loop detector is running", "gauge",
           [({"iface": LOOP_IFACE}, STATE["loop_enabled"])])
    metric("nest_lan_reflected_frames_total",
           "Frames received with this host's own source MAC (L2 loop/reflection)", "counter",
           [({"iface": LOOP_IFACE}, STATE["loop_frames"])])
    metric("nest_scrape_duration_seconds", "Time spent polling points", "gauge", [({}, round(time.time() - t0, 3))])
    return "\n".join(out) + "\n"


class Handler(BaseHTTPRequestHandler):
    def do_GET(self):
        if self.path.split("?")[0] != "/metrics":
            self.send_response(404); self.end_headers(); return
        body = render().encode()
        self.send_response(200)
        self.send_header("Content-Type", "text/plain; version=0.0.4; charset=utf-8")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def log_message(self, *a):  # keep container logs quiet; scrapes every 30s
        pass


if __name__ == "__main__":
    threading.Thread(target=discovery_loop, daemon=True).start()
    if LOOP_IFACE:
        threading.Thread(target=loop_detector, daemon=True).start()
    log.info("serving on :%d (seeds=%s subnet=%s.0/24)", PORT, SEEDS, SUBNET)
    ThreadingHTTPServer(("0.0.0.0", PORT), Handler).serve_forever()

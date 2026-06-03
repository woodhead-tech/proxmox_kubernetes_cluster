#!/usr/bin/env python3
"""
Homelab auto-healer: receives Alertmanager webhooks, executes safe SSH
remediation actions, rate-limits to avoid restart loops, logs everything.
"""
import json
import logging
import os
import sqlite3
import subprocess
import time
from datetime import datetime, timezone
from pathlib import Path

import yaml
from fastapi import FastAPI, Request
from fastapi.responses import HTMLResponse, JSONResponse

logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(message)s")
log = logging.getLogger("healer")

CONFIG_PATH = os.environ.get("HEALER_CONFIG", "/etc/healer/config.yaml")
DB_PATH = os.environ.get("HEALER_DB", "/var/lib/healer/healer.db")
SSH_KEY = os.environ.get("HEALER_SSH_KEY", "/root/.ssh/id_ansible")
MAX_HEALS_PER_HOUR = int(os.environ.get("HEALER_RATE_LIMIT", "3"))
DRY_RUN = os.environ.get("HEALER_DRY_RUN", "false").lower() == "true"

app = FastAPI(title="Homelab Healer")


def get_db():
    Path(DB_PATH).parent.mkdir(parents=True, exist_ok=True)
    db = sqlite3.connect(DB_PATH)
    db.execute("""
        CREATE TABLE IF NOT EXISTS actions (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            ts TEXT NOT NULL,
            alert_name TEXT NOT NULL,
            instance TEXT,
            action TEXT NOT NULL,
            target_host TEXT,
            command TEXT,
            outcome TEXT,
            dry_run INTEGER DEFAULT 0
        )
    """)
    db.commit()
    return db


def load_config():
    try:
        with open(CONFIG_PATH) as f:
            return yaml.safe_load(f)
    except Exception as e:
        log.error("Failed to load config: %s", e)
        return {"rules": []}


def rate_limited(db, alert_name, instance):
    cutoff = time.time() - 3600
    cutoff_ts = datetime.fromtimestamp(cutoff, tz=timezone.utc).isoformat()
    row = db.execute(
        "SELECT COUNT(*) FROM actions WHERE alert_name=? AND instance=? AND ts>? AND outcome='success'",
        (alert_name, instance, cutoff_ts)
    ).fetchone()
    return row[0] >= MAX_HEALS_PER_HOUR


def run_ssh(host, command):
    cmd = ["ssh", "-i", SSH_KEY, "-o", "StrictHostKeyChecking=accept-new",
           "-o", "ConnectTimeout=10", f"root@{host}", command]
    try:
        result = subprocess.run(cmd, capture_output=True, text=True, timeout=30)
        if result.returncode == 0:
            return "success", result.stdout.strip()
        return "failed", result.stderr.strip()
    except subprocess.TimeoutExpired:
        return "timeout", "SSH command timed out"
    except Exception as e:
        return "error", str(e)


def find_rule(config, alert_name, instance, labels):
    for rule in config.get("rules", []):
        if rule.get("alert") != alert_name:
            continue
        match = rule.get("match", {})
        if all(labels.get(k, "") == v or instance == v
               for k, v in match.items()):
            return rule
    return None


def log_action(db, alert_name, instance, action, target_host, command, outcome, dry_run):
    ts = datetime.now(tz=timezone.utc).isoformat()
    db.execute(
        "INSERT INTO actions (ts,alert_name,instance,action,target_host,command,outcome,dry_run) VALUES (?,?,?,?,?,?,?,?)",
        (ts, alert_name, instance, action, target_host, command, outcome, int(dry_run))
    )
    db.commit()
    log.info("[%s] alert=%s instance=%s action=%s host=%s outcome=%s dry_run=%s",
             ts, alert_name, instance, action, target_host, outcome, dry_run)


@app.post("/webhook")
async def webhook(request: Request):
    try:
        payload = await request.json()
    except Exception:
        return JSONResponse({"error": "invalid JSON"}, status_code=400)

    config = load_config()
    db = get_db()
    results = []

    for alert in payload.get("alerts", []):
        if alert.get("status") != "firing":
            continue

        labels = alert.get("labels", {})
        alert_name = labels.get("alertname", "")
        instance = labels.get("instance", "")

        rule = find_rule(config, alert_name, instance, labels)
        if not rule:
            log.debug("No rule for alert=%s instance=%s", alert_name, instance)
            continue

        if rate_limited(db, alert_name, instance):
            log.warning("Rate limited: alert=%s instance=%s (>%d heals/hour)",
                        alert_name, instance, MAX_HEALS_PER_HOUR)
            log_action(db, alert_name, instance, rule["action"],
                       rule.get("host", ""), rule.get("command", ""), "rate_limited", DRY_RUN)
            results.append({"alert": alert_name, "instance": instance, "outcome": "rate_limited"})
            continue

        if DRY_RUN:
            log_action(db, alert_name, instance, rule["action"],
                       rule.get("host", ""), rule.get("command", ""), "dry_run", True)
            results.append({"alert": alert_name, "instance": instance, "outcome": "dry_run"})
            continue

        outcome, detail = run_ssh(rule["host"], rule["command"])
        log_action(db, alert_name, instance, rule["action"],
                   rule["host"], rule["command"], outcome, False)
        results.append({"alert": alert_name, "instance": instance,
                        "outcome": outcome, "detail": detail})

    db.close()
    return JSONResponse({"processed": len(results), "results": results})


@app.get("/health")
def health():
    return {"status": "ok", "dry_run": DRY_RUN}


@app.get("/actions")
def actions(limit: int = 100):
    db = get_db()
    rows = db.execute(
        "SELECT ts,alert_name,instance,action,target_host,command,outcome,dry_run FROM actions ORDER BY id DESC LIMIT ?",
        (limit,)
    ).fetchall()
    db.close()
    return [{"ts": r[0], "alert": r[1], "instance": r[2], "action": r[3],
             "host": r[4], "command": r[5], "outcome": r[6], "dry_run": bool(r[7])}
            for r in rows]


@app.get("/", response_class=HTMLResponse)
def dashboard():
    db = get_db()
    rows = db.execute(
        "SELECT ts,alert_name,instance,action,outcome,dry_run FROM actions ORDER BY id DESC LIMIT 100"
    ).fetchall()
    db.close()

    outcome_color = {"success": "#22c55e", "failed": "#ef4444", "rate_limited": "#f59e0b",
                     "dry_run": "#6366f1", "timeout": "#f97316", "error": "#dc2626"}

    rows_html = ""
    for r in rows:
        color = outcome_color.get(r[4], "#9ca3af")
        dry = " [DRY]" if r[5] else ""
        rows_html += f"""<tr>
            <td>{r[0][:19]}</td>
            <td>{r[1]}</td>
            <td>{r[2]}</td>
            <td>{r[3]}</td>
            <td style="color:{color};font-weight:bold">{r[4]}{dry}</td>
        </tr>"""

    return f"""<!DOCTYPE html><html><head><title>Homelab Healer</title>
<style>body{{font-family:monospace;background:#0f172a;color:#e2e8f0;padding:2rem}}
h1{{color:#38bdf8}}table{{width:100%;border-collapse:collapse}}
th{{text-align:left;border-bottom:1px solid #334155;padding:.5rem;color:#94a3b8}}
td{{padding:.4rem .5rem;border-bottom:1px solid #1e293b;font-size:.85rem}}
tr:hover{{background:#1e293b}}</style></head>
<body><h1>Homelab Healer</h1>
<p>Last 100 healing actions — <a href="/actions" style="color:#38bdf8">JSON</a></p>
<table><tr><th>Time</th><th>Alert</th><th>Instance</th><th>Action</th><th>Outcome</th></tr>
{rows_html if rows_html else '<tr><td colspan="5" style="color:#64748b">No actions yet</td></tr>'}
</table></body></html>"""

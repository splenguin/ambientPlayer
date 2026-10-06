#!/usr/bin/env python3
"""Phone-friendly control page for the ambient player.

Serves index.html, relays button presses to SuperCollider as OSC messages
(UDP 127.0.0.1:57120), runs the nightly on/off schedule, and pulls updates
from git. Standard library only, so there is nothing to pip install.

Environment:
  AMBIENT_PORT      HTTP port (default 8080)
  AMBIENT_STATUS    status JSON written by sc/main.scd (default /tmp/ambient-status.json)
  AMBIENT_SETTINGS  where settings are saved (default ~/.config/ambient/settings.json)
  AMBIENT_REPO      git checkout to pull for updates (default: the repo this file is in)
  AMBIENT_SOUNDS    ambientSounds checkout, also pulled on update (default ~/ambientSounds)
  AMBIENT_RESTART   command that restarts SuperCollider after an update
                    (default: sudo systemctl restart ambient-sc.service)
"""

import json
import os
import shlex
import socket
import struct
import subprocess
import threading
import time
from datetime import datetime
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path

HERE = Path(__file__).resolve().parent
PORT = int(os.environ.get("AMBIENT_PORT", "8080"))
STATUS_PATH = Path(os.environ.get("AMBIENT_STATUS", "/tmp/ambient-status.json"))
SETTINGS_PATH = Path(os.environ.get(
    "AMBIENT_SETTINGS", Path.home() / ".config" / "ambient" / "settings.json"))
REPO = Path(os.environ.get("AMBIENT_REPO", HERE.parent))
SOUNDS = Path(os.environ.get("AMBIENT_SOUNDS") or Path.home() / "ambientSounds")
RESTART = shlex.split(os.environ.get(
    "AMBIENT_RESTART", "sudo -n systemctl restart ambient-sc.service"))
SC_ADDR = ("127.0.0.1", 57120)

DEFAULT_SETTINGS = {
    "master": 0.8,
    "birds": True,
    "trims": {},
    "schedule": {"enabled": False, "on": "18:30", "off": "23:30"},
}

lock = threading.Lock()
last_status = {}
settings = {}


# --- OSC -------------------------------------------------------------------

def _osc_string(s):
    b = s.encode() + b"\0"
    return b + b"\0" * (-len(b) % 4)


def send_osc(address, *args):
    tags, data = ",", b""
    for a in args:
        if isinstance(a, bool):
            a = int(a)
        if isinstance(a, int):
            tags += "i"
            data += struct.pack(">i", a)
        elif isinstance(a, float):
            tags += "f"
            data += struct.pack(">f", a)
        else:
            tags += "s"
            data += _osc_string(str(a))
    packet = _osc_string(address) + _osc_string(tags) + data
    with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as sock:
        sock.sendto(packet, SC_ADDR)


# --- settings and status -----------------------------------------------------

def load_settings():
    s = json.loads(json.dumps(DEFAULT_SETTINGS))
    try:
        saved = json.loads(SETTINGS_PATH.read_text())
        s.update({k: v for k, v in saved.items() if k in s})
    except (OSError, ValueError):
        pass
    return s


def save_settings():
    SETTINGS_PATH.parent.mkdir(parents=True, exist_ok=True)
    tmp = SETTINGS_PATH.with_suffix(".tmp")
    tmp.write_text(json.dumps(settings, indent=2))
    tmp.replace(SETTINGS_PATH)


def read_status():
    """Latest status from SuperCollider; keeps the last good one if the file
    is mid-write. 'online' is false when SC hasn't written for 10 s."""
    global last_status
    try:
        st = json.loads(STATUS_PATH.read_text())
        st["online"] = time.time() - STATUS_PATH.stat().st_mtime < 10
        last_status = st
    except (OSError, ValueError):
        last_status = dict(last_status, online=False) if last_status else {"online": False}
    return last_status


def push_settings():
    """Send saved master and trims to SuperCollider (after it (re)starts)."""
    send_osc("/master", float(settings["master"]))
    send_osc("/birds", int(bool(settings["birds"])))
    for layer, amp in settings["trims"].items():
        send_osc("/trim", layer, float(amp))


def in_window(now, on, off):
    t = now.strftime("%H:%M")
    return on <= t < off if on <= off else (t >= on or t < off)


def background():
    """Re-sends settings whenever SuperCollider restarts, and runs the schedule."""
    seen_boot, was_on = None, None
    while True:
        st = read_status()
        if st.get("online") and st.get("boot") != seen_boot:
            time.sleep(3)  # let the patch finish building its layers
            seen_boot = st.get("boot")
            with lock:
                push_settings()
            was_on = None  # re-apply the schedule to the fresh instance
        sch = settings["schedule"]
        if sch.get("enabled"):
            on = in_window(datetime.now(), sch["on"], sch["off"])
            if on != was_on:
                send_osc("/start" if on else "/stop", 60.0)
                was_on = on
        else:
            was_on = None
        time.sleep(5)


def git_update():
    """Pull the software and the sounds; restart SuperCollider if either changed."""
    log, changed = [], False
    for name, repo in (("ambientPlayer", REPO), ("ambientSounds", SOUNDS)):
        if not (repo / ".git").exists() and name == "ambientSounds":
            log.append(f"{name}: not found at {repo}, skipped")
            continue
        out = subprocess.run(["git", "-C", str(repo), "pull", "--ff-only"],
                             capture_output=True, text=True, timeout=300)
        text = (out.stdout + out.stderr).strip()
        log.append(f"{name}: {text}")
        if out.returncode != 0:
            return False, "\n".join(log)
        changed = changed or "Already up to date" not in text
    log = "\n".join(log)
    if not changed:
        return True, log
    r = subprocess.run(RESTART, capture_output=True, text=True, timeout=60)
    log += "\n" + (r.stdout + r.stderr).strip()
    return r.returncode == 0, log + ("\nRestarted SuperCollider." if r.returncode == 0 else "")


# --- HTTP ------------------------------------------------------------------

class Handler(BaseHTTPRequestHandler):
    def _send(self, code, body, ctype="application/json"):
        data = body if isinstance(body, bytes) else json.dumps(body).encode()
        self.send_response(code)
        self.send_header("Content-Type", ctype)
        self.send_header("Content-Length", str(len(data)))
        self.send_header("Cache-Control", "no-store")
        self.end_headers()
        self.wfile.write(data)

    def log_message(self, fmt, *args):
        pass  # keep the journal quiet; errors still raise

    def do_GET(self):
        if self.path in ("/", "/index.html"):
            self._send(200, (HERE / "index.html").read_bytes(), "text/html; charset=utf-8")
        elif self.path == "/api/status":
            with lock:
                self._send(200, {"sc": read_status(), "settings": settings})
        else:
            self._send(404, {"error": "not found"})

    def do_POST(self):
        try:
            length = int(self.headers.get("Content-Length", 0))
            req = json.loads(self.rfile.read(length) or b"{}")
        except ValueError:
            return self._send(400, {"error": "bad json"})

        if self.path == "/api/cmd":
            cmd, args = req.get("cmd"), req.get("args", [])
            allowed = {"scene", "auto", "solo", "start", "stop", "test"}
            if cmd not in allowed or not isinstance(args, list):
                return self._send(400, {"error": "unknown command"})
            send_osc("/" + cmd, *args)
            return self._send(200, {"ok": True})

        if self.path == "/api/settings":
            with lock:
                if "master" in req:
                    settings["master"] = min(max(float(req["master"]), 0.0), 1.0)
                    send_osc("/master", settings["master"])
                if "birds" in req:
                    settings["birds"] = bool(req["birds"])
                    send_osc("/birds", int(settings["birds"]))
                if "trim" in req:
                    layer, amp = str(req["trim"][0]), min(max(float(req["trim"][1]), 0.0), 2.0)
                    settings["trims"][layer] = amp
                    send_osc("/trim", layer, amp)
                if "schedule" in req:
                    sch = req["schedule"]
                    settings["schedule"] = {
                        "enabled": bool(sch.get("enabled")),
                        "on": str(sch.get("on", "18:30"))[:5],
                        "off": str(sch.get("off", "23:30"))[:5],
                    }
                save_settings()
                return self._send(200, {"ok": True, "settings": settings})

        if self.path == "/api/update":
            ok, log = git_update()
            return self._send(200 if ok else 500, {"ok": ok, "log": log})

        self._send(404, {"error": "not found"})


def main():
    global settings
    settings = load_settings()
    threading.Thread(target=background, daemon=True).start()
    server = ThreadingHTTPServer(("0.0.0.0", PORT), Handler)
    print(f"ambient web control on http://0.0.0.0:{PORT}", flush=True)
    server.serve_forever()


if __name__ == "__main__":
    main()

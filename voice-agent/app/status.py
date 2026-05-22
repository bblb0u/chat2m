from __future__ import annotations

import json
import os
from pathlib import Path
import sys
import threading
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

from app.agent import DisplayClient, log


DISPLAY_SERIAL_PORT = os.getenv("DISPLAY_SERIAL_PORT", "")
DISPLAY_SERIAL_CANDIDATES = tuple(
    candidate.strip()
    for candidate in os.getenv(
        "DISPLAY_SERIAL_CANDIDATES",
        "/dev/ttyACM0,/dev/ttyACM1,/dev/ttyUSB0,/dev/ttyUSB1",
    ).split(",")
    if candidate.strip()
)
DISPLAY_SERIAL_BAUD = int(os.getenv("DISPLAY_SERIAL_BAUD", "115200"))
STATUS_HOST = os.getenv("STATUS_HOST", "0.0.0.0")
STATUS_PORT = int(os.getenv("STATUS_PORT", "8091"))


def resolve_display_port(port: str) -> str:
    if port and port.lower() != "auto":
        return port
    for candidate in DISPLAY_SERIAL_CANDIDATES:
        if Path(candidate).exists():
            return candidate
    return ""


display_port = resolve_display_port(DISPLAY_SERIAL_PORT)
display = DisplayClient(display_port, DISPLAY_SERIAL_BAUD)
state_lock = threading.Lock()
last_state = {"state": "idle", "text": ""}


def set_state(state: str, text: str = "") -> None:
    with state_lock:
        last_state["state"] = state
        last_state["text"] = text
    display.set_state(state, text)
    log(f"display state: {state}")


class StatusHandler(BaseHTTPRequestHandler):
    def log_message(self, format: str, *args: object) -> None:
        return

    def _send_json(self, status: int, payload: dict[str, object]) -> None:
        body = json.dumps(payload, ensure_ascii=False, separators=(",", ":")).encode("utf-8")
        self.send_response(status)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def do_GET(self) -> None:
        if self.path != "/health":
            self._send_json(404, {"error": "not found"})
            return
        with state_lock:
            state = dict(last_state)
        self._send_json(200, {"ok": True, "display": bool(display_port), "port": display_port, **state})

    def do_POST(self) -> None:
        if self.path != "/state":
            self._send_json(404, {"error": "not found"})
            return

        length = int(self.headers.get("Content-Length", "0") or "0")
        try:
            payload = json.loads(self.rfile.read(length).decode("utf-8") or "{}")
            state = str(payload["state"])[:24]
            text = str(payload.get("text", ""))[:80]
        except Exception:
            self._send_json(400, {"error": "invalid state payload"})
            return

        set_state(state, text)
        self._send_json(200, {"ok": True})


def main() -> None:
    log(f"display serial: {display_port or 'disabled'}")
    set_state("idle")
    server = ThreadingHTTPServer((STATUS_HOST, STATUS_PORT), StatusHandler)
    log(f"status forwarder listening on {STATUS_HOST}:{STATUS_PORT}")
    try:
        server.serve_forever()
    finally:
        display.close()


if __name__ == "__main__":
    try:
        main()
    except KeyboardInterrupt:
        log("stopped")
    except Exception as exc:
        log(f"fatal: {exc}")
        sys.exit(1)

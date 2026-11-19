"""Lectura de procesos desde /proc (sin pgrep ni dependencias): lista de líneas de comando del usuario actual."""
import os
import threading
import time


def scan() -> list:
    """Devuelve las líneas de comando (argumentos unidos por espacios) de los procesos del usuario actual."""
    uid, out = os.getuid(), []
    try:
        pids = [p for p in os.listdir("/proc") if p.isdigit()]
    except OSError:
        return out
    for pid in pids:
        try:
            if os.stat("/proc/" + pid).st_uid != uid:
                continue
            with open(f"/proc/{pid}/cmdline", "rb") as f:
                raw = f.read(4096)
        except OSError:
            continue
        if raw:
            out.append(raw.replace(b"\0", b" ").decode("utf-8", "replace").strip())
    return out


class Snapshot:
    """Foto compartida de /proc, como máximo una exploración por TTL."""
    def __init__(self, scan_fn=scan, ttl: float = 1.0):
        self.scan_fn, self.ttl = scan_fn, ttl
        self.lock = threading.Lock()
        self.at, self.data = 0.0, []

    def get(self) -> list:
        now = time.monotonic()
        with self.lock:
            if now - self.at >= self.ttl:
                self.data = self.scan_fn()
                self.at = now
            return self.data

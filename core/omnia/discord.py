"""Discord, nivel A: presencia («Jugando a …») por el IPC local de Discord (Rich Presence). Sin cuentas ni tokens.

El cliente de Discord abre un socket Unix (`discord-ipc-N`) en el que cualquier programa local puede anunciar una actividad si
conoce el Application ID (público) de una aplicación creada por el usuario en discord.com/developers. Todo el trabajo de red vive en
un hilo propio para no frenar el sondeo de juegos; si Discord no está abierto, se reintenta cada 30 s sin ruido.
"""
import json
import logging
import os
import re
import socket
import struct
import threading
import time
import uuid
from pathlib import Path

log = logging.getLogger("omnia")

APP_ID_RE = re.compile(r"\d{17,20}")
RETRY_SECS = 30
HANDSHAKE, FRAME, CLOSE = 0, 1, 2


def socket_paths(env=None) -> list:
    """Sockets posibles del cliente: nativo, Flatpak y Snap (discord-ipc-0..9)."""
    env = os.environ if env is None else env
    run = env.get("XDG_RUNTIME_DIR") or "/run/user/%d" % os.getuid()
    bases = [run, run + "/app/com.discordapp.Discord", run + "/app/com.discordapp.DiscordCanary", run + "/snap.discord"]
    return [str(Path(b) / ("discord-ipc-%d" % i)) for b in bases for i in range(10)]


def encode(op: int, payload: dict) -> bytes:
    data = json.dumps(payload, separators=(",", ":")).encode("utf-8")
    return struct.pack("<II", op, len(data)) + data


def read_frame(sock) -> tuple:
    head = _recv(sock, 8)
    op, size = struct.unpack("<II", head)
    if size > 1_000_000:
        raise OSError("respuesta demasiado grande")
    return op, json.loads(_recv(sock, size).decode("utf-8")) if size else {}


def _recv(sock, n: int) -> bytes:
    buf = b""
    while len(buf) < n:
        chunk = sock.recv(n - len(buf))
        if not chunk:
            raise OSError("Discord cerró la conexión")
        buf += chunk
    return buf


def activity(name: str, since: int, lang: str = "es") -> dict:
    return {"details": ("Jugando a " if lang != "en" else "Playing ") + name[:100], "state": "Omnia",
            "timestamps": {"start": int(since)}, "assets": {"large_image": "omnia", "large_text": "Omnia"}}


class DiscordPresence:
    def __init__(self, settings_fn, connect=None, clock=time.time):
        """settings_fn() -> {"enabled": bool, "app_id": str, "lang": str}."""
        self.settings_fn = settings_fn
        self._connect = connect or self._unix_connect
        self.clock = clock
        self._game = None                    # (nombre, inicio) o None
        self._sent = "unset"                 # lo último que Discord tiene
        self._sock = None
        self._app = ""
        self.user = ""
        self.connected = False
        self._next_try = 0.0
        self._wake = threading.Event()
        self._stop = threading.Event()
        self._lock = threading.Lock()
        self._thread = None

    # ---- API para el servicio
    def start(self):
        self._thread = threading.Thread(target=self._loop, daemon=True, name="discord")
        self._thread.start()

    def stop(self):
        self._stop.set()
        self._wake.set()
        if self._thread:
            self._thread.join(2)
        self._close()

    def set_game(self, name, since=None):
        game = (str(name), int(since or self.clock())) if name else None
        with self._lock:
            if (game and self._game and game[0] == self._game[0]):
                return
            self._game = game
        self._wake.set()

    def poke(self):
        """Pide revisar ya los ajustes (el usuario los cambió)."""
        self._next_try = 0.0
        self._wake.set()

    def status(self) -> dict:
        s = self.settings_fn()
        return {"enabled": bool(s.get("enabled")), "app_id_set": bool(APP_ID_RE.fullmatch(s.get("app_id", ""))),
                "connected": self.connected, "user": self.user,
                "socket": any(os.path.exists(p) for p in socket_paths())}

    # ---- hilo
    def _unix_connect(self):
        for p in socket_paths():
            if not os.path.exists(p):
                continue
            s = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
            s.settimeout(3)
            try:
                s.connect(p)
                return s
            except OSError:
                s.close()
        raise OSError("Discord no está abierto")

    def _close(self):
        if self._sock is not None:
            try:
                self._sock.close()
            except OSError:
                pass
        self._sock, self.connected, self._sent, self.user = None, False, "unset", ""

    def _handshake(self, app_id: str):
        s = self._connect()
        s.sendall(encode(HANDSHAKE, {"v": 1, "client_id": app_id}))
        op, data = read_frame(s)
        if op != FRAME or data.get("evt") != "READY":
            s.close()
            raise OSError("Discord rechazó el Application ID")
        self._sock, self._app, self.connected = s, app_id, True
        self.user = str(((data.get("data") or {}).get("user") or {}).get("username", ""))[:64]

    def _send_activity(self, game, lang):
        args = {"pid": os.getpid(), "activity": activity(game[0], game[1], lang) if game else None}
        self._sock.sendall(encode(FRAME, {"cmd": "SET_ACTIVITY", "args": args, "nonce": str(uuid.uuid4())}))
        read_frame(self._sock)

    def _tick(self):
        s = self.settings_fn()
        app_id = str(s.get("app_id", ""))
        if not s.get("enabled") or not APP_ID_RE.fullmatch(app_id):
            if self._sock is not None:
                try:
                    self._send_activity(None, "es")
                except (OSError, ValueError):
                    pass
                self._close()
            return
        if self._sock is not None and app_id != self._app:
            self._close()
        if self._sock is None:
            if self.clock() < self._next_try:
                return
            try:
                self._handshake(app_id)
            except (OSError, ValueError) as e:
                self._next_try = self.clock() + RETRY_SECS
                log.debug("discord: %s", e)
                return
        with self._lock:
            game = self._game
        if game != self._sent:
            try:
                self._send_activity(game, s.get("lang", "es"))
                self._sent = game
            except (OSError, ValueError):
                self._close()
                self._next_try = self.clock() + RETRY_SECS

    def _loop(self):
        while not self._stop.is_set():
            try:
                self._tick()
            except Exception:
                log.exception("fallo en la presencia de Discord")
            self._wake.wait(5)
            self._wake.clear()

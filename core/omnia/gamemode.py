"""Modo juego: mientras un juego de la biblioteca está en marcha, congela descargas en segundo plano y sube el perfil de
energía; al cerrarlo, restaura todo.

Seguridad ante fallos (un juego que se cierra de golpe no debe dejar tu sistema a medias):
  * El perfil de energía se pide con HoldProfile de power-profiles-daemon: lo mantiene la conexión de omnia-core al bus del
    sistema, así que si el servicio muere el sistema lo suelta solo.
  * Lo congelado se anota en ~/.cache/omnia/gamemode.json (pid + hora de arranque del proceso) y se reanuda al arrancar el
    servicio, sin tocar un pid reutilizado por otro proceso.
  * Solo se tocan procesos del propio usuario y por nombre exacto (config.json -> game_mode.freeze).
  * Los juegos en la nube (`"cloud": true`) no activan el modo juego.
"""
import logging
import os
import signal
import subprocess
import time
from pathlib import Path

from . import paths
from .store import load_json, write_json_atomic

log = logging.getLogger("omnia")

DEFAULTS = {"enabled": True, "profile": "performance",
            "freeze": ["qbittorrent", "transmission-gtk", "transmission-qt", "deluge", "deluged", "aria2c"]}
START_AFTER, END_AFTER = 2, 3          # sondeos seguidos (cada ~2 s) antes de entrar o salir: evita parpadeos de lanzadores


def settings(cfg: dict) -> dict:
    gm = cfg.get("game_mode") if isinstance(cfg.get("game_mode"), dict) else {}
    out = {**DEFAULTS, **{k: v for k, v in gm.items() if k in DEFAULTS}}
    out["freeze"] = [str(x) for x in out["freeze"]] if isinstance(out["freeze"], list) else DEFAULTS["freeze"]
    return out


def proc_info(pid: int, proc: str = "/proc"):
    """(nombre, estado, hora de arranque) leídos de /proc/<pid>/stat, o None si ya no existe."""
    try:
        raw = Path(proc, str(pid), "stat").read_text()
    except OSError:
        return None
    # el nombre va entre paréntesis y puede contener espacios y paréntesis: se corta por el último «)»
    comm, rest = raw[raw.index("(") + 1:raw.rindex(")")], raw[raw.rindex(")") + 2:].split()
    return comm, rest[0], int(rest[19])          # rest[0]=estado, rest[19]=starttime (campo 22 de stat)


class Freezer:
    def __init__(self, state_file: Path, proc: str = "/proc", uid: int | None = None):
        self.state_file, self.proc = Path(state_file), proc
        self.uid = os.getuid() if uid is None else uid

    def _mine(self, pid: int) -> bool:
        try:
            return os.stat(Path(self.proc, str(pid))).st_uid == self.uid
        except OSError:
            return False

    def freeze(self, names: list, extra: dict | None = None) -> list:
        """SIGSTOP a los procesos del usuario cuyo nombre coincide exactamente. Devuelve [(pid, arranque)]."""
        wanted, frozen = set(names), []
        if not wanted:
            return frozen
        for entry in os.listdir(self.proc):
            if not entry.isdigit() or int(entry) == os.getpid() or not self._mine(int(entry)):
                continue
            info = proc_info(int(entry), self.proc)
            if info and info[0] in wanted and info[1] != "T":
                try:
                    os.kill(int(entry), signal.SIGSTOP)
                    frozen.append((int(entry), info[2]))
                except OSError:
                    pass
        if frozen:       # se anota ANTES de seguir: si el servicio muere, el arranque siguiente los reanuda
            write_json_atomic(self.state_file, {"frozen": frozen, "when": int(time.time()), **(extra or {})})
        return frozen

    def resume(self) -> int:
        """Reanuda lo anotado. Un pid reutilizado por otro proceso (otra hora de arranque) no se toca."""
        state = load_json(self.state_file, {})
        n = 0
        for pid, start in state.get("frozen", []):
            info = proc_info(pid, self.proc)
            if info and info[2] == start:
                try:
                    os.kill(pid, signal.SIGCONT)
                    n += 1
                except OSError:
                    pass
        try:
            self.state_file.unlink()
        except OSError:
            pass
        return n


class HoldPower:
    """Retiene un perfil con power-profiles-daemon (bus del sistema); se libera solo si este proceso muere."""

    def __init__(self):
        self.cookie = None
        self.conn = None          # la conexión DEBE seguir viva mientras dure la retención: si GDBus la cierra, el demonio suelta el perfil

    def hold(self, profile: str) -> bool:
        try:
            import gi
            gi.require_version("Gio", "2.0")
            from gi.repository import Gio, GLib
            self.conn = conn = Gio.bus_get_sync(Gio.BusType.SYSTEM, None)
            r = conn.call_sync("net.hadess.PowerProfiles", "/net/hadess/PowerProfiles", "net.hadess.PowerProfiles",
                               "HoldProfile", GLib.Variant("(sss)", (profile, "Omnia: modo juego", "org.omnia.Core")),
                               GLib.VariantType("(u)"), Gio.DBusCallFlags.NONE, 5000, None)
            self.cookie = r.unpack()[0]
            return True
        except Exception as e:           # sin PyGObject, sin power-profiles-daemon o perfil no disponible
            log.warning("modo juego: no se pudo retener el perfil «%s»: %s", profile, e)
            return False

    def release(self) -> None:
        if self.cookie is None:
            return
        try:
            from gi.repository import Gio, GLib
            conn = self.conn or Gio.bus_get_sync(Gio.BusType.SYSTEM, None)
            conn.call_sync("net.hadess.PowerProfiles", "/net/hadess/PowerProfiles", "net.hadess.PowerProfiles",
                           "ReleaseProfile", GLib.Variant("(u)", (self.cookie,)), None, Gio.DBusCallFlags.NONE, 5000, None)
        except Exception as e:
            log.warning("modo juego: no se pudo soltar el perfil: %s", e)
        self.cookie = self.conn = None


class GameMode:
    def __init__(self, cfg: dict, freezer: Freezer, power=None, say=log.info):
        self.cfg, self.freezer, self.power, self.say = settings(cfg), freezer, power or HoldPower(), say
        self.active, self.games, self.frozen, self.held = False, [], 0, False
        self._on = self._off = 0

    def status(self) -> dict:
        return {"enabled": self.cfg["enabled"], "active": self.active, "games": self.games,
                "frozen": self.frozen, "profile": self.cfg["profile"] if self.held else ""}

    def update(self, running: list) -> bool:
        """Se llama cada pocos segundos con los nombres de los juegos en marcha. Devuelve True si cambió el estado."""
        if not self.cfg["enabled"]:
            return False
        if running:
            self._on, self._off = self._on + 1, 0
            self.games = list(running)
            if not self.active and self._on >= START_AFTER:
                self._start()
                return True
        else:
            self._off, self._on = self._off + 1, 0
            if self.active and self._off >= END_AFTER:
                self._stop()
                return True
        return False

    def _start(self):
        self.active = True
        try:
            self.frozen = len(self.freezer.freeze(self.cfg["freeze"], {"games": self.games}))
        except Exception:
            log.exception("modo juego: fallo al congelar procesos")
            self.freezer.resume()
        self.held = self.power.hold(self.cfg["profile"])
        self.say("modo juego activado (%s): %d procesos congelados, perfil %s", ", ".join(self.games), self.frozen,
                 self.cfg["profile"] if self.held else "sin cambios")

    def _stop(self):
        n = self.freezer.resume()
        self.power.release()
        self.say("modo juego desactivado: %d procesos reanudados", n)
        self.active, self.held, self.frozen, self.games = False, False, 0, []

    def shutdown(self):
        """Al parar el servicio: nada queda congelado ni retenido."""
        if self.active:
            self._stop()


def new(cfg: dict) -> GameMode:
    return GameMode(cfg, Freezer(paths.cache_dir() / "gamemode.json"))

"""GeForce NOW: un juego por cada acceso .desktop del escritorio que apunte a GeForce NOW.

La app de GeForce NOW para Linux no ofrece «Crear acceso directo», así que el usuario (o su script) deja el acceso en el
escritorio y Omnia lo muestra como juego de PC (src «GeForce NOW», lanzado con `gio launch`). El acceso al launcher en sí
(nombre «GeForce NOW») nunca es un juego. Si se borra el acceso, el juego desaparece solo. La app queda abierta al jugar,
así que estos juegos no se marcan como «en ejecución» ni activan el modo juego.
"""
from __future__ import annotations

import os
import re
from pathlib import Path

from .base import Detector

SUFFIX = re.compile(r"\s*\((?:GeForce NOW|GFN)\)\s*$", re.IGNORECASE)
LAUNCHER_NAMES = {"geforce now", "nvidia geforce now", "geforcenow"}


def desktop_dirs(home: Path | None = None) -> list:
    h = Path(home) if home else Path.home()
    out = []
    try:
        for line in (h / ".config/user-dirs.dirs").read_text(errors="replace").splitlines():
            if line.startswith("XDG_DESKTOP_DIR="):
                out.append(Path(line.partition("=")[2].strip().strip('"').replace("$HOME", str(h))))
    except OSError:
        pass
    out += [h / "Escritorio", h / "Desktop"]
    seen, dirs = set(), []
    for d in out:
        if d.is_dir() and d.resolve() not in seen:
            seen.add(d.resolve())
            dirs.append(d)
    return dirs


def parse(path: Path) -> dict:
    """Name y Exec de la sección [Desktop Entry] (sin dependencias)."""
    out, inside = {}, False
    try:
        text = path.read_text(encoding="utf-8", errors="replace")
    except OSError:
        return out
    for raw in text.splitlines():
        line = raw.strip()
        if line.startswith("["):
            inside = line == "[Desktop Entry]"
        elif inside and "=" in line:
            k, _, v = line.partition("=")
            if k in ("Name", "Exec") and k not in out:
                out[k] = v.strip()
    return out


def slug(name: str) -> str:
    return re.sub(r"[^a-z0-9]+", "-", name.lower()).strip("-") or "juego"


class GeForceNowDetector(Detector):
    name = "gfn"
    label = "GeForce NOW"

    def __init__(self, home: Path | None = None, dirs: list | None = None):
        self.dirs = [Path(d) for d in dirs] if dirs is not None else desktop_dirs(home)

    def detect(self) -> list:
        games, seen = [], set()
        for d in self.dirs:
            try:
                files = sorted(d.glob("*.desktop"))
            except OSError:
                continue
            for f in files:
                entry = parse(f)
                shown = entry.get("Name", "")
                if not shown or "geforcenow" not in (entry.get("Exec", "") + " " + shown).lower().replace(" ", ""):
                    continue
                name = SUFFIX.sub("", shown).strip()
                if name.lower() in LAUNCHER_NAMES or shown.strip().lower() in LAUNCHER_NAMES:
                    continue                                    # el launcher no es un juego
                gid = "gfn-" + slug(name)
                if gid in seen:
                    continue
                seen.add(gid)
                games.append({"id": gid, "name": name, "sub": "PC · GeForce NOW", "platform": "pc", "src": "GeForce NOW",
                              "auto": "gfn", "art": {"slug": gid, "sgdb": name},
                              "ports": [{"id": gid + "-main", "name": "GeForce NOW", "chips": ["Nube"],
                                         "launch": ["gio", "launch", str(f)], "check": str(f), "proc": ""}]})
        return games

    def is_installed(self, game: dict, port: dict) -> bool:
        return os.path.isfile(port.get("check") or "")          # existe mientras exista el acceso del escritorio

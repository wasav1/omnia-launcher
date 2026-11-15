"""Heroic (Epic vía legendary, GOG, Amazon vía nile): juegos instalados según los installed.json de Heroic."""
import json
import os
from pathlib import Path

from .base import Detector

RUNNERS = {"legendary": ("Epic", "legendaryConfig/legendary/installed.json", "legendary_library.json", "library"),
           "gog": ("GOG", "gog_store/installed.json", "gog_library.json", "games"),
           "nile": ("Amazon", "nile_store/installed.json", "nile_library.json", "library")}
FLATPAK_ID = "com.heroicgameslauncher.hgl"


def _load(path: Path):
    try:
        with open(path, encoding="utf-8") as f:
            return json.load(f)
    except (OSError, ValueError):
        return None


def config_dirs(home: Path | None = None) -> list:
    """(carpeta de config, comando base para lanzar). Nativo primero, después Flatpak."""
    h = Path(home) if home else Path.home()
    out = []
    for d, cmd in ((h / ".config/heroic", ["heroic"]),
                   (h / ".var/app" / FLATPAK_ID / "config/heroic", ["flatpak", "run", FLATPAK_ID])):
        if d.is_dir():
            out.append((d, cmd))
    return out


def gog_exe(path: str) -> str:
    """Ejecutable principal de un juego de GOG (goggame-*.info -> playTasks con isPrimary)."""
    try:
        for f in sorted(Path(path).glob("goggame-*.info")):
            for t in (_load(f) or {}).get("playTasks", []):
                if t.get("isPrimary") and t.get("path"):
                    return t["path"].replace("\\", "/")
    except OSError:
        pass
    return ""


class HeroicDetector(Detector):
    name = "heroic"
    label = "Heroic"

    def __init__(self, home: Path | None = None):
        self.home = home

    def detect(self) -> list:
        games, seen = [], set()
        for cfg, cmd in config_dirs(self.home):
            for runner, (store, rel, cache, key) in RUNNERS.items():
                d = _load(cfg / rel)
                if isinstance(d, dict) and "installed" in d:
                    items = d["installed"]
                elif isinstance(d, dict):
                    items = list(d.values())
                else:
                    items = d if isinstance(d, list) else []
                for v in items:
                    g = self._game(v, runner, store, cfg, cache, key, cmd)
                    if g and g["id"] not in seen:
                        seen.add(g["id"])
                        games.append(g)
        return games

    @staticmethod
    def _title(cfg: Path, cache: str, key: str, aid: str) -> str:
        """El installed.json de GOG y Amazon no trae el título: se busca en la caché de la biblioteca de Heroic."""
        d = _load(cfg / "store_cache" / cache)
        for x in (d or {}).get(key, []) if isinstance(d, dict) else []:
            if str(x.get("app_name")) == aid and x.get("title"):
                return x["title"]
        return ""

    def _game(self, v, runner, store, cfg, cache, key, cmd):
        if not isinstance(v, dict) or v.get("is_dlc"):
            return None
        aid = v.get("app_name") or v.get("appName")
        path = v.get("install_path") or (v.get("install") or {}).get("install_path")
        if not aid or not path or not os.path.isdir(path):
            return None             # sin carpeta de instalación no cuenta como instalado
        aid = str(aid)
        title = v.get("title") or self._title(cfg, cache, key, aid) or os.path.basename(str(path).rstrip("/")) or aid
        exe = v.get("executable") or gog_exe(path)
        return {"id": "heroic-%s-%s" % (runner, aid), "name": title, "sub": "PC · " + store, "platform": "pc",
                "src": "Heroic", "auto": "heroic", "art": {"slug": "heroic-%s-%s" % (runner, aid), "sgdb": title},
                "ports": [{"id": "heroic-%s-%s-main" % (runner, aid), "name": "Heroic", "chips": ["Heroic", store],
                           "launch": cmd + ["heroic://launch/%s/%s" % (runner, aid)], "check": str(path),
                           "proc": os.path.basename(exe.replace("\\", "/")), "disk_dir": str(path)}]}

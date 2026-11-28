"""Lutris: juegos instalados en su base de datos (pga.db), sin los de Steam ni los launchers."""
import os
import re
import sqlite3
from pathlib import Path

from . import ubisoft_lutris
from .base import Detector

# Un launcher nunca aparece como juego (regla heredada del prototipo).
NOT_GAMES = re.compile(r"^(steam|hydra|ea[ -]?app|ea[ -]?desktop|origin|ubisoft[ -]?connect|uplay|battle\.?net|"
                       r"epic[ -]games[ -]launcher|gog[ -]galaxy|rockstar[ -]games[ -]launcher|heroic.*|lutris)$", re.IGNORECASE)


def db_path(home: Path | None = None) -> Path:
    h = Path(home) if home else Path.home()
    base = os.environ.get("XDG_DATA_HOME", "")
    root = Path(base) if base and os.path.isabs(base) else h / ".local/share"
    return root / "lutris" / "pga.db"


_IMAGE_EXT = (".jpg", ".jpeg", ".png", ".webp")
_MAX_IMAGE = 12 * 1024 * 1024


def local_cover(slug: str, root: Path) -> str:
    """Carátula que Lutris ya descargó (`coverart/<slug>.jpg|png|webp`): un archivo normal, sin enlaces y de tamaño razonable."""
    if not re.fullmatch(r"[A-Za-z0-9._-]{1,120}", slug or ""):
        return ""
    for ext in _IMAGE_EXT:
        path = root / "coverart" / (slug + ext)
        try:
            if path.is_file() and not path.is_symlink() and 0 < path.stat().st_size <= _MAX_IMAGE:
                return str(path)
        except OSError:
            continue
    return ""


class LutrisDetector(Detector):
    name = "lutris"
    label = "Lutris"

    def __init__(self, home: Path | None = None, db: Path | None = None):
        self.db = Path(db) if db else db_path(home)
        self.home = Path(home) if home else Path.home()

    def config_dirs(self) -> list:
        """Carpetas donde Lutris guarda el `.yml` de cada juego (la nueva y la de versiones antiguas)."""
        return [self.db.parent / "games", self.home / ".config/lutris/games"]

    def config_file(self, configpath: str):
        if not configpath or not re.fullmatch(r"[A-Za-z0-9._-]{1,200}", configpath):
            return None
        for folder in self.config_dirs():
            path = folder / (configpath + ".yml")
            if path.is_file() and not path.is_symlink():
                return path
        return None

    def detect(self) -> list:
        if not self.db.is_file():
            return []
        try:       # solo lectura: nunca se modifica la base de datos de Lutris
            con = sqlite3.connect(f"file:{self.db}?mode=ro", uri=True, timeout=2)
            try:
                rows = con.execute("SELECT id, name, slug, runner, directory, configpath FROM games WHERE installed = 1").fetchall()
            except sqlite3.Error:           # bases antiguas sin configpath
                rows = [(*r, "") for r in con.execute("SELECT id, name, slug, runner, directory FROM games WHERE installed = 1").fetchall()]
            con.close()
        except sqlite3.Error:
            return []
        games = []
        for gid, name, slug, runner, directory, configpath in rows:
            if not name or runner == "steam" or NOT_GAMES.match(name.strip()) or NOT_GAMES.match(slug or ""):
                continue
            art = {"slug": f'lutris-{gid:d}', "sgdb": name}
            cover = local_cover(slug, self.db.parent)
            if cover:
                art["local"] = {"portada": cover}
            game = {"id": f'lutris-{gid:d}', "name": name, "sub": "PC · Lutris", "platform": "pc", "src": "Lutris",
                          "auto": "lutris", "art": art,
                          "ports": [{"id": f'lutris-{gid:d}-main', "name": "Lutris", "chips": ["Lutris"],
                                     "launch": ["lutris", f'lutris:rungameid/{gid:d}'],
                                     "check": str(directory) if directory and os.path.isdir(directory) else "",
                                     "proc": "lutris-wrapper: " + name}]}
            yml = self.config_file(configpath)
            fix = ubisoft_lutris.check(yml, name, slug) if yml else {}
            if fix:            # Ubisoft Connect lanza con el GUID: Omnia puede corregirlo (Administrar)
                game["ubisoftFix"] = {"productId": fix["productId"], "configpath": configpath}
            games.append(game)
        return [g for g in games if g["ports"][0]["check"]]    # sin carpeta del juego no cuenta como instalado

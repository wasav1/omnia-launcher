"""Lutris: juegos instalados en su base de datos (pga.db), sin los de Steam ni los launchers."""
import os
import re
import sqlite3
from pathlib import Path

from .base import Detector

# Un launcher nunca aparece como juego (regla heredada del prototipo).
NOT_GAMES = re.compile(r"^(steam|hydra|ea[ -]?app|ea[ -]?desktop|origin|ubisoft[ -]?connect|uplay|battle\.?net|"
                       r"epic[ -]games[ -]launcher|gog[ -]galaxy|rockstar[ -]games[ -]launcher|heroic.*|lutris)$", re.I)


def db_path(home: Path | None = None) -> Path:
    h = Path(home) if home else Path.home()
    base = os.environ.get("XDG_DATA_HOME", "")
    root = Path(base) if base and os.path.isabs(base) else h / ".local/share"
    return root / "lutris" / "pga.db"


class LutrisDetector(Detector):
    name = "lutris"
    label = "Lutris"

    def __init__(self, home: Path | None = None, db: Path | None = None):
        self.db = Path(db) if db else db_path(home)

    def detect(self) -> list:
        if not self.db.is_file():
            return []
        try:       # solo lectura: nunca se modifica la base de datos de Lutris
            con = sqlite3.connect("file:%s?mode=ro" % self.db, uri=True, timeout=2)
            rows = con.execute("SELECT id, name, slug, runner, directory FROM games WHERE installed = 1").fetchall()
            con.close()
        except sqlite3.Error:
            return []
        games = []
        for gid, name, slug, runner, directory in rows:
            if not name or runner == "steam" or NOT_GAMES.match(name.strip()) or NOT_GAMES.match(slug or ""):
                continue
            games.append({"id": "lutris-%d" % gid, "name": name, "sub": "PC · Lutris", "platform": "pc", "src": "Lutris",
                          "auto": "lutris", "art": {"slug": "lutris-%d" % gid, "sgdb": name},
                          "ports": [{"id": "lutris-%d-main" % gid, "name": "Lutris", "chips": ["Lutris"],
                                     "launch": ["lutris", "lutris:rungameid/%d" % gid],
                                     "check": str(directory) if directory and os.path.isdir(directory) else "",
                                     "proc": "lutris-wrapper: " + name}]})
        return [g for g in games if g["ports"][0]["check"]]    # sin carpeta del juego no cuenta como instalado

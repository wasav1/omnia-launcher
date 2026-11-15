"""Biblioteca y estado del usuario, en JSON con escritura atómica."""
import copy
import json
import os
import threading
from pathlib import Path

from . import paths


def load_json(path: Path, default):
    try:
        with open(path, encoding="utf-8") as f:
            return json.load(f)
    except (OSError, ValueError):
        return default


def write_json_atomic(path: Path, obj, mode: int = 0o600) -> None:
    path = Path(path)
    paths.ensure(path.parent)
    tmp = path.with_name(path.name + ".tmp")
    fd = os.open(tmp, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, mode)
    with os.fdopen(fd, "w", encoding="utf-8") as f:
        json.dump(obj, f, indent=1, ensure_ascii=False)
        f.flush()
        os.fsync(f.fileno())
    os.replace(tmp, path)


STATE_DEFAULT = {"last_played": {}, "sessions": {}, "art": {}, "backups": {},
                 "apps_used": {}, "apps_fav": None, "game_fav": [], "game_hidden": [],
                 "active_sessions": {}, "history": []}


class Store:
    def __init__(self, config_dir: Path | None = None):
        self.dir = Path(config_dir) if config_dir else paths.config_dir()
        self.lib_file = self.dir / "library.json"
        self.state_file = self.dir / "state.json"
        self.lock = threading.RLock()
        self._library = load_json(self.lib_file, {"games": []})
        self.state = {**copy.deepcopy(STATE_DEFAULT), **load_json(self.state_file, {})}   # copia profunda: los dict internos no se comparten

    # --- biblioteca
    def games(self) -> list:
        with self.lock:
            return list(self._library.get("games", []))

    def set_games(self, games: list) -> None:
        with self.lock:
            self._library["games"] = games
            write_json_atomic(self.lib_file, self._library)

    def find_game(self, gid: str):
        return next((g for g in self.games() if g.get("id") == gid), None)

    def find_port(self, gid: str, pid: str = ""):
        g = self.find_game(gid)
        if not g:
            return None, None
        ports = g.get("ports", [])
        for p in ports:
            if p.get("id") == pid or (not pid and p is ports[0]):
                return g, p
        return g, None

    # --- estado
    def save_state(self) -> None:
        with self.lock:
            write_json_atomic(self.state_file, self.state)

    def toggle(self, key: str, gid: str) -> bool:
        """Añade o quita gid de la lista state[key] (favoritos u ocultos). Devuelve si queda activo."""
        with self.lock:
            lst = list(self.state.get(key) or [])
            on = gid not in lst
            lst.append(gid) if on else lst.remove(gid)
            self.state[key] = lst
            self.save_state()
            return on

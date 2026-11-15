"""Rutas XDG de Omnia. Nada de rutas fijas ni de usuarios: todo sale del entorno."""
import os
import tempfile
from pathlib import Path

APP = "omnia"


def _xdg(var: str, default: str) -> Path:
    v = os.environ.get(var, "")
    # La especificación XDG exige ruta absoluta; si no lo es, se ignora.
    return Path(v) if v and os.path.isabs(v) else Path(default).expanduser()


def config_dir() -> Path:
    return _xdg("XDG_CONFIG_HOME", "~/.config") / APP


def data_dir() -> Path:
    return _xdg("XDG_DATA_HOME", "~/.local/share") / APP


def cache_dir() -> Path:
    return _xdg("XDG_CACHE_HOME", "~/.cache") / APP


def runtime_dir() -> Path:
    base = os.environ.get("XDG_RUNTIME_DIR", "")
    if base and os.path.isabs(base):
        return Path(base) / APP
    return Path(tempfile.gettempdir()) / f"{APP}-{os.getuid()}"


def ensure(path: Path, mode: int = 0o700) -> Path:
    path.mkdir(parents=True, exist_ok=True, mode=mode)
    return path

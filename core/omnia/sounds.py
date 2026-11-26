"""Paquetes de sonidos de la interfaz de Big Mode: carpetas `sounds/<paquete>/` con los mismos nombres de archivo.

Cada paquete debe traer al menos `move.wav` y `confirm.wav`. Los sonidos del paquete «omnia» están sintetizados por Omnia
(`tools/sound/generate_ui_sounds.py`); otros paquetes (p. ej. una biblioteca de licencia libre) se añaden como otra carpeta.
"""
from __future__ import annotations

from pathlib import Path

SEARCH = (Path("/usr/share/omnia/ui/qml/sounds"), Path(__file__).resolve().parents[2] / "ui" / "qml" / "sounds")
LABELS = {"omnia": "Omnia (sintetizados)", "kenney": "Kenney · Interface Sounds (CC0)"}
REQUIRED = ("move.wav", "confirm.wav")


def packs(dirs=SEARCH) -> list:
    """[{id, label}] de los paquetes instalados (el de Omnia siempre primero)."""
    found = {}
    for base in dirs:
        try:
            for entry in sorted(Path(base).iterdir()):
                if entry.is_dir() and entry.name not in found and all((entry / name).is_file() for name in REQUIRED):
                    found[entry.name] = {"id": entry.name, "label": LABELS.get(entry.name, entry.name)}
        except OSError:
            continue
    return sorted(found.values(), key=lambda p: (p["id"] != "omnia", p["id"]))

"""Sincroniza la biblioteca con lo que detectan los detectores: añade lo nuevo y quita lo desinstalado."""
import os
import threading

_LOCK = threading.Lock()      # el refresco periódico y el de la API no deben pisarse


def port_installed(p: dict) -> bool:
    chk = p.get("check") or (p.get("launch") or [""])[0]
    return bool(p.get("launch")) and bool(chk) and os.path.exists(os.path.expanduser(chk))


def refresh(store, detectors) -> dict:
    """Solo toca los juegos cuyo "auto" coincide con un detector que se ejecutó; las entradas manuales no se tocan."""
    with _LOCK:
        return _refresh(store, detectors)


def _refresh(store, detectors) -> dict:
    games = store.games()
    added = removed = 0
    for det in detectors:
        found = {g["id"]: g for g in det.detect()}
        keep = []
        for g in games:
            if g.get("auto") != det.name:
                keep.append(g)
            elif g["id"] in found:
                new = found.pop(g["id"])
                keep.append({**g, "ports": new["ports"]})     # conserva arte y ajustes del usuario
            else:
                removed += 1
        games = keep + list(found.values())
        added += len(found)
    store.set_games(games)
    return {"added": added, "removed": removed, "total": len(games)}

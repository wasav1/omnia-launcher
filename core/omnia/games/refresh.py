"""Sincroniza la biblioteca con lo que detectan los detectores: añade lo nuevo y quita lo desinstalado."""
import copy
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
    with store.lock:
        games = store.games()
        unlinked = store.state.setdefault("game_unlinked", {})
        previous_unlinked = copy.deepcopy(unlinked)
        added = removed = 0
        for det in detectors:
            found = {g["id"]: g for g in det.detect()}
            # Una desvinculación de un juego detectado se mantiene mientras el detector
            # siga encontrándolo. Si desaparece (p. ej. se desinstala), se limpia la
            # exclusión para que una instalación futura vuelva a aparecer normalmente.
            for gid, source in list(unlinked.items()):
                if source == det.name and gid not in found:
                    del unlinked[gid]
            for gid, source in unlinked.items():
                if source == det.name:
                    found.pop(gid, None)
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
        if unlinked != previous_unlinked:
            store.save_state()
        return {"added": added, "removed": removed, "total": len(games)}


def unlink(store, gid: str) -> bool:
    """Quita un juego de Omnia y evita que un detector lo vuelva a añadir."""
    with store.lock:
        games = store.games()
        game = next((g for g in games if g.get("id") == gid), None)
        if not game:
            return False
        if game.get("auto"):
            store.state.setdefault("game_unlinked", {})[gid] = game["auto"]
        store.set_games([g for g in games if g.get("id") != gid])
        state = store.state
        for key in ("game_fav", "game_hidden"):
            state[key] = [item for item in (state.get(key) or []) if item != gid]
        for key in ("saves", "sessions", "last_played", "backups", "art", "art_sources"):
            (state.get(key) or {}).pop(gid, None)
        state["history"] = [item for item in state.get("history", []) if item.get("id") != gid]
        state.get("active_sessions", {}).pop(gid, None)
        if state.get("selected_game") == gid:
            state["selected_game"] = ""
        store.save_state()
    return True

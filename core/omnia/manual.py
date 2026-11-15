"""Juegos manuales: los que Omnia no detecta sola (ports, emuladores, juegos de Windows sueltos, nativos).

Se guardan en la biblioteca SIN el campo `auto`, así que los refrescos de los detectores nunca los tocan. Usan el mismo
formato que el prototipo, de modo que el historial, el modo juego, el arte y las partidas funcionan igual con ellos.
"""
import os
import re
import shutil
from pathlib import Path

from . import templates

KINDS = {"port": "Port recompilado", "emulator": "Emulador", "windows": "Juego de Windows", "native": "Juego nativo"}
PLATFORMS = {"gopher64": "n64"}


class ManualError(Exception):
    pass


def slug(name: str) -> str:
    return re.sub(r"[^a-z0-9]+", "-", name.lower()).strip("-")[:48] or "juego"


def _inside(path: str, roots) -> bool:
    real = os.path.realpath(path)
    return any(real == str(r) or real.startswith(str(r).rstrip("/") + "/") for r in map(os.path.realpath, roots))


def add_game(store, data: dict, roots, gopher64=None, which=shutil.which) -> dict:
    name = str(data.get("name", "")).strip()
    if not name or len(name) > 80:
        raise ManualError("Pon un nombre al juego (hasta 80 letras).")
    tpl = str(data.get("template", "")) or ""
    kind = templates.TEMPLATES[tpl]["kind"] if tpl in templates.TEMPLATES else str(data.get("kind", ""))
    if kind not in KINDS:
        raise ManualError("Tipo de juego no válido.")
    exe, rom = str(data.get("exe", "")), str(data.get("rom", ""))
    for p in (exe, rom):
        if p and not _inside(p, roots):
            raise ManualError("Ese archivo está fuera de las carpetas permitidas.")
    try:
        if tpl:
            built = templates.build(tpl, exe=exe, rom=rom, gopher64=gopher64)
        else:
            if not exe or not os.path.isfile(exe):
                raise ManualError("Elige el ejecutable del juego.")
            install = os.path.dirname(exe)
            if kind == "windows":
                if not which("umu-run"):
                    raise ManualError("Falta umu-launcher para ejecutar juegos de Windows.")
                prefix = str(Path.home() / "Juegos/PC/_Prefijos" / slug(name))
                launch = ["env", "GAMEID=umu-0", "PROTONPATH=GE-Proton", "WINEPREFIX=" + prefix, "umu-run", exe]
            else:
                if not os.access(exe, os.X_OK):
                    raise ManualError("El archivo elegido no es ejecutable.")
                launch = [exe]
            built = {"launch": launch, "cwd": install, "check": exe, "proc": os.path.basename(exe), "saves": None,
                     "suggest": templates.suggest_dirs(install)}
    except templates.TemplateError as e:
        raise ManualError(str(e))
    saves = data.get("saves") if isinstance(data.get("saves"), dict) else built["saves"]
    with store.lock:
        games = store.games()
        base = "manual-" + slug(name)
        gid, n = base, 2
        while any(g.get("id") == gid for g in games):
            gid, n = "%s-%d" % (base, n), n + 1
        port = {"id": gid + "-main", "name": templates.TEMPLATES[tpl]["name"] if tpl else KINDS[kind], "chips": [KINDS[kind]],
                "launch": built["launch"], "check": built["check"], "proc": built["proc"]}
        if built["cwd"]:
            port["cwd"] = built["cwd"]
        if saves:
            port["saves"] = saves
        if isinstance(data.get("backup_dir"), str) and data["backup_dir"]:
            port["backup_dir"] = data["backup_dir"]
        entry = {"id": gid, "name": name, "sub": KINDS[kind], "platform": PLATFORMS.get(tpl, "pc"), "src": "Manual",
                 "art": {"slug": gid, "sgdb": name}, "ports": [port]}
        store.set_games(games + [entry])
    return entry


def remove_game(store, gid: str) -> bool:
    """Solo se quitan juegos manuales: los detectados reaparecerían en el siguiente refresco."""
    with store.lock:
        games = store.games()
        g = next((x for x in games if x.get("id") == gid), None)
        if not g or g.get("auto") or not gid.startswith("manual-"):
            return False
        store.set_games([x for x in games if x.get("id") != gid])
        st = store.state
        for key in ("game_fav", "game_hidden"):
            st[key] = [x for x in (st.get(key) or []) if x != gid]
        for key in ("saves", "sessions", "last_played", "backups"):
            (st.get(key) or {}).pop(gid, None)
        store.save_state()
    return True

"""Importador de la biblioteca anterior (el prototipo «Estantería», en Bazzite).

Primero se calcula un PLAN (vista previa, no escribe nada) y solo después se aplica lo elegido.
Reglas, con el motivo de cada omisión:
  * Entradas con `auto` (Steam, Heroic, Hydra…): no se importan. Steam, Heroic y Lutris los detecta Omnia sola; las
    carpetas de Hydra no se importan (se puede añadir el juego a mano).
  * GeForce NOW: aún sin soporte.
  * Ports y emuladores: se importan como juegos manuales. Un juego con varios ports pasa a ser un juego por port
    («Ocarina of Time · Longshot»), porque la interfaz lanza un port por tarjeta.
  * Un port sin lanzador o cuyo archivo ya no existe se omite.
Las rutas /var/home/<usuario> y /home/<usuario> pasan al home actual; se conservan carpetas de partidas y de respaldos.
"""
import json
import os
import re
from pathlib import Path

from . import templates

MAX_BYTES = 5 * 1024 * 1024
PLATFORM_LABEL = {"n64": "Nintendo 64", "sw1": "Nintendo Switch", "sw2": "Nintendo Switch 2", "pc": "PC"}
KEEP_PORT = ("name", "chips", "launch", "cwd", "check", "proc", "saves", "backup_dir")
CANDIDATES = ("/mnt/bazzite/home/{u}/.config/estanteria/library.json", "~/.config/estanteria/library.json")


class ImportError_(Exception):
    pass


def find_legacy(user: str | None = None, exists=os.path.isfile) -> list:
    """Bibliotecas anteriores que existen en los sitios habituales (el disco de Bazzite montado, o el home)."""
    user = user or Path.home().name
    out = []
    for c in CANDIDATES:
        p = os.path.expanduser(c.format(u=user))
        if exists(p) and p not in [x["path"] for x in out]:
            out.append({"path": p, "label": "Disco de Bazzite" if p.startswith("/mnt/") else "Esta cuenta"})
    return out


def load(path) -> dict:
    p = Path(path)
    if p.name != "library.json" or not p.is_file():
        raise ImportError_("No es una biblioteca anterior (library.json).")
    if p.stat().st_size > MAX_BYTES:
        raise ImportError_("El archivo es demasiado grande.")
    try:
        d = json.loads(p.read_text(encoding="utf-8"))
    except (OSError, ValueError):
        raise ImportError_("No se pudo leer la biblioteca anterior.")
    if not isinstance(d, dict) or not isinstance(d.get("games"), list):
        raise ImportError_("La biblioteca anterior no tiene el formato esperado.")
    return d


def make_mapper(new_home: str, user: str):
    pat = re.compile(r"(^|=)(?:/var/home/%s|/home/%s)(?=/|$)" % (re.escape(user), re.escape(user)))

    def mp(value):
        if isinstance(value, str):
            if value.startswith("~"):
                return new_home + value[1:]
            return pat.sub(lambda m: m.group(1) + new_home, value)
        if isinstance(value, list):
            return [mp(v) for v in value]
        if isinstance(value, dict):
            return {k: mp(v) for k, v in value.items()}
        return value
    return mp


def _slug(s: str) -> str:
    return re.sub(r"[^a-z0-9]+", "-", s.lower()).strip("-")


def _exe(port: dict) -> str:
    """El archivo que hay que tener para poder lanzar este port: `check`, o el último argumento del comando."""
    launch = port.get("launch") or []
    return port.get("check") or (launch[-1] if launch else "")


def plan(legacy: dict, current_games: list, new_home: str | None = None, user: str | None = None,
         exists=os.path.exists, gopher64_installed=None) -> dict:
    new_home, user = new_home or str(Path.home()), user or Path.home().name
    mp = make_mapper(new_home, user)
    have = {g.get("id") for g in current_games}
    items, warnings = [], []
    g64_used = False
    for g in legacy.get("games", []):
        gid = str(g.get("id", ""))
        if not gid:
            continue
        name = str(g.get("name", gid))
        if g.get("auto"):
            src = (g.get("src") or "").strip()
            reason = {"Steam": "Omnia detecta los juegos de Steam sola",
                      "Heroic": "aparecerá cuando Heroic conozca el juego (abre Heroic e importa los instalados)",
                      "Lutris": "Omnia detecta los juegos de Lutris sola"}.get(src, "las carpetas de Hydra no se importan: añade el juego a mano si lo quieres")
            items.append({"id": "", "legacyId": gid, "name": name, "status": "skip", "reason": reason, "src": src})
            continue
        if (g.get("src") or "") == "GeForce NOW" or gid.startswith("gfn-"):
            items.append({"id": "", "legacyId": gid, "name": name, "status": "skip", "reason": "GeForce NOW todavía no está soportado",
                          "src": "GeForce NOW"})
            continue
        ports = [p for p in g.get("ports", []) if isinstance(p, dict)]
        ok = []
        for p in ports:
            mapped = mp(p)
            if not mapped.get("launch"):
                items.append({"id": "", "legacyId": gid, "name": "%s · %s" % (name, p.get("name", p.get("id", ""))), "status": "skip",
                              "reason": "este port no tiene lanzador", "src": PLATFORM_LABEL.get(g.get("platform"), "")})
                continue
            exe = _exe(mapped)
            if not exe or not exists(exe):
                items.append({"id": "", "legacyId": gid, "name": "%s · %s" % (name, p.get("name", "")), "status": "skip",
                              "reason": "ya no existe: %s" % exe, "src": PLATFORM_LABEL.get(g.get("platform"), "")})
                continue
            ok.append((p, mapped))
        for p, mapped in ok:
            multi = len(ok) > 1
            new_id = "manual-" + _slug(gid) + ("-" + _slug(str(p.get("id", ""))) if multi else "")
            shown = "%s · %s" % (name, p.get("name", "")) if multi else name
            uses_g64 = any("gopher64" in str(a) for a in mapped["launch"])
            g64_used = g64_used or uses_g64
            entry = {"id": new_id, "name": shown, "sub": PLATFORM_LABEL.get(g.get("platform"), g.get("sub", "")),
                     "platform": g.get("platform", "pc"), "src": PLATFORM_LABEL.get(g.get("platform"), "Manual"),
                     "art": {"slug": new_id, "sgdb": (g.get("art") or {}).get("sgdb") or name},
                     "ports": [{"id": new_id + "-main", **{k: mapped[k] for k in KEEP_PORT if mapped.get(k)}}]}
            items.append({"id": new_id, "legacyId": gid, "name": shown, "status": "existing" if new_id in have else "new",
                          "reason": "ya está en tu biblioteca" if new_id in have else "", "src": entry["src"], "entry": entry,
                          "hasSaves": bool(mapped.get("saves"))})
    if g64_used:
        installed = gopher64_installed
        if installed is None:
            try:
                templates.gopher64_install()
                installed = True
            except templates.TemplateError:
                installed = False
        if not installed:
            warnings.append("Gopher64 no está instalado: los juegos de N64 aparecerán, pero no arrancarán hasta instalarlo.")
    order = {"new": 0, "existing": 1, "skip": 2}
    items.sort(key=lambda i: (order[i["status"]], i["name"].casefold()))
    summary = {s: sum(1 for i in items if i["status"] == s) for s in order}
    return {"items": items, "warnings": warnings, "summary": summary}


def apply(store, plan_: dict, ids=None) -> list:
    """Añade a la biblioteca los juegos NUEVOS del plan (todos, o solo los ids indicados). Devuelve los ids añadidos."""
    chosen = [i for i in plan_["items"] if i["status"] == "new" and (ids is None or i["id"] in ids)]
    added = []
    with store.lock:
        games = store.games()
        have = {g.get("id") for g in games}
        for i in chosen:
            if i["id"] in have:
                continue
            games.append(i["entry"])
            added.append(i["id"])
        if added:
            store.set_games(games)
    return added

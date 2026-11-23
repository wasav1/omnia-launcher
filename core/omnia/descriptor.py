"""Lectura (solo datos) del descriptor `recomplauncher.json` de un port instalado.

Muchos ports traen en su carpeta un `recomplauncher.json` (formato del SDK de RecompLauncher, MIT) que dice dónde guardan sus
partidas, qué copia del juego aceptan, qué necesitan del PC y qué carpetas conviene abrir. Omnia lo lee como datos: nunca ejecuta
nada de él (no usa `prepare`) y cada ruta se resuelve con una lista cerrada de marcadores, sin shell.

Marcadores admitidos: {install} {data} {local} {config} {home} {documents}. Los que dependen del jugador o de la sesión
({input:…}, {pad}) no se resuelven aquí: una ruta que los use se descarta.
"""
from __future__ import annotations

import json
import os
import re
from pathlib import Path

MAX_BYTES = 512 * 1024
NAME = "recomplauncher.json"
_PLACEHOLDER = re.compile(r"\{([a-z]+)(?::[^}]*)?\}")
_KNOWN = {"install", "data", "local", "config", "home", "documents"}


def load(root) -> dict:
    """El descriptor de la carpeta `root` ({} si no hay, es demasiado grande o no es un objeto JSON)."""
    path = Path(root) / NAME
    try:
        if path.is_symlink() or not path.is_file() or path.stat().st_size > MAX_BYTES:
            return {}
        data = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, ValueError):
        return {}
    return data if isinstance(data, dict) else {}


def find_root(game: dict, port: dict | None = None) -> Path | None:
    """Carpeta instalada de un juego que tiene descriptor: la del paquete de Omnia o la del port (cwd o carpeta del ejecutable)."""
    port = port or {}
    candidates = [game.get("installPath"), port.get("cwd"), os.path.dirname(str(port.get("check") or ""))]
    for raw in candidates:
        if not raw:
            continue
        root = Path(os.path.expanduser(str(raw)))
        if root.is_dir() and (root / NAME).is_file():
            return root
    return None


def _bases(root: Path) -> dict:
    home = Path.home()
    xdg = lambda var, default: Path(os.environ.get(var) or "") if os.path.isabs(os.environ.get(var) or "") else home / default
    documents = home / "Documents"
    try:                                                    # XDG_DOCUMENTS_DIR si el usuario lo definió
        for line in (xdg("XDG_CONFIG_HOME", ".config") / "user-dirs.dirs").read_text().splitlines():
            if line.startswith("XDG_DOCUMENTS_DIR="):
                documents = Path(os.path.expandvars(line.split("=", 1)[1].strip().strip('"')))
    except OSError:
        pass
    return {"install": root, "data": root / "recompdata", "local": xdg("XDG_DATA_HOME", ".local/share"),
            "config": xdg("XDG_CONFIG_HOME", ".config"), "home": home, "documents": documents}


def expand(template, root) -> str | None:
    """Ruta absoluta de una plantilla, o None si usa marcadores desconocidos, no es absoluta o intenta salir con `..`.

    Una ruta que sea justo una carpeta base ({home}, {local}…) también se rechaza: sería respaldar o abrir un árbol entero."""
    if not isinstance(template, str) or not template or "\0" in template:
        return None
    root = Path(root)
    bases = _bases(root)
    for name in _PLACEHOLDER.findall(template):
        if name not in _KNOWN:
            return None
    if re.search(r"\{(?:input|pad)", template):
        return None
    out = template
    for name, base in bases.items():
        out = out.replace("{" + name + "}", str(base))
    if "{" in out or "}" in out:
        return None
    path = os.path.normpath(out)
    if not os.path.isabs(path) or ".." in Path(out).parts:
        return None
    if path in {str(b) for k, b in bases.items() if k != "install" and k != "data"} or path == "/":
        return None
    return path


def _first(entries, root: Path) -> str | None:
    """Entre varias rutas candidatas ({path, if}), la primera cuyo `if` existe; sin `if` es el valor por defecto."""
    if isinstance(entries, str):
        return expand(entries, root)
    if isinstance(entries, dict):
        entries = [entries]
    fallback = None
    for entry in entries if isinstance(entries, list) else []:
        if isinstance(entry, str):
            fallback = fallback or expand(entry, root)
        elif isinstance(entry, dict):
            path = expand(entry.get("path"), root)
            if path is None:
                continue
            cond = entry.get("if")
            if cond is None:
                fallback = fallback or path
            else:
                resolved = expand(cond, root)
                if resolved and os.path.exists(resolved):
                    return path
    return fallback


def saves_spec(root, data: dict | None = None) -> dict:
    """Especificación de partidas (como la de `omnia.saves`) a partir de `saves` del descriptor.

    Un patrón con `*` o un archivo que ya existe va en `files`; lo demás (carpetas, existan ya o no) en `dirs`."""
    data = data if data is not None else load(root)
    files, dirs = [], []
    for template in data.get("saves") if isinstance(data.get("saves"), list) else []:
        path = expand(template, root)
        if not path:
            continue
        if any(ch in path for ch in "*?[") or os.path.isfile(path):
            if path not in files:
                files.append(path)
        elif path not in dirs:
            dirs.append(path)
    return {"files": files, "dirs": dirs, "name": "Partida"} if files or dirs else {}


def folders(root, data: dict | None = None) -> dict:
    """{nombre: ruta absoluta} de las carpetas con nombre del descriptor (`folders`), ya resueltas."""
    data = data if data is not None else load(root)
    out = {}
    named = data.get("folders") if isinstance(data.get("folders"), dict) else {}
    for name, entries in named.items():
        if isinstance(name, str) and re.fullmatch(r"[A-Za-z0-9_-]{1,40}", name):
            path = _first(entries, Path(root))
            if path:
                out[name] = path
    return out


def actions(root, data: dict | None = None) -> list:
    """Botones «abrir carpeta» del descriptor: [{id, label, help, folder}] solo con carpetas que existan."""
    data = data if data is not None else load(root)
    known = folders(root, data)
    out = []
    for item in data.get("actions") if isinstance(data.get("actions"), list) else []:
        if not isinstance(item, dict) or item.get("open") not in known or not os.path.isdir(known[item["open"]]):
            continue
        out.append({"id": str(item.get("id") or item["open"])[:40], "label": str(item.get("label") or item["open"])[:60],
                    "help": str(item.get("help") or "")[:200], "folder": item["open"]})
    return out


def build_id_prefixes(data: dict) -> list:
    """Build IDs (hex, mínimo 8 dígitos) que el port acepta: `inputs[].check.nup_build_id` (texto o lista)."""
    out = []
    inputs = list(data.get("inputs") or [])
    if isinstance(data.get("game"), dict):                  # forma antigua del descriptor: `game` suelto
        inputs.append(data["game"])
    for item in inputs:
        check = item.get("check") if isinstance(item, dict) else None
        values = (check or {}).get("nup_build_id")
        for value in values if isinstance(values, list) else [values]:
            if isinstance(value, str) and re.fullmatch(r"[0-9a-fA-F]{8,64}", value):
                out.append(value.lower())
    return out


def compatibility(data: dict, build_id: str) -> dict:
    """¿La copia del jugador (su build ID) es la que acepta el port? state: ok | mismatch | unknown."""
    expected = build_id_prefixes(data)
    build = (build_id or "").lower()
    if not expected:
        return {"state": "unknown", "expected": [], "found": build}
    if not build:
        return {"state": "unknown", "expected": expected, "found": ""}
    state = "ok" if any(build.startswith(prefix) or prefix.startswith(build) for prefix in expected) else "mismatch"
    return {"state": state, "expected": expected, "found": build}


def _version_tuple(text) -> tuple:
    parts = re.findall(r"\d+", str(text or ""))
    return tuple(int(p) for p in parts[:3])


def glibc_version() -> str:
    try:
        return os.confstr("CS_GNU_LIBC_VERSION").split()[-1]
    except (ValueError, OSError, AttributeError, IndexError):
        return ""


def requirements(data: dict, glibc: str | None = None) -> list:
    """Requisitos de Linux del descriptor (`system.linux`) y si este equipo los cumple.

    [{key, label, need, have, ok}]; `ok` es None cuando no se puede comprobar (solo se informa). El juego arranca igual:
    es un aviso, no un bloqueo."""
    linux = (data.get("system") or {}).get("linux") if isinstance(data.get("system"), dict) else None
    if not isinstance(linux, dict):
        return []
    out = []
    need = linux.get("glibc")
    if isinstance(need, str) and need:
        have = glibc if glibc is not None else glibc_version()
        ok = None if not have else _version_tuple(have) >= _version_tuple(need)
        out.append({"key": "glibc", "label": "glibc", "need": need, "have": have, "ok": ok})
    graphics = linux.get("graphics") if isinstance(linux.get("graphics"), dict) else {}
    for api, version in graphics.items():
        if isinstance(api, str) and isinstance(version, (str, int, float)):
            out.append({"key": api, "label": {"vulkan": "Vulkan", "opengl": "OpenGL"}.get(api, api), "need": str(version),
                        "have": "", "ok": None})
    return out


def exit_message(data: dict, code: int) -> str:
    """Mensaje que el port declara para un código de salida («» si no hay; «ok» = cierre normal)."""
    codes = data.get("exit_codes") if isinstance(data.get("exit_codes"), dict) else {}
    value = codes.get(str(code))
    return str(value)[:300] if isinstance(value, str) else ""

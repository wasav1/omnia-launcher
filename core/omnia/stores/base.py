"""Utilidades comunes de las tiendas: localizar herramientas y ejecutar subprocesos de forma segura."""
import json
import os
import shutil
import subprocess
from pathlib import Path

HEROIC_BIN_DIRS = ("/usr/lib/heroic-games-launcher/app.asar.unpacked/build/bin/x64/linux",
                   "/opt/Heroic/resources/app.asar.unpacked/build/bin/x64/linux")


class StoreError(Exception):
    """Error mostrable al usuario (mensaje en español)."""


def find_tool(name: str, extra_dirs=HEROIC_BIN_DIRS) -> str | None:
    """Ruta de una herramienta: primero el PATH, luego el paquete que incluye Heroic."""
    found = shutil.which(name)
    if found:
        return found
    for d in extra_dirs:
        p = Path(d) / name
        if p.is_file() and os.access(p, os.X_OK):
            return str(p)
    return None


def run(cmd: list, env_extra: dict | None = None, timeout: int = 60, runner=subprocess.run):
    """Ejecuta sin shell; devuelve (código, stdout, stderr). Nunca lanza por salida distinta de cero."""
    env = dict(os.environ)
    env.update(env_extra or {})
    try:
        r = runner(cmd, capture_output=True, text=True, timeout=timeout, env=env, stdin=subprocess.DEVNULL)
    except subprocess.TimeoutExpired:
        raise StoreError("La tienda tardó demasiado en responder.")
    except OSError as e:
        raise StoreError("No se pudo ejecutar la herramienta de la tienda (" + str(e) + ").")
    return r.returncode, r.stdout or "", r.stderr or ""


def parse_json(text: str):
    """JSON de la salida de una herramienta (puede traer líneas de registro antes)."""
    text = text.strip()
    try:
        return json.loads(text)
    except ValueError:
        pass
    for i, ch in enumerate(text):
        if ch in "[{":
            try:
                return json.loads(text[i:])
            except ValueError:
                continue
    raise StoreError("La tienda devolvió datos que Omnia no entiende.")


def pasted_code(raw: str, names, pattern) -> str:
    """Código de un solo uso pegado por el usuario: solo, o dentro de la URL de retorno (?code=…)."""
    import re
    import urllib.parse
    raw = (raw or "").strip().strip('"')
    if "://" in raw or "?" in raw:
        query = urllib.parse.urlsplit(raw).query or raw.split("?", 1)[-1]
        params = urllib.parse.parse_qs(query)
        for n in names:
            if params.get(n):
                raw = params[n][0]
                break
    if not re.fullmatch(pattern, raw):
        raise StoreError("El código no es válido. Copia la dirección completa de la página a la que te lleva el inicio de sesión.")
    return raw

"""Juegos de Ubisoft instalados con Lutris: lanzar con el número de producto en lugar del GUID.

El instalador de Lutris deja `uplay://launch/<GUID>` en el `.yml` del juego; con eso Ubisoft Connect puede quedarse en
«Initializing». Con el número de producto (`uplay://launch/2688/0`) arranca bien. Ubisoft Connect registra cada juego
instalado en el registro del prefijo de Wine (`Ubisoft\\Launcher\\Installs\\<producto>` con su `InstallDir`), así que
Omnia puede encontrar el número sin preguntar.

Detectarlo es solo lectura. Corregir el `.yml` es una acción explícita del usuario (Administrar → Corregir lanzamiento de
Ubisoft): se guarda una copia `.omnia.bak` y solo se cambia la línea `args` del bloque `game:`.
"""
import re
import shutil
from pathlib import Path

_GUID = r"[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}"
_GUID_ARGS = re.compile(r"^(  args:\s*)uplay://launch/(" + _GUID + r")(?:/\d+)?\s*$")
_INSTALL_KEY = re.compile(r"^\[Software\\\\Wow6432Node\\\\Ubisoft\\\\Launcher\\\\Installs\\\\(\d{1,9})\]", re.I)
_INSTALL_DIR = re.compile(r'^"InstallDir"="(.*)"\s*$', re.I)
_MAX_REG = 64 * 1024 * 1024


def _norm(text: str) -> str:
    return re.sub(r"[^a-z0-9]+", "", (text or "").lower())


def game_block(yml_text: str) -> dict:
    """Valores simples del bloque `game:` de nivel superior (args, exe, prefix)."""
    out, inside = {}, False
    for line in (yml_text or "").splitlines():
        if re.match(r"^game:\s*$", line):
            inside = True
            continue
        if inside:
            if line and not line.startswith(" "):
                break
            match = re.match(r"^  ([a-z_]+):\s*(.*?)\s*$", line)
            if match:
                out[match.group(1)] = match.group(2).strip("'\"")
    return out


def installs(prefix) -> dict:
    """{producto: carpeta} de los juegos que Ubisoft Connect registró en el prefijo."""
    reg = Path(prefix) / "system.reg"
    try:
        if not reg.is_file() or reg.stat().st_size > _MAX_REG:
            return {}
        text = reg.read_text(encoding="utf-8", errors="replace")
    except OSError:
        return {}
    found, current = {}, ""
    for line in text.splitlines():
        key = _INSTALL_KEY.match(line)
        if key:
            current = key.group(1)
            found.setdefault(current, "")
            continue
        if line.startswith("["):
            current = ""
            continue
        if current:
            value = _INSTALL_DIR.match(line)
            if value:
                found[current] = value.group(1).replace("\\\\", "/").rstrip("/").split("/")[-1]
    return found


def product_for(name: str, slug: str, prefix) -> str:
    """Número de producto del juego: por nombre de carpeta (WATCH_DOGS2 ↔ «WATCH_DOGS® 2»), o el único instalado."""
    found = installs(prefix)
    if not found:
        return ""
    wanted = {_norm(name), _norm(re.sub(r"-ubisoft$", "", slug or ""))} - {""}
    for product, folder in found.items():
        if _norm(folder) and _norm(folder) in wanted:
            return product
    return next(iter(found)) if len(found) == 1 else ""


def check(yml_path, name: str = "", slug: str = "") -> dict:
    """{productId, guid} si el juego lanza con un GUID y se conoce su número de producto; {} si no hace falta nada."""
    try:
        text = Path(yml_path).read_text(encoding="utf-8")
    except (OSError, UnicodeDecodeError):
        return {}
    block = game_block(text)
    match = re.fullmatch(r"uplay://launch/(" + _GUID + r")(?:/\d+)?", block.get("args", ""))
    if not match or not block.get("prefix"):
        return {}
    product = product_for(name, slug, block["prefix"])
    return {"productId": product, "guid": match.group(1)} if product else {}


def apply(yml_path, product_id: str) -> Path:
    """Cambia `uplay://launch/<GUID>` por `uplay://launch/<producto>/0` en el bloque `game:`; devuelve la copia de respaldo."""
    if not re.fullmatch(r"\d{1,9}", str(product_id)):
        raise ValueError("Número de producto no válido.")
    path = Path(yml_path)
    text = path.read_text(encoding="utf-8")
    lines = text.splitlines(keepends=True)
    inside, changed = False, False
    for i, line in enumerate(lines):
        bare = line.rstrip("\n")
        if re.match(r"^game:\s*$", bare):
            inside = True
            continue
        if inside and bare and not bare.startswith(" "):
            break
        if inside:
            match = _GUID_ARGS.match(bare)
            if match:
                lines[i] = f"{match.group(1)}uplay://launch/{product_id}/0" + ("\n" if line.endswith("\n") else "")
                changed = True
                break
    if not changed:
        raise ValueError("El juego ya no lanza con un GUID de Ubisoft.")
    backup = path.with_name(path.name + ".omnia.bak")
    if not backup.exists():
        shutil.copy2(path, backup)
    tmp = path.with_name(path.name + ".omnia.tmp")
    tmp.write_text("".join(lines), encoding="utf-8")
    tmp.replace(path)
    return backup

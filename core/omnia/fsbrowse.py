"""Explorador de carpetas para la ventana de selección (con mando): lista carpetas, y opcionalmente archivos.

Seguridad: solo se puede mirar dentro del home del usuario y de los discos externos montados; la ruta se resuelve
(enlaces simbólicos incluidos) ANTES de comprobar que cae dentro de esas raíces, así un enlace no sirve para escapar.
Solo devuelve nombres: nunca el contenido de un archivo.
"""
import os
from pathlib import Path

LIMIT = 500


class FsError(Exception):
    pass


def allowed_roots() -> list:
    user, home = os.environ.get("USER") or Path.home().name, Path.home()
    cands = [home, Path("/run/media") / user, Path("/media") / user, Path("/mnt")]
    return [c for c in cands if c.is_dir()]


def _under(path: str, root: str) -> bool:
    return path == root or path.startswith(root.rstrip("/") + "/")


def _real_roots(roots) -> list:
    return [os.path.realpath(r) for r in roots]


def shortcuts(roots=None) -> list:
    """Atajos de la primera pantalla: Inicio, Juegos (si existe) y los discos externos."""
    roots, home = roots if roots is not None else allowed_roots(), Path.home()
    out = [{"name": "Inicio", "path": str(home)}]
    if (home / "Juegos").is_dir():
        out.append({"name": "Juegos", "path": str(home / "Juegos")})
    for r in roots:
        if str(r).startswith(("/run/media", "/media", "/mnt")):
            try:
                out += [{"name": d.name, "path": str(d)} for d in sorted(r.iterdir()) if d.is_dir()] if str(r) != "/mnt" else \
                       [{"name": "/mnt/" + d.name, "path": str(d)} for d in sorted(r.iterdir()) if d.is_dir()]
            except OSError:
                pass
    return out


def list_dir(path=None, roots=None, hidden: bool = False, files: bool = False, exts=None, limit: int = LIMIT) -> dict:
    roots = roots if roots is not None else allowed_roots()
    real_roots = _real_roots(roots)
    start = Path(path).expanduser() if path else Path.home()
    real = os.path.realpath(start)
    if not any(_under(real, r) for r in real_roots):
        raise FsError("ruta fuera de las carpetas permitidas")
    if not os.path.isdir(real):
        raise FsError("no es una carpeta")
    exts = {e.lower() for e in (exts or [])}
    dirs, fl = [], []
    try:
        with os.scandir(real) as it:
            for e in it:
                if not hidden and e.name.startswith("."):
                    continue
                try:
                    if e.is_dir():
                        dirs.append({"name": e.name, "path": os.path.join(real, e.name)})
                    elif files and e.is_file() and (not exts or Path(e.name).suffix.lower() in exts):
                        fl.append({"name": e.name, "path": os.path.join(real, e.name)})
                except OSError:
                    continue
    except PermissionError:
        raise FsError("sin permiso para leer la carpeta")
    key = lambda x: x["name"].casefold()
    dirs.sort(key=key)
    fl.sort(key=key)
    parent = os.path.dirname(real)
    return {"path": real, "parent": parent if parent != real and any(_under(parent, r) for r in real_roots) else None,
            "dirs": dirs[:limit], "files": fl[:limit], "truncated": len(dirs) > limit or len(fl) > limit,
            "shortcuts": shortcuts(roots)}

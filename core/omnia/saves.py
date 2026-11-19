"""Partidas: localizar, respaldar y restaurar.

Una «especificación» (spec) dice dónde están las partidas de un juego. Es compatible con el prototipo y añade `dirs`:
  {"glob": "~/.local/share/longshot/save/*/slot_*"}      cada coincidencia es una CARPETA (una ranura)
  {"files": ["~/…/saves/*-<SHA256 de la ROM>.*"]}         cada coincidencia es un ARCHIVO
  {"dirs": ["~/…/MiJuego/Saved"]}                         carpetas completas (las que el usuario elige en el explorador)
  «name»: plantilla del nombre de cada ranura, p. ej. "Ranura {n}".

Respaldos: un .tar.gz con un manifiesto (omnia-backup.json) que guarda la ruta original de cada cosa, para poder restaurar
(los respaldos del prototipo no lo tienen: se listan, pero no se restauran solos).
Restaurar es prudente: solo escribe dentro de las carpetas de partidas del juego, rechaza enlaces y rutas con `..`, y antes
hace un respaldo de lo que había, para poder volver atrás.
"""
import glob
import io
import json
import os
import re
import tarfile
import time
from pathlib import Path

MANIFEST = "omnia-backup.json"
MAX_BYTES = 2 * 1024 ** 3          # un respaldo de más de 2 GiB casi seguro es una carpeta mal elegida (p. ej. el home entero)
KINDS = {"eep": "Partida (EEPROM)", "sra": "Partida (SRAM)", "fla": "Partida (Flash)", "mpk": "Controller Pak", "srm": "Partida"}


class SaveError(Exception):
    pass


def expand(p) -> str:
    return os.path.expanduser(p) if isinstance(p, str) else ""


# ---------------------------------------------------------------- localizar
def matches(spec) -> list:
    """Rutas existentes que describe la especificación (ranuras, archivos y carpetas), sin repetidos, ordenadas."""
    spec, out = spec or {}, []
    for pat in spec.get("files") or []:
        out += [f for f in sorted(glob.glob(expand(pat), recursive=True)) if os.path.isfile(f)]
    pat = expand(spec.get("glob") or "")
    if pat:
        out += [d for d in sorted(glob.glob(pat, recursive=True)) if os.path.isdir(d)]
    out += [d for d in (expand(x) for x in spec.get("dirs") or []) if os.path.isdir(d)]
    seen, uniq = set(), []
    for p in out:
        r = os.path.realpath(p)
        if r not in seen:
            seen.add(r)
            uniq.append(p)
    return uniq


def roots(spec) -> list:
    """Carpetas donde es legítimo escribir al restaurar: el tramo fijo de cada patrón (antes del primer comodín)."""
    spec, out = spec or {}, []
    pats = [expand(p) for p in (spec.get("files") or [])] + ([expand(spec["glob"])] if spec.get("glob") else [])
    for pat in pats:
        static = re.split(r"[*?\[]", pat, maxsplit=1)[0]
        out.append(static if static.endswith("/") else os.path.dirname(static))
    out += [expand(x) for x in spec.get("dirs") or []]
    return [os.path.realpath(r) for r in out if r and os.path.isabs(r) and r not in ("/", "")]


def _size(path: str) -> int:
    if os.path.isfile(path):
        return os.path.getsize(path)
    total = 0
    for root, _, files in os.walk(path):
        for f in files:
            try:
                if not os.path.islink(os.path.join(root, f)):
                    total += os.path.getsize(os.path.join(root, f))
            except OSError:
                pass
    return total


def slots(spec) -> list:
    """Lo que ve el usuario: una entrada por ranura o archivo, con su fecha."""
    out, chosen = [], {os.path.realpath(expand(x)) for x in (spec or {}).get("dirs") or []}
    for i, p in enumerate(matches(spec), 1):
        try:
            mt = max([os.path.getmtime(os.path.join(r, f)) for r, _, fs in os.walk(p) for f in fs] or [os.path.getmtime(p)]) \
                if os.path.isdir(p) else os.path.getmtime(p)
        except OSError:
            mt = 0
        m = re.search(r"(\d+)$", os.path.basename(p))
        n = int(m.group(1)) + 1 if m and os.path.isdir(p) else i
        if os.path.realpath(p) in chosen:
            label = os.path.basename(p.rstrip("/")) or p                     # una carpeta elegida por el usuario: se llama como ella
        elif os.path.isdir(p):
            label = (spec.get("name") or "Ranura {n}").format(n=n)
        else:
            label = KINDS.get(os.path.splitext(p)[1].lstrip(".").lower(), spec.get("name") or "Partida")
        out.append({"name": label, "path": p, "mtime": mt, "used": mt > 0})
    return out


def folder(spec) -> str:
    """Carpeta a abrir con el gestor de archivos: la de las partidas si existen; si no, el tramo fijo del patrón."""
    found = matches(spec)
    if found:
        return os.path.dirname(found[0]) if len(found) > 1 or os.path.isfile(found[0]) else found[0]
    r = roots(spec)
    return r[0] if r else ""


# ---------------------------------------------------------------- respaldar
def _unique(dest: Path, label: str, stamp: str) -> Path:
    base = dest / (f"{label}-{stamp}")
    out, n = Path(str(base) + ".tar.gz"), 1
    while out.exists():
        out, n = Path(f'{base}-{n:d}.tar.gz'), n + 1
    return out


def backup(spec, dest_dir, label: str, meta: dict | None = None, max_bytes: int = MAX_BYTES) -> Path:
    found = matches(spec)
    if not found:
        raise SaveError("No hay partidas que respaldar.")
    if sum(_size(p) for p in found) > max_bytes:
        raise SaveError("Las partidas ocupan demasiado: revisa la carpeta elegida.")
    dest = Path(expand(str(dest_dir)))
    dest.mkdir(parents=True, exist_ok=True)
    label = re.sub(r"[^A-Za-z0-9._-]+", "-", label).strip("-") or "juego"
    out = _unique(dest, label, time.strftime("%Y%m%d-%H%M%S"))
    tmp = out.with_name(out.name + ".part")
    entries = []
    with tarfile.open(tmp, "w:gz") as tf:
        for i, p in enumerate(found):
            arc = 'data/{:d}/{}'.format(i, os.path.basename(p.rstrip("/")))
            entries.append({"arc": arc, "orig": os.path.abspath(p), "kind": "dir" if os.path.isdir(p) else "file"})
            tf.add(p, arcname=arc, filter=lambda ti: None if ti.issym() or ti.islnk() else ti)   # los enlaces no se respaldan
        raw = json.dumps({"version": 1, "created": int(time.time()), "label": label, "entries": entries, **(meta or {})},
                         ensure_ascii=False, indent=1).encode()
        ti = tarfile.TarInfo(MANIFEST)
        ti.size, ti.mtime = len(raw), int(time.time())
        tf.addfile(ti, io.BytesIO(raw))
    os.replace(tmp, out)
    return out


def read_manifest(archive) -> dict | None:
    try:
        with tarfile.open(archive, "r:gz") as tf:
            f = tf.extractfile(MANIFEST)
            return json.load(f) if f else None
    except (tarfile.TarError, OSError, KeyError, ValueError):
        return None


def list_backups(dest_dir, label: str | None = None) -> list:
    d = Path(expand(str(dest_dir))) if dest_dir else None
    if not d or not d.is_dir():
        return []
    out = []
    for f in sorted(d.glob("*.tar.gz"), key=lambda x: x.stat().st_mtime, reverse=True):
        if label and not f.name.lower().startswith(re.sub(r"[^A-Za-z0-9._-]+", "-", label).strip("-").lower()):
            continue                         # sin distinguir mayúsculas: los respaldos del prototipo eran «longshot-…»
        st = f.stat()
        out.append({"name": f.name, "size": st.st_size, "mtime": st.st_mtime, "restorable": read_manifest(f) is not None})
    return out


# ---------------------------------------------------------------- restaurar
def _inside(path: str, bases) -> bool:
    p = os.path.realpath(path)
    return any(p == b or p.startswith(b.rstrip("/") + "/") for b in bases)


def restore(archive, spec, dest_dir, label: str) -> dict:
    """Restaura un respaldo con manifiesto. Antes guarda lo que hubiera como «<label>-antes-de-restaurar-…»."""
    man = read_manifest(archive)
    if not man:
        raise SaveError("Este respaldo es antiguo (sin manifiesto): ábrelo con el gestor de archivos.")
    bases = roots(spec)
    if not bases:
        raise SaveError("El juego no tiene carpeta de partidas configurada.")
    plan = []
    for e in man.get("entries", []):
        orig, arc = e.get("orig", ""), e.get("arc", "")
        if not os.path.isabs(orig) or ".." in Path(orig).parts or not _inside(os.path.dirname(orig) if e.get("kind") == "file" else orig, bases):
            raise SaveError("El respaldo apunta fuera de las carpetas de partidas de este juego: no se restaura.")
        if arc.startswith("/") or ".." in Path(arc).parts:
            raise SaveError("Respaldo no válido.")
        plan.append((arc, orig, e.get("kind")))
    # Primera pasada: se valida TODO el respaldo antes de escribir nada (un respaldo manipulado no restaura a medias).
    work = []
    with tarfile.open(archive, "r:gz") as tf:
        for m in tf.getmembers():
            if m.name == MANIFEST or not (m.isreg() or m.isdir()):
                continue                                         # nada de enlaces, dispositivos ni tuberías
            for arc, orig, kind in plan:
                if m.name == arc or m.name.startswith(arc + "/"):
                    rel = m.name[len(arc):].lstrip("/")
                    target = orig if not rel else os.path.join(orig, rel)
                    if ".." in Path(rel).parts or not _inside(target if m.isdir() else os.path.dirname(target), bases):
                        raise SaveError("Ruta no permitida en el respaldo.")
                    work.append((m, target))
                    break
    safety = None
    if matches(spec):
        safety = backup(spec, dest_dir, f"{label}-antes-de-restaurar")
    n = 0
    with tarfile.open(archive, "r:gz") as tf:
        for m, target in work:
            if m.isdir():
                os.makedirs(target, exist_ok=True)
                continue
            os.makedirs(os.path.dirname(target), exist_ok=True)
            tmp = target + ".omnia-part"
            with open(tmp, "wb") as out:
                out.write(tf.extractfile(m).read())
            os.utime(tmp, (m.mtime, m.mtime))
            os.replace(tmp, target)
            n += 1
    return {"restored": n, "safety": safety.name if safety else ""}

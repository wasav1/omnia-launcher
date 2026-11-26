"""Utilidades para conservar artwork local antiguo de Omnia.

El artwork nuevo se consulta y descarga desde Omnia Backend en ``online_catalog``.
Este módulo solo localiza archivos ya existentes para mantener compatibilidad con
bibliotecas migradas; no contiene clientes, secretos ni llamadas directas a proveedores.
"""
from __future__ import annotations

import re
import threading
from pathlib import Path

from . import paths

KINDS = ("portada", "fondo", "logo")
EXTENSIONS = {".png", ".jpg", ".jpeg", ".webp"}
_index_lock = threading.RLock()
_file_index: dict[str, tuple[tuple, list[Path]]] = {}
_best_index: dict[str, tuple[tuple, str]] = {}


class ArtError(Exception):
    """Error de compatibilidad con callers existentes de arte local."""


def safe_slug(slug: str) -> str:
    value = re.sub(r"[^A-Za-z0-9._-]+", "-", str(slug)).strip("-.")
    return value[:80] or "juego"


def art_dir(slug: str, kind: str, base: Path | None = None) -> Path:
    if kind not in KINDS:
        raise ValueError("tipo de artwork no válido")
    return (Path(base) if base else paths.data_dir() / "art") / safe_slug(slug) / kind


def _files_stamp(files: list[Path]) -> tuple:
    """Huella de nombres e inodos para invalidar la caché tras reemplazar archivos."""
    out = []
    for path in files:
        try:
            stat = path.stat()
        except OSError:
            continue
        out.append((path.name, stat.st_mtime_ns, stat.st_size, stat.st_ino))
    return tuple(out)


def cached_files(slug: str, kind: str, base: Path | None = None) -> list[Path]:
    """Archivos de arte ya guardados en disco, ordenados por nombre."""
    directory = art_dir(slug, kind, base)
    key = str(directory)
    try:
        stat = directory.stat()
        directory_stamp = (stat.st_mtime_ns, stat.st_ino)
    except OSError:
        with _index_lock:
            _file_index.pop(key, None)
            _best_index.pop(key, None)
        return []
    with _index_lock:
        try:
            files = [p for p in directory.iterdir() if p.suffix.lower() in EXTENSIONS and p.is_file()]
        except OSError:
            files = []
        files.sort(key=lambda p: (1, int(p.stem)) if p.stem.isdigit() else (0, p.name.casefold()))
        stamp = (directory_stamp, _files_stamp(files))
        hit = _file_index.get(key)
        if hit and hit[0] == stamp:
            return hit[1]
        _file_index[key] = (stamp, files)
        _best_index.pop(key, None)
        return files


def cached(slug: str, kind: str, base: Path | None = None, index: int = 0) -> str:
    """Ruta del archivo local seleccionado, o cadena vacía."""
    files = cached_files(slug, kind, base)
    return str(files[index % len(files)]) if files else ""


def image_dimensions(path: Path) -> tuple[int, int]:
    """Lee dimensiones PNG/JPEG/WebP desde la cabecera sin cargar la imagen completa."""
    try:
        with Path(path).open("rb") as file:
            head = file.read(30)
            if head.startswith(b"\x89PNG\r\n\x1a\n") and len(head) >= 24:
                return int.from_bytes(head[16:20], "big"), int.from_bytes(head[20:24], "big")
            if head[:4] == b"RIFF" and head[8:12] == b"WEBP":
                if head[12:16] == b"VP8X" and len(head) >= 30:
                    return 1 + int.from_bytes(head[24:27], "little"), 1 + int.from_bytes(head[27:30], "little")
                if head[12:16] == b"VP8L" and len(head) >= 25 and head[20] == 0x2F:
                    b1, b2, b3, b4 = head[21:25]
                    return 1 + b1 + ((b2 & 0x3F) << 8), 1 + ((b2 >> 6) & 3) + (b3 << 2) + ((b4 & 0x0F) << 10)
                if head[12:16] == b"VP8 " and len(head) >= 30 and head[23:26] == b"\x9d\x01\x2a":
                    return int.from_bytes(head[26:28], "little") & 0x3FFF, int.from_bytes(head[28:30], "little") & 0x3FFF
            if head[:2] != b"\xff\xd8":
                return 0, 0
            file.seek(2)
            sof = {0xC0, 0xC1, 0xC2, 0xC3, 0xC5, 0xC6, 0xC7, 0xC9, 0xCA, 0xCB, 0xCD, 0xCE, 0xCF}
            while True:
                byte = file.read(1)
                if not byte:
                    return 0, 0
                if byte != b"\xff":
                    continue
                marker = file.read(1)
                while marker == b"\xff":
                    marker = file.read(1)
                if not marker or marker in (b"\x00", b"\xd9", b"\xda"):
                    return 0, 0
                code = marker[0]
                if code in (0xD8, 0x01) or 0xD0 <= code <= 0xD7:
                    continue
                length = int.from_bytes(file.read(2), "big")
                if length < 2:
                    return 0, 0
                if code in sof:
                    dims = file.read(5)
                    if len(dims) == 5:
                        return int.from_bytes(dims[3:5], "big"), int.from_bytes(dims[1:3], "big")
                    return 0, 0
                file.seek(length - 2, 1)
    except OSError:
        return 0, 0


def highest_resolution(slug: str, kind: str, base: Path | None = None) -> str:
    """Ruta del artwork local con mayor área; conserva el orden si no se leen dimensiones."""
    files = cached_files(slug, kind, base)
    if not files:
        return ""
    key = str(art_dir(slug, kind, base))
    stamp = _files_stamp(files)
    with _index_lock:
        hit = _best_index.get(key)
        if hit and hit[0] == stamp:
            return hit[1]
        best = str(max(files, key=lambda p: image_dimensions(p)[0] * image_dimensions(p)[1]))
        _best_index[key] = (stamp, best)
        return best

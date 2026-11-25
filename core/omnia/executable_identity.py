"""Inspección acotada de metadata local. El ejecutable nunca se inicia."""
import configparser
import json
import os
import re
import shlex
import struct
import unicodedata
from pathlib import Path

from . import library_metadata, online_catalog
from .stores.base import StoreError


def _read_at(source, offset, size):
    source.seek(offset)
    data = source.read(size)
    if len(data) != size:
        raise ValueError("archivo incompleto")
    return data


def _aligned(offset):
    return (offset + 3) & ~3


def _version_strings(data):
    """VS_VERSION_INFO → StringFileInfo → tabla de idioma → cadenas."""
    fields = {}

    def visit(start, end, depth):
        if depth > 3 or start + 6 > end:
            return start
        length, value_size, kind = struct.unpack_from("<HHH", data, start)
        limit = start + length
        if length < 8 or limit > end:
            return start
        cursor = start + 6
        while cursor + 2 <= limit and data[cursor:cursor + 2] != b"\0\0":
            cursor += 2
        if cursor + 2 > limit:
            return start
        key = data[start + 6:cursor].decode("utf-16-le", "replace")
        value_at = _aligned(cursor + 2)
        value_end = value_at + value_size * (2 if kind else 1)
        if value_end > limit:
            return start
        if depth == 3 and kind == 1 and key in {"ProductName", "FileDescription"}:
            value = data[value_at:value_end].decode("utf-16-le", "replace").strip("\0 ")
            if value:
                fields.setdefault(key, value)
        if depth < 3 and (depth != 1 or key == "StringFileInfo"):
            child = _aligned(value_end)
            while child + 6 <= limit:
                following = visit(child, limit, depth + 1)
                if following <= child:
                    break
                child = _aligned(following)
        return limit

    visit(0, len(data), 0)
    return fields


def _pe_identity(source):
    header_at, = struct.unpack("<I", _read_at(source, 60, 4))
    header = _read_at(source, header_at, 24)
    if header[:4] != b"PE\0\0":
        return None
    sections, = struct.unpack_from("<H", header, 6)
    opt_size, characteristics = struct.unpack_from("<HH", header, 20)
    if not characteristics & 2 or characteristics & 0x2000:
        return None                       # imagen ejecutable, sin DLL
    optional = _read_at(source, header_at + 24, opt_size)
    magic, = struct.unpack_from("<H", optional)
    directories = {0x10B: 96, 0x20B: 112}.get(magic)
    if directories is None:
        return None
    resource_rva, resource_size = struct.unpack_from("<II", optional, directories + 16)
    if not resource_rva or resource_size < 16 or sections > 96:
        return {}
    table = _read_at(source, header_at + 24 + opt_size, sections * 40)
    mappings = [struct.unpack_from("<III", table, off + 12) for off in range(0, len(table), 40)]

    def from_rva(rva, count):
        for address, raw_size, offset in mappings:
            rel = rva - address
            if 0 <= rel and rel + count <= raw_size:
                return _read_at(source, offset + rel, count)
        raise ValueError("dirección de recurso fuera de la imagen")

    def entries(offset):
        if offset + 16 > resource_size:
            return []
        header = from_rva(resource_rva + offset, 16)
        named, ids = struct.unpack_from("<HH", header, 12)
        count = named + ids
        if count > 512 or offset + 16 + count * 8 > resource_size:
            return []
        return list(struct.iter_unpack("<II", from_rva(resource_rva + offset + 16, count * 8)))

    def directory_entries(pointer):
        return entries(pointer & 0x7FFFFFFF) if pointer & 0x80000000 else []

    for resource, directory in entries(0):
        if resource != 16:                 # RT_VERSION
            continue
        for _, names in directory_entries(directory)[:8]:
            for _, pointer in directory_entries(names)[:16]:
                if pointer & 0x80000000 or pointer + 16 > resource_size:
                    continue
                rva, size = struct.unpack_from("<II", from_rva(resource_rva + pointer, 16))
                if 6 <= size <= 65536:
                    fields = _version_strings(from_rva(rva, size))
                    if fields:
                        return fields
    return {}


def _small_text(path, limit=65536):
    if not path.is_file() or path.is_symlink():
        return ""
    with path.open("rb") as source:
        data = source.read(limit + 1)
    return data.decode("utf-8", "replace") if len(data) <= limit else ""


def _title(value):
    if not isinstance(value, str):
        return ""
    value = " ".join(value.split())
    return value[:80] if any(ch.isalnum() for ch in value) and "\ufffd" not in value else ""


def _desktop_name(path):
    for folder in (path.parent, path.parent.parent / "share/applications"):
        if not folder.is_dir() or folder.is_symlink():
            continue
        for entry in (folder / (path.stem + ".desktop"), folder / "game.desktop"):
            try:
                parser = configparser.ConfigParser(interpolation=None, strict=False)
                parser.read_string(_small_text(entry))
                if not parser.has_section("Desktop Entry"):
                    continue
                desktop = parser["Desktop Entry"]
                args = shlex.split(desktop.get("Exec", ""))
                if desktop.get("Type") == "Application" and args:
                    command = Path(args[0])
                    if command.name == path.name and (not command.is_absolute() or command.resolve() == path):
                        return _title(desktop.get("Name"))
            except (OSError, ValueError, configparser.Error, RuntimeError):
                continue
    return ""


def _known_install(path, games):
    exact, enclosing = [], []
    for game in games:
        identified = game.get("detectedIdentity")
        identity = library_metadata.store_identity(game) or (identified if isinstance(identified, dict) else {})
        appid = online_catalog.steam_appid(game)
        if appid:
            identity = {"store": "steam", "id": appid}
        if not identity.get("id") and game.get("auto") != "heroic" and game.get("src") != "Manual":
            continue
        for port in game.get("ports", []):
            for key in ("check", "folder", "disk_dir", "cwd"):
                value = port.get(key)
                if not isinstance(value, str) or not Path(value).is_absolute():
                    continue
                target = Path(value).resolve()
                if key == "check" and path == target:
                    exact.append((game, identity))
                elif identity and key in {"folder", "disk_dir"} and path.is_relative_to(target):
                    enclosing.append((game, identity))
    candidates = {game["id"]: (game, identity) for game, identity in (exact or enclosing)}
    if len(candidates) == 1:
        return next(iter(candidates.values()))
    return {}, {}


def _gog_identity(path):
    matches = {}
    for folder in list(path.parents)[:4]:
        for index, marker in enumerate(folder.glob("goggame-*.info")):
            if index >= 32:
                break
            match = re.fullmatch(r"goggame-([0-9]{1,12})\.info", marker.name)
            if not match:
                continue
            try:
                record = json.loads(_small_text(marker))
                for task in record.get("playTasks", []):
                    rel = task.get("path", "").replace("\\", "/")
                    if task.get("isPrimary") and rel and (folder / rel).resolve() == path:
                        matches[match[1]] = _title(record.get("name"))
            except (OSError, ValueError, TypeError, AttributeError, RuntimeError):
                continue
    if len(matches) == 1:
        product, title = next(iter(matches.items()))
        return {"store": "gog", "id": product}, title
    return {}, ""


def _steam_sidecar(path, title, steam_library):
    if not title or steam_library is None:
        return {}, ""
    product = _small_text(path.parent / "steam_appid.txt", 128).strip()
    if not re.fullmatch(r"[0-9]{1,10}", product):
        return {}, ""

    def normalize(value):
        return " ".join(re.findall(r"[^\W_]+", unicodedata.normalize("NFKC", value.casefold())))

    try:
        for game in steam_library():
            name = _title(game.get("title"))
            if str(game.get("id")) == product and name and normalize(title) == normalize(name):
                return {"store": "steam", "id": product}, name
    except StoreError:
        pass
    return {}, ""


def inspect(path, games, steam_library=None):
    """Devuelve nombre sugerido, tipo, evidencia y ficha local cuando ya existe."""
    with path.open("rb") as source:
        header = source.read(4)
        is_windows = path.suffix.casefold() == ".exe"
        if is_windows:
            try:
                fields = _pe_identity(source) if header.startswith(b"MZ") else None
            except (struct.error, ValueError):
                fields = None
            if fields is None:
                raise ValueError("El archivo no es un ejecutable de Windows válido.")
        elif not os.access(path, os.X_OK) or not (header == b"\x7fELF" or header.startswith(b"#!")):
            raise ValueError("El archivo no es un ejecutable de Linux válido.")
    if re.search(r"(^|[._ -])(unins\d*|uninstall|setup|crash(report(er)?|handler)?|updater)([._ -]|$)",
                 path.stem, re.IGNORECASE):
        raise ValueError("Elige el ejecutable del juego, en lugar del instalador o desinstalador.")
    game, identity = _known_install(path, games)
    title = _title(game.get("name"))
    if not identity:
        identity, gog_title = _gog_identity(path)
        title = title or gog_title
    if not title:
        title = (_title(fields.get("ProductName")) or _title(fields.get("FileDescription"))) if is_windows else _desktop_name(path)
    if not identity:
        identity, steam_title = _steam_sidecar(path, title, steam_library)
        title = steam_title or title
    label = {"steam": "Steam", "epic": "Epic", "gog": "GOG", "amazon": "Amazon"}.get(identity.get("store"), "")
    result = {"name": title or _title(path.stem), "kind": "windows" if is_windows else "native",
              "platform": "pc", "recognized": label or title}
    if identity:
        result["identity"] = {"store": identity["store"], "id": str(identity["id"])}
    if game:
        result["existingId"] = game["id"]
    return result

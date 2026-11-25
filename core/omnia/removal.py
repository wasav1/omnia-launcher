"""Desinstalación local a partir de registros de instalación, nunca de rutas enviadas por la UI."""
import json
import os
import re
import shutil
import stat
import tempfile
from dataclasses import dataclass, replace
from pathlib import Path

from .games import heroic, steam
from .games.vdf import parse_vdf
from .store import write_json_atomic
from .stores.installer import FORBIDDEN


class RemovalError(Exception):
    pass


@dataclass(frozen=True)
class Installation:
    folder: Path
    registry: Path | None = None
    original: bytes | None = None
    remaining: object = None
    client: str = ""


def _read(path):
    if path.is_symlink() or not path.is_file():
        raise RemovalError("No se pudo verificar el registro de instalación.")
    with path.open("rb") as source:
        data = source.read(16 * 1024 * 1024 + 1)
    if len(data) > 16 * 1024 * 1024:
        raise RemovalError("El registro de instalación es demasiado grande.")
    return data


def _path_refs(game):
    yield game.get("installPath")
    yield game.get("storeInstallPath")
    for port in game.get("ports", []):
        yield from (port.get(key) for key in ("folder", "disk_dir", "cwd", "check"))


def _resolved(value):
    return Path(os.path.realpath(value)) if isinstance(value, str) and os.path.isabs(value) else None


def _overlaps(first, second):
    return first.is_relative_to(second) or second.is_relative_to(first)


def _uses_folder(game, folder):
    for value in (game.get("installPath"), game.get("storeInstallPath")):
        if (ref := _resolved(value)) is not None and _overlaps(ref, folder):
            return True
    for port in game.get("ports", []):
        for key in ("folder", "disk_dir", "check", "cwd"):
            if (ref := _resolved(port.get(key))) is None:
                continue
            if ref.is_relative_to(folder) or (key in {"folder", "disk_dir", "check"} and folder.is_relative_to(ref)):
                return True
    return False


def _steam_installation(game, home):
    appid = game["id"].removeprefix("steam-")
    if not re.fullmatch(r"[0-9]{1,10}", appid):
        raise RemovalError("No se pudo verificar el App ID de Steam.")
    locations = []
    for root in steam.steam_roots(home):
        for library in steam.library_dirs(root):
            registry = library.resolve() / f"appmanifest_{appid}.acf"
            if registry.exists() and registry not in locations:
                locations.append(registry)
    if len(locations) != 1:
        raise RemovalError("No se pudo verificar una única instalación de Steam.")
    registry = locations[0]
    original = _read(registry)
    app = parse_vdf(original.decode("utf-8", "replace")).get("AppState", {})
    name = app.get("installdir") if isinstance(app, dict) else None
    if (not isinstance(name, str) or name in {"", ".", ".."} or "/" in name or "\\" in name
            or app.get("appid") != appid):
        raise RemovalError("No se pudo verificar el registro de instalación.")
    if app.get("StateFlags") != str(steam.FULLY_INSTALLED):
        raise RemovalError("Termina la descarga o actualización de Steam antes de desinstalar.")
    common = registry.parent / "common"
    if common.is_symlink():
        raise RemovalError("La carpeta de instalación no supera la validación de seguridad.")
    folder = common / name
    refs = {p for value in _path_refs(game) if (p := _resolved(value)) is not None}
    if folder.resolve() not in refs:
        raise RemovalError("La instalación cambió. Actualiza la biblioteca y vuelve a intentarlo.")
    for other in registry.parent.glob("appmanifest_*.acf"):
        if other != registry:
            record = parse_vdf(_read(other).decode("utf-8", "replace")).get("AppState", {})
            if isinstance(record, dict) and str(record.get("installdir", "")).casefold() == name.casefold():
                raise RemovalError("La carpeta de instalación se comparte con otro juego.")
    return Installation(folder, registry, original, client="steam")


def _registry_row_path(item):
    if not isinstance(item, dict):
        return ""
    install = item.get("install")
    return item.get("install_path") or item.get("path") or (install.get("install_path") if isinstance(install, dict) else "")


def _registry_row_id(item, key=""):
    return str(item.get("app_name") or item.get("appName") or item.get("id") or key) if isinstance(item, dict) else ""


def _registry_installation(path, product, client):
    if not path.exists():
        return None
    original = _read(path)
    data = json.loads(original)
    wrapped = isinstance(data, dict) and isinstance(data.get("installed"), (list, dict))
    rows = data["installed"] if wrapped else data
    if not isinstance(rows, (list, dict)):
        return None
    entries = list(rows.items()) if isinstance(rows, dict) else list(enumerate(rows))
    matches = [(key, item) for key, item in entries
               if _registry_row_id(item, key if isinstance(rows, dict) else "") == product]
    if len(matches) != 1:
        return None
    match, selected = matches[0]
    raw = _registry_row_path(selected)
    folder = _resolved(raw)
    if folder is None:
        return None
    if any(key != match and other is not None and _overlaps(folder, other)
           for key, item in entries if (other := _resolved(_registry_row_path(item))) is not None):
        raise RemovalError("La carpeta de instalación se comparte con otro juego.")
    kept = {key: item for key, item in entries if key != match} if isinstance(rows, dict) else [
        item for key, item in entries if key != match]
    remaining = {**data, "installed": kept} if wrapped else kept
    return Installation(Path(raw), path, original, remaining, client)


def manual_gog_identity(game):
    identity = game.get("detectedIdentity")
    return identity if isinstance(identity, dict) and identity.get("store") == "gog" else {}


def _registered_store(game, stores, home):
    identity = game.get("store_id") or manual_gog_identity(game)
    ports = game.get("ports", [])
    exe = _resolved(ports[0].get("check")) if len(ports) == 1 else None
    if game.get("auto") == "heroic":
        parts = game["id"].split("-", 2)
        if len(parts) != 3 or parts[1] not in heroic.RUNNERS:
            return None
        _, runner, product = parts
        path = heroic.RUNNERS[runner][1]
        matches = [install for cfg, _ in heroic.config_dirs(home)
                   if (install := _registry_installation(cfg / path, product, "heroic")) is not None
                   and exe == install.folder.resolve()]
        return matches[0] if len(matches) == 1 else None

    if game.get("auto") or not game["id"].startswith("manual-") or not isinstance(identity, dict):
        return None
    source, product = identity.get("store"), identity.get("id")
    if not isinstance(product, str) or not re.fullmatch(r"[A-Za-z0-9._-]{1,128}", product) or not exe:
        return None
    store = stores.get(source)
    if source == "gog" and product.isascii() and product.isdigit() and exe.is_file():
        # gogdl instala archivos, pero Omnia es quien registra el juego instalado.
        for parent in list(exe.parents)[:5]:
            manifest = parent / f"goggame-{product}.info"
            if manifest.is_file():
                data = json.loads(_read(manifest))
                if any(isinstance(task, dict) and task.get("isPrimary")
                       and (parent / str(task.get("path", "")).replace("\\", "/")).resolve() == exe
                       for task in data.get("playTasks", [])):
                    return Installation(parent)
    if store is not None and source in {"epic", "amazon"} and hasattr(store, "dir"):
        registry = store.dir / ("installed.json" if source == "epic" else "nile/installed.json")
        result = _registry_installation(registry, product, "")
        if result and exe.is_relative_to(result.folder.resolve()):
            return result
    return None


def locate(game, games, roots, stores, home=None):
    home = Path(home or Path.home()).resolve()
    try:
        result = (_steam_installation(game, home) if game.get("auto") == "steam"
                  else _registered_store(game, stores, home))
    except (OSError, ValueError, TypeError, AttributeError, RuntimeError) as exc:
        raise RemovalError("No se pudo verificar el registro de instalación.") from exc
    if result is None:
        raise RemovalError("Omnia no pudo verificar qué archivos pertenecen a este juego.")
    return replace(result, folder=validate_folder(result.folder, game, games, roots, home))


def validate_folder(path, game, games, roots, home=None):
    home = Path(home or Path.home()).resolve()
    folder = path.resolve()
    allowed = [Path(root).resolve() for root in roots]
    private = [home / part for part in (".config", ".cache", "Documents", "Desktop", "Downloads", "Documentos", "Descargas")]
    protected = [home, *allowed, *private]
    forbidden = [Path(root) for root in FORBIDDEN if root not in {"/", "/run"}]
    if (not path.is_absolute() or path.is_symlink() or not folder.is_dir()
            or any(root.is_relative_to(folder) for root in protected)
            or any(folder.is_relative_to(root) for root in forbidden + private)
            or not any(folder.is_relative_to(root) for root in allowed)
            or not shutil.rmtree.avoids_symlink_attacks):
        raise RemovalError("La carpeta de instalación no supera la validación de seguridad.")
    try:
        with open("/proc/self/mountinfo", encoding="utf-8", errors="surrogateescape") as mounts:
            for line in mounts:
                mount = re.sub(r"\\([0-7]{3})", lambda m: chr(int(m[1], 8)), line.split()[4])
                if Path(mount).is_relative_to(folder):
                    raise RemovalError("La carpeta de instalación contiene un punto de montaje.")
    except OSError as exc:
        raise RemovalError("No se pudieron verificar los puntos de montaje.") from exc
    if any(other["id"] != game["id"] and _uses_folder(other, folder) for other in games):
        raise RemovalError("La carpeta de instalación se comparte con otro juego.")
    return folder


def client_is_running(client, cmdlines):
    names = {"steam": {"steam", "steam.sh", "steamwebhelper"},
             "heroic": {"heroic", "heroic.sh", "heroicgameslauncher"}}
    return client in names and any(Path(cmd.split(" ", 1)[0]).name.casefold() in names[client] for cmd in cmdlines)


def uninstall(installation):
    """Retira la carpeta y sincroniza el registro. Si falla el registro, restaura la ruta."""
    folder, registry = installation.folder, installation.registry
    try:
        if folder.is_symlink() or not folder.is_dir() or folder.resolve() != folder:
            raise RemovalError("La carpeta de instalación no supera la validación de seguridad.")
        if registry is not None and _read(registry) != installation.original:
            raise RemovalError("La instalación cambió. Actualiza la biblioteca y vuelve a intentarlo.")
        tmp = Path(tempfile.mkdtemp(prefix=".omnia-removal-", dir=folder.parent))
        staged = tmp / folder.name
        try:
            folder.rename(staged)
            try:
                if registry is not None:
                    if _read(registry) != installation.original:
                        raise RemovalError("La instalación cambió. Actualiza la biblioteca y vuelve a intentarlo.")
                    if installation.client == "steam":
                        registry.unlink()
                    else:
                        mode = stat.S_IMODE(registry.stat().st_mode) & 0o666
                        write_json_atomic(registry, installation.remaining, mode=mode)
            except (OSError, RemovalError):
                staged.rename(folder)
                raise
            try:
                shutil.rmtree(staged)
            except OSError:
                return str(staged)
        finally:
            if not staged.exists():
                tmp.rmdir()
    except OSError as exc:
        raise RemovalError("Omnia no pudo retirar todos los archivos de instalación.") from exc

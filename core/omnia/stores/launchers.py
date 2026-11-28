"""Ubisoft Connect y EA app en Linux (entrega 6): dónde están instalados y qué juegos tienen.

No hay herramientas de código abierto que descarguen juegos de Ubisoft ni de EA, así que esos juegos se instalan con el
lanzador oficial dentro de un prefijo de Wine y se lanzan con umu-run (como hace Lutris). Este módulo solo lee:

- Busca prefijos con el lanzador en Lutris (pga.db y su `.yml`), Heroic, Bottles, `~/.wine`, los prefijos de Omnia y las
  carpetas de juegos (la ruta de instalación elegida y las bibliotecas), hasta 3 niveles y sin seguir enlaces.
- Juegos instalados: Ubisoft Connect los registra en el registro del prefijo (`Ubisoft\\Launcher\\Installs\\<producto>`);
  la EA app deja `Program Files/EA Games/<juego>/__Installer/installerdata.xml` con sus `contentID`.

Instalar el lanzador (descargar el instalador oficial y ejecutarlo en un prefijo nuevo) lo hace `StoreLaunchers.install`.
"""
import os
import re
import sqlite3
import time
import xml.etree.ElementTree as ElementTree
from pathlib import Path

from ..games import ubisoft_lutris

LAUNCHERS = {
    "ubisoft": {
        "name": "Ubisoft Connect",
        "exe": ("drive_c/Program Files (x86)/Ubisoft/Ubisoft Game Launcher/UbisoftConnect.exe",
                "drive_c/Program Files (x86)/Ubisoft/Ubisoft Game Launcher/upc.exe"),
        "installer": "https://ubistatic3-a.akamaihd.net/orbit/launcher_installer/UbisoftConnectInstaller.exe",
        "installer_args": ["/S"],
    },
    "ea": {
        "name": "EA app",
        "exe": ("drive_c/Program Files/Electronic Arts/EA Desktop/EA Desktop/EADesktop.exe",),
        "installer": "https://origin-a.akamaihd.net/EA-Desktop-Client-Download/installer-releases/EAappInstaller.exe",
        "installer_args": ["/quiet"],
    },
}
_MAX_DIRS = 3000
_CACHE_SECONDS = 600
_cache = {}


def _home() -> Path:
    return Path.home()


def _lutris_db() -> Path:
    base = os.environ.get("XDG_DATA_HOME", "")
    root = Path(base) if base and os.path.isabs(base) else _home() / ".local/share"
    return root / "lutris" / "pga.db"


def _lutris_rows():
    db = _lutris_db()
    if not db.is_file():
        return []
    try:
        con = sqlite3.connect(f"file:{db}?mode=ro", uri=True, timeout=2)
        try:
            return con.execute("SELECT name, slug, directory FROM games WHERE installed = 1").fetchall()
        finally:
            con.close()
    except sqlite3.Error:
        return []


def _exe_in(prefix: str, launcher: str) -> str:
    for rel in LAUNCHERS[launcher]["exe"]:
        path = os.path.join(prefix, rel)
        if os.path.isfile(path) and not os.path.islink(path):
            return path
    return ""


def _candidate_prefixes(search_roots) -> list:
    """(prefijo, origen) posibles, sin repetir. Los de Lutris primero: son los que la persona ya usa."""
    out = []
    # cualquier prefijo de Lutris puede tener el lanzador dentro (el suyo, «ubisoft-connect», o el de un juego)
    out += [(directory, "lutris") for _name, _slug, directory in _lutris_rows() if directory]
    home = _home()
    fixed = [(home / ".wine", "wine")]
    for base, source in ((home / "Games/Heroic/Prefixes/default", "heroic"), (home / "Games/Heroic/Prefixes", "heroic"),
                         (home / ".local/share/bottles/bottles", "bottles"),
                         (home / ".var/app/com.usebottles.bottles/data/bottles/bottles", "bottles"),
                         (home / "Juegos/PC/_Prefijos", "omnia")):
        try:
            fixed += [(p, source) for p in base.iterdir() if p.is_dir() and not p.is_symlink()]
        except OSError:
            pass
    out += [(str(p), s) for p, s in fixed]
    visited = 0
    for root in search_roots:                          # la ruta elegida y las bibliotecas: carpetas con drive_c
        stack = [(str(root), 0)]
        while stack and visited < _MAX_DIRS:
            current, depth = stack.pop()
            visited += 1
            if os.path.isdir(os.path.join(current, "drive_c")):
                out.append((current, "folder"))
                continue
            if depth >= 3:
                continue
            try:
                with os.scandir(current) as entries:
                    stack += [(e.path, depth + 1) for e in entries
                              if not e.name.startswith(".") and e.is_dir(follow_symlinks=False)]
            except OSError:
                continue
    seen, unique = set(), []
    for prefix, source in out:
        real = os.path.realpath(prefix)
        if real not in seen:
            seen.add(real)
            unique.append((real, source))
    return unique


def search_roots(config_dir=None) -> list:
    """Dónde buscar prefijos además de los conocidos: la ruta de instalación elegida, las bibliotecas y los discos montados."""
    from ..store import load_json
    cfg = load_json(Path(config_dir) / "config.json", {}) if config_dir else {}
    cfg = cfg if isinstance(cfg, dict) else {}
    roots = [cfg.get("install_root")] + list(cfg.get("external_roots") or [])
    user = os.environ.get("USER") or _home().name
    for mount in (Path("/mnt"), Path("/run/media") / user, Path("/media") / user):
        try:
            roots += [str(p) for p in mount.iterdir() if p.is_dir()]
        except OSError:
            pass
    out = []
    for root in roots:
        if isinstance(root, str) and os.path.isabs(root) and os.path.isdir(root) and os.path.realpath(root) not in out:
            out.append(os.path.realpath(root))
    return out


def find(launcher: str, search_roots=(), fresh=False) -> list:
    """[{prefix, exe, source}] donde está instalado el lanzador (`ubisoft` o `ea`). En caché 10 minutos."""
    if launcher not in LAUNCHERS:
        return []
    key = (launcher, tuple(str(r) for r in search_roots))
    hit = _cache.get(key)
    if hit and not fresh and time.monotonic() - hit[0] < _CACHE_SECONDS:
        return [dict(x) for x in hit[1]]
    found = []
    for prefix, source in _candidate_prefixes(search_roots):
        exe = _exe_in(prefix, launcher)
        if exe:
            found.append({"prefix": prefix, "exe": exe, "source": source})
    _cache[key] = (time.monotonic(), found)
    return [dict(x) for x in found]


def forget():
    _cache.clear()


def installed_games(launcher: str, prefix: str) -> list:
    """[{id, title, folder}] de los juegos que el lanzador instaló en ese prefijo."""
    if launcher == "ubisoft":
        return [{"id": product, "title": _folder_title(folder) or "Ubisoft " + product, "folder": _unix_path(prefix, folder)}
                for product, folder in sorted(_ubisoft_installs(prefix).items())]
    if launcher == "ea":
        games = []
        base = Path(prefix) / "drive_c/Program Files/EA Games"
        try:
            folders = sorted(p for p in base.iterdir() if p.is_dir() and not p.is_symlink())
        except OSError:
            return []
        for folder in folders:
            data = folder / "__Installer/installerdata.xml"
            try:
                if not data.is_file() or data.stat().st_size > 2 * 1024 * 1024:
                    continue
                root = ElementTree.parse(data).getroot()
            except (OSError, ElementTree.ParseError):
                continue
            ids = [n.text.strip() for n in root.iter("contentID") if n.text and re.fullmatch(r"[A-Za-z0-9._:-]{1,80}", n.text.strip())]
            if ids:
                games.append({"id": ",".join(ids), "title": folder.name, "folder": str(folder)})
        return games
    return []


def _ubisoft_installs(prefix: str) -> dict:
    """{producto: carpeta de Windows} del registro del prefijo (`Ubisoft\\Launcher\\Installs`)."""
    reg = Path(prefix) / "system.reg"
    try:
        if not reg.is_file() or reg.stat().st_size > 64 * 1024 * 1024:
            return {}
        text = reg.read_text(encoding="utf-8", errors="replace")
    except OSError:
        return {}
    found, current = {}, ""
    for line in text.splitlines():
        key = ubisoft_lutris._INSTALL_KEY.match(line)
        if key:
            current = key.group(1)
            found.setdefault(current, "")
            continue
        if line.startswith("["):
            current = ""
            continue
        value = ubisoft_lutris._INSTALL_DIR.match(line) if current else None
        if value:
            found[current] = value.group(1).replace("\\\\", "/")
    return found


def _unix_path(prefix: str, windows: str) -> str:
    """«C:/Program Files (x86)/…/WATCH_DOGS2/» → «<prefijo>/drive_c/Program Files (x86)/…/WATCH_DOGS2»."""
    match = re.match(r"^([A-Za-z]):[\\/](.*)$", windows or "")
    if not match or match.group(1).lower() != "c":
        return ""
    return os.path.join(prefix, "drive_c", match.group(2).replace("\\", "/").rstrip("/"))


def _folder_title(folder: str) -> str:
    """«C:/Program Files (x86)/Ubisoft/Ubisoft Game Launcher/games/WATCH_DOGS2/» → «WATCH_DOGS2»."""
    name = re.split(r"[\\/]", (folder or "").rstrip("\\/"))[-1]
    return name.replace("_", " ").strip()


def launch_uri(launcher: str, game_id: str, action="launch") -> str:
    """Dirección que el lanzador entiende: abre o instala el juego desde el propio lanzador."""
    if launcher == "ubisoft":
        return f"uplay://{'install' if action == 'install' else 'launch'}/{game_id}/0"
    return f"origin2://game/launch?offerIds={game_id}&autoDownload=1"


def launch_argv(prefix: str, exe: str, uri: str = "") -> list:
    """Orden para abrir el lanzador (y el juego, con `uri`) en su prefijo con umu-run, como los instala Lutris."""
    argv = ["env", "WINEPREFIX=" + prefix, "GAMEID=umu-0", "PROTONPATH=GE-Proton", "umu-run", exe]
    return argv + [uri] if uri else argv

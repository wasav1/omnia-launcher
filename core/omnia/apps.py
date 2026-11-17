"""Catálogo de aplicaciones instaladas para el Big Menu, leído de los archivos .desktop de XDG.

Solo se lanzan aplicaciones de este catálogo, por su id: la API nunca recibe una ruta ni un comando.
"""
import configparser
import os
import shutil
import subprocess
from dataclasses import dataclass, field
from pathlib import Path

GROUPS = [   # (categoría de freedesktop, grupo mostrado); gana la primera coincidencia, en este orden
    ("Game", "Juegos"), ("Network", "Internet"), ("Office", "Oficina"), ("AudioVideo", "Multimedia"),
    ("Audio", "Multimedia"), ("Video", "Multimedia"), ("Graphics", "Gráficos"), ("Development", "Desarrollo"),
    ("Education", "Educación"), ("Science", "Educación"), ("Settings", "Sistema"), ("System", "Sistema"),
    ("Utility", "Utilidades"),
]
OTHER = "Otras"
FAV_DEFAULT = ["org.kde.dolphin.desktop", "steam.desktop", "org.kde.konsole.desktop", "firefox.desktop",
               "org.kde.kate.desktop", "net.lutris.Lutris.desktop", "com.heroicgameslauncher.hgl.desktop"]


@dataclass
class App:
    id: str
    name: str
    comment: str
    icon: str
    group: str
    path: str
    keywords: list = field(default_factory=list)


def data_dirs() -> list:
    home = os.environ.get("XDG_DATA_HOME", "")
    dirs = [Path(home) if home and os.path.isabs(home) else Path.home() / ".local/share"]
    dirs += [Path(d) for d in (os.environ.get("XDG_DATA_DIRS") or "/usr/local/share:/usr/share").split(":") if d]
    dirs += [Path("/var/lib/flatpak/exports/share"), Path.home() / ".local/share/flatpak/exports/share"]
    seen, out = set(), []
    for d in dirs:
        if str(d) not in seen:
            seen.add(str(d))
            out.append(d / "applications")
    return out


def locales() -> list:
    """Variantes del idioma del usuario para los campos Name[xx], de la más a la menos específica."""
    lang = (os.environ.get("LC_ALL") or os.environ.get("LC_MESSAGES") or os.environ.get("LANG") or "").split(".")[0]
    out = []
    if lang and lang not in ("C", "POSIX"):
        out.append(lang)
        if "_" in lang:
            out.append(lang.split("_")[0])
    return out


def group_for(categories: list) -> str:
    cats = set(categories)
    return next((g for c, g in GROUPS if c in cats), OTHER)


def _true(v) -> bool:
    return str(v).strip().lower() == "true"


def parse_desktop(path: Path, desktop_id: str, langs=None, only_in: str = "KDE"):
    cp = configparser.RawConfigParser(strict=False, interpolation=None, delimiters=("=",), comment_prefixes=("#",))
    cp.optionxform = str
    try:
        cp.read(path, encoding="utf-8")
        e = cp["Desktop Entry"]
    except (configparser.Error, KeyError, OSError, UnicodeDecodeError):
        return None
    if e.get("Type", "Application") != "Application" or _true(e.get("NoDisplay", "")) or _true(e.get("Hidden", "")):
        return None
    show, hide = [x for x in e.get("OnlyShowIn", "").split(";") if x], [x for x in e.get("NotShowIn", "").split(";") if x]
    if (show and only_in not in show) or only_in in hide:
        return None
    try_exec = e.get("TryExec", "")
    if try_exec and not (shutil.which(try_exec) or (os.path.isabs(try_exec) and os.access(try_exec, os.X_OK))):
        return None
    if not e.get("Exec", "").strip():
        return None

    def localized(key):
        for lg in (langs if langs is not None else locales()):
            v = e.get("%s[%s]" % (key, lg), "")
            if v:
                return v
        return e.get(key, "")

    name = localized("Name").strip()
    if not name:
        return None
    cats = [c for c in e.get("Categories", "").split(";") if c]
    kw = [k for k in localized("Keywords").split(";") if k]
    return App(desktop_id, name, localized("Comment").strip(), e.get("Icon", "").strip(), group_for(cats), str(path), kw)


def load_apps(dirs=None, langs=None, only_in: str = "KDE") -> list:
    """Aplicaciones visibles. Si un mismo id está en varias carpetas, gana la de mayor prioridad (la del usuario)."""
    found = {}
    for d in (dirs if dirs is not None else data_dirs()):
        d = Path(d)
        if not d.is_dir():
            continue
        for f in sorted(d.rglob("*.desktop")):
            did = str(f.relative_to(d)).replace("/", "-")
            if did in found:
                continue                       # ya la definió una carpeta más prioritaria (aunque esté oculta)
            found[did] = parse_desktop(f, did, langs, only_in)
    return sorted((a for a in found.values() if a), key=lambda a: a.name.casefold())


class Catalog:
    """Caché del catálogo: se relee si cambia alguna carpeta de aplicaciones (instalar o desinstalar)."""

    def __init__(self, dirs=None):
        self.dirs, self._sig, self._apps = dirs, None, []

    def _signature(self):
        out = []
        for d in (self.dirs if self.dirs is not None else data_dirs()):
            try:
                out.append((str(d), Path(d).stat().st_mtime_ns))
            except OSError:
                pass
        return tuple(out)

    def apps(self) -> list:
        sig = self._signature()
        if sig != self._sig:
            self._apps, self._sig = load_apps(self.dirs), sig
        return self._apps

    def find(self, app_id: str):
        return next((a for a in self.apps() if a.id == app_id), None)


def launch(app: App, env: dict | None = None) -> subprocess.Popen:
    """`gio launch` interpreta Exec (códigos %u, %f…) y la activación por D-Bus como lo haría el escritorio."""
    return subprocess.Popen(["gio", "launch", app.path], start_new_session=True,
                            env={**os.environ, **(env or {})}, stdin=subprocess.DEVNULL,
                            stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)

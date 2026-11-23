"""Minecraft Bedrock con BedrockOnLinux: detecta el AppImage `BedrockOnLinux-<versión>-<arq>.AppImage`.

Busca (a poca profundidad) en las carpetas externas configuradas, en las bibliotecas de Steam (las carpetas que
contienen `steamapps`, donde mucha gente deja también sus AppImage) y en algunas carpetas habituales del usuario.
Se lanza con `<AppImage> play`. No descarga ni instala nada: solo reconoce un AppImage que ya existe.
"""
import os
import re
from pathlib import Path

from .. import paths
from ..store import load_json
from .base import Detector
from .steam import library_dirs, steam_roots

PATTERN = re.compile(r"^BedrockOnLinux-(?P<version>[0-9][0-9A-Za-z.\-]*?)-[A-Za-z0-9_]+\.AppImage$", re.IGNORECASE)
HOME_DIRS = ("Juegos/PC", "Juegos", "Games", "Applications", "AppImages", "Descargas", "Downloads", ".local/bin")
MAX_DEPTH = 2          # carpeta + subcarpetas de primer nivel


def _version_key(text: str) -> tuple:
    return tuple(int(n) for n in re.findall(r"\d+", text)) or (0,)


class BedrockDetector(Detector):
    name = "bedrock"
    label = "BedrockOnLinux"

    def __init__(self, store=None, folders_fn=None):
        self.store = store
        self._folders_fn = folders_fn or self._folders

    def _folders(self) -> list:
        base = self.store.dir if self.store is not None else paths.config_dir()
        cfg = load_json(base / "config.json", {})
        raw = list(cfg.get("external_roots", [])) if isinstance(cfg, dict) else []
        for root in steam_roots():
            raw += [lib.parent for lib in library_dirs(root)]
        raw += [Path.home() / d for d in HOME_DIRS]
        out = []
        for item in raw:
            real = os.path.realpath(os.path.expanduser(str(item)))
            if os.path.isdir(real) and real not in out:
                out.append(real)
        return out

    @staticmethod
    def _appimages(folder: str, depth: int = 0):
        try:
            entries = list(os.scandir(folder))
        except OSError:
            return
        for entry in entries:
            try:
                if entry.is_file() and PATTERN.match(entry.name):
                    yield entry.path
                elif entry.is_dir(follow_symlinks=False) and depth + 1 < MAX_DEPTH and not entry.name.startswith("."):
                    yield from BedrockDetector._appimages(entry.path, depth + 1)
            except OSError:
                continue

    def _manual_paths(self) -> set:
        """AppImages que el usuario ya añadió a mano (como lanzador o como `check`): no se duplican."""
        found = set()
        for game in (self.store.games() if self.store else []):
            if game.get("auto") == self.name:
                continue
            for port in game.get("ports", []):
                if isinstance(port, dict):
                    for item in [port.get("check")] + list(port.get("launch") or []):
                        if item and str(item).startswith(("/", "~")):
                            found.add(os.path.realpath(os.path.expanduser(str(item))))
        return found

    def detect(self) -> list:
        candidates = {}
        for folder in self._folders_fn():
            for path in self._appimages(folder):
                real = os.path.realpath(path)
                match = PATTERN.match(os.path.basename(real))
                if match and os.access(real, os.X_OK):
                    candidates[real] = match.group("version")
        if not candidates:
            return []
        skip = self._manual_paths()
        if any(path in skip for path in candidates):
            return []
        newest = max(candidates, key=lambda p: _version_key(candidates[p]))
        port = {"id": "bedrock-on-linux-main", "name": "Minecraft Bedrock (BedrockOnLinux)", "chips": ["Port nativo"],
                "launch": [newest, "play"], "cwd": os.path.dirname(newest), "check": newest,
                "proc": "Minecraft.Windows.exe", "s": "BedrockOnLinux " + candidates[newest]}
        return [{"id": "bedrock-on-linux", "name": "Minecraft Bedrock", "sub": "PC · Port nativo", "platform": "pc",
                 "src": self.label, "auto": self.name, "art": {"slug": "bedrock-on-linux", "sgdb": "Minecraft Bedrock Edition"},
                 "ports": [port]}]

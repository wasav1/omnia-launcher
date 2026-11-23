"""Detector de ROMs en las carpetas de la biblioteca: basta con añadir la carpeta, sin elegir emulador.

Recorre las carpetas externas configuradas (config.json → external_roots), reconoce las ROMs por su cabecera con
`omnia.roms` y las publica como juegos. El emulador se elige o se rehace al pulsar «Jugar» (`manual.resolve_rom_launch`),
así que una ROM aparece aunque todavía no haya ningún emulador instalado. No sube ni envía nada.
"""
import hashlib
import os
import re
from pathlib import Path

from .. import fsbrowse, paths, roms
from ..store import load_json
from .base import Detector

GENERIC_FOLDERS = {"juego", "game", "base", "dump", "volcado", "base game", "juego base", "rom", "roms"}


def clean_title(file_name: str, fallback: str = "") -> str:
    """«A Bug_s Life (U) [!].z64» → «A Bug's Life»: sin extensión, etiquetas de región/volcado ni guiones bajos."""
    stem = Path(file_name).stem
    stem = re.sub(r"\s*[\(\[][^)\]]*[\)\]]", "", stem)
    stem = re.sub(r"_(?=s\b)", "'", stem).replace("_", " ")
    stem = " ".join(stem.split()).strip(" -.")
    moved = re.match(r"^(.+?), (The|A|An)( - .*)?$", stem)         # «Legend of Zelda, The - X» → «The Legend of Zelda - X»
    if moved:
        stem = f"{moved.group(2)} {moved.group(1)}{moved.group(3) or ''}"
    return stem or fallback or Path(file_name).stem


def _signature(folders) -> tuple:
    """Cambia cuando se añade, quita o renombra algo en el árbol (mtime de cada carpeta); no lee las ROMs."""
    rows = []
    for folder in folders:
        count = 0
        for current, dirs, files in os.walk(folder, followlinks=False):
            dirs[:] = [d for d in dirs if not d.startswith(".")]
            try:
                rows.append((current, os.stat(current).st_mtime_ns, len(files)))
            except OSError:
                continue
            count += 1
            if count > roms.MAX_DIRECTORIES:
                break
    return tuple(rows)


class RomFolderDetector(Detector):
    name = "roms"
    label = "ROM local"

    def __init__(self, store=None, folders_fn=None, scan_fn=None):
        self.store = store
        self._folders_fn = folders_fn or self._config_folders
        self._scan = scan_fn or roms.scan
        self._seen = None
        self._games: list = []

    def _config_folders(self) -> list:
        base = self.store.dir if self.store is not None else paths.config_dir()
        cfg = load_json(base / "config.json", {})
        raw = cfg.get("external_roots", []) if isinstance(cfg, dict) else []
        out = []
        for item in raw:
            real = os.path.realpath(os.path.expanduser(str(item)))
            if os.path.isdir(real) and real not in out:
                out.append(real)
        return out

    def _manual_paths(self) -> set:
        """ROMs que el usuario ya añadió a mano: no se duplican."""
        found = set()
        for game in (self.store.games() if self.store else []):
            if game.get("auto") == self.name:
                continue
            for port in game.get("ports", []):
                if isinstance(port, dict):
                    for key in ("check",):
                        if port.get(key):
                            found.add(os.path.realpath(os.path.expanduser(str(port[key]))))
        return found

    def detect(self) -> list:
        folders = self._folders_fn()
        if not folders:
            self._seen, self._games = None, []
            return []
        signature = (tuple(folders), _signature(folders))
        if signature != self._seen:
            self._seen, self._games = signature, self._build(folders)
        skip = self._manual_paths()
        return [g for g in self._games if g["ports"][0]["rom"]["path"] not in skip]

    def _build(self, folders) -> list:
        allowed = [str(p) for p in fsbrowse.allowed_roots()] + list(folders)
        games, seen_paths = [], set()
        for folder in folders:
            try:
                result = self._scan(folder, allowed)
            except roms.RomScanError:
                continue
            for item in result.get("items", []):
                games.append(self._game(item)) if item["path"] not in seen_paths else None
                seen_paths.add(item["path"])
        return [g for g in games if g]

    def _game(self, item: dict):
        if item.get("format") == "folder" and item.get("internalIdType") != "switch2":
            return None          # un volcado exefs+romfs de Switch 1 no lo ejecuta ningún emulador de Omnia: no se lista como juego
        choices = item.get("systemChoices") or []
        # una extensión compartida (iso/bin/chd...) sin sistema detectado queda para revisarla a mano
        if len(choices) > 1 and not item.get("internalIdType"):
            return None
        system = item["system"]
        system_name = "Nintendo Switch 2" if item.get("internalIdType") == "switch2" else item["systemName"]
        gid = "rom-" + hashlib.sha1(item["path"].encode("utf-8")).hexdigest()[:12]
        label = item["fileName"]
        if item.get("format") == "folder" and label.casefold() in GENERIC_FOLDERS:         # «Zelda OoT/Juego» → «Zelda OoT»
            label = os.path.basename(os.path.dirname(item["path"])) or label
        name = clean_title(label, item.get("internalTitle") or item.get("name", ""))
        port = {"id": gid + "-main", "name": "Emulador por elegir", "chips": ["ROM", system_name],
                "launch": [], "check": item["path"], "proc": item["path"],
                "cwd": item["path"] if item.get("format") == "folder" else os.path.dirname(item["path"]),
                "rom": {"path": item["path"], "system": system, "emulator": "",
                        "internalId": item.get("internalId", ""), "internalIdType": item.get("internalIdType", ""),
                        "buildId": item.get("buildId", "")}}
        return {"id": gid, "name": name, "variant": "ROM", "sub": "ROM · " + system_name,
                "platform": roms.platform_for(system, item.get("internalIdType", "")), "src": self.label, "auto": self.name,
                "art": {"slug": gid, "sgdb": name}, "ports": [port]}

    def is_installed(self, game: dict, port: dict) -> bool:
        rom = port.get("rom") or {}
        return bool(rom.get("path")) and os.path.exists(rom["path"])           # un archivo, o la carpeta de un volcado exefs+romfs

"""Epic Games Store mediante legendary (con configuración propia de Omnia)."""
import os
import re
import time
from pathlib import Path

from .base import StoreError, find_tool, parse_json, run
from ..library_metadata import _text

LOGIN_URL = ("https://www.epicgames.com/id/login?redirectUrl="
             "https%3A%2F%2Fwww.epicgames.com%2Fid%2Fapi%2Fredirect%3FclientId%3D34a02cf8f4414e29b15921876da36f9a%26responseType%3Dcode")
CODE_RE = re.compile(r"^[A-Za-z0-9]{16,64}$")


def clean_code(raw: str) -> str:
    """Acepta el código solo o el JSON que muestra Epic ({"authorizationCode": "…"})."""
    raw = (raw or "").strip()
    m = re.search(r'"authorizationCode"\s*:\s*"([^"]+)"', raw)
    code = (m.group(1) if m else raw).strip().strip('"')
    if not CODE_RE.match(code):
        raise StoreError("El código de Epic no es válido. Pégalo tal como lo muestra la página.")
    return code


class Epic:
    id = "epic"
    name = "Epic Games"
    short = "Epic"

    def __init__(self, data_dir: Path, runner=None, tool=None):
        self.dir = Path(data_dir) / "legendary"
        self._runner = runner
        self._tool = tool
        self._details = {}
        self._library_details = {}

    def tool(self):
        return self._tool or find_tool("legendary")

    def _run(self, args, timeout=60):
        tool = self.tool()
        if not tool:
            raise StoreError("Falta legendary. Instala Heroic o el paquete legendary.")
        self.dir.mkdir(parents=True, exist_ok=True, mode=0o700)
        self.dir.chmod(0o700)
        kw = {"runner": self._runner} if self._runner else {}
        return run([tool, *args], {"LEGENDARY_CONFIG_PATH": str(self.dir)}, timeout, **kw)

    def status(self) -> dict:
        if not self.tool():
            return {"id": self.id, "name": self.name, "available": False, "logged_in": False, "account": ""}
        code, out, _ = self._run(["status", "--json"], 20)
        try:
            info = parse_json(out) if code == 0 else {}
        except StoreError:
            info = {}
        account = str(info.get("account", ""))
        logged = bool(account) and not account.startswith("<")
        return {"id": self.id, "name": self.name, "available": True, "logged_in": logged,
                "account": account if logged else "", "games": int(info.get("games_available", 0) or 0)}

    def login_url(self) -> str:
        return LOGIN_URL

    def login(self, raw_code: str) -> dict:
        code = clean_code(raw_code)
        rc, _, err = self._run(["auth", "--code", code], 90)
        st = self.status()
        if rc != 0 or not st["logged_in"]:
            raise StoreError("Epic no aceptó el código (caduca en pocos minutos). Genera uno nuevo e inténtalo otra vez.")
        return st

    def logout(self) -> dict:
        self._run(["auth", "--delete"], 30)
        return self.status()

    def library(self) -> list:
        code, out, _ = self._run(["list", "--json"], 180)
        if code != 0:
            raise StoreError("No se pudo leer la biblioteca de Epic.")
        installed = set()
        c2, o2, _ = self._run(["list-installed", "--json"], 60)
        if c2 == 0:
            try:
                installed = {g.get("app_name") for g in parse_json(o2)}
            except StoreError:
                pass
        items = []
        details = {}
        for g in parse_json(out):
            app = g.get("app_name")
            if not app or not isinstance(app, str):
                continue
            art = ""
            metadata = g.get("metadata") or {}
            hero = ""
            for im in metadata.get("keyImages", []):
                if im.get("type") in ("DieselGameBoxWide", "OfferImageWide") and str(im.get("url", "")).startswith("https://"):
                    hero = im["url"]
            for im in metadata.get("keyImages", []):
                if im.get("type") in ("DieselGameBoxTall", "Thumbnail") and str(im.get("url", "")).startswith("https://"):
                    art = im["url"]
                    if im["type"] == "DieselGameBoxTall":
                        break
            item = {"id": app, "title": g.get("app_title") or app, "art": art, "installed": app in installed}
            if hero:
                item["hero"] = hero
            info = {key: value for key, value in {
                "description": _text(metadata.get("description"), 1500),
                "developer": _text(metadata.get("developer")),
                "publisher": _text(metadata.get("publisher")),
            }.items() if value}
            if info:
                item["metadata"] = info
                details[app] = info
            items.append(item)
        self._library_details = details
        return sorted(items, key=lambda x: x["title"].lower())

    def game_metadata(self, game_id: str) -> dict:
        """Lee tamaños del manifiesto vía Legendary, sin descargar archivos del juego."""
        if not re.fullmatch(r"[A-Za-z0-9][A-Za-z0-9._-]{0,119}", game_id) or os.path.exists(game_id):
            return {}
        info = self._library_details.get(game_id) or {}
        cached, expires = self._details.get(game_id, ({}, 0))
        if time.monotonic() < expires:
            return {**info, **cached}
        self._details[game_id] = (cached, time.monotonic() + 90)
        try:
            status, output, _ = self._run(["info", game_id, "--json"], 12)
            raw = parse_json(output) if status == 0 else {}
        except (StoreError, OSError):
            return {**info, **cached}
        manifest = raw.get("manifest") if isinstance(raw, dict) else None
        if not isinstance(manifest, dict) or manifest.get("app_name") != game_id:
            return {**info, **cached}
        result = {}
        for field, key in (("disk_size", "diskBytes"), ("download_size", "downloadBytes")):
            size = manifest.get(field)
            if type(size) is int and size > 0:
                result[key] = size
        # Con descargas selectivas el tamaño del manifiesto equivale a todos sus componentes.
        result["fullDownload"] = len(manifest.get("install_tags") or []) > 1
        self._details[game_id] = (result, time.monotonic() + 86400)
        return {**info, **result}

    def install_command(self, game_id: str, folder: str):
        tool = self.tool()
        if not tool:
            raise StoreError("Falta legendary. Instala Heroic o el paquete legendary.")
        self.dir.mkdir(parents=True, exist_ok=True, mode=0o700)
        return [tool, "install", game_id, "--base-path", folder, "-y"], {"LEGENDARY_CONFIG_PATH": str(self.dir)}

    def find_executable(self, game_id: str, folder: str) -> str:
        code, out, _ = self._run(["list-installed", "--json"], 60)
        for g in (parse_json(out) if code == 0 else []):
            if isinstance(g, dict) and g.get("app_name") == game_id:
                exe = os.path.join(str(g.get("install_path", "")), str(g.get("executable", "")).replace("\\", "/"))
                if os.path.isfile(exe):
                    return exe
        raise StoreError("Se instaló, pero Omnia no encontró el ejecutable del juego.")

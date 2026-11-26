"""Amazon Games mediante nile (configuración propia de Omnia en XDG_CONFIG_HOME/nile)."""
import json
import re
from pathlib import Path

from .base import StoreError, find_tool, parse_json, pasted_code, run

CODE_RE = r"[A-Za-z0-9_\-]{8,200}"


class Amazon:
    id = "amazon"
    name = "Amazon Games"
    short = "Amazon"

    def __init__(self, data_dir: Path, runner=None, tool=None):
        self.dir = Path(data_dir) / "nile"
        self._runner, self._tool = runner, tool
        self._pending = None

    def tool(self):
        return self._tool or find_tool("nile")

    def _run(self, args, timeout=60):
        tool = self.tool()
        if not tool:
            raise StoreError("Falta nile. Instala Heroic.")
        self.dir.mkdir(parents=True, exist_ok=True, mode=0o700)
        self.dir.chmod(0o700)
        kw = {"runner": self._runner} if self._runner else {}
        return run([tool, *args], {"XDG_CONFIG_HOME": str(self.dir)}, timeout, **kw)

    def status(self) -> dict:
        if not self.tool():
            return {"id": self.id, "name": self.name, "available": False, "logged_in": False, "account": ""}
        code, out, _ = self._run(["auth", "--status"], 20)
        try:
            info = parse_json(out) if code == 0 else {}
        except StoreError:
            info = {}
        logged = bool(info.get("LoggedIn"))
        return {"id": self.id, "name": self.name, "available": True, "logged_in": logged,
                "account": str(info.get("Username", "")) if logged else ""}

    def login_url(self) -> str:
        code, out, _ = self._run(["auth", "--login", "--non-interactive"], 30)
        if code != 0:
            raise StoreError("No se pudo preparar el inicio de sesión de Amazon.")
        info = parse_json(out)
        url = str(info.get("url", ""))
        if not url.startswith("https://www.amazon.com/") and not url.startswith("https://amazon.com/"):
            raise StoreError("Amazon devolvió una dirección de inicio de sesión inesperada.")
        self._pending = {k: str(info.get(k, "")) for k in ("client_id", "code_verifier", "serial")}
        return url

    def login(self, raw: str) -> dict:
        if not self._pending or not all(self._pending.values()):
            raise StoreError("Pulsa primero «Abrir inicio de sesión» para obtener la dirección de Amazon.")
        code = pasted_code(raw, ("openid.oa2.authorization_code",), CODE_RE)
        p = self._pending
        rc, _, _ = self._run(["register", "--code", code, "--client-id", p["client_id"],
                              "--code-verifier", p["code_verifier"], "--serial", p["serial"]], 90)
        st = self.status()
        if rc != 0 or not st["logged_in"]:
            raise StoreError("Amazon no aceptó el código. Genera uno nuevo e inténtalo otra vez.")
        self._pending = None
        return st

    def logout(self) -> dict:
        self._run(["auth", "--logout"], 30)
        self._pending = None
        return self.status()

    def library(self) -> list:
        self._run(["library", "sync"], 180)
        code, out, _ = self._run(["library", "list", "--json"], 60)
        if code != 0:
            raise StoreError("No se pudo leer la biblioteca de Amazon.")
        data = parse_json(out)
        if isinstance(data, dict):
            data = data.get("library") or []
        installed = set()
        c2, o2, _ = self._run(["library", "list", "--installed", "--json"], 60)
        if c2 == 0:
            try:
                d2 = parse_json(o2)
                installed = {str(g.get("id")) for g in (d2.get("library") if isinstance(d2, dict) else d2) or [] if isinstance(g, dict)}
            except StoreError:
                pass
        items = []
        for g in data:
            if not isinstance(g, dict) or not isinstance(g.get("id"), str):
                continue
            prod = g.get("product") or {}
            detail = (prod.get("productDetail") or {})
            art = ""
            for url in ((detail.get("details") or {}).get("logoUrl"), detail.get("iconUrl")):
                if isinstance(url, str) and re.match(r"^https://[a-z0-9.-]+\.(?:media-amazon|ssl-images-amazon)\.com/", url):
                    art = url
                    break
            items.append({"id": g["id"], "title": str(prod.get("title") or g.get("title") or g["id"]), "art": art,
                          "installed": g["id"] in installed})
        return sorted(items, key=lambda x: x["title"].lower())

    def install_command(self, game_id: str, folder: str):
        tool = self.tool()
        if not tool:
            raise StoreError("Falta nile. Instala Heroic.")
        self.dir.mkdir(parents=True, exist_ok=True, mode=0o700)
        return [tool, "install", game_id, "--base-path", folder], {"XDG_CONFIG_HOME": str(self.dir)}

    def find_executable(self, game_id: str, folder: str) -> str:
        try:
            installed = json.loads((self.dir / "nile" / "installed.json").read_text(encoding="utf-8"))
        except (OSError, ValueError):
            installed = []
        for g in installed if isinstance(installed, list) else []:
            if isinstance(g, dict) and g.get("id") == game_id and g.get("path"):
                path = Path(str(g["path"]))
                try:
                    fuel = json.loads((path / "fuel.json").read_text(encoding="utf-8"))
                    exe = path / str((fuel.get("Main") or {}).get("Command", "")).replace("\\", "/")
                except (OSError, ValueError):
                    continue
                if exe.is_file():
                    return str(exe)
        raise StoreError("Se instaló, pero Omnia no encontró el ejecutable del juego.")

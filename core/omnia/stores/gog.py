"""GOG mediante gogdl (sesión) y la API web de GOG (biblioteca), con configuración propia de Omnia."""
import json
import re
import urllib.error
import urllib.request
from pathlib import Path

from .base import StoreError, find_tool, parse_json, pasted_code, run

LOGIN_URL = ("https://auth.gog.com/auth?client_id=46899977096215655&redirect_uri="
             "https%3A%2F%2Fembed.gog.com%2Fon_login_success%3Forigin%3Dclient&response_type=code&layout=galaxy")
CODE_RE = r"[A-Za-z0-9_\-]{20,200}"
IMAGE_RE = re.compile(r"^(?:https:)?//images(?:-\d+)?\.gog(?:-statics)?\.com/[0-9a-f]{8,80}$")
PRODUCTS = "https://embed.gog.com/account/getFilteredProducts?mediaType=1&page=%d"


def _http_json(url: str, token: str, opener=urllib.request.urlopen):
    req = urllib.request.Request(url, headers={"Authorization": "Bearer " + token, "User-Agent": "Omnia/0.3", "Accept": "application/json"})
    try:
        with opener(req, timeout=30) as r:
            return json.loads(r.read(8_000_000).decode("utf-8"))
    except (urllib.error.URLError, OSError, ValueError):
        raise StoreError("No se pudo consultar la biblioteca de GOG.")


class Gog:
    id = "gog"
    name = "GOG"

    def __init__(self, data_dir: Path, runner=None, tool=None, opener=urllib.request.urlopen):
        self.dir = Path(data_dir) / "gogdl"
        self.auth_file = self.dir / "auth.json"
        self.profile = self.dir / "profile.json"
        self._runner, self._tool, self._opener = runner, tool, opener

    def tool(self):
        return self._tool or find_tool("gogdl")

    def _run(self, args, timeout=60):
        tool = self.tool()
        if not tool:
            raise StoreError("Falta gogdl. Instala Heroic.")
        self.dir.mkdir(parents=True, exist_ok=True, mode=0o700)
        self.dir.chmod(0o700)
        kw = {"runner": self._runner} if self._runner else {}
        return run([tool, "--auth-config-path", str(self.auth_file), *args], None, timeout, **kw)

    def _credentials(self):
        """Credenciales vigentes (gogdl renueva el token si hace falta) o None si no hay sesión."""
        if not self.auth_file.exists():
            return None
        code, out, _ = self._run(["auth"], 45)
        if code != 0:
            return None
        try:
            data = parse_json(out)
        except StoreError:
            return None
        if isinstance(data, dict) and "access_token" not in data:
            data = next((v for v in data.values() if isinstance(v, dict) and "access_token" in v), None)
        return data if isinstance(data, dict) and data.get("access_token") else None

    def _profile(self) -> dict:
        try:
            return json.loads(self.profile.read_text())
        except (OSError, ValueError):
            return {}

    def status(self) -> dict:
        if not self.tool():
            return {"id": self.id, "name": self.name, "available": False, "logged_in": False, "account": ""}
        logged = self.auth_file.exists()
        return {"id": self.id, "name": self.name, "available": True, "logged_in": logged,
                "account": str(self._profile().get("username", "")) if logged else ""}

    def login_url(self) -> str:
        return LOGIN_URL

    def login(self, raw: str) -> dict:
        code = pasted_code(raw, ("code",), CODE_RE)
        rc, out, _ = self._run(["auth", "--code", code], 90)
        if rc != 0 or not self.auth_file.exists():
            raise StoreError("GOG no aceptó el código (caduca en pocos minutos). Genera uno nuevo e inténtalo otra vez.")
        self.auth_file.chmod(0o600)
        cred = self._credentials()
        name = ""
        if cred:
            try:
                name = str(_http_json("https://embed.gog.com/userData.json", cred["access_token"], self._opener).get("username", ""))[:64]
            except StoreError:
                pass
        self.profile.write_text(json.dumps({"username": name}))
        self.profile.chmod(0o600)
        return self.status()

    def logout(self) -> dict:
        for f in (self.auth_file, self.profile):
            f.unlink(missing_ok=True)
        return self.status()

    def library(self) -> list:
        cred = self._credentials()
        if not cred:
            raise StoreError("Inicia sesión en GOG primero.")
        items, page, pages = [], 1, 1
        while page <= pages and page <= 50:
            data = _http_json(PRODUCTS % page, cred["access_token"], self._opener)
            pages = int(data.get("totalPages", 1) or 1)
            for p in data.get("products", []):
                if not isinstance(p.get("id"), int):
                    continue
                img = p.get("image") if isinstance(p.get("image"), str) else ""
                art = ("https:" if img.startswith("//") else "") + img + "_product_card_v2_mobile_slider_639.jpg" if IMAGE_RE.match(img) else ""
                items.append({"id": str(p["id"]), "title": str(p.get("title") or p["id"]), "art": art, "installed": False,
                              "linux": bool((p.get("worksOn") or {}).get("Linux"))})
            page += 1
        return sorted(items, key=lambda x: x["title"].lower())

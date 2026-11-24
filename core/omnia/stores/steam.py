"""Steam: sin clave de API ni contraseñas en Omnia.

El usuario inicia sesión en la página oficial de Steam dentro de la ventana de Omnia (StoreLogin.qml). Con esa sesión web, la ventana
lee de su propia página de juegos el token de corta duración de la Web API (`strWebAPIToken`) y el id de la cuenta, y se los entrega a
Omnia. Omnia consulta `IPlayerService/GetOwnedGames` solo en api.steampowered.com, usa el token una vez, NO lo guarda, y conserva
únicamente la lista (id y nombre). Instalar abre el diálogo oficial `steam://install/<id>`; Steam no permite otra vía.
"""
import json
import re
import time
import urllib.error
import urllib.parse
import urllib.request
from pathlib import Path

from .base import StoreError

LOGIN_URL = "https://steamcommunity.com/my/"
OWNED_URL = "https://api.steampowered.com/IPlayerService/GetOwnedGames/v1/?"
STEAMID_RE = re.compile(r"7656\d{13}")
TOKEN_RE = re.compile(r"[A-Za-z0-9_.\-]{40,2000}")


def fetch_owned(steamid: str, token: str, opener=urllib.request.urlopen) -> list:
    """Juegos de la cuenta [{id, title}] con el token de la sesión web. El token solo viaja a api.steampowered.com."""
    if not STEAMID_RE.fullmatch(steamid or "") or not TOKEN_RE.fullmatch(token or ""):
        raise StoreError("Steam no entregó los datos de la sesión. Inicia sesión e inténtalo otra vez.")
    query = urllib.parse.urlencode({"access_token": token, "steamid": steamid, "include_appinfo": 1,
                                    "include_played_free_games": 1, "format": "json"})
    req = urllib.request.Request(OWNED_URL + query, headers={"User-Agent": "Omnia/0.3", "Accept": "application/json"})
    try:
        with opener(req, timeout=30) as r:
            data = json.loads(r.read(20_000_000).decode("utf-8"))
    except urllib.error.HTTPError as e:
        raise StoreError("Steam rechazó la sesión (código %d). Inicia sesión otra vez." % e.code)
    except (urllib.error.URLError, OSError, ValueError):
        raise StoreError("No se pudo consultar tu biblioteca de Steam.")
    games = []
    for g in (data.get("response") or {}).get("games", []) if isinstance(data, dict) else []:
        appid = str(g.get("appid", "")) if isinstance(g, dict) else ""
        if appid.isdigit() and len(appid) <= 10:
            games.append({"id": appid, "title": str(g.get("name") or appid).strip()[:120]})
    return games


def parse_capture(raw: str, opener=urllib.request.urlopen) -> dict:
    """Lo que entrega la ventana: JSON {steamid, name, token}. Devuelve {steamid, name, games}."""
    try:
        env = json.loads(raw)
    except (TypeError, ValueError):
        env = None
    if not isinstance(env, dict):
        raise StoreError("La respuesta de Steam no es válida.")
    steamid, token = str(env.get("steamid", "")).strip(), str(env.get("token", "")).strip()
    return {"steamid": steamid, "name": str(env.get("name", "")).strip()[:64], "games": fetch_owned(steamid, token, opener)}


class Steam:
    id = "steam"
    name = "Steam"
    short = "Steam"

    def __init__(self, data_dir: Path, opener=urllib.request.urlopen):
        self.dir = Path(data_dir) / "steam"
        self.file = self.dir / "library.json"
        self._opener = opener

    def _read(self) -> dict | None:
        try:
            data = json.loads(self.file.read_text(encoding="utf-8"))
            return data if isinstance(data, dict) and isinstance(data.get("games"), list) else None
        except (OSError, ValueError):
            return None

    def status(self) -> dict:
        data = self._read()
        return {"id": self.id, "name": self.name, "available": True, "logged_in": data is not None,
                "account": str((data or {}).get("name", "")), "games": len((data or {}).get("games", [])),
                "updated": int((data or {}).get("updated", 0) or 0)}

    def login_url(self) -> str:
        return LOGIN_URL

    def login(self, raw: str) -> dict:
        data = parse_capture(raw, self._opener)
        data["updated"] = int(time.time())
        self.dir.mkdir(parents=True, exist_ok=True, mode=0o700)
        self.dir.chmod(0o700)
        self.file.write_text(json.dumps(data, ensure_ascii=False), encoding="utf-8")
        self.file.chmod(0o600)
        return self.status()

    def logout(self) -> dict:
        self.file.unlink(missing_ok=True)
        return self.status()

    def library(self) -> list:
        data = self._read()
        if data is None:
            raise StoreError("Conecta tu cuenta de Steam primero.")
        return sorted(({"id": g["id"], "title": g["title"], "installed": False,
                        "art": "https://cdn.cloudflare.steamstatic.com/steam/apps/%s/library_600x900.jpg" % g["id"]}
                       for g in data["games"] if isinstance(g, dict) and str(g.get("id", "")).isdigit()),
                      key=lambda x: x["title"].lower())

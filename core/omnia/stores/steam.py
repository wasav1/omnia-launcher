"""Steam: sin clave de API ni contraseñas en Omnia.

El usuario inicia sesión en la página oficial de Steam dentro de la ventana de Omnia (StoreLogin.qml). Con esa sesión web, la ventana pide
`/my/games?tab=all&xml=1` (la propia lista de juegos de la cuenta, con cualquier privacidad) y entrega el XML a Omnia, que guarda solo la
lista (id y nombre). Instalar abre el diálogo oficial `steam://install/<id>`; Steam no permite otra vía.
"""
import html as htmllib
import json
import re
import time
import xml.etree.ElementTree as ET
from pathlib import Path

from .base import StoreError

LOGIN_URL = "https://steamcommunity.com/my/"
MAX_XML = 8_000_000


def parse_games_xml(text: str) -> dict:
    """{steamid, name, games:[{id, title}]} desde el XML de /games?xml=1. Rechaza DTD/entidades (sin expansión de entidades)."""
    if not isinstance(text, str) or len(text) > MAX_XML:
        raise StoreError("La respuesta de Steam no es válida.")
    head = text[:4000].upper()
    if "<!DOCTYPE" in head or "<!ENTITY" in text.upper():
        raise StoreError("La respuesta de Steam no es válida.")
    start = text.find("<")
    try:
        root = ET.fromstring(text[start:] if start > 0 else text)
    except ET.ParseError:
        raise StoreError("La respuesta de Steam no es válida.")
    err = root.findtext("error")
    if root.tag == "response" and err:
        raise StoreError("Steam no dejó leer tu biblioteca. Inicia sesión en Steam e inténtalo otra vez.")
    steamid = (root.findtext("steamID64") or "").strip()
    if not re.fullmatch(r"7656\d{13}", steamid):
        raise StoreError("Steam no devolvió una cuenta válida. Inicia sesión e inténtalo otra vez.")
    games = []
    for g in root.iter("game"):
        appid = (g.findtext("appID") or "").strip()
        if appid.isdigit() and len(appid) <= 10:
            games.append({"id": appid, "title": (g.findtext("name") or appid).strip()[:120]})
    return {"steamid": steamid, "name": (root.findtext("steamID") or "").strip()[:64], "games": games}


def parse_games_html(text: str) -> list:
    """Juegos de la página moderna /games (la lista va en el atributo data-profile-gameslist, en JSON)."""
    m = re.search(r'data-profile-gameslist="([^"]*)"', text or "")
    if not m:
        raise StoreError("Steam no mostró tu lista de juegos. Inicia sesión e inténtalo otra vez.")
    try:
        data = json.loads(htmllib.unescape(m.group(1)))
    except ValueError:
        raise StoreError("La lista de juegos de Steam no se pudo leer.")
    games = []
    for g in (data.get("rgGames") or []) if isinstance(data, dict) else []:
        appid = str(g.get("appid", "")) if isinstance(g, dict) else ""
        if appid.isdigit() and len(appid) <= 10:
            games.append({"id": appid, "title": str(g.get("name") or appid).strip()[:120]})
    return games


def parse_capture(raw: str) -> dict:
    """Resultado de lo que entrega la ventana: sobre JSON {steamid, name, xml, html} o, por compatibilidad, el XML directo."""
    try:
        env = json.loads(raw)
    except (TypeError, ValueError):
        env = None
    if not isinstance(env, dict):
        return parse_games_xml(raw)
    if len(str(env.get("html", ""))) > MAX_XML or len(str(env.get("xml", ""))) > MAX_XML:
        raise StoreError("La respuesta de Steam no es válida.")
    steamid = str(env.get("steamid", "")).strip()
    name = str(env.get("name", "")).strip()[:64]
    if env.get("xml"):
        data = parse_games_xml(env["xml"])
        data["name"] = data["name"] or name
        return data
    if not re.fullmatch(r"7656\d{13}", steamid):
        raise StoreError("Steam no devolvió una cuenta válida. Inicia sesión e inténtalo otra vez.")
    return {"steamid": steamid, "name": name, "games": parse_games_html(str(env.get("html", "")))}


class Steam:
    id = "steam"
    name = "Steam"
    short = "Steam"

    def __init__(self, data_dir: Path):
        self.dir = Path(data_dir) / "steam"
        self.file = self.dir / "library.json"

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
        data = parse_capture(raw)
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

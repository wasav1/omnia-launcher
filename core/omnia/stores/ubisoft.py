"""Ubisoft Connect (entrega 6): inicio de sesión en la página oficial y biblioteca de la cuenta. Omnia nunca ve la contraseña.

La persona inicia sesión en connect.ubisoft.com dentro de la ventana de Omnia (StoreLogin.qml). Al terminar, la página guarda la
sesión en su `localStorage` (`PRODloginData`, `PRODrememberMe`); la ventana la lee y se la entrega a Omnia, que guarda solo el
ticket, el id de sesión, el «recordarme» y el nombre (archivo 0600). Con el ticket se consulta la lista de juegos de la cuenta en
la API pública de Ubisoft (la misma que usan Lutris y la integración de GOG Galaxy) y se renueva antes de caducar.

API no oficial: si Ubisoft la cambia, la biblioteca deja de cargar (se avisa) pero los juegos instalados siguen funcionando,
porque se lanzan con Ubisoft Connect desde su prefijo (ver `launchers.py`). Instalar abre Ubisoft Connect.
"""
import json
import re
import time
from pathlib import Path

from .base import StoreError
from .web import request_json

APP_ID = "82b650c0-6cb3-40c0-9f41-25a53b62b206"
GENOME_ID = "42d07c95-9914-4450-8b38-267c4e462b21"
LOGIN_URL = (f"https://connect.ubisoft.com/login?appId={APP_ID}&genomeId={GENOME_ID}"
             "&lang=es-ES&nextUrl=https:%2F%2Fconnect.ubisoft.com%2Fready")
SESSIONS = "https://public-ubiservices.ubi.com/v3/profiles/sessions"
GRAPHQL = "https://public-ubiservices.ubi.com/v1/profiles/me/uplay/graphql"
_TICKET = re.compile(r"[A-Za-z0-9+/=_.\-]{20,4000}")
_ID = re.compile(r"[A-Za-z0-9-]{8,80}")
_QUERY = ("query AllGames { viewer { id ...ownedGamesList } } "
          "fragment gameProps on Game { id spaceId name coverUrl backgroundUrl bannerUrl } "
          "fragment ownedGameProps on Game { ...gameProps viewer { meta { id ownedPlatformGroups { id name type } } } } "
          "fragment ownedGamesList on User { ownedGames: games(filterBy: {isOwned: true}) { totalCount nodes { ...ownedGameProps } } }")


def parse_login(raw: str) -> dict:
    """Sesión a partir de lo que entrega la ventana: JSON con `loginData` y `rememberMe` (los valores de localStorage)."""
    try:
        data = json.loads(raw) if isinstance(raw, str) else None
    except ValueError:
        data = None
    if not isinstance(data, dict):
        raise StoreError("Ubisoft no entregó la sesión. Inicia sesión otra vez.")
    merged = {}
    for key in ("loginData", "rememberMe", "lastProfile"):
        value = data.get(key)
        if isinstance(value, str):
            try:
                value = json.loads(value)
            except ValueError:
                value = None
        if isinstance(value, dict):
            merged.update(value)
    session = {"ticket": merged.get("ticket"), "sessionId": merged.get("sessionId"), "userId": merged.get("userId"),
               "username": merged.get("nameOnPlatform") or merged.get("username") or "",
               "rememberMeTicket": merged.get("rememberMeTicket") or ""}
    if not (isinstance(session["ticket"], str) and _TICKET.fullmatch(session["ticket"])
            and isinstance(session["sessionId"], str) and _ID.fullmatch(session["sessionId"])
            and isinstance(session["userId"], str) and _ID.fullmatch(session["userId"])):
        raise StoreError("Ubisoft no entregó la sesión. Inicia sesión otra vez.")
    if not (isinstance(session["rememberMeTicket"], str) and _TICKET.fullmatch(session["rememberMeTicket"] or "x" * 20)):
        session["rememberMeTicket"] = ""
    session["username"] = str(session["username"])[:64]
    session["refreshAt"] = time.time() + 2 * 3600          # el ticket dura unas 3 horas; se renueva antes
    return session


class Ubisoft:
    id = "ubisoft"
    name = "Ubisoft Connect"
    short = "Ubisoft"
    web_login = True                       # inicio de sesión solo en la ventana de Omnia (no hay código para pegar)

    def __init__(self, data_dir: Path, opener=None):
        self.dir = Path(data_dir) / "ubisoft"
        self.file = self.dir / "session.json"
        self.cache = self.dir / "library.json"
        self._opener = opener

    def _session(self) -> dict:
        try:
            data = json.loads(self.file.read_text(encoding="utf-8"))
        except (OSError, ValueError):
            return {}
        return data if isinstance(data, dict) and data.get("ticket") else {}

    def _save(self, session: dict):
        self.dir.mkdir(parents=True, exist_ok=True, mode=0o700)
        self.dir.chmod(0o700)
        self.file.write_text(json.dumps(session), encoding="utf-8")
        self.file.chmod(0o600)

    def status(self) -> dict:
        session = self._session()
        return {"id": self.id, "name": self.name, "available": True, "logged_in": bool(session),
                "account": session.get("username", "") if session else "", "web_login": True}

    def login_url(self) -> str:
        return LOGIN_URL

    def login(self, raw: str) -> dict:
        session = parse_login(raw)
        self._save(session)
        try:
            self._refresh(session, force=True)           # comprueba la sesión con Ubisoft antes de darla por buena
        except StoreError:
            self.file.unlink(missing_ok=True)
            raise StoreError("Ubisoft no aceptó la sesión. Inicia sesión otra vez.")
        return self.status()

    def logout(self) -> dict:
        for f in (self.file, self.cache):
            f.unlink(missing_ok=True)
        return self.status()

    def _headers(self, session, auth=None) -> dict:
        return {"Ubi-AppId": APP_ID, "Authorization": auth or "Ubi_v1 t=" + session["ticket"],
                "Ubi-SessionId": session.get("sessionId", ""), "Content-Type": "application/json",
                "Origin": "https://connect.ubisoft.com", "Referer": "https://connect.ubisoft.com/"}

    def _refresh(self, session, force=False) -> dict:
        """Renueva el ticket (PUT con el ticket; si caducó, POST con «recordarme»). Sin éxito, cierra la sesión."""
        if not force and time.time() < float(session.get("refreshAt") or 0):
            return session
        attempts = [("PUT", None, None)]
        if session.get("rememberMeTicket"):
            attempts.append(("POST", "rm_v1 t=" + session["rememberMeTicket"], {"rememberMe": True}))
        for method, auth, body in attempts:
            try:
                data = request_json(method, SESSIONS, self._headers(session, auth), body, opener=self._opener)
            except StoreError:
                continue
            if isinstance(data, dict) and isinstance(data.get("ticket"), str) and _TICKET.fullmatch(data["ticket"]):
                session = {**session, "ticket": data["ticket"], "sessionId": str(data.get("sessionId") or session["sessionId"]),
                           "refreshAt": time.time() + 2 * 3600}
                if isinstance(data.get("rememberMeTicket"), str) and _TICKET.fullmatch(data["rememberMeTicket"]):
                    session["rememberMeTicket"] = data["rememberMeTicket"]
                if data.get("nameOnPlatform"):
                    session["username"] = str(data["nameOnPlatform"])[:64]
                self._save(session)
                return session
        raise StoreError("La sesión de Ubisoft caducó. Inicia sesión otra vez.")

    def library(self) -> list:
        session = self._session()
        if not session:
            raise StoreError("Inicia sesión en Ubisoft Connect para ver tu biblioteca.")
        try:
            session = self._refresh(session)
            data = request_json("POST", GRAPHQL, self._headers(session), {"operationName": "AllGames", "variables": {"owned": True},
                                                                          "query": _QUERY}, opener=self._opener)
        except StoreError:
            cached = self._cached()
            if cached:
                return cached                       # sin conexión o API cambiada: la última lista conocida
            raise
        nodes = ((((data or {}).get("data") or {}).get("viewer") or {}).get("ownedGames") or {}).get("nodes") or []
        items = []
        for game in nodes:
            if not isinstance(game, dict) or not game.get("name"):
                continue
            groups = ((game.get("viewer") or {}).get("meta") or {}).get("ownedPlatformGroups") or []
            platforms = {str(p.get("type")) for group in groups if isinstance(group, list) for p in group if isinstance(p, dict)}
            if platforms and "PC" not in platforms:
                continue                              # solo los de PC
            gid = str(game.get("spaceId") or game.get("id") or "")
            if not _ID.fullmatch(gid):
                continue
            item = {"id": gid, "title": str(game["name"])[:200], "art": str(game.get("coverUrl") or ""), "installed": False}
            if game.get("backgroundUrl"):
                item["hero"] = str(game["backgroundUrl"])
            items.append(item)
        items.sort(key=lambda x: x["title"].lower())
        try:
            self.cache.write_text(json.dumps(items), encoding="utf-8")
            self.cache.chmod(0o600)
        except OSError:
            pass
        return items

    def _cached(self) -> list:
        try:
            data = json.loads(self.cache.read_text(encoding="utf-8"))
        except (OSError, ValueError):
            return []
        return data if isinstance(data, list) else []

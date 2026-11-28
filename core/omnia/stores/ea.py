"""EA app (entrega 6): inicio de sesión en la página oficial de EA y biblioteca de la cuenta. Omnia nunca ve la contraseña.

La persona inicia sesión en ea.com dentro de la ventana de Omnia (StoreLogin.qml). Con la sesión web de esa ventana, la ventana
abre `accounts.ea.com/connect/auth?…response_type=token` (lo mismo que hace Lutris) y le entrega a Omnia el token de acceso que
muestra la página; dura alrededor de una hora. Omnia lo guarda (archivo 0600) junto con la lista de juegos, que consulta en la API
GraphQL de EA. Cuando caduca, la ventana pide otro en segundo plano con la misma sesión web (sin volver a escribir nada).

API no oficial: si EA la cambia, la biblioteca deja de cargar (se avisa) pero los juegos instalados siguen funcionando con la
EA app. Instalar abre la EA app en el juego (`origin2://game/launch?offerIds=…&autoDownload=1`).
"""
import json
import re
import time
from pathlib import Path

from .base import StoreError
from .web import request_json

LOGIN_URL = "https://www.ea.com/login"
TOKEN_URL = ("https://accounts.ea.com/connect/auth?client_id=ORIGIN_JS_SDK&response_type=token"
             "&redirect_uri=nucleus:rest&prompt=none")
GRAPHQL = "https://service-aggregation-layer.juno.ea.com/graphql"
_TOKEN = re.compile(r"[A-Za-z0-9._~+/=-]{20,4000}")
_ID = re.compile(r"[A-Za-z0-9._:-]{1,80}")
_ENTITLEMENTS = """query getEntitlements($limit: Int, $next: String) { me { ownedGameProducts(locale: "DEFAULT"
  entitlementEnabled: true storefronts: [EA] type: [DIGITAL_FULL_GAME, PACKAGED_FULL_GAME] platforms: [PC]
  paging: { limit: $limit, next: $next }) { next items { originOfferId product { baseItem { gameType } } } } } }"""
_OFFERS = """query getOffers($offerIds: [String!]!) { legacyOffers(offerIds: $offerIds, locale: "DEFAULT") { offerId: id contentId }
  gameProducts(offerIds: $offerIds, locale: "DEFAULT") { items { id originOfferId gameSlug baseItem {
  keyArt { largestImage { path } } packArt { largestImage { path } } title } } } }"""


def parse_token(raw: str) -> dict:
    """{access_token, expires_in} que muestra la página de EA; acepta también el JSON dentro de más texto."""
    text = raw if isinstance(raw, str) else ""
    match = re.search(r"\{.*\}", text, re.S)
    try:
        data = json.loads(match.group(0)) if match else {}
    except ValueError:
        data = {}
    token = data.get("access_token") if isinstance(data, dict) else None
    if not isinstance(token, str) or not _TOKEN.fullmatch(token):
        raise StoreError("EA no entregó la sesión. Inicia sesión otra vez.")
    try:
        lifetime = max(60, min(int(data.get("expires_in", 3600)), 24 * 3600))
    except (TypeError, ValueError):
        lifetime = 3600
    return {"token": token, "expiresAt": time.time() + lifetime - 60}


class Ea:
    id = "ea"
    name = "EA app"
    short = "EA"
    web_login = True
    token_url = TOKEN_URL

    def __init__(self, data_dir: Path, opener=None):
        self.dir = Path(data_dir) / "ea"
        self.file = self.dir / "session.json"
        self._opener = opener

    def _session(self) -> dict:
        try:
            data = json.loads(self.file.read_text(encoding="utf-8"))
        except (OSError, ValueError):
            return {}
        return data if isinstance(data, dict) and data.get("account") is not None else {}

    def _save(self, session: dict):
        self.dir.mkdir(parents=True, exist_ok=True, mode=0o700)
        self.dir.chmod(0o700)
        self.file.write_text(json.dumps(session), encoding="utf-8")
        self.file.chmod(0o600)

    def status(self) -> dict:
        s = self._session()
        return {"id": self.id, "name": self.name, "available": True, "logged_in": bool(s), "account": s.get("account", ""),
                "web_login": True, "token_expired": bool(s) and time.time() >= float(s.get("expiresAt") or 0)}

    def login_url(self) -> str:
        return LOGIN_URL

    def _gql(self, token, query, variables=None):
        data = request_json("POST", GRAPHQL, {"Authorization": "Bearer " + token, "Content-Type": "application/json"},
                            {"query": query, "variables": variables or {}}, opener=self._opener)
        if not isinstance(data, dict) or data.get("errors") or not isinstance(data.get("data"), dict):
            raise StoreError("EA no devolvió los datos de la cuenta.")
        return data["data"]

    def login(self, raw: str) -> dict:
        """Recibe el token (al iniciar sesión o al renovarlo en segundo plano), comprueba la cuenta y guarda la lista."""
        fresh = parse_token(raw)
        try:
            player = ((self._gql(fresh["token"], "query{me{player{displayName}}}").get("me") or {}).get("player") or {})
        except StoreError:
            raise StoreError("EA no aceptó la sesión. Inicia sesión otra vez.")
        games = self._fetch_library(fresh["token"])
        self._save({**fresh, "account": str(player.get("displayName") or "")[:64], "games": games})
        return self.status()

    def logout(self) -> dict:
        self.file.unlink(missing_ok=True)
        return self.status()

    def _fetch_library(self, token) -> list:
        offers, variables = [], {"limit": 100}
        for _ in range(50):                                     # páginas de 100; tope por seguridad
            page = ((self._gql(token, _ENTITLEMENTS, variables).get("me") or {}).get("ownedGameProducts") or {})
            for item in page.get("items") or []:
                product = (item or {}).get("product") or {}
                if ((product.get("baseItem") or {}).get("gameType")) == "BASE_GAME" and _ID.fullmatch(str(item.get("originOfferId") or "")):
                    offers.append(str(item["originOfferId"]))
            variables["next"] = page.get("next")
            if not variables["next"]:
                break
        games = []
        for start in range(0, len(offers), 100):
            data = self._gql(token, _OFFERS, {"offerIds": offers[start:start + 100]})
            products = {p.get("originOfferId"): p for p in ((data.get("gameProducts") or {}).get("items") or []) if isinstance(p, dict)}
            for legacy in data.get("legacyOffers") or []:
                if not isinstance(legacy, dict):
                    continue
                offer, content = str(legacy.get("offerId") or ""), str(legacy.get("contentId") or "")
                product = products.get(offer) or {}
                base = product.get("baseItem") or {}
                if not base.get("title") or not _ID.fullmatch(content or offer):
                    continue
                art = ((base.get("packArt") or {}).get("largestImage") or {}).get("path") or ""
                hero = ((base.get("keyArt") or {}).get("largestImage") or {}).get("path") or ""
                item = {"id": content or offer, "offerId": offer, "title": str(base["title"])[:200], "art": str(art), "installed": False}
                if hero:
                    item["hero"] = str(hero)
                games.append(item)
        return sorted(games, key=lambda g: g["title"].lower())

    def library(self) -> list:
        """La lista guardada; si el token sigue vigente, se vuelve a pedir a EA."""
        s = self._session()
        if not s:
            raise StoreError("Inicia sesión en la EA app para ver tu biblioteca.")
        if time.time() < float(s.get("expiresAt") or 0):
            try:
                s["games"] = self._fetch_library(s["token"])
                self._save(s)
            except StoreError:
                pass
        return [dict(g) for g in s.get("games") or []]

"""Ficha pública de un juego de la biblioteca, con caché por identidad e idioma."""
import hashlib
import json
import threading
import time
from html import unescape
from urllib.parse import urlencode, urlsplit
from urllib.request import HTTPRedirectHandler, Request, build_opener

from . import online_catalog, paths
from .store import load_json, write_json_atomic

_STEAM_HOST = "store.steampowered.com"
_CACHE_AGE = 24 * 3600
_CACHE_LOCK = threading.Lock()


class _NoRedirect(HTTPRedirectHandler):
    def redirect_request(self, req, fp, code, msg, headers, newurl):
        return None


def _steam_details(appid, language):
    url = f"https://{_STEAM_HOST}/api/appdetails?" + urlencode({"appids": appid, "l": language})
    request = Request(url, headers={"Accept": "application/json", "User-Agent": "Omnia/0.3"})
    with build_opener(_NoRedirect()).open(request, timeout=4) as response:
        if urlsplit(response.geturl()).netloc != _STEAM_HOST:
            raise ValueError("Origen inesperado para la ficha de Steam")
        raw = response.read(online_catalog.MAX_RESPONSE + 1)
    if len(raw) > online_catalog.MAX_RESPONSE:
        raise ValueError("Ficha de Steam demasiado grande")
    data = json.loads(raw)[appid].get("data")
    return data if isinstance(data, dict) else {}


def _read_steam(appid, locale):
    for lang in (("latam", "spanish", "english") if locale == "es" else ("english",)):
        try:
            yield lang, _steam_details(appid, lang)
        except (OSError, ValueError, TypeError, KeyError, AttributeError):
            continue


def _text(value, limit=250):
    return " ".join(unescape(value).split())[:limit] if isinstance(value, str) else ""


def _names(value, field=None):
    if not isinstance(value, list):
        return _text(value)
    names = [_text(item.get(field) if field and isinstance(item, dict) else item) for item in value[:12]]
    return ", ".join(filter(None, names))


def _catalog_metadata(raw):
    year = raw.get("releaseYear")
    return {
        "description": _text(raw.get("description"), 1500),
        "release": str(year) if isinstance(year, int) else "",
        "genres": _names(raw.get("genres"), "name"),
        "developer": _names(raw.get("developer")),
        "publisher": _names(raw.get("publisher")),
    }


def _steam_metadata(appid, locale):
    # Steam puede devolver la descripción inglesa aunque localice géneros y fecha.
    variants = dict(_read_steam(appid, locale))
    if not variants:
        return {}, False
    english = _text(variants.get("english", {}).get("short_description"), 1500)
    metadata = next((data for data in variants.values() if data), {})
    description = english if locale == "en" else ""
    if locale == "es" and english:
        for lang in ("latam", "spanish"):
            candidate = _text(variants.get(lang, {}).get("short_description"), 1500)
            if candidate and candidate != english:
                description = candidate
                metadata = variants[lang]
                break
    return {
        "description": description,
        "release": _text((metadata.get("release_date") or {}).get("date")),
        "genres": _names(metadata.get("genres"), "description"),
        "developer": _names(metadata.get("developers")),
        "publisher": _names(metadata.get("publishers")),
    }, bool(metadata) and (locale != "es" or len(variants) == 3)


def game_metadata(game, locale):
    slug = str(game.get("catalogSlug") or "")
    appid = online_catalog.steam_appid(game)
    if not slug and not appid:
        return {}
    key = hashlib.sha256(f"{slug}:{appid}:{locale}".encode()).hexdigest()
    path = paths.cache_dir() / "library-metadata" / (key + ".json")
    cached = load_json(path, {})
    if time.time() - cached.get("updated", 0) < _CACHE_AGE:
        return cached.get("data") or {}
    result = {}

    complete = True
    if slug:
        response = online_catalog.game_detail(slug)
        raw = response.get("data")
        if isinstance(raw, dict):
            result.update({k: v for k, v in _catalog_metadata(raw).items() if v})
        complete = not response.get("offline") and bool(raw)
    if appid:
        steam, ready = _steam_metadata(appid, locale)
        # Prefiere la fecha y los géneros de la ficha localizada cuando existen.
        for key, value in steam.items():
            if value and (key in {"description", "release", "genres"} or not result.get(key)):
                result[key] = value
        complete = complete and ready

    if not complete:
        # Una caída parcial no debe quitar campos ya guardados en el mismo idioma.
        result = {**result, **(cached.get("data") or {})}
    entry = {"data": result, "updated": time.time() if complete else time.time() - _CACHE_AGE + 300}
    try:
        with _CACHE_LOCK:
            write_json_atomic(path, entry, durable=False)
    except OSError:
        pass
    return result

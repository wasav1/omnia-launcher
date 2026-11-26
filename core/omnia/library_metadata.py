"""Ficha pública de un juego de la biblioteca, con caché por identidad e idioma."""
import hashlib
import json
import re
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


def _public_details(host, path, query, *, html=False):
    url = f"https://{host}{path}?" + urlencode(query)
    request = Request(url.rstrip("?"), headers={"Accept": "text/html" if html else "application/json", "User-Agent": "Omnia/0.3"})
    with build_opener(_NoRedirect()).open(request, timeout=4) as response:
        if urlsplit(response.geturl()).netloc != host:
            raise ValueError("Origen inesperado para la ficha de tienda")
        limit = 3_000_000 if html else online_catalog.MAX_RESPONSE
        raw = response.read(limit + 1)
    if len(raw) > limit:
        raise ValueError("Ficha de tienda demasiado grande")
    return raw.decode("utf-8") if html else json.loads(raw)


def _steam_details(appid, language):
    data = _public_details(_STEAM_HOST, "/api/appdetails", {"appids": appid, "l": language})[appid].get("data")
    return data if isinstance(data, dict) else {}


def _read_steam(appid, locale):
    for lang in (("latam", "spanish", "english") if locale == "es" else ("english",)):
        try:
            yield lang, _steam_details(appid, lang)
        except (OSError, ValueError, TypeError, KeyError, AttributeError):
            continue


def _text(value, limit=250):
    return " ".join(unescape(re.sub(r"<[^>]+>", " ", value)).split())[:limit] if isinstance(value, str) else ""


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
    requirements = {}
    for platform in ("linux", "pc", "mac"):
        entries = metadata.get(platform + "_requirements")
        if isinstance(entries, dict):
            requirements[platform] = {level: _text(entries.get(level), 1400) for level in ("minimum", "recommended")}
    date = _text((metadata.get("release_date") or {}).get("date"))
    return {
        "requirements": requirements,
        "description": description,
        "release": date,
        "releaseSource": "steam" if date else "",
        "genres": _names(metadata.get("genres"), "description"),
        "developer": _names(metadata.get("developers")),
        "publisher": _names(metadata.get("publishers")),
    }, bool(metadata) and (locale != "es" or len(variants) == 3)


def gog_requirements(html):
    """Lee los bloques de requisitos por sistema que publica la ficha de GOG."""
    results = {}
    decoder = json.JSONDecoder()
    platforms = {"windows": "pc", "linux": "linux", "osx": "mac", "mac": "mac", "macos": "mac"}
    for match in re.finditer(r'\{"operatingSystem"\s*:\s*\{', html):
        try:
            row, _ = decoder.raw_decode(html, match.start())
        except ValueError:
            continue
        platform = platforms.get(str((row.get("operatingSystem") or {}).get("name", "")).lower())
        if not platform:
            continue
        for item in row.get("systemRequirements") or []:
            level = item.get("type") if isinstance(item, dict) else None
            if level in ("minimum", "recommended"):
                fields = []
                for field in item.get("requirements") or []:
                    if isinstance(field, dict) and field.get("description"):
                        fields.append(" ".join(filter(None, (_text(field.get("name")), _text(field["description"])))))
                value = (" · ".join(fields) or _text(item.get("description"), 1400))[:1400]
                if value:
                    results.setdefault(platform, {})[level] = value
    return results


def _gog_metadata(product, locale):
    raw = _public_details("api.gog.com", "/products/" + product, {
        "expand": "description,downloads", "locale": "es-ES" if locale == "es" else "en-US",
    })
    if not isinstance(raw, dict) or str(raw.get("id")) != product:
        return {}
    description = raw.get("description") or {}
    # El mismo producto puede ofrecer varios instaladores. Solo se muestra el peso
    # si la fuente identifica un instalador completo con un tamaño en bytes.
    downloads = raw.get("downloads") or {}
    installers = [i for i in downloads.get("installers", []) if isinstance(i, dict) and i.get("os") == "windows"]
    chosen = next((i for i in installers if i.get("language") == locale), None)
    if not chosen and len(installers) == 1:
        chosen = installers[0]
    size = (chosen or {}).get("total_size")
    requirements = {}
    slug = str(raw.get("slug") or "")
    if re.fullmatch(r"[a-z0-9_]{1,150}", slug):
        try:
            requirements = gog_requirements(_public_details("www.gog.com", "/en/game/" + slug, {}, html=True))
        except (OSError, TypeError, ValueError, AttributeError):
            pass
    date = _text(raw.get("release_date"), 10)
    return {
        "requirements": requirements,
        "description": _text(description.get("lead") or description.get("full"), 1500),
        "release": date,
        "releaseSource": "gog" if date else "",
        "downloadBytes": size if type(size) is int and size > 0 else 0,
    }


def store_identity(game):
    descriptor = game.get("store_id")
    if isinstance(descriptor, dict):
        return descriptor
    match = re.fullmatch(r"heroic-(legendary|gog|nile)-(.+)", str(game.get("id") or ""))
    if match and game.get("src") == "Heroic":
        return {"store": {"legendary": "epic", "gog": "gog", "nile": "amazon"}[match[1]], "id": match[2]}
    return {}


def game_metadata(game, locale):
    slug = str(game.get("catalogSlug") or "")
    appid = online_catalog.steam_appid(game) or online_catalog.manual_steam_appid(game)
    store_info = store_identity(game) or game.get("detectedIdentity") or {}
    product = str(store_info.get("id") or "")
    source = store_info.get("store")
    gog = product if source == "gog" and re.fullmatch(r"[0-9]{1,12}", product) else ""
    if not slug and not appid and not gog:
        return {}
    key = hashlib.sha256(f"v2:{slug}:{appid}:{gog}:{locale}".encode()).hexdigest()
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
            if value and (key in {"description", "release", "releaseSource", "genres"} or not result.get(key)):
                result[key] = value
        complete = complete and ready

    if gog:
        try:
            metadata = _gog_metadata(gog, locale)
            result.update({key: value for key, value in metadata.items() if value})
            complete = complete and bool(metadata)
        except (OSError, ValueError, TypeError, AttributeError):
            complete = False
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

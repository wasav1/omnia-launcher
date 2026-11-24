"""Cliente de solo lectura del catálogo público de Omnia Backend.

Toda la red pasa por el servicio local de Omnia: QML conserva su origen loopback y no
requiere CORS ni claves del proveedor de artwork. Las respuestas exitosas se guardan
en caché para que Inicio siga teniendo contenido cuando no hay conexión.
"""
from __future__ import annotations

import hashlib
import json
import re
import threading
import time
import urllib.error
import urllib.parse
import urllib.request
from pathlib import Path

from . import paths
from .store import load_json, write_json_atomic

# El Worker aún conserva este nombre por compatibilidad con la infraestructura activa.
# No es una dependencia de RecompLauncher ni una clave: es la URL pública de Omnia API.
BASE_URL = "https://recompihub-backend.wichmann-saenz.workers.dev/api/v1"
PUBLIC_ORIGIN = urllib.parse.urlsplit(BASE_URL).scheme + "://" + urllib.parse.urlsplit(BASE_URL).netloc
TIMEOUT = 8
MAX_RESPONSE = 2 * 1024 * 1024
ROM_IDENTIFIERS_PATH = "/games/rom-identifiers"
ROM_IDENTIFIERS_MAX_RESPONSE = 16 * 1024 * 1024
MAX_AGE = 60 * 60 * 12
_LOCK = threading.RLock()
_SORTS = {"name", "releaseYear", "createdAt", "updatedAt"}
_COMPAT = {"supported", "planned", "unsupported", "none"}


class CatalogError(Exception):
    """El catálogo remoto no está disponible o respondió con datos inválidos."""

    def __init__(self, message: str, code: str = ""):
        super().__init__(message)
        self.code = code


def _response_limit(path: str) -> int:
    return ROM_IDENTIFIERS_MAX_RESPONSE if path == ROM_IDENTIFIERS_PATH else MAX_RESPONSE


def _cache_dir(base: Path | None = None) -> Path:
    return (Path(base) if base else paths.cache_dir()) / "online-catalog"


def _request(path: str, params: dict[str, str] | None = None, opener=None) -> tuple[dict, str | None]:
    if not path.startswith("/") or ".." in path.split("/"):
        raise CatalogError("ruta de catálogo inválida")
    url = BASE_URL + path
    if params:
        url += "?" + urllib.parse.urlencode(params)
    req = urllib.request.Request(url, headers={"Accept": "application/json", "User-Agent": "Omnia/0.3"})
    open_ = opener or urllib.request.urlopen
    try:
        with open_(req, timeout=TIMEOUT) as response:
            response_limit = _response_limit(path)
            raw = response.read(response_limit + 1)
    except (OSError, urllib.error.URLError, TimeoutError) as exc:
        raise CatalogError("No se pudo conectar con el catálogo de Omnia.") from exc
    response_limit = _response_limit(path)
    if len(raw) > response_limit:
        raise CatalogError("La respuesta del catálogo supera el tamaño permitido.")
    try:
        envelope = json.loads(raw)
    except (UnicodeDecodeError, json.JSONDecodeError) as exc:
        raise CatalogError("El catálogo devolvió una respuesta inválida.") from exc
    if not isinstance(envelope, dict) or envelope.get("ok") is not True:
        error = envelope.get("error") if isinstance(envelope, dict) else None
        message = error.get("message") if isinstance(error, dict) else None
        code = str(error.get("code", "")) if isinstance(error, dict) else ""
        raise CatalogError(str(message or "El catálogo no pudo atender la solicitud.")[:240], code)
    data = envelope.get("data")
    meta = envelope.get("meta")
    if not isinstance(data, (dict, list)):
        raise CatalogError("El catálogo devolvió datos incompletos.")
    return {"data": data, "meta": meta if isinstance(meta, dict) else {}}, None


def _cache_key(path: str, params: dict[str, str] | None) -> str:
    raw = json.dumps([path, params or {}], sort_keys=True, separators=(",", ":")).encode()
    return hashlib.sha256(raw).hexdigest()


def _cached(path: str, params: dict[str, str] | None, base: Path | None):
    return load_json(_cache_dir(base) / (_cache_key(path, params) + ".json"), {})


def _get(path: str, params: dict[str, str] | None = None, *, base: Path | None = None, opener=None) -> dict:
    cacheable = not (params or {}).get("q")
    try:
        response, _ = _request(path, params, opener)
        entry = {"saved_at": int(time.time()), **response}
        if cacheable:
            try:
                with _LOCK:
                    write_json_atomic(_cache_dir(base) / (_cache_key(path, params) + ".json"), entry, mode=0o600, durable=False)
            except OSError:
                # Un error de disco no debe ocultar el catálogo que ya respondió correctamente.
                pass
        return {**response, "stale": False, "offline": False}
    except CatalogError as exc:
        if exc.code == "not_found" and path.endswith("/install-packages"):
            return {"data": [], "meta": {}, "stale": False, "offline": False, "unsupported": True,
                    "warning": "Este backend todavía no publica manifiestos de instalación."}
        entry = _cached(path, params if cacheable else {k: v for k, v in (params or {}).items() if k != "q"}, base)
        if isinstance(entry, dict) and isinstance(entry.get("data"), (dict, list)):
            data = entry["data"]
            try:
                saved_at = max(0, int(entry.get("saved_at", 0) or 0))
            except (TypeError, ValueError):
                saved_at = 0
            cache_age = max(0, int(time.time()) - saved_at) if saved_at else None
            if not cacheable and isinstance(data, list):
                query = str((params or {}).get("q", "")).casefold()
                data = [item for item in data if isinstance(item, dict) and query in (str(item.get("name", "")) + " " + str(item.get("description", ""))).casefold()]
            return {"data": data, "meta": entry.get("meta") or {}, "stale": True,
                    "offline": True, "saved_at": saved_at, "cache_age_seconds": cache_age,
                    "cache_expired": cache_age is None or cache_age > MAX_AGE, "warning": str(exc)}
        return {"data": [], "meta": {}, "stale": False, "offline": True, "warning": str(exc)}


def list_games(query: dict | None = None, *, base: Path | None = None, opener=None) -> dict:
    """Lista pública filtrable. La respuesta siempre conserva items/meta y estado de caché."""
    query = query or {}
    try:
        page = max(1, min(100000, int(query.get("page", 1))))
        page_size = max(1, min(30, int(query.get("pageSize", 20))))
    except (TypeError, ValueError):
        page, page_size = 1, 20
    params = {"page": str(page), "pageSize": str(page_size)}
    q = str(query.get("q", "")).strip()[:100]
    platform = str(query.get("platform", "")).strip().lower()
    compatibility = str(query.get("compatibility", "")).strip()
    sort = str(query.get("sort", "updatedAt"))
    order = str(query.get("order", "desc")).lower()
    if q:
        params["q"] = q
    if platform and re.fullmatch(r"[a-z0-9-]{1,40}", platform):
        params["platform"] = platform
    if compatibility in _COMPAT:
        params["compatibility"] = compatibility
    params["sort"] = sort if sort in _SORTS else "updatedAt"
    params["order"] = "asc" if order == "asc" else "desc"
    response = _get("/games", params, base=base, opener=opener)
    items = response.get("data")
    return {**response, "items": items if isinstance(items, list) else []}


def game_detail(slug: str, *, base: Path | None = None, opener=None) -> dict:
    slug = str(slug or "")
    if not re.fullmatch(r"[a-z0-9][a-z0-9-]{0,119}", slug):
        return {"data": {}, "meta": {}, "offline": False, "stale": False, "warning": "Juego no válido.", "ok": False}
    response = _get("/games/" + urllib.parse.quote(slug, safe=""), base=base, opener=opener)
    return {**response, "ok": isinstance(response.get("data"), dict)}


# Plataforma local de Omnia → plataformas del catálogo que pueden describirla. Una ficha de otra plataforma
# (p. ej. Ocarina de N64 frente al remake de Switch 2) no debe asociarse ni aportar su arte.
LOCAL_TO_CATALOG = {
    "n64": {"n64"}, "nes": {"nes"}, "snes": {"snes"}, "gba": {"gba"}, "nds": {"nds"}, "ps1": {"ps1"}, "ps2": {"ps2"},
    "gcwii": {"gamecube", "wii"}, "gamecube": {"gamecube"}, "wii": {"wii"}, "dreamcast": {"dreamcast"}, "xbox": {"xbox"},
    "sw1": {"switch"}, "switch": {"switch"}, "sw2": {"switch2"}, "switch2": {"switch2"}, "pc": {"pc"},
}


def local_platform_for(catalog_platforms) -> str:
    """Plataforma local de Omnia para las plataformas de una ficha del catálogo (la más específica; «pc» si no hay otra)."""
    known = {str(p).lower() for p in (catalog_platforms or []) if p}
    for local in ("sw2", "sw1", "n64", "nes", "snes", "gba", "nds", "ps1", "ps2", "gcwii", "dreamcast", "xbox", "pc"):
        if LOCAL_TO_CATALOG[local] & known:
            return local
    return "pc"


def platform_compatible(local_platform: str, catalog_platforms) -> bool:
    """False solo si ambas plataformas se conocen y no coinciden; con datos incompletos no se bloquea."""
    allowed = LOCAL_TO_CATALOG.get(str(local_platform or "").lower())
    known = {str(p).lower() for p in (catalog_platforms or []) if p}
    return not allowed or not known or bool(allowed & known)


def _name_key(value) -> str:
    return re.sub(r"[^a-z0-9]", "", str(value or "").lower())


_STOP_WORDS = {"the", "of", "a", "an", "and", "usa", "us", "europe", "eu", "japan", "jp", "rev", "v1", "ntsc", "pal"}


def _words(value) -> list:
    """Palabras significativas de un título o nombre de archivo: sin etiquetas entre ( ) o [ ] ni palabras vacías."""
    text = re.sub(r"[\(\[][^)\]]*[\)\]]", " ", str(value or "").lower())
    return [w for w in re.findall(r"[a-z0-9]+", text) if w not in _STOP_WORDS]


def _word_in(word: str, words: list) -> bool:
    """La palabra está en la lista, o es un prefijo/ampliación de otra de más de 4 letras (hasta 2 letras de diferencia)."""
    return any(word == w or (len(word) > 4 and len(w) > 4 and abs(len(word) - len(w)) <= 2 and
                             (word.startswith(w) or w.startswith(word))) for w in words)


def words_match(game_name: str, file_name: str) -> bool:
    """Todas las palabras del juego aparecen en el nombre del archivo y al menos la mitad de las del archivo son del juego."""
    game, rom = _words(game_name), _words(file_name)
    if not game or not rom:
        return False
    if not all(_word_in(w, rom) for w in game):
        return False
    return sum(1 for w in rom if _word_in(w, game)) * 2 >= len(rom)


def match_local_game(game: dict, catalog_items, fuzzy: bool = False) -> str:
    """Slug de la ficha con el mismo nombre y una plataforma que coincide con la del juego; '' si no hay una única.

    Solo se enlaza cuando el juego aún no tiene ficha o la que tiene es de otra plataforma. Exige nombre idéntico y
    plataformas conocidas en ambos lados, y no elige si hay varias candidatas.
    """
    allowed = LOCAL_TO_CATALOG.get(str(game.get("platform") or "").lower())
    if not allowed:
        return ""
    key = _name_key(game.get("name"))
    exact, loose = [], []
    for item in catalog_items or []:
        if not isinstance(item, dict) or not item.get("slug"):
            continue
        plats = {str(p.get("slug", "")).lower() for p in (item.get("platforms") or []) if isinstance(p, dict)}
        if not plats & allowed:
            continue
        if _name_key(item.get("name")) == key:
            exact.append(str(item["slug"]))
        elif fuzzy and words_match(item.get("name"), game.get("name")):
            loose.append(str(item["slug"]))
    for found in (exact, loose):                  # primero el nombre idéntico; las palabras solo si no lo hay
        if len(found) == 1:
            return found[0]
        if found:
            return ""                             # varias candidatas: no se adivina
    return ""


def fetch_entry(slug: str, *, opener=None) -> dict:
    """Plataformas y artwork publicados de una ficha; imageUrl solo se acepta como ruta relativa del backend."""
    response = game_detail(slug, opener=opener)
    data = response.get("data") if isinstance(response.get("data"), dict) else {}
    items = data.get("artwork") if isinstance(data.get("artwork"), list) else []
    out = []
    for item in items:
        if not isinstance(item, dict):
            continue
        kind = str(item.get("type", ""))
        image_path = str(item.get("imageUrl", ""))
        if kind not in {"grid", "hero", "logo", "icon"} or not re.fullmatch(r"/api/v1/artwork/[0-9a-fA-F-]{36}/image", image_path):
            continue
        out.append({"kind": kind, "url": PUBLIC_ORIGIN + image_path, "mimeType": item.get("mimeType")})
    platforms = [str(p.get("slug", "")).lower() for p in (data.get("platforms") or []) if isinstance(p, dict) and p.get("slug")]
    return {"platforms": platforms, "artwork": out}


def fetch_artwork(slug: str, *, opener=None) -> list[dict]:
    return fetch_entry(slug, opener=opener)["artwork"]


_OPTION_KINDS = {"portada": "grid", "fondo": "hero", "logo": "logo"}


def fetch_art_options(slug: str, kind: str, page: int = 0, *, base: Path | None = None, opener=None) -> dict:
    """Una página de opciones de arte de un juego (SteamGridDB, a través del backend de Omnia: la clave no sale de ahí).

    Devuelve {linked, hasMore, items:[{id,url,thumb,width,height,author,style,score}]}; ante un fallo del backend lanza CatalogError."""
    slug = str(slug or "")
    if not re.fullmatch(r"[a-z0-9][a-z0-9-]{0,119}", slug) or kind not in _OPTION_KINDS or not isinstance(page, int) or not 0 <= page <= 20:
        raise CatalogError("Opciones de arte no válidas.")
    response = _get("/games/" + urllib.parse.quote(slug, safe="") + "/artwork/options", {"type": _OPTION_KINDS[kind], "page": str(page)},
                    base=base, opener=opener)
    data = response.get("data")
    if not isinstance(data, dict) or not isinstance(data.get("items"), list):
        raise CatalogError("El backend no devolvió opciones de arte.")
    items = []
    for row in data["items"][:60]:
        if not isinstance(row, dict) or not (_is_option_url(row.get("url")) and _is_option_url(row.get("thumb"))):
            continue
        items.append({key: row.get(key) for key in ("id", "url", "thumb", "width", "height", "author", "style", "score")})
    return {"linked": bool(data.get("linked")), "hasMore": bool(data.get("hasMore")), "items": items,
            "offline": bool(response.get("offline")), "stale": bool(response.get("stale"))}


def _is_option_url(url) -> bool:
    parsed = urllib.parse.urlsplit(url) if isinstance(url, str) else None
    return bool(parsed and parsed.scheme == "https" and not parsed.username and not parsed.fragment and parsed.port in (None, 443) and _is_art_cdn(parsed.hostname))


def download_option_image(url: str, *, opener=None, limit: int = 25 * 1024 * 1024) -> bytes:
    """Descarga la imagen que la persona eligió entre las opciones: solo HTTPS del CDN público de SteamGridDB, sin credenciales ni
    redirecciones a otros orígenes, con límite de tamaño y solo PNG, JPEG o WebP."""
    if not _is_option_url(url):
        raise CatalogError("La imagen no es del CDN permitido.")
    request = urllib.request.Request(url, headers={"Accept": "image/png,image/jpeg,image/webp", "User-Agent": "Omnia/0.3"})
    try:
        with (opener or urllib.request.urlopen)(request, timeout=30) as response:
            if not _is_option_url(response.geturl()):
                raise CatalogError("La imagen se redirigió a otro origen.")
            raw = response.read(limit + 1)
            mime = (response.headers.get("Content-Type") or "").split(";", 1)[0].lower()
    except (OSError, urllib.error.URLError, TimeoutError) as exc:
        raise CatalogError("No se pudo descargar la imagen elegida.") from exc
    if len(raw) > limit or mime not in {"image/png", "image/jpeg", "image/webp"}:
        raise CatalogError("La imagen elegida supera los límites permitidos.")
    return raw


def _is_art_cdn(host) -> bool:
    """El backend redirige las imágenes al CDN público de SteamGridDB (sin clave); no se acepta ningún otro destino."""
    host = str(host or "").lower()
    return host == "steamgriddb.com" or host.endswith(".steamgriddb.com")


STEAM_CDN_HOST = "cdn.cloudflare.steamstatic.com"
_STEAM_FILES = {"portada": "library_600x900.jpg", "fondo": "library_hero.jpg", "logo": "logo.png"}
_STEAM_ART_RE = re.compile(r"https://" + re.escape(STEAM_CDN_HOST) + r"/steam/apps/[0-9]{1,10}/(library_600x900\.jpg|library_hero\.jpg|logo\.png)")


def steam_appid(game) -> str:
    """AppID de un juego detectado en Steam (su id local es «steam-<appid>»); '' si no es de Steam."""
    match = re.fullmatch(r"steam-([0-9]{1,10})", str((game or {}).get("id", "")))
    return match.group(1) if match else ""


def steam_art_urls(game) -> dict:
    """URLs del arte público de Steam (portada, banner y logo) de un juego de Steam; sin claves ni cuentas."""
    appid = steam_appid(game)
    return {kind: f"https://{STEAM_CDN_HOST}/steam/apps/{appid}/{name}" for kind, name in _STEAM_FILES.items()} if appid else {}


# Arte público que Heroic guarda en su caché de la biblioteca (GOG y Epic): solo estas URLs exactas de sus CDN, sin claves ni cuentas.
_STORE_ART_RE = re.compile(
    r"https://images\.gog(?:-statics)?\.com/[0-9a-f]{40,80}(?:\.(?:jpg|jpeg|png|webp))?(?:\?namespace=gamesdb)?"
    r"|https://cdn1\.epicgames\.com/[A-Za-z0-9_./-]{1,200}")
_STORE_ART_KEYS = {"portada": ("art_square", "art_cover"), "fondo": ("art_background", "art_cover")}


def _is_steam_art_url(url) -> bool:
    return isinstance(url, str) and (_STEAM_ART_RE.fullmatch(url) is not None or _STORE_ART_RE.fullmatch(url) is not None)


def store_art_from_heroic(entry) -> dict:
    """{portada, fondo} con las URLs de arte de un juego de la biblioteca de Heroic (GOG/Epic) que son de un CDN admitido.

    `art_square` es la portada vertical; el fondo es `art_background` (GOG) o, si falta, `art_cover` (apaisada)."""
    out = {}
    for kind, keys in _STORE_ART_KEYS.items():
        for key in keys:
            url = (entry or {}).get(key) if isinstance(entry, dict) else None
            if isinstance(url, str) and _STORE_ART_RE.fullmatch(url):
                out[kind] = url
                break
    return out


def game_art_urls(game) -> dict:
    """Todas las URLs públicas de arte que se pueden bajar para un juego: las de Steam y las que Heroic trae de su tienda."""
    urls = dict(steam_art_urls(game))
    remote = ((game or {}).get("art") or {}).get("remote") if isinstance((game or {}).get("art"), dict) else None
    for kind, url in (remote or {}).items() if isinstance(remote, dict) else []:
        if kind in ("portada", "fondo") and isinstance(url, str) and _STORE_ART_RE.fullmatch(url) and kind not in urls:
            urls[kind] = url
    return urls


def download_artwork(url: str, *, opener=None) -> tuple[bytes, str]:
    """Descarga solo una imagen servida por el origen oficial de Omnia, sin reenviar credenciales."""
    parsed = urllib.parse.urlsplit(url)
    steam = _is_steam_art_url(url)
    if not steam and (parsed.scheme != "https" or parsed.netloc != urllib.parse.urlsplit(PUBLIC_ORIGIN).netloc or not parsed.path.startswith("/api/v1/artwork/")):
        raise CatalogError("La URL de imagen no pertenece al backend de Omnia.")
    request = urllib.request.Request(url, headers={"Accept": "image/png,image/jpeg,image/webp", "User-Agent": "Omnia/0.3"})
    try:
        with (opener or urllib.request.urlopen)(request, timeout=TIMEOUT) as response:
            final = urllib.parse.urlsplit(response.geturl())
            if final.scheme != "https" or not (final.netloc == parsed.netloc or (not steam and _is_art_cdn(final.hostname))):
                raise CatalogError("El backend redirigió la imagen a otro origen.")
            raw = response.read(12 * 1024 * 1024 + 1)
            mime = (response.headers.get("Content-Type") or "").split(";", 1)[0].lower()
    except (OSError, urllib.error.URLError, TimeoutError) as exc:
        raise CatalogError("No se pudo descargar el artwork de Omnia.") from exc
    if len(raw) > 12 * 1024 * 1024 or mime not in {"image/png", "image/jpeg", "image/webp"}:
        raise CatalogError("La imagen del backend supera los límites permitidos.")
    return raw, mime


def list_platforms(*, base: Path | None = None, opener=None) -> dict:
    response = _get("/platforms", base=base, opener=opener)
    return {**response, "items": response.get("data") if isinstance(response.get("data"), list) else []}


def list_rom_identifiers(platform: str, *, base: Path | None = None, opener=None) -> dict:
    """Índice público de IDs; se descarga por plataforma y se compara localmente con cabeceras de ROM."""
    platform = str(platform or "").strip().lower()
    if not re.fullmatch(r"[a-z0-9][a-z0-9-]{0,99}", platform):
        return {"items": [], "offline": False, "stale": False, "warning": "Plataforma no válida."}
    response = _get(ROM_IDENTIFIERS_PATH, {"platform": platform}, base=base, opener=opener)
    items = response.get("data")
    return {**response, "items": items if isinstance(items, list) else []}


def list_install_packages(slug: str, *, base: Path | None = None, opener=None) -> dict:
    """Manifiestos públicos aprobados para un juego; no descarga ni ejecuta contenido."""
    slug = str(slug or "")
    if not re.fullmatch(r"[a-z0-9][a-z0-9-]{0,119}", slug):
        return {"items": [], "offline": False, "stale": False, "warning": "Juego no válido."}
    response = _get("/games/" + urllib.parse.quote(slug, safe="") + "/install-packages", base=base, opener=opener)
    items = response.get("data")
    return {**response, "items": items if isinstance(items, list) else []}


def install_package(slug: str, package_id: str, *, opener=None) -> dict | None:
    """Obtiene el manifiesto vigente. No utiliza una copia offline para iniciar instalaciones."""
    if not isinstance(package_id, str) or not re.fullmatch(r"[0-9a-fA-F-]{36}", package_id):
        return None
    response = list_install_packages(slug, opener=opener)
    if response.get("offline"):
        return None
    return next((item for item in response.get("items", []) if isinstance(item, dict) and item.get("id") == package_id), None)


# ---- caché local de artwork: las imágenes se descargan una vez y la interfaz las lee como archivos locales
_EXT = {"image/png": ".png", "image/jpeg": ".jpg", "image/webp": ".webp"}
_ART_LOCK = threading.Lock()
_ART_QUEUE: list[str] = []
_ART_SEEN: dict[str, float] = {}       # url -> instante del último intento (evita reintentos inmediatos)
_ART_WORKER: list[threading.Thread] = []


def art_cache_dir(base: Path | None = None) -> Path:
    return (Path(base) if base else paths.cache_dir()) / "catalog-art"


def _art_stem(url: str) -> str:
    return hashlib.sha256(url.encode("utf-8")).hexdigest()[:40]


def cached_artwork_path(url: str, base: Path | None = None) -> Path | None:
    stem = _art_stem(url)
    folder = art_cache_dir(base)
    for ext in _EXT.values():
        candidate = folder / (stem + ext)
        if candidate.is_file():
            return candidate
    return None


def store_artwork(url: str, *, base: Path | None = None, opener=None) -> Path:
    cached = cached_artwork_path(url, base)
    if cached:
        return cached
    raw, mime = download_artwork(url, opener=opener)
    folder = art_cache_dir(base)
    folder.mkdir(parents=True, exist_ok=True)
    target = folder / (_art_stem(url) + _EXT[mime])
    tmp = target.with_name(target.name + ".part")
    tmp.write_bytes(raw)
    tmp.chmod(0o600)
    tmp.replace(target)
    return target


def _is_art_url(url) -> bool:
    return (isinstance(url, str) and url.startswith(PUBLIC_ORIGIN + "/api/v1/artwork/")) or _is_steam_art_url(url)


def _art_loop():
    while True:
        with _ART_LOCK:
            if not _ART_QUEUE:
                _ART_WORKER.clear()
                return
            url = _ART_QUEUE.pop(0)
        try:
            store_artwork(url)
        except (CatalogError, OSError, KeyError):
            pass


def prefetch_artwork(urls) -> None:
    """Pone en cola, sin bloquear, las imágenes del backend que aún no están en caché (reintento tras 10 min)."""
    now = time.monotonic()
    with _ART_LOCK:
        for url in urls:
            if _is_art_url(url) and url not in _ART_QUEUE and now - _ART_SEEN.get(url, -1e9) > 600 \
                    and not cached_artwork_path(url):
                _ART_SEEN[url] = now
                _ART_QUEUE.append(url)
        if _ART_QUEUE and not _ART_WORKER:
            worker = threading.Thread(target=_art_loop, name="omnia-art-prefetch", daemon=True)
            _ART_WORKER.append(worker)
            worker.start()


def local_or_remote(url: str) -> str:
    """file:// si la imagen ya está en caché; si no, la URL remota y se encola su descarga."""
    local = cached_artwork_path(url) if _is_art_url(url) else None
    if local:
        return "file://" + str(local)
    prefetch_artwork([url])
    return url


def add_local_art(items) -> None:
    """Añade `localUrl` a cada artwork del catálogo que ya esté en caché y encola el resto."""
    for item in items or []:
        if not isinstance(item, dict):
            continue
        for art in item.get("artwork") or []:
            if isinstance(art, dict) and isinstance(art.get("imageUrl"), str) and art["imageUrl"].startswith("/"):
                art["localUrl"] = local_or_remote(PUBLIC_ORIGIN + art["imageUrl"])
                if art["localUrl"].startswith("http"):
                    del art["localUrl"]

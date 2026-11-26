"""Novedades públicas para Explorar, con caché independiente por fuente."""
import gzip
import io
import json
import logging
import re
import threading
import time
from concurrent.futures import ThreadPoolExecutor, as_completed
from html.parser import HTMLParser
from urllib.parse import urlencode, urljoin, urlsplit
from urllib.request import HTTPRedirectHandler, Request, build_opener
from xml.etree import ElementTree

from . import online_catalog, paths
from .store import load_json, write_json_atomic

_LOG = logging.getLogger(__name__)
_SOURCES = {
    "steam": "https://api.steampowered.com/ISteamNews/GetNewsForApp/v2/",
    "gog": "https://www.gog.com/en/frontpage/rss",
    "epic": "https://store.epicgames.com/en-US/news",
    "amazon": "https://www.amazongamestudios.com/en-us/news",
}
_SPANISH = {
    "amazon": "https://www.amazongamestudios.com/es-es/news",
}
_EPIC_CONTENT = "https://store-content.ak.epicgames.com/api/{locale}/content/blog"
_LONGSHOT = "https://git.magicbean.dev/MagicBeanDev/Longshot"
_LONGSHOT_SLUG = "the-legend-of-zelda-ocarina-of-time-switch-2"
_PER_SOURCE = 4
_CACHE_TTL = 30 * 60
_RETRY_DELAY = 5 * 60
_LIMIT = 4 * 1024 * 1024


class _SameHostRedirect(HTTPRedirectHandler):
    def redirect_request(self, req, fp, code, msg, headers, newurl):
        if not _trusted(newurl, urlsplit(req.full_url).hostname):
            raise ValueError("Redirección de noticias fuera del origen")
        return super().redirect_request(req, fp, code, msg, headers, newurl)


def _trusted(url, host):
    parsed = urlsplit(url)
    return parsed.scheme == "https" and parsed.netloc == host


def _fetch(url):
    request = Request(url, headers={"User-Agent": "Omnia/0.3"})
    with build_opener(_SameHostRedirect()).open(request, timeout=5) as response:
        raw = response.read(_LIMIT + 1)
    if raw.startswith(b"\x1f\x8b"):
        with gzip.GzipFile(fileobj=io.BytesIO(raw)) as stream:
            raw = stream.read(_LIMIT + 1)
    if len(raw) > _LIMIT:
        raise ValueError("Respuesta de noticias demasiado grande")
    return raw


def _row(source, title, url, **extra):
    return {"source": source, "title": " ".join(title.split())[:240], "url": url, **extra}


class _Articles(HTMLParser):
    """Lee enlaces a artículos con su título visible o accesible."""
    def __init__(self, source, base=None):
        super().__init__()
        self.source = source
        self.base = base or _SOURCES[source]
        self.host = urlsplit(self.base).hostname
        self.active = None
        self.items = {}

    def handle_starttag(self, tag, attrs):
        if self.active and tag == "img":
            image = dict(attrs)
            if image.get("src"):
                self.active[3].setdefault("artwork", urljoin(self.base, image["src"]))
        if tag != "a":
            return
        self.active = None
        attributes = dict(attrs)
        href = attributes.get("href") or ""
        url = urljoin(self.base, href)
        pattern = (r"/[a-z]{2}-[a-z]{2}/news/articles/[^/]+/?" if self.source == "amazon" else r"/(?:[a-z]{2}(?:-[A-Za-z]{2})?/)?news/[^/]+/?")
        if _trusted(url, self.host) and re.fullmatch(pattern, urlsplit(url).path):
            self.active = (url.split("?", 1)[0].split("#", 1)[0], attributes.get("aria-label") or "", [], {})

    def handle_data(self, data):
        if self.active:
            self.active[2].append(data)

    def handle_endtag(self, tag):
        if tag != "a" or not self.active:
            return
        url, label, chunks, extra = self.active
        self.active = None
        title = " ".join((label or " ".join(chunks)).split())
        title = re.sub(r"\s*(?:Read more|Leer más)\s*$", "", title, flags=re.IGNORECASE)
        if title and title.casefold() not in {"news", "noticias"}:
            self.items.setdefault(url, _row(self.source, title, url, **extra))


class _ArticleMetadata(HTMLParser):
    def __init__(self):
        super().__init__()
        self.properties = {}
        self.language = ""

    def handle_starttag(self, tag, attrs):
        values = dict(attrs)
        if tag == "html":
            self.language = values.get("lang") or ""
        if tag == "meta":
            name = values.get("property") or values.get("name")
            if name and values.get("content"):
                self.properties.setdefault(name, values["content"])


def _enrich(item, language):
    # Read article metadata only on the same source, and only for the handful of stories shown.
    url = item["url"]
    try:
        parser = _ArticleMetadata()
        parser.feed(_fetch(url).decode("utf-8", errors="replace"))
    except (OSError, ValueError):
        return item
    props = parser.properties
    original = parser.language or props.get("og:locale", "")
    localized = original.lower().startswith(("es-", "es_", "es")) if original else False
    title = props.get("og:title")
    article_title = bool(title and title.strip() and not title.startswith("Steam :: "))
    if localized and article_title or language == "en":
        if article_title:
            item["title"] = " ".join(title.split())[:240]
        description = props.get("og:description") or props.get("description")
        if description:
            item["summary"] = " ".join(description.split())[:280]
    if localized and article_title:
        item["originalLanguage"] = "es"
    for image in (props.get("og:image"), props.get("twitter:image"), item.get("artwork")):
        if image:
            art = urljoin(url, image)
            if online_catalog.is_news_art(art):
                item["artwork"] = art
                break
    return item


def _epic_news(language):
    locale = "es-ES" if language == "es" else "en-US"
    data = json.loads(_fetch(_EPIC_CONTENT.format(locale=locale)))
    if not isinstance(data, list):
        return []
    ordered = sorted((row for row in data if isinstance(row, dict)),
                     key=lambda row: str(row.get("date") or ""), reverse=True)
    items = []
    for row in ordered:
        slug, title = row.get("slug"), row.get("title")
        if not isinstance(slug, str) or not re.fullmatch(r"[a-z0-9-]{1,180}", slug):
            continue
        if not isinstance(title, str) or not title.strip():
            continue
        metadata = _ArticleMetadata()
        metadata.feed(str(row.get("_metaTags") or ""))
        original = str(row.get("_locale") or locale).split("-", 1)[0].lower()
        assets = row.get("_images_") or []
        options = [metadata.properties.get("og:image"), row.get("trendingImage"),
                   *(assets if isinstance(assets, list) else [])]
        image = next((url for url in options if online_catalog.is_news_art(url)), "")
        items.append(_row("epic", title, f"https://store.epicgames.com/{locale}/news/{slug}",
                          originalLanguage=original, artwork=image,
                          summary=metadata.properties.get("description", "")[:280]))
        if len(items) == _PER_SOURCE:
            break
    return items


def _public_news(source, language="en"):
    if source == "epic":
        return _epic_news(language)
    base = _SPANISH.get(source, _SOURCES[source]) if language == "es" else _SOURCES[source]
    raw = _fetch(base)
    if source != "gog":
        parser = _Articles(source, base)
        parser.feed(raw.decode("utf-8", errors="replace"))
        items = list(parser.items.values())
    else:
        if re.search(rb"<!\s*(?:DOCTYPE|ENTITY)", raw, re.IGNORECASE):
            raise ValueError("Declaración XML inesperada")
        items = []
        for item in ElementTree.fromstring(raw).findall("./channel/item"):
            title = item.findtext("title", "").strip()
            url = item.findtext("link", "").strip()
            if url.startswith("http://"):
                url = "https://" + url[7:]
            if title and _trusted(url, "www.gog.com"):
                enclosure = item.find("enclosure")
                art = enclosure.get("url", "") if enclosure is not None else ""
                items.append(_row("gog", title, url, artwork=art))
    for item in items[:_PER_SOURCE]:
        item["originalLanguage"] = "es" if base == _SPANISH.get(source) else "en"
        _enrich(item, language)
        if source == "gog" and language == "es" and item.get("originalLanguage") == "en":
            for prefix, translated in (("Coming soon: ", "Próximamente: "), ("Release: ", "Lanzamiento: ")):
                if item["title"].startswith(prefix):
                    item["title"] = translated + item["title"][len(prefix):]
                    item["originalLanguage"] = "es"
                    break
    return items[:_PER_SOURCE]


def _steam_news(game, language="en"):
    appid = online_catalog.steam_appid(game)
    query = urlencode({"appid": appid, "count": 3, "maxlength": 240,
                       "feeds": "steam_community_announcements"})
    data = json.loads(_fetch(_SOURCES["steam"] + "?" + query))
    hero = online_catalog.steam_art_urls(game).get("fondo", "")
    items = []
    for post in data["appnews"]["newsitems"]:
        if post.get("feedname") != "steam_community_announcements":
            continue
        gid = str(post.get("gid", ""))
        title = post.get("title")
        if isinstance(title, str) and title.strip() and re.fullmatch(r"[0-9]{1,25}", gid):
            url = f"https://steamcommunity.com/games/{appid}/announcements/detail/{gid}"
            contents = post.get("contents") or ""
            image = re.search(r"\[img\]([^\[\s]+)\[/img\]", contents, re.IGNORECASE)
            proposed = image[1].replace("{STEAM_CLAN_IMAGE}/", "https://clan.cloudflare.steamstatic.com/images/", 1) if image else ""
            art = proposed if online_catalog.is_news_art(proposed) else hero
            items.append(_row("steam", title, url, game=game["name"],
                              date=int(post.get("date") or 0), artwork=art, originalLanguage="en"))
    return items


def _read_source(source, steam_games, language):
    if source == "omnia":
        try:
            rows = json.loads(_fetch("https://git.magicbean.dev/api/v1/repos/MagicBeanDev/Longshot/releases?limit=8"))
            release = next((row for row in rows if isinstance(row, dict) and not row.get("draft") and not row.get("prerelease")), {})
            return [_featured(language, release.get("tag_name"))]
        except (OSError, ValueError, TypeError):
            return [_featured(language)]
    if source != "steam":
        return _public_news(source, language)
    items = []
    for game in steam_games:
        try:
            items.extend(_steam_news(game, language))
        except (OSError, ValueError, KeyError, TypeError) as exc:
            _LOG.debug("Novedades de Steam: %s", exc)
    latest = sorted(items, key=lambda item: item["date"], reverse=True)[:_PER_SOURCE]
    if language == "es":
        for item in latest:
            item["url"] += "?l=latam"
            _enrich(item, language)
    return latest


def _featured(language, tag=None):
    title = "The Legend of Zelda: Ocarina of Time — Longshot"
    if isinstance(tag, str) and re.fullmatch(r"[A-Za-z0-9._-]{1,40}", tag):
        title += " " + tag
    summary = ("Conoce el port nativo de Ocarina of Time para Linux. Requiere tu propia copia del juego."
               if language == "es" else
               "Explore the native Linux port of Ocarina of Time. It requires your own copy of the game.")
    return _row("omnia", title, _LONGSHOT + "/releases", slug=_LONGSHOT_SLUG,
                summary=summary, originalLanguage=language)


class StoreNews:
    def __init__(self):
        self._lock = threading.Lock()
        self._running = False
        self._path = paths.cache_dir() / "news-v2.json"
        cached = load_json(self._path, {})
        self._cache = cached if isinstance(cached, dict) else {}
        self._tried = {}

    def snapshot(self, games, language="es"):
        language = "en" if language == "en" else "es"
        sources_in_order = ("omnia", *_SOURCES)
        steam_games = []
        seen = set()
        for game in games:
            appid = online_catalog.steam_appid(game)
            if appid and appid not in seen:
                steam_games.append(game)
                seen.add(appid)
        steam_games = steam_games[:8]
        signature = sorted(online_catalog.steam_appid(game) for game in steam_games)
        now = time.time()
        with self._lock:
            cache = self._cache.setdefault(language, {})
            steam_changed = cache.get("steam", {}).get("appids", []) != signature
            sources = [
                source for source in sources_in_order if (source != "steam" or steam_games)
                and now - self._tried.get((language, source), 0) >= _RETRY_DELAY
                and (now - cache.get(source, {}).get("updated", 0) >= _CACHE_TTL
                     or (source == "steam" and steam_changed))
            ]
            if sources and not self._running:
                self._running = True
                self._tried.update({(language, source): now for source in sources})
                threading.Thread(target=self._refresh, args=(sources, steam_games, signature, language),
                                 name="omnia-store-news", daemon=True).start()
            batches = [cache.get(source, {}).get("items", [])
                       for source in sources_in_order if source != "steam" or (steam_games and not steam_changed)]
            if not batches[0]:
                batches[0] = [_featured(language)]
            loading = self._running
        items = [dict(batch[i]) for i in range(_PER_SOURCE) for batch in batches if i < len(batch)]
        for item in items:
            art = item.get("artwork", "")
            item["artwork"] = online_catalog.local_or_remote(art, news=True) if online_catalog._is_art_url(art, news=True) else ""
        return {"items": items, "loading": loading}

    def _refresh(self, sources, steam_games, signature, language):
        try:
            with ThreadPoolExecutor(max_workers=5) as pool:
                futures = {pool.submit(_read_source, source, steam_games, language): source for source in sources}
                for future in as_completed(futures):
                    source = futures[future]
                    try:
                        items = future.result()
                        if source == "omnia" and items:
                            response = online_catalog.game_detail(_LONGSHOT_SLUG)
                            artwork = (response.get("data") or {}).get("artwork") or []
                            for image in artwork:
                                url = urljoin(online_catalog.PUBLIC_ORIGIN, image.get("imageUrl") or "")
                                if image.get("type") == "hero" and online_catalog._is_art_url(url):
                                    items[0]["artwork"] = url
                                    break
                        if items:
                            with self._lock:
                                row = {"items": items, "updated": time.time()}
                                if source == "steam":
                                    row["appids"] = signature
                                self._cache[language][source] = row
                    except (OSError, ValueError, TypeError, AttributeError, online_catalog.CatalogError, ElementTree.ParseError) as exc:
                        _LOG.debug("Novedades de %s: %s", source, exc)
                paths.ensure(self._path.parent)
                write_json_atomic(self._path, self._cache)
        except OSError as exc:
            _LOG.debug("Caché de novedades: %s", exc)
        finally:
            with self._lock:
                self._running = False

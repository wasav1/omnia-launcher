"""Novedades públicas para Explorar, con caché independiente por fuente."""
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
    if len(raw) > _LIMIT:
        raise ValueError("Respuesta de noticias demasiado grande")
    return raw


def _row(source, title, url, **extra):
    return {"source": source, "title": " ".join(title.split())[:240], "url": url, **extra}


class _Articles(HTMLParser):
    """Lee enlaces a artículos con su título visible o accesible."""
    def __init__(self, source):
        super().__init__()
        self.source = source
        self.base = _SOURCES[source]
        self.host = urlsplit(self.base).hostname
        self.active = None
        self.items = {}

    def handle_starttag(self, tag, attrs):
        if tag != "a":
            return
        self.active = None
        attributes = dict(attrs)
        href = attributes.get("href") or ""
        url = urljoin(self.base, href)
        pattern = (r"/[a-z]{2}-[a-z]{2}/news/articles/[^/]+/?" if self.source == "amazon" else r"/(?:[a-z]{2}(?:-[A-Za-z]{2})?/)?news/[^/]+/?")
        if _trusted(url, self.host) and re.fullmatch(pattern, urlsplit(url).path):
            self.active = (url.split("?", 1)[0].split("#", 1)[0], attributes.get("aria-label") or "", [])

    def handle_data(self, data):
        if self.active:
            self.active[2].append(data)

    def handle_endtag(self, tag):
        if tag != "a" or not self.active:
            return
        url, label, chunks = self.active
        self.active = None
        title = " ".join((label or " ".join(chunks)).split())
        title = re.sub(r"\s*(?:Read more|Leer más)\s*$", "", title, flags=re.IGNORECASE)
        if title and title.casefold() not in {"news", "noticias"}:
            self.items.setdefault(url, _row(self.source, title, url))


def _public_news(source):
    raw = _fetch(_SOURCES[source])
    if source != "gog":
        parser = _Articles(source)
        parser.feed(raw.decode("utf-8", errors="replace"))
        return list(parser.items.values())[:8]
    if re.search(rb"<!\s*(?:DOCTYPE|ENTITY)", raw, re.IGNORECASE):
        raise ValueError("Declaración XML inesperada")
    items = []
    for item in ElementTree.fromstring(raw).findall("./channel/item"):
        title = item.findtext("title", "").strip()
        url = item.findtext("link", "").strip()
        if url.startswith("http://"):
            url = "https://" + url[7:]
        if title and _trusted(url, "www.gog.com"):
            items.append(_row("gog", title, url))
    return items[:8]


def _steam_news(game):
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
            items.append(_row("steam", title, url, game=game["name"],
                              date=int(post.get("date") or 0), artwork=hero))
    return items


def _read_source(source, steam_games):
    if source != "steam":
        return _public_news(source)
    items = []
    for game in steam_games:
        try:
            items.extend(_steam_news(game))
        except (OSError, ValueError, KeyError, TypeError) as exc:
            _LOG.debug("Novedades de Steam: %s", exc)
    return sorted(items, key=lambda item: item["date"], reverse=True)[:8]


class StoreNews:
    def __init__(self):
        self._lock = threading.Lock()
        self._running = False
        self._path = paths.cache_dir() / "store-news.json"
        cached = load_json(self._path, {})
        self._cache = cached if isinstance(cached, dict) else {}
        self._tried = {}

    def snapshot(self, games):
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
            steam_changed = self._cache.get("steam", {}).get("appids", []) != signature
            sources = [
                source for source in _SOURCES
                if (source != "steam" or steam_games)
                and now - self._tried.get(source, 0) >= _RETRY_DELAY
                and (now - self._cache.get(source, {}).get("updated", 0) >= _CACHE_TTL
                     or (source == "steam" and steam_changed))
            ]
            if sources and not self._running:
                self._running = True
                self._tried.update(dict.fromkeys(sources, now))
                threading.Thread(target=self._refresh, args=(sources, steam_games, signature),
                                 name="omnia-store-news", daemon=True).start()
            batches = [self._cache.get(source, {}).get("items", []) for source in _SOURCES
                       if source != "steam" or (steam_games and not steam_changed)]
            loading = self._running
        # Alterna fuentes para que una tienda con mucha actividad no llene el carrusel.
        items = [dict(batch[i]) for i in range(8) for batch in batches if i < len(batch)]
        for item in items:
            art = item.get("artwork", "")
            if art:
                item["artwork"] = online_catalog.local_or_remote(art)
        return {"items": items, "loading": loading}

    def _refresh(self, sources, steam_games, signature):
        try:
            with ThreadPoolExecutor(max_workers=4) as pool:
                futures = {pool.submit(_read_source, source, steam_games): source for source in sources}
                for future in as_completed(futures):
                    source = futures[future]
                    try:
                        items = future.result()
                        if items:
                            with self._lock:
                                row = {"items": items, "updated": time.time()}
                                if source == "steam":
                                    row["appids"] = signature
                                self._cache[source] = row
                    except (OSError, ValueError, ElementTree.ParseError) as exc:
                        _LOG.debug("Novedades de %s: %s", source, exc)
                paths.ensure(self._path.parent)
                write_json_atomic(self._path, self._cache)
        except OSError as exc:
            _LOG.debug("Caché de novedades: %s", exc)
        finally:
            with self._lock:
                self._running = False

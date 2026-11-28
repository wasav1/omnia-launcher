"""Ofertas, juegos gratis y lanzamientos de las tiendas para el Inicio (rediseño D, fase 4).

Fuentes públicas, sin cuenta y solo de lectura:
  Steam  featuredcategories → «specials» (ofertas; las de precio 0 cuentan como gratis) y «new_releases».
  Epic   freeGamesPromotions → gratis ahora y próximamente gratis.
  GOG    catálogo con descuento → ofertas (las de -100 % cuentan como gratis).

Cada fuente tiene su propia caché (30 min, reintento a los 5 min) que se refresca en segundo plano: la
respuesta nunca espera a la red. Solo biblioteca estándar.
"""
import json
import logging
import re
import threading
import time
from concurrent.futures import ThreadPoolExecutor, as_completed
from datetime import datetime
from urllib.parse import urlencode, urlsplit

from . import online_catalog, paths
from .store import load_json, write_json_atomic
from .store_news import _fetch

_LOG = logging.getLogger(__name__)
SOURCES = ("steam", "epic", "gog")
KINDS = ("deal", "free", "upcoming", "release")
_PER_KIND = 12
_CACHE_TTL = 30 * 60
_RETRY_DELAY = 5 * 60
_REGION = {"es": ("co", "es-ES", "spanish", "CO"), "en": ("us", "en-US", "english", "US")}


def _money(amount, currency, language="es"):
    """Precio legible: 59700 COP → «$ 59.700»; 4.99 USD → «US$ 4,99» (es) o «US$ 4.99» (en)."""
    try:
        value = float(amount)
    except (TypeError, ValueError):
        return ""
    if value <= 0:
        return ""
    if currency in ("COP", "CLP", "JPY", "KRW"):
        return "$ " + f"{round(value):,}".replace(",", ".")
    symbol = {"USD": "US$", "EUR": "€", "MXN": "MX$", "ARS": "AR$", "BRL": "R$"}.get(currency, (currency or "") + " ")
    text = f"{value:,.2f}"
    if language == "es":
        text = text.replace(",", " ").replace(".", ",").replace(" ", ".")
    return symbol.strip() + " " + text


def _item(source, kind, title, url, **extra):
    title = " ".join(str(title or "").split())[:200]
    return {"source": source, "kind": kind, "title": title, "url": url, **extra}


def _trusted_url(url, hosts):
    try:
        parsed = urlsplit(url)
    except ValueError:
        return False
    return parsed.scheme == "https" and parsed.netloc in hosts


def _steam(language):
    cc, _, steam_lang, _ = _REGION[language]
    data = json.loads(_fetch("https://store.steampowered.com/api/featuredcategories?" + urlencode({"cc": cc, "l": steam_lang})))
    out = []
    seen = set()
    for key, kind in (("specials", "deal"), ("new_releases", "release")):
        for row in (data.get(key) or {}).get("items") or []:
            if not isinstance(row, dict) or row.get("type") not in (0, None):
                continue
            appid = row.get("id")
            if not isinstance(appid, int) or appid in seen or not row.get("name"):
                continue
            seen.add(appid)
            currency = str(row.get("currency") or "")
            final = (row.get("final_price") or 0) / 100
            original = (row.get("original_price") or 0) / 100
            discount = int(row.get("discount_percent") or 0)
            item_kind = kind
            if kind == "deal" and row.get("discounted") and final == 0:
                item_kind = "free"
            art = row.get("large_capsule_image") or row.get("header_image") or ""
            out.append(_item("steam", item_kind, row["name"], f"https://store.steampowered.com/app/{appid}/",
                             artwork=art if online_catalog.is_news_art(art) else "",
                             discount=discount if row.get("discounted") else 0,
                             price=_money(final, currency, language), originalPrice=_money(original, currency, language) if discount else "",
                             endsAt=int(row.get("discount_expiration") or 0), linux=bool(row.get("linux_available")),
                             appid=appid))
    return out


def _epic_date(text):
    try:
        return int(datetime.fromisoformat(str(text).replace("Z", "+00:00")).timestamp())
    except ValueError:
        return 0


def _epic(language):
    _, locale, _, country = _REGION[language]
    data = json.loads(_fetch("https://store-site-backend-static-ipv4.ak.epicgames.com/freeGamesPromotions?"
                             + urlencode({"locale": locale, "country": country, "allowCountries": country})))
    elements = (((data.get("data") or {}).get("Catalog") or {}).get("searchStore") or {}).get("elements") or []
    out = []
    for row in elements:
        if not isinstance(row, dict) or not row.get("title"):
            continue
        promos = row.get("promotions") or {}
        now = [o for group in promos.get("promotionalOffers") or [] for o in group.get("promotionalOffers") or []]
        upcoming = [o for group in promos.get("upcomingPromotionalOffers") or [] for o in group.get("promotionalOffers") or []]
        # discountPercentage 0 = el precio queda en 0: es una promoción de juego gratis
        free_now = [o for o in now if (o.get("discountSetting") or {}).get("discountPercentage") == 0]
        free_next = [o for o in upcoming if (o.get("discountSetting") or {}).get("discountPercentage") == 0]
        if not free_now and not free_next:
            continue
        offer = (free_now or free_next)[0]
        slug = row.get("productSlug") or next((m.get("pageSlug") for m in ((row.get("catalogNs") or {}).get("mappings") or [])
                                               + (row.get("offerMappings") or []) if m.get("pageSlug")), "")
        slug = str(slug or "").split("/")[0]
        if not re.fullmatch(r"[A-Za-z0-9-]{1,160}", slug):
            continue
        images = {i.get("type"): i.get("url") for i in row.get("keyImages") or [] if isinstance(i, dict)}
        art = images.get("OfferImageWide") or images.get("DieselStoreFrontWide") or images.get("Thumbnail") or ""
        price = ((row.get("price") or {}).get("totalPrice") or {}).get("fmtPrice") or {}
        out.append(_item("epic", "free" if free_now else "upcoming", row["title"],
                         f"https://store.epicgames.com/{locale}/p/{slug}",
                         artwork=art if online_catalog.is_news_art(art) else "",
                         discount=100, price="", originalPrice=str(price.get("originalPrice") or "").replace("\xa0", " ")
                         if price.get("originalPrice") not in (None, "0") else "",
                         startsAt=_epic_date(offer.get("startDate")), endsAt=_epic_date(offer.get("endDate"))))
    return out


def _gog(language):
    _, locale, _, country = _REGION[language]
    data = json.loads(_fetch("https://catalog.gog.com/v1/catalog?" + urlencode({
        "limit": 24, "order": "desc:trending", "discounted": "eq:true", "productType": "in:game,pack",
        "countryCode": country, "locale": locale, "currencyCode": "USD"})))
    out = []
    for row in data.get("products") or []:
        if not isinstance(row, dict) or not row.get("title"):
            continue
        url = row.get("storeLink") or ""
        if not _trusted_url(url, {"www.gog.com"}):
            continue
        price = row.get("price") or {}
        match = re.search(r"(\d+)", str(price.get("discount") or ""))
        discount = int(match.group(1)) if match else 0
        final = (price.get("finalMoney") or {}).get("amount")
        base = (price.get("baseMoney") or {}).get("amount")
        art = row.get("coverHorizontal") or ""
        out.append(_item("gog", "free" if discount >= 100 else "deal", row["title"], url,
                         artwork=art if online_catalog.is_news_art(art) else "",
                         discount=discount, price=_money(final, "USD", language), originalPrice=_money(base, "USD", language), endsAt=0))
    return out


_READERS = {"steam": _steam, "epic": _epic, "gog": _gog}


class StoreDeals:
    def __init__(self, readers=None, cache_path=None):
        self._lock = threading.Lock()
        self._running = False
        self._readers = readers or _READERS
        self._path = cache_path or (paths.cache_dir() / "store-deals.json")
        cached = load_json(self._path, {})
        self._cache = cached if isinstance(cached, dict) else {}
        self._tried = {}

    def snapshot(self, language="es", stores=None, wait=False):
        """{items, loading, updated}. `stores` limita las fuentes (Ajustes → Novedades)."""
        language = "en" if language == "en" else "es"
        wanted = [s for s in SOURCES if stores is None or s in stores]
        now = time.time()
        with self._lock:
            cache = self._cache.setdefault(language, {})
            due = [s for s in wanted
                   if now - self._tried.get((language, s), 0) >= _RETRY_DELAY
                   and now - cache.get(s, {}).get("updated", 0) >= _CACHE_TTL]
            start = bool(due) and not self._running
            if start:
                self._running = True
                self._tried.update({(language, s): now for s in due})
        if start:
            if wait:
                self._refresh(due, language)
            else:
                threading.Thread(target=self._refresh, args=(due, language), name="omnia-store-deals", daemon=True).start()
        with self._lock:
            cache = self._cache.get(language, {})
            items, updated = [], 0
            for source in wanted:
                row = cache.get(source) or {}
                updated = max(updated, row.get("updated", 0))
                for kind in KINDS:
                    items += [dict(i) for i in row.get("items", []) if i.get("kind") == kind][:_PER_KIND]
            loading = self._running
        for item in items:
            art = item.get("artwork", "")
            item["artwork"] = online_catalog.local_or_remote(art, news=True) if online_catalog._is_art_url(art, news=True) else ""
        return {"items": items, "loading": loading, "updated": int(updated)}

    def _refresh(self, sources, language):
        try:
            with ThreadPoolExecutor(max_workers=3) as pool:
                futures = {pool.submit(self._readers[s], language): s for s in sources}
                for future in as_completed(futures):
                    source = futures[future]
                    try:
                        items = future.result()
                        if items:
                            with self._lock:
                                self._cache.setdefault(language, {})[source] = {"items": items, "updated": time.time()}
                    except (OSError, ValueError, TypeError, AttributeError, KeyError) as exc:
                        _LOG.debug("Ofertas de %s: %s", source, exc)
            paths.ensure(self._path.parent)
            with self._lock:
                write_json_atomic(self._path, self._cache)
        except OSError as exc:
            _LOG.debug("Caché de ofertas: %s", exc)
        finally:
            with self._lock:
                self._running = False

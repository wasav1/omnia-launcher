"""Ofertas, juegos gratis y lanzamientos de las tiendas para el Inicio (rediseño D, fase 4).

Fuentes públicas, sin cuenta y solo de lectura:
  Steam  featuredcategories → «specials» (ofertas; las de precio 0 cuentan como gratis) y «new_releases».
  Epic   freeGamesPromotions → gratis ahora y próximamente gratis.
  GOG    catálogo con descuento → ofertas (las de -100 % cuentan como gratis).

Cada fuente tiene su propia caché (30 min, reintento a los 5 min) que se refresca en segundo plano: la
respuesta nunca espera a la red. Solo biblioteca estándar.

Precios (entrega 5): a cada tienda se le piden los de la región de la moneda elegida (Steam: el país; Epic: el país;
GOG: el país y la moneda si la tiene). Se guardan como valor + moneda y se dan formateados al responder: en la moneda
elegida tal cual, o convertidos con el tipo de cambio del día y marcados con «≈».
"""
import json
import logging
import re
import threading
import time
from concurrent.futures import ThreadPoolExecutor, as_completed
from datetime import datetime
from urllib.parse import urlencode, urlsplit

from . import currency, online_catalog, paths
from .store import load_json, write_json_atomic
from .store_news import _fetch

_LOG = logging.getLogger(__name__)
SOURCES = ("steam", "epic", "gog")
KINDS = ("deal", "free", "upcoming", "release")
_PER_KIND = 12
_CACHE_TTL = 30 * 60
_RETRY_DELAY = 5 * 60
_LOCALE = {"es": ("es-ES", "spanish"), "en": ("en-US", "english")}
_GOG_CURRENCIES = {"USD", "EUR", "GBP", "AUD", "CAD", "CHF", "PLN", "BRL", "SEK", "NOK", "DKK", "CZK", "NZD", "RUB", "TRY", "CNY"}


def _amount(value, decimals=2):
    try:
        number = float(value) / (10 ** decimals)
    except (TypeError, ValueError):
        return 0
    return number if number > 0 else 0


def _item(source, kind, title, url, **extra):
    title = " ".join(str(title or "").split())[:200]
    return {"source": source, "kind": kind, "title": title, "url": url, **extra}


def _trusted_url(url, hosts):
    try:
        parsed = urlsplit(url)
    except ValueError:
        return False
    return parsed.scheme == "https" and parsed.netloc in hosts


def _steam(language, wanted="USD"):
    steam_lang = _LOCALE[language][1]
    cc = currency.country(wanted).lower()
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
            code = str(row.get("currency") or "")
            final = _amount(row.get("final_price"), 2)
            original = _amount(row.get("original_price"), 2)
            discount = int(row.get("discount_percent") or 0)
            item_kind = kind
            if kind == "deal" and row.get("discounted") and final == 0:
                item_kind = "free"
            art = row.get("large_capsule_image") or row.get("header_image") or ""
            out.append(_item("steam", item_kind, row["name"], f"https://store.steampowered.com/app/{appid}/",
                             artwork=art if online_catalog.is_news_art(art) else "",
                             discount=discount if row.get("discounted") else 0,
                             priceValue=final, originalValue=original if discount else 0, currency=code,
                             endsAt=int(row.get("discount_expiration") or 0), linux=bool(row.get("linux_available")),
                             appid=appid))
    return out


def _epic_date(text):
    try:
        return int(datetime.fromisoformat(str(text).replace("Z", "+00:00")).timestamp())
    except ValueError:
        return 0


def _epic(language, wanted="USD"):
    locale = _LOCALE[language][0]
    country = currency.country(wanted)
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
        total = (row.get("price") or {}).get("totalPrice") or {}
        decimals = (total.get("currencyInfo") or {}).get("decimals")
        out.append(_item("epic", "free" if free_now else "upcoming", row["title"],
                         f"https://store.epicgames.com/{locale}/p/{slug}",
                         artwork=art if online_catalog.is_news_art(art) else "",
                         discount=100, priceValue=0, originalValue=_amount(total.get("originalPrice"), decimals if isinstance(decimals, int) else 2),
                         currency=str(total.get("currencyCode") or ""),
                         startsAt=_epic_date(offer.get("startDate")), endsAt=_epic_date(offer.get("endDate"))))
    return out


def _gog(language, wanted="USD"):
    locale = _LOCALE[language][0]
    country = currency.country(wanted)
    data = json.loads(_fetch("https://catalog.gog.com/v1/catalog?" + urlencode({
        "limit": 24, "order": "desc:trending", "discounted": "eq:true", "productType": "in:game,pack",
        "countryCode": country, "locale": locale, "currencyCode": wanted if wanted in _GOG_CURRENCIES else "USD"})))
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
        final_money = price.get("finalMoney") or {}
        final = _amount(final_money.get("amount"), 0)
        base = _amount((price.get("baseMoney") or {}).get("amount"), 0)
        art = row.get("coverHorizontal") or ""
        out.append(_item("gog", "free" if discount >= 100 else "deal", row["title"], url,
                         artwork=art if online_catalog.is_news_art(art) else "",
                         discount=discount, priceValue=final, originalValue=base,
                         currency=str(final_money.get("currency") or "USD"), endsAt=0))
    return out


_READERS = {"steam": _steam, "epic": _epic, "gog": _gog}


class StoreDeals:
    def __init__(self, readers=None, cache_path=None, rates=None):
        self._lock = threading.Lock()
        self.rates = rates or currency.Rates()
        self._running = False
        self._readers = readers or _READERS
        self._path = cache_path or (paths.cache_dir() / "store-deals.json")
        cached = load_json(self._path, {})
        self._cache = cached if isinstance(cached, dict) else {}
        self._tried = {}

    def snapshot(self, language="es", stores=None, wait=False, money="USD"):
        """{items, loading, updated, currency}. `stores` limita las fuentes (Ajustes → Novedades); `money`, la moneda."""
        language = "en" if language == "en" else "es"
        money = money if currency.known(money) else "USD"
        region = language + "|" + currency.country(money)     # la caché es por idioma y país de los precios
        wanted = [s for s in SOURCES if stores is None or s in stores]
        self.rates.refresh(wait=wait)
        now = time.time()
        with self._lock:
            cache = self._cache.setdefault(region, {})
            due = [s for s in wanted
                   if now - self._tried.get((region, s), 0) >= _RETRY_DELAY
                   and now - cache.get(s, {}).get("updated", 0) >= _CACHE_TTL]
            start = bool(due) and not self._running
            if start:
                self._running = True
                self._tried.update({(region, s): now for s in due})
        if start:
            if wait:
                self._refresh(due, language, money, region)
            else:
                threading.Thread(target=self._refresh, args=(due, language, money, region), name="omnia-store-deals", daemon=True).start()
        with self._lock:
            cache = self._cache.get(region, {})
            items, updated = [], 0
            for source in wanted:
                # Recién cambiada la moneda, mientras llegan los precios de la nueva región se usan los de otra (convertidos).
                row = cache.get(source) or next((c[source] for key, c in self._cache.items()
                                                 if key.startswith(language + "|") and isinstance(c, dict) and c.get(source)), {})
                updated = max(updated, row.get("updated", 0))
                for kind in KINDS:
                    items += [dict(i) for i in row.get("items", []) if i.get("kind") == kind][:_PER_KIND]
            loading = self._running
        for item in items:
            art = item.get("artwork", "")
            item["artwork"] = online_catalog.local_or_remote(art, news=True) if online_catalog._is_art_url(art, news=True) else ""
            self._prices(item, money, language)
        return {"items": items, "loading": loading, "updated": int(updated), "currency": money}

    def _prices(self, item, money, language):
        """price / originalPrice en la moneda elegida; convertidos con «≈» si la tienda dio otra (sin tipo de cambio: la suya)."""
        source = item.pop("currency", "") or money
        values = {key: item.pop(key + "Value", 0) for key in ("price", "original")}
        target, approx = money, source != money
        if approx and self.rates.convert(1, source, money) is None:
            target, approx = source, False                      # sin tipo de cambio todavía: el precio original
        for key, field in (("price", "price"), ("original", "originalPrice")):
            value = values[key]
            if value and approx:
                value = self.rates.convert(value, source, target)
            item[field] = currency.format_money(value, target, language, approx=approx) if value else ""
        item["approx"] = approx

    def _refresh(self, sources, language, money="USD", region=None):
        region = region or language + "|" + currency.country(money)
        try:
            with ThreadPoolExecutor(max_workers=3) as pool:
                futures = {pool.submit(self._readers[s], language, money): s for s in sources}
                for future in as_completed(futures):
                    source = futures[future]
                    try:
                        items = future.result()
                        if items:
                            with self._lock:
                                self._cache.setdefault(region, {})[source] = {"items": items, "updated": time.time()}
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

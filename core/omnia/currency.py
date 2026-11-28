"""Moneda de los precios (entrega 5): la que elige la persona o, si no eligió, la de la región del sistema.

Steam da el precio real de cada región (se le pide la del país de la moneda); Epic y GOG también cuando tienen esa moneda.
Lo que llega en otra moneda se convierte con un tipo de cambio diario y se marca con «≈». Solo biblioteca estándar.

Tipo de cambio: open.er-api.com (base USD, se actualiza una vez al día, sin clave); si falla, el espejo público de
fawazahmed0/currency-api en jsDelivr. Se guarda en la caché y se reintenta a la hora si no se pudo descargar.
"""
import json
import logging
import os
import threading
import time

from . import paths
from .store import load_json, write_json_atomic

_LOG = logging.getLogger(__name__)
_RATES_TTL = 24 * 3600
_RATES_RETRY = 3600
MAIN = ("COP", "MXN", "USD")        # las principales, primero en la lista

# código: (nombre en español, nombre en inglés, país para pedir precios a las tiendas, decimales, símbolo)
CURRENCIES = {
    "COP": ("Peso colombiano", "Colombian peso", "CO", 0, "$"),
    "MXN": ("Peso mexicano", "Mexican peso", "MX", 2, "MX$"),
    "USD": ("Dólar estadounidense", "US dollar", "US", 2, "US$"),
    "EUR": ("Euro", "Euro", "ES", 2, "€"),
    "ARS": ("Peso argentino", "Argentine peso", "AR", 2, "AR$"),
    "CLP": ("Peso chileno", "Chilean peso", "CL", 0, "CLP$"),
    "PEN": ("Sol peruano", "Peruvian sol", "PE", 2, "S/"),
    "UYU": ("Peso uruguayo", "Uruguayan peso", "UY", 2, "$U"),
    "BRL": ("Real brasileño", "Brazilian real", "BR", 2, "R$"),
    "CRC": ("Colón costarricense", "Costa Rican colón", "CR", 0, "₡"),
    "GTQ": ("Quetzal", "Guatemalan quetzal", "GT", 2, "Q"),
    "DOP": ("Peso dominicano", "Dominican peso", "DO", 2, "RD$"),
    "BOB": ("Boliviano", "Bolivian boliviano", "BO", 2, "Bs"),
    "PYG": ("Guaraní", "Paraguayan guaraní", "PY", 0, "₲"),
    "VES": ("Bolívar", "Venezuelan bolívar", "VE", 2, "Bs."),
    "CAD": ("Dólar canadiense", "Canadian dollar", "CA", 2, "CA$"),
    "GBP": ("Libra esterlina", "Pound sterling", "GB", 2, "£"),
    "CHF": ("Franco suizo", "Swiss franc", "CH", 2, "CHF"),
    "NOK": ("Corona noruega", "Norwegian krone", "NO", 2, "kr"),
    "SEK": ("Corona sueca", "Swedish krona", "SE", 2, "kr"),
    "DKK": ("Corona danesa", "Danish krone", "DK", 2, "kr"),
    "PLN": ("Esloti polaco", "Polish złoty", "PL", 2, "zł"),
    "CZK": ("Corona checa", "Czech koruna", "CZ", 2, "Kč"),
    "HUF": ("Forinto húngaro", "Hungarian forint", "HU", 0, "Ft"),
    "RUB": ("Rublo ruso", "Russian ruble", "RU", 0, "₽"),
    "UAH": ("Grivna ucraniana", "Ukrainian hryvnia", "UA", 0, "₴"),
    "KZT": ("Tenge", "Kazakhstani tenge", "KZ", 0, "₸"),
    "TRY": ("Lira turca", "Turkish lira", "TR", 2, "₺"),
    "ILS": ("Séquel", "Israeli shekel", "IL", 2, "₪"),
    "SAR": ("Rial saudí", "Saudi riyal", "SA", 2, "SR"),
    "AED": ("Dírham", "UAE dirham", "AE", 2, "AED"),
    "QAR": ("Rial catarí", "Qatari riyal", "QA", 2, "QR"),
    "KWD": ("Dinar kuwaití", "Kuwaiti dinar", "KW", 3, "KD"),
    "ZAR": ("Rand", "South African rand", "ZA", 2, "R"),
    "INR": ("Rupia india", "Indian rupee", "IN", 0, "₹"),
    "IDR": ("Rupia indonesia", "Indonesian rupiah", "ID", 0, "Rp"),
    "MYR": ("Ringit", "Malaysian ringgit", "MY", 2, "RM"),
    "PHP": ("Peso filipino", "Philippine peso", "PH", 2, "₱"),
    "SGD": ("Dólar de Singapur", "Singapore dollar", "SG", 2, "S$"),
    "THB": ("Baht", "Thai baht", "TH", 0, "฿"),
    "VND": ("Dong", "Vietnamese dong", "VN", 0, "₫"),
    "CNY": ("Yuan", "Chinese yuan", "CN", 2, "¥"),
    "HKD": ("Dólar de Hong Kong", "Hong Kong dollar", "HK", 2, "HK$"),
    "TWD": ("Dólar taiwanés", "New Taiwan dollar", "TW", 0, "NT$"),
    "JPY": ("Yen", "Japanese yen", "JP", 0, "¥"),
    "KRW": ("Won", "South Korean won", "KR", 0, "₩"),
    "AUD": ("Dólar australiano", "Australian dollar", "AU", 2, "A$"),
    "NZD": ("Dólar neozelandés", "New Zealand dollar", "NZ", 2, "NZ$"),
}
# Países cuya moneda no sale de la tabla anterior (zona euro y otros con la moneda de un vecino).
_COUNTRY_EXTRA = {c: "EUR" for c in ("DE", "FR", "IT", "PT", "NL", "BE", "AT", "IE", "FI", "GR", "SK", "SI", "LT", "LV", "EE",
                                     "LU", "MT", "CY", "HR")}
_COUNTRY_EXTRA.update({"EC": "USD", "SV": "USD", "PA": "USD", "PR": "USD"})


def known(code) -> bool:
    return isinstance(code, str) and len(code) == 3 and code.isalpha() and code.isupper()


def from_locale(env=None) -> str:
    """Moneda de la región del sistema: es_CO.UTF-8 → COP; sin región conocida, USD."""
    env = os.environ if env is None else env
    for key in ("LC_MONETARY", "LC_ALL", "LANG"):
        value = str(env.get(key) or "")
        if "_" not in value:
            continue
        country = value.split("_", 1)[1][:2].upper()
        for code, row in CURRENCIES.items():
            if row[2] == country:
                return code
        if country in _COUNTRY_EXTRA:
            return _COUNTRY_EXTRA[country]
    return "USD"


def country(code) -> str:
    """País al que se le piden los precios para esa moneda (US si no se conoce)."""
    row = CURRENCIES.get(code)
    return row[2] if row else "US"


def options(language="es", extra=()) -> list:
    """Monedas para elegir: las principales, luego las que tienen nombre (por nombre) y al final las demás que trae el tipo de
    cambio (`extra`), por código."""
    idx = 1 if language == "en" else 0
    rows = [{"code": c, "name": CURRENCIES[c][idx]} for c in CURRENCIES]
    rows += [{"code": c, "name": c} for c in sorted(set(extra) - set(CURRENCIES)) if known(c)]
    main = [r for r in rows if r["code"] in MAIN]
    main.sort(key=lambda r: MAIN.index(r["code"]))
    named = sorted((r for r in rows if r["code"] not in MAIN and r["code"] in CURRENCIES), key=lambda r: r["name"].casefold())
    other = [r for r in rows if r["code"] not in CURRENCIES]           # las demás del tipo de cambio, por código
    return main + named + other


def format_money(value, code, language="es", approx=False) -> str:
    """59700 COP → «$ 59.700»; 4.99 USD → «US$ 4,99» (es) o «US$ 4.99» (en); con `approx`, «≈ » delante."""
    try:
        value = float(value)
    except (TypeError, ValueError):
        return ""
    if value <= 0:
        return ""
    row = CURRENCIES.get(code)
    decimals = row[3] if row else 2
    symbol = row[4] if row else code
    if approx and decimals == 2 and value >= 1000:
        decimals = 0                    # una conversión grande no gana nada con céntimos
    if decimals and round(value, decimals) == round(value):
        decimals = 0                    # «MX$ 1.199» en lugar de «MX$ 1.199,00»
    text = f"{value:,.{decimals}f}"
    if language != "en":
        text = text.replace(",", " ").replace(".", ",").replace(" ", ".")
    return ("≈ " if approx else "") + symbol + " " + text


class Rates:
    """Tipo de cambio con base USD, en caché un día. `convert` nunca espera a la red: si no hay datos, devuelve None."""
    SOURCES = (
        ("https://open.er-api.com/v6/latest/USD", "er"),
        ("https://cdn.jsdelivr.net/npm/@fawazahmed0/currency-api@latest/v1/currencies/usd.json", "fawaz"),
    )

    def __init__(self, cache_path=None, fetch=None):
        self._lock = threading.Lock()
        self._path = cache_path or (paths.cache_dir() / "exchange-rates.json")
        data = load_json(self._path, {})
        self._data = data if isinstance(data, dict) and isinstance(data.get("rates"), dict) else {"rates": {}, "updated": 0}
        self._fetch = fetch
        self._tried = 0
        self._running = False

    def codes(self) -> list:
        with self._lock:
            return list(self._data["rates"])

    def updated(self) -> int:
        with self._lock:
            return int(self._data.get("updated") or 0)

    def refresh(self, wait=False):
        now = time.time()
        with self._lock:
            fresh = now - self._data.get("updated", 0) < _RATES_TTL
            if fresh or self._running or now - self._tried < _RATES_RETRY:
                return
            self._running, self._tried = True, now
        if wait:
            self._download()
        else:
            threading.Thread(target=self._download, name="omnia-rates", daemon=True).start()

    def _download(self):
        try:
            fetch = self._fetch
            if fetch is None:
                from .store_news import _fetch as fetch
            for url, kind in self.SOURCES:
                try:
                    body = json.loads(fetch(url))
                    rates = body.get("rates") if kind == "er" and body.get("result") == "success" else body.get("usd") if kind == "fawaz" else None
                    rates = {str(k).upper(): float(v) for k, v in (rates or {}).items()
                             if isinstance(v, (int, float)) and v > 0 and known(str(k).upper())}
                except (OSError, ValueError, TypeError, AttributeError) as exc:
                    _LOG.debug("Tipo de cambio de %s: %s", url, exc)
                    continue
                if len(rates) >= 20 and rates.get("USD") == 1:
                    with self._lock:
                        self._data = {"rates": rates, "updated": time.time(), "source": url.split("/")[2]}
                        data = dict(self._data)
                    try:
                        paths.ensure(self._path.parent)
                        write_json_atomic(self._path, data)
                    except OSError as exc:
                        _LOG.debug("Caché del tipo de cambio: %s", exc)
                    return
        finally:
            with self._lock:
                self._running = False

    def convert(self, value, source, target):
        if source == target:
            return value
        with self._lock:
            rates = self._data["rates"]
            a, b = rates.get(source), rates.get(target)
        if not a or not b:
            return None
        return float(value) / a * b

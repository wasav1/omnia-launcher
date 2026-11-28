"""Peticiones JSON a las API web de las tiendas (Ubisoft y EA): HTTPS, sin seguir redirecciones a otros sitios y con límite."""
import json
import urllib.error
import urllib.request
from urllib.parse import urlsplit

from .base import StoreError

_LIMIT = 8_000_000
_UA = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0 Safari/537.36"


class _SameHost(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, req, fp, code, msg, headers, newurl):
        if urlsplit(newurl).hostname != urlsplit(req.full_url).hostname:
            return None
        return super().redirect_request(req, fp, code, msg, headers, newurl)


def request_json(method: str, url: str, headers: dict, body=None, opener=None, timeout=30):
    if not url.startswith("https://"):
        raise StoreError("Dirección de tienda no válida.")
    data = json.dumps(body).encode() if body is not None else (b"" if method in ("POST", "PUT") else None)
    req = urllib.request.Request(url, data=data, method=method, headers={"User-Agent": _UA, "Accept": "application/json", **headers})
    open_ = opener or urllib.request.build_opener(_SameHost()).open
    try:
        with open_(req, timeout=timeout) as response:
            raw = response.read(_LIMIT + 1)
    except urllib.error.HTTPError as exc:
        raise StoreError("La tienda rechazó la petición (código %d)." % exc.code)
    except (urllib.error.URLError, OSError) as exc:
        raise StoreError("No se pudo conectar con la tienda.") from exc
    if len(raw) > _LIMIT:
        raise StoreError("La tienda devolvió demasiados datos.")
    try:
        return json.loads(raw.decode("utf-8")) if raw else {}
    except ValueError:
        raise StoreError("La tienda devolvió datos que Omnia no entiende.")

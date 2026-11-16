"""Arte de los juegos (portada y fondo) desde SteamGridDB, con la clave del propio usuario.

Reglas de seguridad (el prototipo descargaba cualquier URL que le pasaran):
  * La clave vive en ~/.config/omnia/steamgriddb.key (0600), nunca en el repositorio ni en la API.
  * Solo se descarga de hosts de SteamGridDB, por HTTPS, con límite de tamaño.
  * El nombre de carpeta del arte sale de un «slug» saneado: no puede escapar de ~/.local/share/omnia/art.
Si no hay clave, no se hace ninguna petición de red.
"""
import json
import os
import re
import datetime
import urllib.parse
import urllib.request
from pathlib import Path

from . import paths

API = "https://www.steamgriddb.com/api/v2"
HOST_OK = re.compile(r"^([a-z0-9-]+\.)*steamgriddb\.com$")
MAX_BYTES = 12 * 1024 * 1024
EXTS = {"image/png": ".png", "image/jpeg": ".jpg", "image/webp": ".webp"}
# tipo -> (ruta del endpoint, parámetros). Las portadas verticales 600x900 son las que usa la estantería.
KINDS = {"portada": ("grids", {"dimensions": "600x900", "types": "static", "nsfw": "false", "humor": "false"}),
         "fondo": ("heroes", {"types": "static", "nsfw": "false", "humor": "false"}),
         "logo": ("logos", {"types": "static", "nsfw": "false", "humor": "false"})}


class ArtError(Exception):
    pass


def safe_slug(slug: str) -> str:
    s = re.sub(r"[^A-Za-z0-9._-]+", "-", str(slug)).strip("-.")
    return s[:80] or "juego"


def art_dir(slug: str, kind: str, base: Path | None = None) -> Path:
    return (Path(base) if base else paths.data_dir() / "art") / safe_slug(slug) / kind


def cached_files(slug: str, kind: str, base: Path | None = None) -> list[Path]:
    """Archivos de arte descargados en orden de selección."""
    d = art_dir(slug, kind, base)
    try:
        files = [f for f in d.iterdir() if f.suffix.lower() in EXTS.values() and f.is_file()]
    except OSError:
        return []
    return sorted(files, key=lambda f: (0, int(f.stem)) if f.stem.isdigit() else (1, f.name.casefold()))


def cached(slug: str, kind: str, base: Path | None = None, index: int = 0) -> str:
    """Ruta del archivo de arte seleccionado, o cadena vacía."""
    files = cached_files(slug, kind, base)
    return str(files[index % len(files)]) if files else ""


def key_path() -> Path:
    return paths.config_dir() / "steamgriddb.key"


def load_key(path: Path | None = None) -> str:
    try:
        return Path(path or key_path()).read_text(encoding="utf-8").strip()
    except OSError:
        return ""


def key_permissions_ok(path: Path | None = None) -> bool:
    try:
        return (Path(path or key_path()).stat().st_mode & 0o077) == 0
    except OSError:
        return True


def url_allowed(url: str) -> bool:
    u = urllib.parse.urlparse(url)
    return u.scheme == "https" and bool(u.hostname) and bool(HOST_OK.match(u.hostname.lower()))


class Client:
    def __init__(self, key: str, opener=urllib.request.urlopen):
        self.key, self.opener = key, opener

    def _open(self, url: str, auth: bool):
        if not url_allowed(url):
            raise ArtError("URL no permitida: %s" % urllib.parse.urlparse(url).netloc)
        req = urllib.request.Request(url, headers={"User-Agent": "omnia", **({"Authorization": "Bearer " + self.key} if auth else {})})
        return self.opener(req, timeout=15)

    def get_json(self, path: str, params: dict | None = None) -> dict:
        q = ("?" + urllib.parse.urlencode(params)) if params else ""
        try:
            with self._open(API + path + q, True) as r:
                return json.loads(r.read(2 * 1024 * 1024))
        except (OSError, ValueError) as e:
            raise ArtError("SteamGridDB: %s" % e)

    def candidates(self, game: dict, kind: str) -> list:
        """URLs candidatas para un juego: por appid si es de Steam, si no por búsqueda del nombre."""
        endpoint, params = KINDS[kind]
        gid = str(game.get("id", ""))
        if gid.startswith("steam-") and gid[6:].isdigit():
            data = self.get_json("/%s/steam/%s" % (endpoint, gid[6:]), params)
        else:
            name = (game.get("art") or {}).get("sgdb") or game.get("name", "")
            found = self.get_json("/search/autocomplete/" + urllib.parse.quote(name, safe="")).get("data") or []
            if not found:
                return []
            data = self.get_json("/%s/game/%s" % (endpoint, found[0]["id"]), params)
        return [x["url"] for x in (data.get("data") or []) if isinstance(x, dict) and x.get("url")]

    def browse(self, game: dict, kind: str, page: int = 0, sgid: int = 0) -> dict:
        """Busca ediciones y propuestas de arte; solo entrega URLs verificadas de SteamGridDB."""
        if kind not in KINDS:
            raise ArtError("tipo de arte no válido")
        page = max(0, min(500, int(page)))
        name = (game.get("art") or {}).get("sgdb") or game.get("name", "")
        found = self.get_json("/search/autocomplete/" + urllib.parse.quote(name, safe="")).get("data") or []
        games = []
        for item in found[:12]:
            if not isinstance(item, dict) or not isinstance(item.get("id"), int) or not item.get("name"):
                continue
            release = item.get("release_date")
            try:
                year = datetime.datetime.fromtimestamp(int(release), tz=datetime.timezone.utc).year if release else 0
            except (ValueError, TypeError, OSError, OverflowError):
                year = 0
            games.append({"id": item["id"], "name": str(item["name"]), "year": year})
        if not sgid:
            sgid = games[0]["id"] if games else 0
        if not sgid or not any(g["id"] == int(sgid) for g in games):
            if sgid:
                raise ArtError("edición de SteamGridDB no válida")
            return {"sgid": 0, "games": games, "items": [], "page": page, "more": False}
        endpoint, params = KINDS[kind]
        params = {**params, "page": page}
        payload = self.get_json("/%s/game/%d" % (endpoint, int(sgid)), params)
        data = payload.get("data") or []
        items = []
        for item in data:
            if not isinstance(item, dict) or not url_allowed(item.get("url", "")):
                continue
            thumb = item.get("thumb") or item["url"]
            if not url_allowed(thumb):
                thumb = item["url"]
            author = item.get("author") or {}
            items.append({"url": item["url"], "thumb": thumb, "w": int(item.get("width") or 0),
                          "h": int(item.get("height") or 0), "by": str(author.get("name") or "")})
        total, limit = int(payload.get("total") or 0), int(payload.get("limit") or 0)
        return {"sgid": int(sgid), "games": games, "items": items, "page": page,
                "more": bool(limit and (page + 1) * limit < total)}

    def download(self, url: str, dest_dir: Path) -> Path:
        with self._open(url, False) as r:
            ctype = (r.headers.get("Content-Type") or "").split(";")[0].strip().lower()
            if ctype not in EXTS:
                raise ArtError("tipo de archivo no permitido: %s" % ctype)
            data = r.read(MAX_BYTES + 1)
        if len(data) > MAX_BYTES:
            raise ArtError("imagen demasiado grande")
        paths.ensure(Path(dest_dir), 0o700)
        n = 1 + len([f for f in Path(dest_dir).iterdir() if f.suffix in EXTS.values()])
        dest = Path(dest_dir) / ("%d%s" % (n, EXTS[ctype]))
        tmp = dest.with_name(dest.name + ".tmp")
        tmp.write_bytes(data)
        os.replace(tmp, dest)
        return dest


def fetch_game(client: Client, game: dict, kinds=("portada", "fondo", "logo"), base: Path | None = None) -> dict:
    """Descarga el arte que falte de un juego. Devuelve {tipo: ruta} de lo que descargó ahora."""
    slug = (game.get("art") or {}).get("slug") or game.get("id", "")
    got = {}
    for kind in kinds:
        if cached(slug, kind, base):
            continue
        for url in client.candidates(game, kind)[:3]:          # prueba pocas opciones: no es un rastreo
            try:
                got[kind] = str(client.download(url, art_dir(slug, kind, base)))
                break
            except ArtError:
                continue
    return got

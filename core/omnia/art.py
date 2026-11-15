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
import urllib.parse
import urllib.request
from pathlib import Path

from . import paths

API = "https://www.steamgriddb.com/api/v2"
HOST_OK = re.compile(r"^([a-z0-9-]+\.)*steamgriddb\.com$")
MAX_BYTES = 12 * 1024 * 1024
EXTS = {"image/png": ".png", "image/jpeg": ".jpg", "image/webp": ".webp"}
# tipo -> (ruta del endpoint, parámetros). Las portadas verticales 600x900 son las que usa la estantería.
KINDS = {"portada": ("grids", {"dimensions": "600x900", "types": "static"}),
         "fondo": ("heroes", {"types": "static"})}


class ArtError(Exception):
    pass


def safe_slug(slug: str) -> str:
    s = re.sub(r"[^A-Za-z0-9._-]+", "-", str(slug)).strip("-.")
    return s[:80] or "juego"


def art_dir(slug: str, kind: str, base: Path | None = None) -> Path:
    return (Path(base) if base else paths.data_dir() / "art") / safe_slug(slug) / kind


def cached(slug: str, kind: str, base: Path | None = None) -> str:
    """Ruta del primer archivo de arte ya descargado, o cadena vacía."""
    d = art_dir(slug, kind, base)
    try:
        files = sorted(f for f in d.iterdir() if f.suffix in EXTS.values() and f.is_file())
    except OSError:
        return ""
    return str(files[0]) if files else ""


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


def fetch_game(client: Client, game: dict, kinds=("portada", "fondo"), base: Path | None = None) -> dict:
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

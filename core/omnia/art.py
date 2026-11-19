"""Arte de los juegos (portada y fondo) desde SteamGridDB, con la clave del propio usuario.

Reglas de seguridad (el prototipo descargaba cualquier URL que le pasaran):
  * La clave vive en ~/.config/omnia/steamgriddb.key (0600), nunca en el repositorio ni en la API.
  * Solo se descarga de hosts de SteamGridDB, por HTTPS, con límite de tamaño.
  * El nombre de carpeta del arte sale de un «slug» saneado: no puede escapar de ~/.local/share/omnia/art.
Si no hay clave, no se hace ninguna petición de red.
"""
import datetime
import json
import os
import re
import threading
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


class _SafeRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, req, fp, code, msg, headers, newurl):
        if not url_allowed(newurl):
            raise ArtError("redirección a un host no permitido")
        return super().redirect_request(req, fp, code, msg, headers, newurl)


NONE_MARK = ".sin-arte"      # marca: SteamGridDB no tiene este tipo de arte para el juego
_index_lock = threading.RLock()
_download_lock = threading.RLock()
_file_index: dict[str, tuple[tuple, list[Path]]] = {}
_best_index: dict[str, tuple[tuple, str]] = {}


def safe_slug(slug: str) -> str:
    s = re.sub(r"[^A-Za-z0-9._-]+", "-", str(slug)).strip("-.")
    return s[:80] or "juego"


def art_dir(slug: str, kind: str, base: Path | None = None) -> Path:
    return (Path(base) if base else paths.data_dir() / "art") / safe_slug(slug) / kind


def _files_stamp(files: list[Path]) -> tuple:
    """Huella de nombres e inodos: detecta también reemplazos sin cambio de carpeta."""
    out = []
    for path in files:
        try:
            stat = path.stat()
        except OSError:
            continue
        out.append((path.name, stat.st_mtime_ns, stat.st_size, stat.st_ino))
    return tuple(out)


def cached_files(slug: str, kind: str, base: Path | None = None) -> list[Path]:
    """Archivos de arte descargados en orden de selección."""
    d = art_dir(slug, kind, base)
    key = str(d)
    try:
        stat = d.stat()
        dir_stamp = (stat.st_mtime_ns, stat.st_ino)
    except OSError:
        with _index_lock:
            _file_index.pop(key, None); _best_index.pop(key, None)
        return []
    # El mtime de un directorio no cambia al reemplazar un archivo existente.
    # Leer la huella de cada imagen evita devolver índices/rutas cacheados obsoletos.
    with _download_lock, _index_lock:
        try:
            files = [f for f in d.iterdir() if f.suffix.lower() in EXTS.values() and f.is_file()]
        except OSError:
            files = []
        files.sort(key=lambda f: (1, int(f.stem)) if f.stem.isdigit() else (0, f.name.casefold()))
        stamp = (dir_stamp, _files_stamp(files))
        hit = _file_index.get(key)
        if hit and hit[0] == stamp:
            return hit[1]
        _file_index[key] = (stamp, files)
        _best_index.pop(key, None)
        return files


def cached(slug: str, kind: str, base: Path | None = None, index: int = 0) -> str:
    """Ruta del archivo de arte seleccionado, o cadena vacía."""
    files = cached_files(slug, kind, base)
    return str(files[index % len(files)]) if files else ""


def image_dimensions(path: Path) -> tuple[int, int]:
    """Lee las dimensiones PNG/JPEG/WebP desde la cabecera, sin cargar la imagen en memoria."""
    try:
        with Path(path).open("rb") as f:
            head = f.read(30)
            if head.startswith(b"\x89PNG\r\n\x1a\n") and len(head) >= 24:
                return int.from_bytes(head[16:20], "big"), int.from_bytes(head[20:24], "big")
            if head[:4] == b"RIFF" and head[8:12] == b"WEBP":
                if head[12:16] == b"VP8X" and len(head) >= 30:
                    return 1 + int.from_bytes(head[24:27], "little"), 1 + int.from_bytes(head[27:30], "little")
                if head[12:16] == b"VP8L" and len(head) >= 25 and head[20] == 0x2F:
                    b1, b2, b3, b4 = head[21:25]
                    return 1 + b1 + ((b2 & 0x3F) << 8), 1 + ((b2 >> 6) & 3) + (b3 << 2) + ((b4 & 0x0F) << 10)
                if head[12:16] == b"VP8 " and len(head) >= 30 and head[23:26] == b"\x9d\x01\x2a":
                    return int.from_bytes(head[26:28], "little") & 0x3FFF, int.from_bytes(head[28:30], "little") & 0x3FFF
            if head[:2] != b"\xff\xd8":
                return 0, 0
            f.seek(2)
            sof = {0xC0, 0xC1, 0xC2, 0xC3, 0xC5, 0xC6, 0xC7, 0xC9, 0xCA, 0xCB, 0xCD, 0xCE, 0xCF}
            while True:
                byte = f.read(1)
                if not byte:
                    return 0, 0
                if byte != b"\xff":
                    continue
                marker = f.read(1)
                while marker == b"\xff":
                    marker = f.read(1)
                if not marker or marker in (b"\x00", b"\xd9", b"\xda"):
                    return 0, 0
                code = marker[0]
                if code in (0xD8, 0x01) or 0xD0 <= code <= 0xD7:
                    continue
                length = int.from_bytes(f.read(2), "big")
                if length < 2:
                    return 0, 0
                if code in sof:
                    dims = f.read(5)
                    if len(dims) == 5:
                        return int.from_bytes(dims[3:5], "big"), int.from_bytes(dims[1:3], "big")
                    return 0, 0
                f.seek(length - 2, 1)
    except OSError:
        return 0, 0


def highest_resolution(slug: str, kind: str, base: Path | None = None) -> str:
    """Ruta del arte local con mayor área; en empate o dimensiones no legibles mantiene el orden de caché."""
    files = cached_files(slug, kind, base)
    if not files:
        return ""
    key = str(art_dir(slug, kind, base))
    stamp = _files_stamp(files)
    with _index_lock:
        hit = _best_index.get(key)
        if hit and hit[0] == stamp:
            return hit[1]
        best = str(max(files, key=lambda f: image_dimensions(f)[0] * image_dimensions(f)[1]))
        _best_index[key] = (stamp, best)
        return best


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


# Plataformas cuya edición en SteamGridDB suele ser la más reciente (remasters) o la original (emulados)
NEWEST = {"sw2", "ps5"}
OLDEST = {"n64", "sw1", "ps3", "ps4"}


def _norm_name(s: str) -> str:
    return re.sub(r"[^a-z0-9]+", "", str(s).casefold())


def pick_edition(editions: list, game: dict) -> int:
    """Elige la edición de SteamGridDB que corresponde al juego, no solo el primer resultado.

    Entre las que se llaman igual que el juego: el año guardado (`art.year`) si coincide; si no, la plataforma
    (Switch 2/PS5 -> la más reciente; N64/Switch/PS3/PS4 -> la original). Sin coincidencia exacta, la primera."""
    art_info = game.get("art") or {}
    name = _norm_name(art_info.get("sgdb") or game.get("name", ""))
    exact = [e for e in editions if _norm_name(e["name"]) == name]
    if not exact:
        return editions[0]["id"]
    year = art_info.get("year")
    if isinstance(year, int) and year > 0:
        match = [e for e in exact if e["year"] == year]
        if match:
            return match[0]["id"]
    dated = [e for e in exact if e["year"]]
    platform = game.get("platform", "")
    if dated and platform in NEWEST:
        return max(dated, key=lambda e: e["year"])["id"]
    if dated and platform in OLDEST:
        return min(dated, key=lambda e: e["year"])["id"]
    return exact[0]["id"]


class Client:
    def __init__(self, key: str, opener=urllib.request.urlopen):
        self.key = key
        self.opener = urllib.request.build_opener(_SafeRedirect()).open if opener is urllib.request.urlopen else opener

    def _open(self, url: str, auth: bool):
        if not url_allowed(url):
            raise ArtError(f"URL no permitida: {urllib.parse.urlparse(url).netloc}")
        req = urllib.request.Request(url, headers={"User-Agent": "omnia", **({"Authorization": "Bearer " + self.key} if auth else {})})
        return self.opener(req, timeout=15)

    def get_json(self, path: str, params: dict | None = None) -> dict:
        q = ("?" + urllib.parse.urlencode(params)) if params else ""
        try:
            with self._open(API + path + q, True) as r:
                return json.loads(r.read(2 * 1024 * 1024))
        except (OSError, ValueError) as e:
            raise ArtError(f"SteamGridDB: {e}")

    def editions(self, name: str) -> list:
        """Ediciones del juego en SteamGridDB: [{id, name, year}] en el orden de la búsqueda."""
        found = self.get_json("/search/autocomplete/" + urllib.parse.quote(name, safe="")).get("data") or []
        out = []
        for item in found[:12]:
            if not isinstance(item, dict) or not isinstance(item.get("id"), int):
                continue
            release = item.get("release_date")
            try:
                year = datetime.datetime.fromtimestamp(int(release), tz=datetime.UTC).year if release else 0
            except (ValueError, TypeError, OSError, OverflowError):
                year = 0
            out.append({"id": item["id"], "name": str(item.get("name") or ""), "year": year})
        return out

    def candidates(self, game: dict, kind: str) -> list:
        """URLs candidatas para un juego: por appid si es de Steam, si no por búsqueda del nombre."""
        endpoint, params = KINDS[kind]
        gid = str(game.get("id", ""))
        if gid.startswith("steam-") and gid[6:].isdigit():
            data = self.get_json(f"/{endpoint}/steam/{gid[6:]}", params)
        else:
            name = (game.get("art") or {}).get("sgdb") or game.get("name", "")
            eds = self.editions(name)
            if not eds:
                return []
            data = self.get_json(f"/{endpoint}/game/{pick_edition(eds, game)}", params)
        items = [x for x in (data.get("data") or []) if isinstance(x, dict) and x.get("url")]
        if kind == "fondo":
            items.sort(key=lambda x: int(x.get("width") or 0) * int(x.get("height") or 0), reverse=True)
        return [x["url"] for x in items]

    def browse(self, game: dict, kind: str, page: int = 0, sgid: int = 0) -> dict:
        """Busca ediciones y propuestas de arte; solo entrega URLs verificadas de SteamGridDB."""
        if kind not in KINDS:
            raise ArtError("tipo de arte no válido")
        page = max(0, min(500, int(page)))
        name = (game.get("art") or {}).get("sgdb") or game.get("name", "")
        games = [e for e in self.editions(name) if e["name"]]       # para elegir se necesita el nombre
        if not sgid:
            sgid = pick_edition(games, game) if games else 0
        if not sgid or not any(g["id"] == int(sgid) for g in games):
            if sgid:
                raise ArtError("edición de SteamGridDB no válida")
            return {"sgid": 0, "games": games, "items": [], "page": page, "more": False}
        endpoint, params = KINDS[kind]
        params = {**params, "page": page}
        payload = self.get_json(f'/{endpoint}/game/{int(sgid):d}', params)
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
                raise ArtError(f"tipo de archivo no permitido: {ctype}")
            data = r.read(MAX_BYTES + 1)
        if len(data) > MAX_BYTES:
            raise ArtError("imagen demasiado grande")
        folder = paths.ensure(Path(dest_dir), 0o700)
        # No reutilizar una ruta: Qt puede conservar el pixmap anterior en su caché
        # aunque el contenido del archivo cambie. El número mayor mantiene estable
        # el orden y permite guardar la selección como índice en state.json.
        with _download_lock:
            numbers = [int(f.stem) for f in folder.iterdir()
                       if f.suffix.lower() in EXTS.values() and f.stem.isdigit()]
            n = max(numbers, default=0) + 1
            dest = folder / (f'{n:d}{EXTS[ctype]}')
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
        marker = art_dir(slug, kind, base) / NONE_MARK
        if marker.exists():
            continue                                            # ya se comprobó que SteamGridDB no tiene este tipo
        cands = client.candidates(game, kind)
        if not cands:
            try:
                marker.parent.mkdir(parents=True, exist_ok=True)
                marker.touch()                                  # no repetir la consulta en cada ciclo
            except OSError:
                pass
            continue
        for url in cands[:3]:                                   # prueba pocas opciones: no es un rastreo
            try:
                got[kind] = str(client.download(url, art_dir(slug, kind, base)))
                break
            except ArtError:
                continue
    return got

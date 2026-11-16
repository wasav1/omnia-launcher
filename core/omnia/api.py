"""API HTTP local de Omnia.

Reglas de seguridad (ver security.py):
  * Solo 127.0.0.1 y Host propio; sin CORS (nunca se responde a un preflight).
  * Todo menos /health exige `Authorization: Bearer <token>`.
  * Las rutas que cambian algo solo aceptan POST.
  * El comando de lanzamiento sale de la biblioteca del usuario, nunca de la petición.
"""
import json
import os
import re
import subprocess
import threading
import time
import urllib.parse
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

from . import apps, art, fsbrowse, importer, launcher, manual, procs, saves, security, templates
from .events import EventBus
from .games.base import Detector
from .games import refresh as games_refresh


DEFAULT_BACKUP_ROOT = "~/Juegos/_Partidas"        # donde van los respaldos de un juego que no tiene carpeta propia
PAD_KEYS = {"l", "r", "u", "d", "A", "B", "X", "Y", "LB", "RB", "LT", "RT", "START", "SELECT", "MODE"}


class ApiError(Exception):
    def __init__(self, code: int, msg: str):
        super().__init__(msg)
        self.code, self.msg = code, msg


class Api:
    def __init__(self, store, token: str, detectors=(), port: int = 0, launch_fn=launcher.launch, scan_fn=procs.scan, bus=None,
                 catalog=None, app_launch_fn=apps.launch, fs_roots=None, open_fn=None, backup_root=DEFAULT_BACKUP_ROOT):
        self.store, self.token, self.detectors, self.launch_fn, self.scan_fn = store, token, list(detectors), launch_fn, scan_fn
        self.bus = bus or EventBus()
        self.catalog, self.app_launch_fn = catalog or apps.Catalog(), app_launch_fn
        self.fs_roots, self.backup_root = fs_roots, backup_root
        self.steam_root = None                      # solo para pruebas: carpeta de Steam distinta de ~/.local/share/Steam
        self.open_fn = open_fn or (lambda path: subprocess.Popen(["xdg-open", path], start_new_session=True,
                                                                 stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL))
        self.desktop_visible = True          # lo actualiza el vigilante de ventanas de KWin (D-Bus); por defecto se asume activo
        self._gate_t, self._gate_v = 0.0, True
        self.gamemode = None                       # lo asigna el servicio (gamemode.GameMode)
        self.sessions = None                       # lo asigna el servicio (sessions.Sessions)
        self.menu_open, self._last_poll = False, 0.0       # el Big Menu abierto lo comunica la UI; _last_poll evita un estado atascado
        self.routes = {
            "/health": ("GET", False, self.health),
            "/library": ("GET", True, self.library),
            "/library/refresh": ("POST", True, self.refresh),
            "/game/fav": ("POST", True, lambda q: self.toggle("game_fav", q)),
            "/game/hide": ("POST", True, lambda q: self.toggle("game_hidden", q)),
            "/launch": ("POST", True, self.launch),
            "/apps": ("GET", True, self.apps_list),
            "/app/launch": ("POST", True, self.app_launch),
            "/app/fav": ("POST", True, self.app_fav),
            "/menu": ("POST", True, lambda q: self.toggle_menu() or {"ok": True}),
            "/menu/state": ("POST", True, self.set_menu_state),
            "/gamemode": ("GET", True, lambda q: self.gamemode.status() if self.gamemode else {"enabled": False, "active": False}),
            "/fs/list": ("GET", True, self.fs_list),
            "/templates": ("GET", True, lambda q: {"templates": templates.catalog()}),
            "/game/add": ("POST", True, self.game_add),
            "/game/remove": ("POST", True, self.game_remove),
            "/saves/suggest": ("GET", True, self.saves_suggest),
            "/import/find": ("GET", True, lambda q: {"candidates": importer.find_legacy()}),
            "/import/preview": ("GET", True, self.import_preview),
            "/import/apply": ("POST", True, self.import_apply),
            "/saves": ("GET", True, self.saves_info),
            "/saves/config": ("POST", True, self.saves_config),
            "/saves/backup": ("POST", True, self.saves_backup),
            "/saves/restore": ("POST", True, self.saves_restore),
            "/saves/open": ("POST", True, self.saves_open),
            "/art/browse": ("GET", True, self.art_browse),
            "/art/pick": ("POST", True, self.art_pick),
            "/art/cycle": ("POST", True, self.art_cycle),
            "/audio": ("GET", True, self.audio_status),
            "/events": ("GET", True, self.events),
            "/pad": ("GET", True, self.pad_status),
            "/emit": ("POST", True, self.emit),
            "/desktop": ("POST", True, self.set_desktop),
        }
        api = self

        class Handler(BaseHTTPRequestHandler):
            def log_message(self, *a):
                pass

            def _send(self, code, obj):
                b = json.dumps(obj).encode()
                self.send_response(code)
                self.send_header("Content-Type", "application/json")
                self.send_header("Content-Length", str(len(b)))
                self.send_header("Cache-Control", "no-store")
                self.end_headers()
                self.wfile.write(b)

            def _handle(self, method):
                try:
                    if not security.host_ok(self.headers.get("Host", ""), api.port):
                        raise ApiError(403, "host no permitido")
                    u = urllib.parse.urlparse(self.path)
                    route = api.routes.get(u.path)
                    if not route:
                        raise ApiError(404, "ruta desconocida")
                    verb, needs_auth, fn = route
                    if method != verb:
                        raise ApiError(405, "método no permitido")
                    if needs_auth and not security.check_bearer(self.headers.get("Authorization", ""), api.token):
                        raise ApiError(401, "token inválido")
                    q = {k: v[0] for k, v in urllib.parse.parse_qs(u.query).items()}
                    n = int(self.headers.get("Content-Length") or 0)
                    if n:
                        if n > 65536:
                            raise ApiError(413, "cuerpo demasiado grande")
                        body = json.loads(self.rfile.read(n) or b"{}")
                        if isinstance(body, dict):
                            q.update({k: v for k, v in body.items() if isinstance(v, (str, int, bool))})
                            q["_body"] = body                       # las rutas que reciben listas leen el cuerpo completo
                    self._send(200, fn(q))
                except ApiError as e:
                    self._send(e.code, {"error": e.msg})
                except (BrokenPipeError, ConnectionResetError):
                    pass
                except Exception:
                    self._send(500, {"error": "error interno"})

            def do_GET(self):
                self._handle("GET")

            def do_POST(self):
                self._handle("POST")

            def do_OPTIONS(self):          # sin CORS: el preflight de un navegador siempre falla
                self._send(405, {"error": "sin CORS"})

        self.httpd = ThreadingHTTPServer(("127.0.0.1", port), Handler)
        self.httpd.daemon_threads = True
        self.port = self.httpd.server_address[1]

    # --- rutas
    def health(self, q):
        return {"ok": True}

    def audio_status(self, q):
        source = getattr(self, "audio", None)
        return source.snapshot() if source else {"available": False, "active": False, "bands": []}

    def _detector(self, g):
        return next((d for d in self.detectors if d.name == g.get("auto")), Detector())

    def _is_running(self, g, p, cmdlines):
        return self._detector(g).is_running(g, p, cmdlines)

    def library(self, q):
        fav, hid = self.store.state.get("game_fav", []), self.store.state.get("game_hidden", [])
        cmds = self.scan_fn()
        out = []
        for g in self.store.games():
            ports = [p for p in g.get("ports", []) if games_refresh.port_installed(p)]
            if ports:
                snap = self.sessions.snapshot(g["id"]) if self.sessions else {"lastPlayed": 0, "totalSecs": 0, "plays": 0, "playingSince": 0}
                platform = g.get("platform", "")
                platform_accents = {"n64": "#d9a441", "sw1": "#e8604f", "sw2": "#58a6f0", "pc": "#6fc3c9"}
                port_rows = []
                for p in ports:
                    port_rows.append({"id": p["id"], "name": p["name"], "running": self._is_running(g, p, cmds),
                                      "chips": list(p.get("chips") or []), "description": p.get("s", ""),
                                      "canLaunch": games_refresh.port_installed(p), "canBackup": bool(p.get("saves"))})
                session = (self.store.state.get("sessions") or {}).get(g["id"]) or {}
                btime = self.store.state.get("backups", {}).get(g["id"], 0)
                out.append({"id": g["id"], "name": g["name"], "src": g.get("src", ""), "platform": g.get("platform", ""),
                            "sub": g.get("sub", ""), "description": g.get("s", ""), "chips": list(g.get("chips") or []),
                            "pal": g.get("pal") or ["#10150f", "#1f3328", "#18271f", "#0d1510", platform_accents.get(platform, "#e6d9a0")],
                            "acc": g.get("acc") or platform_accents.get(platform, "#e6d9a0"), "font": g.get("font", "Hanken Grotesk"),
                            "added": int(g.get("added", 0) or 0), "lastSessionSecs": int(session.get("last_secs", 0) or 0),
                            "lastBackup": int(btime or 0), "lastPlayed": snap["lastPlayed"], "totalSecs": snap["totalSecs"],
                            "plays": snap["plays"], "playingSince": snap["playingSince"], "portCount": len(ports),
                            "ports": port_rows,
                            "running": any(self._is_running(g, p, cmds) for p in ports),
                            **self._art(g, self.store.state),
                            "fav": g["id"] in fav, "hidden": g["id"] in hid})
        out.sort(key=lambda x: (-x["lastPlayed"], x["name"].casefold()))
        return {"games": out}

    @staticmethod
    def _art(g, state=None):
        slug = (g.get("art") or {}).get("slug") or g["id"]
        out = {}
        selected = ((state or {}).get("art") or {}).get(g["id"], {})
        for kind in art.KINDS:
            f = art.cached(slug, kind, index=max(0, int(selected.get(kind, 0) or 0)))
            if f:
                out[kind] = "file://" + f
        return out

    def refresh(self, q):
        return games_refresh.refresh(self.store, self.detectors)

    def toggle(self, key, q):
        gid = q.get("id", "")
        if not self.store.find_game(gid):
            raise ApiError(404, "juego desconocido")
        return {"ok": True, "on": self.store.toggle(key, gid)}

    def launch(self, q):
        g, p = self.store.find_port(q.get("id", ""), q.get("port", ""))
        if not g or not p:
            raise ApiError(404, "juego o port desconocido")
        if not games_refresh.port_installed(p):
            raise ApiError(409, "no está instalado")
        if self._is_running(g, p, self.scan_fn()):
            raise ApiError(409, "ya está en ejecución")
        self.launch_fn(p, g["id"])
        return {"ok": True}

    # --- aplicaciones (Big Menu)
    def _fav_ids(self) -> list:
        fav = self.store.state.get("apps_fav")
        if fav is None:                      # primera vez: favoritos por defecto, solo los que existen
            have = {a.id for a in self.catalog.apps()}
            fav = [i for i in apps.FAV_DEFAULT if i in have]
        return fav

    def apps_list(self, q):
        fav, used = self._fav_ids(), self.store.state.get("apps_used", {})
        items = self.catalog.apps()
        order = {g: i for i, g in enumerate(dict.fromkeys(g for _, g in apps.GROUPS))}
        groups = sorted({a.group for a in items}, key=lambda g: order.get(g, 99))
        return {"groups": groups, "apps": [
            {"id": a.id, "name": a.name, "comment": a.comment, "icon": a.icon, "group": a.group,
             "keywords": a.keywords, "fav": a.id in fav, "uses": (used.get(a.id) or {}).get("n", 0)} for a in items]}

    def app_launch(self, q):
        a = self.catalog.find(q.get("id", ""))
        if not a:
            raise ApiError(404, "aplicación desconocida")      # solo se lanza lo que está en el catálogo
        self.app_launch_fn(a)
        with self.store.lock:
            u = self.store.state.setdefault("apps_used", {}).setdefault(a.id, {"n": 0, "t": 0})
            u["n"] += 1
            u["t"] = int(time.time())
            self.store.save_state()
        return {"ok": True}

    def app_fav(self, q):
        a = self.catalog.find(q.get("id", ""))
        if not a:
            raise ApiError(404, "aplicación desconocida")
        with self.store.lock:
            fav = list(self._fav_ids())
            on = a.id not in fav
            fav.append(a.id) if on else fav.remove(a.id)
            self.store.state["apps_fav"] = fav
            self.store.save_state()
        return {"ok": True, "on": on}

    def running_list(self, cmds=None) -> list:
        """Juegos de la biblioteca en marcha (dicts de la biblioteca), con un solo repaso de los procesos."""
        cmds = self.scan_fn() if cmds is None else cmds
        return [g for g in self.store.games()
                if any(games_refresh.port_installed(p) and self._is_running(g, p, cmds) for p in g.get("ports", []))]

    def running_games(self) -> list:
        """Nombres de los juegos en marcha que activan el modo juego (los de la nube no consumen este equipo)."""
        return [g.get("name", g["id"]) for g in self.running_list() if not g.get("cloud")]

    # --- partidas y explorador de carpetas
    def _roots(self):
        return self.fs_roots if self.fs_roots is not None else fsbrowse.allowed_roots()

    def _allowed(self, path: str) -> bool:
        real = os.path.realpath(os.path.expanduser(path))
        return any(real == r or real.startswith(r.rstrip("/") + "/") for r in fsbrowse._real_roots(self._roots()))

    def fs_list(self, q):
        try:
            exts = [e if e.startswith(".") else "." + e for e in q.get("ext", "").split(",") if e]
            return fsbrowse.list_dir(q.get("path") or None, self._roots(), hidden=str(q.get("hidden", "0")) == "1",
                                     files=str(q.get("files", "0")) == "1", exts=exts)
        except fsbrowse.FsError as e:
            raise ApiError(403, str(e))

    def _port_for(self, q):
        g, p = self.store.find_port(q.get("id", ""), q.get("port", ""))
        if not g:
            raise ApiError(404, "juego desconocido")
        return g, p or {}

    def _saves_cfg(self, g, p):
        """Dónde están las partidas y a dónde van los respaldos. Lo que el usuario eligió manda sobre lo de la biblioteca;
        va aparte (state) para que sobreviva a que la biblioteca se regenere (Steam, Heroic, Lutris)."""
        ov = (self.store.state.get("saves") or {}).get(g["id"]) or {}
        spec = ov.get("spec") or p.get("saves") or {}
        slug = re.sub(r"[^A-Za-z0-9._-]+", "-", g.get("name", g["id"])).strip("-") or g["id"]
        dest = ov.get("backup_dir") or p.get("backup_dir") or os.path.join(os.path.expanduser(self.backup_root), slug)
        return spec, dest, slug

    def _import_plan(self, q):
        path = q.get("path", "")
        if not path or not self._allowed(path):
            raise ApiError(403, "ruta fuera de las carpetas permitidas")
        try:
            return importer.plan(importer.load(path), self.store.games())
        except importer.ImportError_ as e:
            raise ApiError(400, str(e))

    @staticmethod
    def _public(plan_):
        return {"summary": plan_["summary"], "warnings": plan_["warnings"],
                "items": [{k: v for k, v in i.items() if k != "entry"} for i in plan_["items"]]}

    def import_preview(self, q):
        return self._public(self._import_plan(q))              # solo lectura: no escribe nada

    def import_apply(self, q):
        plan_ = self._import_plan(q)                            # el servidor recalcula el plan: no se fía de lo que traiga el cliente
        body = q.get("_body") if isinstance(q.get("_body"), dict) else {}
        ids = body.get("ids")
        if ids is not None and not (isinstance(ids, list) and all(isinstance(x, str) for x in ids)):
            raise ApiError(400, "«ids» debe ser una lista")
        added = importer.apply(self.store, plan_, ids)
        return {"ok": True, "added": added, "count": len(added)}

    def game_add(self, q):
        body = q.get("_body") if isinstance(q.get("_body"), dict) else {}
        try:
            g = manual.add_game(self.store, body, self._roots(), gopher64=getattr(self, "gopher64_override", None))
        except manual.ManualError as e:
            raise ApiError(400, str(e))
        return {"ok": True, "id": g["id"], "suggest": templates.suggest_dirs(g["ports"][0].get("cwd", ""))}

    def game_remove(self, q):
        if not manual.remove_game(self.store, q.get("id", "")):
            raise ApiError(404, "solo se pueden quitar los juegos añadidos a mano")
        return {"ok": True}

    def saves_suggest(self, q):
        g, p = self._port_for(q)
        gid = g["id"]
        if gid.startswith("steam-") and gid[6:].isdigit():
            found = templates.steam_suggestions(g.get("name", ""), gid[6:], p.get("check", ""), self.steam_root)
        else:
            found = templates.suggest_dirs(p.get("cwd") or os.path.dirname(p.get("check", "")))
        return {"suggestions": [{"path": x["path"], "label": x["label"]} for x in found if self._allowed(x["path"])]}

    def saves_info(self, q):
        g, p = self._port_for(q)
        spec, dest, slug = self._saves_cfg(g, p)
        found = saves.slots(spec) if spec else []
        return {"configured": bool(saves.roots(spec)), "spec": spec, "folder": saves.folder(spec) if spec else "",
                "slots": [{"name": x["name"], "mtime": x["mtime"], "used": bool(x.get("used"))} for x in found], "backupDir": dest,
                "backups": saves.list_backups(dest, slug), "lastBackup": self.store.state.get("backups", {}).get(g["id"], 0)}

    def saves_config(self, q):
        g, _ = self._port_for(q)
        body = q.get("_body") if isinstance(q.get("_body"), dict) else {}
        spec = {}
        for key in ("dirs", "files"):
            vals = body.get(key)
            if vals is not None:
                if not isinstance(vals, list) or not all(isinstance(v, str) for v in vals):
                    raise ApiError(400, "«%s» debe ser una lista de rutas" % key)
                spec[key] = vals
        if isinstance(body.get("glob"), str):
            spec["glob"] = body["glob"]
        if isinstance(body.get("name"), str):
            spec["name"] = body["name"][:60]
        backup_dir = body.get("backup_dir") if isinstance(body.get("backup_dir"), str) else ""
        # el explorador solo deja elegir dentro del home y los discos externos; aquí se vuelve a exigir (no se fía del cliente)
        for path in [x for key in ("dirs", "files") for x in spec.get(key, [])] + ([spec["glob"]] if "glob" in spec else []) + \
                ([backup_dir] if backup_dir else []):
            static = re.split(r"[*?\[]", os.path.expanduser(path), maxsplit=1)[0]
            if not os.path.isabs(static) or ".." in static.split("/") or not self._allowed(static or "/"):
                raise ApiError(403, "carpeta fuera de las permitidas: %s" % path)
        with self.store.lock:
            ov = self.store.state.setdefault("saves", {})
            if spec:
                ov.setdefault(g["id"], {})["spec"] = spec
            if backup_dir:
                ov.setdefault(g["id"], {})["backup_dir"] = backup_dir
            if not spec and not backup_dir:
                ov.pop(g["id"], None)                               # sin datos: vuelve a lo que traiga la biblioteca
            self.store.save_state()
        return {"ok": True}

    def saves_backup(self, q):
        g, p = self._port_for(q)
        spec, dest, slug = self._saves_cfg(g, p)
        try:
            out = saves.backup(spec, dest, slug, {"game": g["id"], "name": g.get("name", "")})
        except saves.SaveError as e:
            raise ApiError(409, str(e))
        with self.store.lock:
            self.store.state.setdefault("backups", {})[g["id"]] = int(time.time())
            self.store.save_state()
        return {"ok": True, "file": out.name}

    def saves_restore(self, q):
        g, p = self._port_for(q)
        spec, dest, slug = self._saves_cfg(g, p)
        name = q.get("file", "")
        if not name or "/" in name or name.startswith(".") or not name.endswith(".tar.gz"):
            raise ApiError(400, "archivo no válido")                 # solo el nombre de un respaldo de ESTE juego, nunca una ruta
        archive = os.path.join(dest, name)
        if not os.path.isfile(archive):
            raise ApiError(404, "ese respaldo no existe")
        try:
            return {"ok": True, **saves.restore(archive, spec, dest, slug)}
        except saves.SaveError as e:
            raise ApiError(409, str(e))

    def saves_open(self, q):
        g, p = self._port_for(q)
        spec, _, _ = self._saves_cfg(g, p)
        path = saves.folder(spec) if spec else ""
        if not path or not os.path.isdir(path):
            raise ApiError(404, "no hay carpeta de partidas")
        self.open_fn(path)
        return {"ok": True}

    # --- arte manual de SteamGridDB (la clave nunca sale del core)
    def _art_client(self):
        key = art.load_key()
        if not key:
            raise ApiError(409, "Configura tu clave de SteamGridDB para buscar arte")
        if not art.key_permissions_ok():
            raise ApiError(403, "La clave de SteamGridDB debe tener permisos 0600")
        return art.Client(key)

    def art_browse(self, q):
        g = self.store.find_game(q.get("id", ""))
        if not g:
            raise ApiError(404, "juego desconocido")
        kind = q.get("kind", "")
        if kind not in art.KINDS:
            raise ApiError(400, "tipo de arte no válido")
        try:
            page, sgid = int(q.get("page", "0")), int(q.get("sgid", "0"))
            if page < 0 or sgid < 0:
                raise ValueError
            result = self._art_client().browse(g, kind, page, sgid)
            current = (((self.store.state.get("art_sources") or {}).get(g["id"]) or {}).get(kind) or "")
            for item in result["items"]:
                item["cur"] = item["url"] == current
            return result
        except ValueError:
            raise ApiError(400, "página o edición no válida")
        except art.ArtError as e:
            raise ApiError(502, str(e))

    def art_pick(self, q):
        g = self.store.find_game(q.get("id", ""))
        if not g:
            raise ApiError(404, "juego desconocido")
        kind = q.get("kind", "")
        if kind not in art.KINDS:
            raise ApiError(400, "tipo de arte no válido")
        try:
            page, sgid, index = int(q.get("page", "0")), int(q.get("sgid", "0")), int(q.get("index", "-1"))
            if page < 0 or sgid <= 0 or index < 0 or index >= 50:
                raise ValueError
            client = self._art_client()
            result = client.browse(g, kind, page, sgid)
            if index >= len(result["items"]):
                raise ApiError(400, "opción de arte fuera de rango")
            slug = (g.get("art") or {}).get("slug") or g["id"]
            client.download(result["items"][index]["url"], art.art_dir(slug, kind))
            files = art.cached_files(slug, kind)
            with self.store.lock:
                self.store.state.setdefault("art", {}).setdefault(g["id"], {})[kind] = max(0, len(files) - 1)
                self.store.state.setdefault("art_sources", {}).setdefault(g["id"], {})[kind] = result["items"][index]["url"]
                self.store.save_state()
            return {"ok": True, "kind": kind}
        except ValueError:
            raise ApiError(400, "edición, página u opción de arte no válida")
        except art.ArtError as e:
            raise ApiError(502, str(e))

    def art_cycle(self, q):
        g = self.store.find_game(q.get("id", ""))
        if not g:
            raise ApiError(404, "juego desconocido")
        kind = q.get("kind", "")
        if kind not in art.KINDS:
            raise ApiError(400, "tipo de arte no válido")
        try:
            delta = int(q.get("dir", "1"))
        except ValueError:
            raise ApiError(400, "dirección no válida")
        if delta not in (-1, 1):
            raise ApiError(400, "dirección no válida")
        slug = (g.get("art") or {}).get("slug") or g["id"]
        files = art.cached_files(slug, kind)
        if len(files) < 2:
            raise ApiError(409, "Este juego no tiene otras opciones de arte descargadas")
        with self.store.lock:
            selected = self.store.state.setdefault("art", {}).setdefault(g["id"], {})
            selected[kind] = (int(selected.get(kind, 0) or 0) + delta) % len(files)
            ((self.store.state.get("art_sources") or {}).get(g["id"]) or {}).pop(kind, None)
            self.store.save_state()
            index = selected[kind]
        return {"ok": True, "index": index}

    # --- mando
    def pad_gate(self) -> bool:
        """¿Se entregan los botones del mando a la estantería? No con un juego abierto ni con el escritorio tapado."""
        now = time.time()
        if now - self._gate_t > 1.0:
            cmds = self.scan_fn()
            self._gate_v = not any(self._is_running(g, p, cmds) for g in self.store.games()
                                   for p in g.get("ports", []) if games_refresh.port_installed(p))
            self._gate_t = now
        # Con el Big Menu abierto (ventana de capa con el teclado en exclusiva) el mando es suyo aunque haya ventanas con foco.
        # Solo vale si la UI sigue viva: su petición larga a /events debe haber llegado hace poco.
        if self.menu_open and time.time() - self._last_poll < 30:
            return self._gate_v
        return self._gate_v and self.desktop_visible

    def set_menu_state(self, q):
        self.menu_open = str(q.get("open", "0")) not in ("0", "false", "False")
        return {"ok": True, "open": self.menu_open}

    def events(self, q):
        self._last_poll = time.time()
        try:
            since, wait = int(q.get("since", -1)), min(25.0, max(0.0, float(q.get("wait", 20))))
        except ValueError:
            raise ApiError(400, "parámetros no válidos")
        r = self.bus.wait(since, wait)
        self._last_poll = time.time()
        return r

    def pad_status(self, q):
        return {**self.bus.pad, "active": self.pad_gate()}

    def emit(self, q):
        k = q.get("k", "")
        if k not in PAD_KEYS:
            raise ApiError(400, "tecla no válida")
        if self.pad_gate():
            self.bus.push(k)
        return {"ok": True}

    def toggle_menu(self) -> None:
        """Tecla Windows: abre o cierra el Big Menu. No pasa por el filtro del mando (no es un botón del mando)."""
        self.bus.push("MENU")

    def set_desktop_state(self, active: bool, covered: bool) -> None:
        """active: ninguna ventana normal tiene el foco, así que el mando es de la estantería. covered: una ventana
        maximizada o a pantalla completa la tapa (la UI puede pausar animaciones)."""
        self.desktop_visible = bool(active)
        self.bus.set_desktop(bool(active), bool(covered))

    def set_desktop(self, q):
        off = ("0", "false", "False")
        self.set_desktop_state(str(q.get("visible", "1")) not in off, str(q.get("covered", "0")) not in off + ("",))
        return {"ok": True, "visible": self.desktop_visible}

    def serve(self):
        threading.Thread(target=self.httpd.serve_forever, daemon=True).start()

    def stop(self):
        self.httpd.shutdown()
        self.httpd.server_close()

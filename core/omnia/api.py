"""API HTTP local de Omnia.

Reglas de seguridad (ver security.py):
  * Solo 127.0.0.1 y Host propio; sin CORS (nunca se responde a un preflight).
  * Todo menos /health exige `Authorization: Bearer <token>`.
  * Las rutas que cambian algo solo aceptan POST.
  * El comando de lanzamiento sale de la biblioteca del usuario, nunca de la petición.
"""
import json
import threading
import time
import urllib.parse
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

from . import apps, art, launcher, procs, security
from .events import EventBus
from .games.base import Detector
from .games import refresh as games_refresh


PAD_KEYS = {"l", "r", "u", "d", "A", "B", "X", "Y", "LB", "RB", "LT", "RT", "START", "SELECT", "MODE"}


class ApiError(Exception):
    def __init__(self, code: int, msg: str):
        super().__init__(msg)
        self.code, self.msg = code, msg


class Api:
    def __init__(self, store, token: str, detectors=(), port: int = 0, launch_fn=launcher.launch, scan_fn=procs.scan, bus=None,
                 catalog=None, app_launch_fn=apps.launch):
        self.store, self.token, self.detectors, self.launch_fn, self.scan_fn = store, token, list(detectors), launch_fn, scan_fn
        self.bus = bus or EventBus()
        self.catalog, self.app_launch_fn = catalog or apps.Catalog(), app_launch_fn
        self.desktop_visible = True          # lo actualiza el vigilante de ventanas de KWin (D-Bus); por defecto se asume activo
        self._gate_t, self._gate_v = 0.0, True
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
                out.append({"id": g["id"], "name": g["name"], "src": g.get("src", ""), "platform": g.get("platform", ""),
                            "ports": [{"id": p["id"], "name": p["name"], "running": self._is_running(g, p, cmds)} for p in ports],
                            "running": any(self._is_running(g, p, cmds) for p in ports),
                            **self._art(g),
                            "fav": g["id"] in fav, "hidden": g["id"] in hid})
        return {"games": out}

    @staticmethod
    def _art(g):
        slug = (g.get("art") or {}).get("slug") or g["id"]
        out = {}
        for kind in art.KINDS:
            f = art.cached(slug, kind)
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

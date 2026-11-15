"""API HTTP local de Omnia.

Reglas de seguridad (ver security.py):
  * Solo 127.0.0.1 y Host propio; sin CORS (nunca se responde a un preflight).
  * Todo menos /health exige `Authorization: Bearer <token>`.
  * Las rutas que cambian algo solo aceptan POST.
  * El comando de lanzamiento sale de la biblioteca del usuario, nunca de la petición.
"""
import json
import threading
import urllib.parse
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

from . import launcher, procs, security
from .games.base import Detector
from .games import refresh as games_refresh


class ApiError(Exception):
    def __init__(self, code: int, msg: str):
        super().__init__(msg)
        self.code, self.msg = code, msg


class Api:
    def __init__(self, store, token: str, detectors=(), port: int = 0, launch_fn=launcher.launch, scan_fn=procs.scan):
        self.store, self.token, self.detectors, self.launch_fn, self.scan_fn = store, token, list(detectors), launch_fn, scan_fn
        self.routes = {
            "/health": ("GET", False, self.health),
            "/library": ("GET", True, self.library),
            "/library/refresh": ("POST", True, self.refresh),
            "/game/fav": ("POST", True, lambda q: self.toggle("game_fav", q)),
            "/game/hide": ("POST", True, lambda q: self.toggle("game_hidden", q)),
            "/launch": ("POST", True, self.launch),
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
                            "fav": g["id"] in fav, "hidden": g["id"] in hid})
        return {"games": out}

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

    def serve(self):
        threading.Thread(target=self.httpd.serve_forever, daemon=True).start()

    def stop(self):
        self.httpd.shutdown()
        self.httpd.server_close()

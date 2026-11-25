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
import shutil
import subprocess
import threading
import time
import urllib.parse
from pathlib import Path
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

from . import (
    apps,
    art,
    audio_out,
    fsbrowse,
    importer,
    launcher,
    library_metadata,
    library_paths,
    paths,
    manual,
    online_catalog,
    package_installs,
    pad,
    port_catalog,
    power,
    procs,
    roms,
    saves,
    security,
    store_news,
    system,
    templates,
)
from .events import EventBus
from .games import refresh as games_refresh
from . import descriptor, mangohud, sounds
from .games.base import Detector
from .games.steam import download_jobs as steam_download_jobs
from .store import load_json
from .themes import accent_for, normalize_theme

DEFAULT_BACKUP_ROOT = "~/Juegos/_Partidas"        # donde van los respaldos de un juego que no tiene carpeta propia
PAD_KEYS = {"l", "r", "u", "d", "A", "B", "X", "Y", "LB", "RB", "LT", "RT", "START", "SELECT", "MODE"}
_LIBRARY_LABELS = {
    "Port recompilado": {"es": "Port nativo", "en": "Native port"},
    "Port nativo": {"es": "Port nativo", "en": "Native port"},
    "Port instalado": {"es": "Port instalado", "en": "Installed port"},
    "PC · Port recompilado": {"es": "PC · Port nativo", "en": "PC · Native port"},
    "PC · Port nativo": {"es": "PC · Port nativo", "en": "PC · Native port"},
    "Emulador": {"es": "Emulador", "en": "Emulator"},
    "Juego de Windows": {"es": "Juego de Windows", "en": "Windows game"},
    "Juego nativo": {"es": "Juego nativo", "en": "Native game"},
}


def _library_label(value, language):
    return _LIBRARY_LABELS.get(str(value), {}).get(language, value)


class ApiError(Exception):
    def __init__(self, code: int, msg: str):
        super().__init__(msg)
        self.code, self.msg = code, msg


class Api:
    def __init__(self, store, token: str, detectors=(), port: int = 0, launch_fn=launcher.launch, scan_fn=procs.scan, bus=None,
                 catalog=None, app_launch_fn=apps.launch, fs_roots=None, open_fn=None, backup_root=DEFAULT_BACKUP_ROOT):
        self.store, self.token, self.detectors, self.launch_fn, self.scan_fn = store, token, list(detectors), launch_fn, scan_fn
        self.detectors_by_src = {d.name: d for d in self.detectors}
        self.process_snapshot = procs.Snapshot(scan_fn, ttl=1.0)
        manual.migrate_bedrock_on_linux(store)
        self.bus = bus or EventBus()
        self.catalog, self.app_launch_fn = catalog or apps.Catalog(), app_launch_fn
        self.fs_roots, self.backup_root = fs_roots, backup_root
        self.package_installs = package_installs.PackageInstallManager(self.store, self._roots, on_change=self.bus.games_changed)
        self.store_news = store_news.StoreNews()
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
            "/library/roots": ("GET", True, self.library_roots),
            "/library/roots/set": ("POST", True, self.library_roots_set),
            "/settings/open": ("POST", True, self.settings_open),
            "/settings": ("GET", True, self.settings),
            "/settings/language": ("POST", True, self.settings_language),
            "/settings/animated-background": ("POST", True, self.settings_animated_background),
            "/settings/install-root": ("POST", True, self.settings_install_root),
            "/settings/update-check": ("POST", True, self.settings_update_check),
            "/settings/mangohud": ("POST", True, self.settings_mangohud),
            "/settings/sounds": ("POST", True, self.settings_sounds),
            "/settings/intro": ("POST", True, self.settings_intro),
            "/settings/profile": ("POST", True, self.settings_profile),
            "/audio/devices": ("GET", True, self.audio_devices),
            "/audio/input/set": ("POST", True, self.audio_input_set),
            "/audio/level": ("POST", True, self.audio_level),
            "/stats": ("GET", True, self.play_stats),
            "/discord": ("GET", True, self.discord_status),
            "/settings/discord": ("POST", True, self.settings_discord),
            "/stores": ("GET", True, self.stores_list),
            "/stores/web-session/clear": ("POST", True, self.stores_clear_web_session),
            "/stores/login-url": ("GET", True, self.stores_login_url),
            "/stores/login": ("POST", True, self.stores_login),
            "/stores/logout": ("POST", True, self.stores_logout),
            "/stores/news": ("GET", True, self.stores_news),
            "/stores/library": ("GET", True, self.stores_library),
            "/pads": ("GET", True, self.pads),
            "/pads/settings": ("POST", True, self.pads_settings),
            "/pads/rumble": ("POST", True, self.pads_rumble),
            "/folders/open": ("POST", True, self.folder_open),
            "/selection": ("GET", True, self.selection),
            "/selection/set": ("POST", True, self.selection_set),
            "/view/set": ("POST", True, self.view_set),
            "/library/refresh": ("POST", True, self.refresh),
            "/game/fav": ("POST", True, lambda q: self.toggle("game_fav", q)),
            "/game/hide": ("POST", True, lambda q: self.toggle("game_hidden", q)),
            "/launch": ("POST", True, self.launch),
            "/apps": ("GET", True, self.apps_list),
            "/app/launch": ("POST", True, self.app_launch),
            "/app/fav": ("POST", True, self.app_fav),
            "/menu": ("POST", True, lambda q: self.toggle_menu(q.get("mode") == "power") or {"ok": True}),
            "/menu/state": ("POST", True, self.set_menu_state),
            "/gamemode": ("GET", True, lambda q: self.gamemode.status() if self.gamemode else {"enabled": False, "active": False}),
            "/fs/list": ("GET", True, self.fs_list),
            "/templates": ("GET", True, lambda q: {"templates": templates.catalog()}),
            "/game/add": ("POST", True, self.game_add),
            "/game/catalog-link": ("POST", True, self.game_catalog_link),
            "/game/suggest": ("GET", True, self.game_suggest),
            "/rom/scan": ("GET", True, self.rom_scan),
            "/rom/add": ("POST", True, self.rom_add),
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
            "/game/metadata": ("GET", True, self.game_metadata),
            "/game/activity": ("GET", True, self.game_activity),
            "/art/browse": ("GET", True, self.art_browse),
            "/art/pick": ("POST", True, self.art_pick),
            "/art/cycle": ("POST", True, self.art_cycle),
            "/art/local": ("POST", True, self.art_local),
            "/art/choose": ("POST", True, self.art_choose),
            "/art/tmp": ("GET", True, self.art_tmp),
            "/art/reset": ("POST", True, self.art_reset),
            "/catalog/games": ("GET", True, self.catalog_games),
            "/catalog/game": ("GET", True, self.catalog_game),
            "/catalog/platforms": ("GET", True, self.catalog_platforms),
            "/catalog/rom-identifiers": ("GET", True, self.catalog_rom_identifiers),
            "/catalog/install-packages": ("GET", True, self.catalog_install_packages),
            "/installations": ("GET", True, self.installations_snapshot),
            "/stores/install": ("POST", True, self.stores_install),
            "/installations/start": ("POST", True, self.installation_start),
            "/installations/cancel": ("POST", True, self.installation_cancel),
            "/installations/pause": ("POST", True, self.installation_pause),
            "/installations/resume": ("POST", True, self.installation_resume),
            "/installations/remove": ("POST", True, self.installation_remove),
            "/installations/update": ("POST", True, self.installation_update),
            "/installations/dismiss": ("POST", True, self.installation_dismiss),
            "/installations/retry": ("POST", True, self.installation_retry),
            "/audio": ("GET", True, self.audio_status),
            "/system": ("GET", True, self.system_status),
            "/audio/outputs": ("GET", True, self.audio_outputs),
            "/audio/set": ("POST", True, self.audio_set),
            "/power": ("POST", True, self.power_action),
            "/events": ("GET", True, self.events),
            "/pad": ("GET", True, self.pad_status),
            "/emit": ("POST", True, self.emit),
            "/desktop": ("POST", True, self.set_desktop),
        }
        api = self

        class BoundedHTTPServer(ThreadingHTTPServer):
            request_queue_size = 32
            daemon_threads = True
            block_on_close = False

            def __init__(self, address, handler):
                self._slots = threading.BoundedSemaphore(32)
                super().__init__(address, handler)

            def process_request(self, request, client_address):
                if not self._slots.acquire(blocking=False):
                    try:
                        request.sendall(b"HTTP/1.1 503 Service Unavailable\r\nConnection: close\r\nContent-Length: 0\r\n\r\n")
                    except OSError:
                        pass
                    self.shutdown_request(request)
                    return
                try:
                    super().process_request(request, client_address)
                except Exception:
                    self._slots.release()
                    raise

            def process_request_thread(self, request, client_address):
                try:
                    super().process_request_thread(request, client_address)
                finally:
                    self._slots.release()

        class Handler(BaseHTTPRequestHandler):
            protocol_version = "HTTP/1.1"
            disable_nagle_algorithm = True

            def setup(self):
                super().setup()
                self.connection.settimeout(15)

            def parse_request(self):
                if len(self.raw_requestline) > 8192:
                    self.send_error(414, "URI demasiado larga")
                    return False
                if not super().parse_request():
                    return False
                if self.headers and len(self.headers.as_bytes()) > 16384:
                    self.send_error(431, "cabeceras demasiado grandes")
                    return False
                return True

            def log_message(self, *a):
                pass

            def _send(self, code, obj):
                b = json.dumps(obj).encode()
                self.send_response(code)
                self.send_header("Content-Type", "application/json")
                self.send_header("Content-Length", str(len(b)))
                self.send_header("Cache-Control", "no-store")
                if self.close_connection:
                    self.send_header("Connection", "close")
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
                    try:
                        n = int(self.headers.get("Content-Length") or 0)
                    except ValueError:
                        raise ApiError(400, "Content-Length no válido")
                    if n:
                        if n > 65536:
                            self.close_connection = True
                            raise ApiError(413, "cuerpo demasiado grande")
                        if method == "POST" and self.headers.get_content_type() not in {"application/json", "application/x-www-form-urlencoded"}:
                            self.close_connection = True
                            raise ApiError(415, "se requiere application/json")
                        body = json.loads(self.rfile.read(n) or b"{}")
                        if isinstance(body, dict):
                            q.update({k: v for k, v in body.items() if isinstance(v, (str, int, bool))})
                            q["_body"] = body                       # las rutas que reciben listas leen el cuerpo completo
                    self._send(200, fn(q))
                except ApiError as e:
                    self._send(e.code, {"error": e.msg})
                except (BrokenPipeError, ConnectionResetError):
                    pass
                except Exception:  # noqa: BLE001 — el límite HTTP devuelve un error sin exponer detalles internos.
                    self._send(500, {"error": "error interno"})

            def do_GET(self):
                self._handle("GET")

            def do_POST(self):
                self._handle("POST")

            def do_OPTIONS(self):          # sin CORS: el preflight de un navegador siempre falla
                self._send(405, {"error": "sin CORS"})

        self.httpd = BoundedHTTPServer(("127.0.0.1", port), Handler)
        self.port = self.httpd.server_address[1]

    # --- rutas
    def health(self, q):
        return {"ok": True}

    def selection(self, q):
        """Lectura ligera para el wallpaper; admite espera larga para avisar cambios sin sondeo frecuente."""
        if "since" in q:
            try:
                since = int(q.get("since", "-1"))
                wait = min(25.0, max(0.0, float(q.get("wait", 20))))
            except ValueError:
                raise ApiError(400, "revisión o espera no válida")
            if since >= 0:
                self.bus.wait_selection(since, wait)
        revision = self.bus.selection_revision
        filter_key = self.store.state.get("filter_key", "all")
        # La selección es propia de la vista donde se hizo. No reaplicar un ID
        # guardado en otra plataforma: cada cambio de sección empieza en el índice 0.
        gid = self.store.state.get("selected_game", "")
        if self.store.state.get("selected_filter_key", "") != filter_key:
            gid = ""
        game = self.store.find_game(gid) if gid else None
        config = load_json(self.store.dir / "config.json", {})
        if game and not any(library_paths.port_visible(game, p, config) for p in game.get("ports", [])):
            game = None
        if not game:
            return {"id": "", "name": "", "fondo": "", "pal": ["#10150f"], "acc": "#e6d9a0", "revision": revision,
                    "filterKey": filter_key, "searchText": self.store.state.get("search_text", "")}
        return {"id": gid, "name": game.get("name", ""), "fondo": self._art(game, self.store.state).get("fondo", ""),
                "pal": game.get("pal") or ["#10150f"], "acc": game.get("acc", "#e6d9a0"), "revision": revision,
                "filterKey": filter_key, "searchText": self.store.state.get("search_text", "")}

    def selection_set(self, q):
        gid = str(q.get("id", ""))
        if gid and not self.store.find_game(gid):
            raise ApiError(404, "juego desconocido")
        filter_key = str(q.get("filterKey", self.store.state.get("filter_key", "all")))[:64] or "all"
        changed = False
        with self.store.lock:
            if (self.store.state.get("selected_game", "") != gid
                    or self.store.state.get("selected_filter_key", "") != filter_key):
                self.store.state["selected_game"] = gid
                self.store.state["selected_filter_key"] = filter_key
                self.store.save_state_soon()
                changed = True
        if changed:
            self.bus.selection_changed()
        return {"ok": True, "id": gid, "filterKey": filter_key}

    def view_set(self, q):
        key = str(q.get("filterKey", "all"))[:64] or "all"
        search = str(q.get("searchText", ""))[:256]
        changed = False
        with self.store.lock:
            view_changed = self.store.state.get("filter_key", "all") != key
            if view_changed or self.store.state.get("search_text", "") != search:
                self.store.state["filter_key"], self.store.state["search_text"] = key, search
                # Si la selección todavía pertenece a la plataforma anterior,
                # elimínala. Una selección nueva enviada para `key` se conserva.
                if view_changed and self.store.state.get("selected_filter_key", "") != key:
                    self.store.state["selected_game"] = ""
                    self.store.state["selected_filter_key"] = ""
                self.store.save_state_soon()
                changed = True
        if changed:
            self.bus.selection_changed()
        return {"ok": True, "filterKey": key, "searchText": search}

    def _notify_selected_art(self, gid, kind):
        if kind == "fondo" and self.store.state.get("selected_game", "") == gid:
            self.bus.selection_changed()

    def audio_outputs(self, q):
        try:
            return {"ok": True, "items": audio_out.list_outputs(getattr(self, "pactl_run", subprocess.run))}
        except audio_out.AudioOutError as e:
            return {"ok": False, "items": [], "error": str(e)}

    def audio_set(self, q):
        try:
            audio_out.set_output(q.get("sink", ""), q.get("port", ""), getattr(self, "pactl_run", subprocess.run))
        except audio_out.AudioOutError as e:
            raise ApiError(400, str(e))
        return {"ok": True}

    def power_action(self, q):
        action = q.get("a", "")
        if action not in power.COMMANDS:
            raise ApiError(400, "acción de energía no válida")
        if not power.run(action, getattr(self, "power_spawn", subprocess.Popen)):
            raise ApiError(500, "no se pudo ejecutar la acción")
        return {"ok": True}

    def settings_open(self, q):
        import shutil
        command = shutil.which("omnia-settings")
        if not command:
            local = os.path.expanduser("~/.local/bin/omnia-settings")
            command = local if os.path.isfile(local) and os.access(local, os.X_OK) else None
        if not command:
            raise ApiError(409, "Actualiza Omnia para instalar los ajustes generales.")
        runner = shutil.which("systemd-run")
        if not runner:
            raise ApiError(503, "Falta systemd-run para abrir los ajustes fuera del núcleo de Omnia.")
        import uuid
        args = [runner, "--user", "--quiet", "--collect", "--property=Type=exec",
                "--unit=omnia-settings-" + uuid.uuid4().hex]
        for name in ("DISPLAY", "WAYLAND_DISPLAY", "XDG_RUNTIME_DIR", "DBUS_SESSION_BUS_ADDRESS", "XDG_CURRENT_DESKTOP", "QT_QPA_PLATFORMTHEME"):
            if name in os.environ:
                args.append("--setenv=" + name + "=" + os.environ[name])
        try:
            result = subprocess.run(args + ["--", command], check=False, capture_output=True, text=True, timeout=15)
        except (OSError, subprocess.TimeoutExpired):
            raise ApiError(503, "No se pudo iniciar la unidad de ajustes de Omnia.")
        if result.returncode:
            raise ApiError(503, "KDE no pudo iniciar los ajustes. Consulta el registro de usuario de systemd.")
        return {"ok": True}

    def settings(self, q):
        cfg = load_json(self.store.dir / "config.json", {})
        position = cfg.get("notification_position", "bottom-right")
        if position not in {"bottom-right", "bottom-left", "top-right", "top-left"}:
            position = "bottom-right"
        theme = normalize_theme(cfg.get("theme"))
        language = cfg.get("language", "es")
        if language not in {"es", "en"}:
            language = "es"
        install_root = cfg.get("install_root", "")
        if not isinstance(install_root, str):
            install_root = ""
        return {"notification_position": position, "theme": theme, "theme_accent": accent_for(theme),
                "language": language, "install_root": install_root,
                "animated_background": cfg.get("animated_background", True) is not False,
                "update_check": cfg.get("update_check", True) is not False,
                "mangohud": cfg.get("mangohud_enabled", False) is True, "mangohud_installed": bool(shutil.which("mangohud")),
                "ui_sounds": cfg.get("ui_sounds", True) is not False, "ui_sound_volume": self._sound_volume(cfg),
                "ui_sound_pack": self._sound_pack(cfg), "ui_sound_packs": sounds.packs(),
                "intro_enabled": cfg.get("intro_enabled", True) is not False, "user_name": self._display_name(cfg),
                "display_name": self._clean_name(cfg.get("display_name"))}

    def settings_language(self, q):
        body = q.get("_body") if isinstance(q.get("_body"), dict) else {}
        language = body.get("language")
        if language not in {"es", "en"}:
            raise ApiError(400, "El idioma debe ser es o en.")
        config_path = self.store.dir / "config.json"
        from .store import write_json_atomic
        with self.store.lock:
            cfg = load_json(config_path, {})
            cfg = cfg if isinstance(cfg, dict) else {}
            cfg["language"] = language
            write_json_atomic(config_path, cfg)
        return {"ok": True, "language": language}

    def settings_animated_background(self, q):
        """Activa o desactiva el fondo animado de BigMode (constelación)."""
        body = q.get("_body") if isinstance(q.get("_body"), dict) else {}
        enabled = body.get("enabled")
        if not isinstance(enabled, bool):
            raise ApiError(400, "enabled debe ser verdadero o falso.")
        config_path = self.store.dir / "config.json"
        from .store import write_json_atomic
        with self.store.lock:
            cfg = load_json(config_path, {})
            cfg = cfg if isinstance(cfg, dict) else {}
            cfg["animated_background"] = enabled
            write_json_atomic(config_path, cfg)
        return {"ok": True, "animated_background": enabled}

    def folder_open(self, q):
        """Abre en el gestor de archivos una carpeta con nombre del descriptor del port (partidas, logs, carpeta del juego…)."""
        body = q.get("_body") if isinstance(q.get("_body"), dict) else {}
        game, name = self.store.find_game(str(body.get("gameId") or "")), str(body.get("folder") or "")
        if not game:
            raise ApiError(404, "juego desconocido")
        for port in game.get("ports", []):
            path = self._descriptor_info(game, port).get("folders", {}).get(name)
            if path and os.path.isdir(path) and self._allowed(path):
                self.open_fn(path)
                return {"ok": True}
        raise ApiError(404, "esa carpeta no existe")

    @staticmethod
    def _sound_volume(cfg) -> int:
        v = cfg.get("ui_sound_volume", 70)
        return v if isinstance(v, int) and not isinstance(v, bool) and 0 <= v <= 100 else 70

    @staticmethod
    def _sound_pack(cfg) -> str:
        ids = [p["id"] for p in sounds.packs()]
        pack = cfg.get("ui_sound_pack", "omnia")
        return pack if pack in ids else (ids[0] if ids else "omnia")

    @staticmethod
    def _clean_name(value) -> str:
        """Nombre elegido por la persona para el saludo: sin caracteres de control ni «<>», 24 como máximo."""
        if not isinstance(value, str):
            return ""
        return re.sub(r"\s+", " ", re.sub(r"[\x00-\x1f<>]", "", value)).strip()[:24]

    def _display_name(self, cfg) -> str:
        """A quién saluda la bienvenida: el nombre que la persona eligió en Ajustes y, si no, el del usuario del sistema que ejecuta Omnia."""
        return self._clean_name(cfg.get("display_name")) or self._user_name()

    @staticmethod
    def _user_name() -> str:
        """Nombre para el saludo de la bienvenida: el nombre completo del sistema (primera palabra) o, si no, el usuario."""
        try:
            import pwd
            entry = pwd.getpwuid(os.getuid())
            full = (entry.pw_gecos or "").split(",")[0].strip()
            return (full.split()[0] if full else entry.pw_name)[:30]
        except (KeyError, ImportError, OSError):
            return os.environ.get("USER", "")[:30]

    def _update_config(self, **changes):
        config_path = self.store.dir / "config.json"
        from .store import write_json_atomic
        with self.store.lock:
            cfg = load_json(config_path, {})
            cfg = cfg if isinstance(cfg, dict) else {}
            cfg.update(changes)
            write_json_atomic(config_path, cfg)
            return cfg

    def settings_sounds(self, q):
        """Sonidos de la interfaz de Big Mode: activar, volumen propio (0–100) y paquete."""
        body = q.get("_body") if isinstance(q.get("_body"), dict) else {}
        changes = {}
        if "enabled" in body:
            if not isinstance(body["enabled"], bool):
                raise ApiError(400, "enabled debe ser verdadero o falso.")
            changes["ui_sounds"] = body["enabled"]
        if "volume" in body:
            v = body["volume"]
            if not isinstance(v, int) or isinstance(v, bool) or not 0 <= v <= 100:
                raise ApiError(400, "el volumen debe ser un entero de 0 a 100.")
            changes["ui_sound_volume"] = v
        if "pack" in body:
            if body["pack"] not in [p["id"] for p in sounds.packs()]:
                raise ApiError(400, "paquete de sonidos no disponible.")
            changes["ui_sound_pack"] = body["pack"]
        if not changes:
            raise ApiError(400, "indica enabled, volume o pack.")
        cfg = self._update_config(**changes)
        return {"ok": True, "ui_sounds": cfg.get("ui_sounds", True) is not False, "ui_sound_volume": self._sound_volume(cfg),
                "ui_sound_pack": self._sound_pack(cfg)}

    def settings_profile(self, q):
        """Nombre que usa la bienvenida para saludar (vacío = el del usuario del sistema)."""
        body = q.get("_body") if isinstance(q.get("_body"), dict) else {}
        if not isinstance(body.get("display_name"), str):
            raise ApiError(400, "display_name debe ser un texto.")
        name = self._clean_name(body["display_name"])
        cfg = self._update_config(display_name=name)
        return {"ok": True, "display_name": name, "user_name": self._display_name(cfg)}

    def settings_intro(self, q):
        """Activa o desactiva la animación de bienvenida de Big Mode."""
        body = q.get("_body") if isinstance(q.get("_body"), dict) else {}
        if not isinstance(body.get("enabled"), bool):
            raise ApiError(400, "enabled debe ser verdadero o falso.")
        self._update_config(intro_enabled=body["enabled"])
        return {"ok": True, "intro_enabled": body["enabled"]}

    # --- audio: salida y micrófono con volumen y silencio ---
    def audio_devices(self, q):
        run = getattr(self, "pactl_run", subprocess.run)
        out = {"ok": True}
        for target, lister in (("output", audio_out.list_outputs), ("input", audio_out.list_inputs)):
            try:
                out[target] = {"items": lister(run), **audio_out.get_level(target, run)}
            except audio_out.AudioOutError as e:
                out[target] = {"items": [], "volume": 0, "muted": False, "error": str(e)}
        return out

    def audio_input_set(self, q):
        body = q.get("_body") if isinstance(q.get("_body"), dict) else {}
        try:
            audio_out.set_input(str(body.get("source", "")), getattr(self, "pactl_run", subprocess.run))
        except audio_out.AudioOutError as e:
            raise ApiError(400, str(e))
        return {"ok": True}

    def audio_level(self, q):
        body = q.get("_body") if isinstance(q.get("_body"), dict) else {}
        target = body.get("target")
        if target not in ("output", "input"):
            raise ApiError(400, "target debe ser output o input.")
        if "muted" in body and not isinstance(body["muted"], bool):
            raise ApiError(400, "muted debe ser verdadero o falso.")
        run = getattr(self, "pactl_run", subprocess.run)
        try:
            audio_out.set_level(target, volume=body.get("volume"), muted=body.get("muted"), run=run)
            return {"ok": True, **audio_out.get_level(target, run)}
        except audio_out.AudioOutError as e:
            raise ApiError(400, str(e))

    # --- mandos: estado en vivo, ajustes y vibración ---
    def _pad_item(self, pad_id):
        reader = getattr(self, "pad_reader", None)
        if reader is None:
            raise ApiError(503, "el lector de mandos no está activo.")
        for item in reader.snapshot():
            if item["id"] == pad_id:
                return reader, item
        raise ApiError(404, "mando desconocido.")

    def pads(self, q):
        reader = getattr(self, "pad_reader", None)
        return {"ok": reader is not None, "pads": reader.snapshot() if reader else []}

    def pads_settings(self, q):
        body = q.get("_body") if isinstance(q.get("_body"), dict) else {}
        reader, item = self._pad_item(body.get("id"))
        mine = {}
        if "nickname" in body:
            name = re.sub(r"\s+", " ", re.sub(r"[\x00-\x1f<>]", "", str(body["nickname"]))).strip()[:24]
            mine["nickname"] = name
        if "family" in body:
            if body["family"] not in ("auto", *pad.FAMILIES):
                raise ApiError(400, "familia de iconos no válida.")
            mine["family"] = "" if body["family"] == "auto" else body["family"]
        if "deadzone" in body:
            dz = body["deadzone"]
            if isinstance(dz, bool) or not isinstance(dz, (int, float)) or not 0.05 <= dz <= 0.4:
                raise ApiError(400, "la zona muerta debe estar entre 0,05 y 0,4.")
            mine["deadzone"] = round(float(dz), 3)
        if "haptics" in body:
            if not isinstance(body["haptics"], bool):
                raise ApiError(400, "haptics debe ser verdadero o falso.")
            mine["haptics"] = body["haptics"]
        if not mine:
            raise ApiError(400, "no hay nada que cambiar.")
        config_path = self.store.dir / "config.json"
        from .store import write_json_atomic
        with self.store.lock:
            cfg = load_json(config_path, {})
            cfg = cfg if isinstance(cfg, dict) else {}
            pads = cfg.get("pads") if isinstance(cfg.get("pads"), dict) else {}
            pads[item["key"]] = {**(pads.get(item["key"]) or {}), **mine}
            cfg["pads"] = pads
            write_json_atomic(config_path, cfg)
        reader.configure(pads)
        return {"ok": True, "pad": self._pad_item(body.get("id"))[1]}

    def play_stats(self, q):
        """Estadísticas de juego (horas, partidas, racha, top, días recientes) del historial de sesiones."""
        from . import stats
        raw = q.get("days", "14")
        raw = raw[0] if isinstance(raw, list) and raw else raw
        if str(raw) not in ("7", "14", "30"):
            raise ApiError(400, "days debe ser 7, 14 o 30.")
        with self.store.lock:
            state = dict(self.store.state)
            games = list(self.store.games())
            active = dict(self.sessions.active) if self.sessions else {}
            history = list(state.get("history") or [])
        state["history"] = history
        from .sessions import HISTORY_MAX
        return stats.compute(state, games, active, time.time(), int(raw), HISTORY_MAX)

    def discord_settings(self) -> dict:
        cfg = load_json(self.store.dir / "config.json", {})
        cfg = cfg if isinstance(cfg, dict) else {}
        app = cfg.get("discord_app_id", "")
        return {"enabled": cfg.get("discord_enabled") is True, "app_id": app if isinstance(app, str) else "",
                "lang": "en" if cfg.get("language") == "en" else "es"}

    def discord_status(self, q):
        presence = getattr(self, "discord", None)
        s = self.discord_settings()
        base = presence.status() if presence else {"enabled": s["enabled"], "app_id_set": False, "connected": False, "user": "", "socket": False}
        base["app_id"] = s["app_id"]
        return base

    def settings_discord(self, q):
        """Presencia de Discord (nivel A): activar y Application ID (público, de la aplicación que crea el usuario)."""
        import re
        body = q.get("_body") if isinstance(q.get("_body"), dict) else {}
        changes = {}
        if "enabled" in body:
            if not isinstance(body["enabled"], bool):
                raise ApiError(400, "enabled debe ser verdadero o falso.")
            changes["discord_enabled"] = body["enabled"]
        if "app_id" in body:
            app = body["app_id"]
            if not isinstance(app, str) or (app.strip() and not re.fullmatch(r"\d{17,20}", app.strip())):
                raise ApiError(400, "El Application ID son 17 a 20 números (está en discord.com/developers).")
            changes["discord_app_id"] = app.strip()
        if not changes:
            raise ApiError(400, "indica enabled o app_id.")
        self._update_config(**changes)
        presence = getattr(self, "discord", None)
        if presence:
            presence.poke()
        return dict(self.discord_status({}), ok=True)

    def stores_clear_web_session(self, q):
        """Marca para borrar la sesión web de las tiendas (cookies de la ventana de inicio de sesión) al abrir Omnia otra vez.
        No se borra en caliente: la ventana la tiene en uso. Las conexiones (bibliotecas, instalaciones) no se tocan."""
        flag = self.store.dir / "clear-web-session"
        flag.parent.mkdir(parents=True, exist_ok=True)
        flag.write_text("1")
        return {"ok": True, "pending": True}

    def _stores(self):
        if getattr(self, "_store_map", None) is None:
            from .stores import registry
            self._store_map = registry.build(self.store.dir / "stores", runner=getattr(self, "store_runner", None))
        return self._store_map

    def _store(self, q):
        body = q.get("_body") if isinstance(q.get("_body"), dict) else {}
        sid = body.get("store", q.get("store"))
        store = self._stores().get(sid) if isinstance(sid, str) else None
        if store is None:
            raise ApiError(404, "tienda desconocida")
        return store, body

    def stores_list(self, q):
        return {"stores": [s.status() for s in self._stores().values()]}

    def stores_login_url(self, q):
        store, _ = self._store(q)
        return {"url": store.login_url()}

    def stores_login(self, q):
        from .stores.base import StoreError
        store, body = self._store(q)
        try:
            return {"ok": True, "store": store.login(str(body.get("code", "")))}
        except StoreError as e:
            raise ApiError(400, str(e))

    def stores_logout(self, q):
        from .stores.base import StoreError
        store, _ = self._store(q)
        try:
            return {"ok": True, "store": store.logout()}
        except StoreError as e:
            raise ApiError(400, str(e))

    def stores_news(self, q):
        return self.store_news.snapshot(self.store.games(), q.get("lang", "es"))

    def stores_library(self, q):
        from .stores.base import StoreError
        store, _ = self._store(q)
        try:
            games = store.library()
        except StoreError as e:
            raise ApiError(502, str(e))
        for game in games:
            for key in ("art", "hero"):
                image = game.get(key) if isinstance(game, dict) else None
                if isinstance(image, str) and image.startswith("https://"):
                    game[key] = online_catalog.local_or_remote(image)
        mine = {g.get("store_id", {}).get("id") for g in self.store.games()
                if isinstance(g.get("store_id"), dict) and g["store_id"].get("store") == store.id}
        local_ids = {g.get("id") for g in self.store.games()}
        for g in games:
            if g["id"] in mine or (store.id == "steam" and "steam-" + g["id"] in local_ids):
                g["installed"] = True
        return {"games": games}

    def _store_installs(self):
        if getattr(self, "_store_install_mgr", None) is None:
            from .stores.installer import StoreInstalls
            self._store_install_mgr = StoreInstalls(self._stores(), self.store, self._roots, on_change=self.bus.games_changed)
        return self._store_install_mgr

    def installations_snapshot(self, q):
        snap = self.package_installs.snapshot()
        snap["jobs"] = snap["jobs"] + self._store_installs().jobs() + steam_download_jobs()
        return snap

    def stores_install(self, q):
        from .stores.base import StoreError
        body = q.get("_body") if isinstance(q.get("_body"), dict) else {}
        store = body.get("store")
        if not isinstance(store, str) or store not in self._stores():
            raise ApiError(404, "tienda desconocida")
        try:
            return {"ok": True, "job": self._store_installs().start(store, body.get("id"), body.get("title"), body.get("destination"))}
        except StoreError as e:
            raise ApiError(400, str(e))

    def pads_rumble(self, q):
        body = q.get("_body") if isinstance(q.get("_body"), dict) else {}
        reader, item = self._pad_item(body.get("id"))
        num = lambda key, default: min(1.0, max(0.0, float(body.get(key, default)))) if isinstance(body.get(key, default), (int, float)) and not isinstance(body.get(key, default), bool) else default
        ms = body.get("ms", 350)
        ms = ms if isinstance(ms, int) and not isinstance(ms, bool) else 350
        try:
            reader.rumble(item["id"], num("strong", 0.7), num("weak", 0.7), max(1, min(1500, ms)))
        except OSError as e:
            raise ApiError(409, "este mando no admite vibración (" + str(e) + ").")
        return {"ok": True}

    def settings_mangohud(self, q):
        """Muestra u oculta el monitor de rendimiento (MangoHud con el estilo de Omnia) en los juegos que Omnia lanza."""
        body = q.get("_body") if isinstance(q.get("_body"), dict) else {}
        enabled = body.get("enabled")
        if not isinstance(enabled, bool):
            raise ApiError(400, "enabled debe ser verdadero o falso.")
        if enabled and not shutil.which("mangohud"):
            raise ApiError(503, "MangoHud no está instalado. Instálalo desde el gestor de paquetes y vuelve a intentarlo.")
        config_path = self.store.dir / "config.json"
        from .store import write_json_atomic
        with self.store.lock:
            cfg = load_json(config_path, {})
            cfg = cfg if isinstance(cfg, dict) else {}
            cfg["mangohud_enabled"] = enabled
            write_json_atomic(config_path, cfg)
        return {"ok": True, "mangohud": enabled}

    def settings_update_check(self, q):
        """Activa o desactiva el aviso de «Actualización disponible» de los ports instalados."""
        body = q.get("_body") if isinstance(q.get("_body"), dict) else {}
        enabled = body.get("enabled")
        if not isinstance(enabled, bool):
            raise ApiError(400, "enabled debe ser verdadero o falso.")
        config_path = self.store.dir / "config.json"
        from .store import write_json_atomic
        with self.store.lock:
            cfg = load_json(config_path, {})
            cfg = cfg if isinstance(cfg, dict) else {}
            cfg["update_check"] = enabled
            write_json_atomic(config_path, cfg)
        self.bus.games_changed()
        return {"ok": True, "update_check": enabled}

    def settings_install_root(self, q):
        """Guarda una carpeta predeterminada para instalaciones; debe existir y estar bajo una raíz permitida."""
        body = q.get("_body") if isinstance(q.get("_body"), dict) else {}
        raw = body.get("path")
        if not isinstance(raw, str) or not raw.strip() or len(raw) > 4096:
            raise ApiError(400, "Elige una carpeta existente para instalar los juegos.")
        path = os.path.realpath(os.path.expanduser(raw.strip()))
        if not os.path.isdir(path):
            raise ApiError(400, "Elige una carpeta existente para instalar los juegos.")
        if not self._allowed(path):
            raise ApiError(403, "La carpeta de instalación debe estar dentro de una ubicación permitida.")
        config_path = self.store.dir / "config.json"
        from .store import write_json_atomic
        with self.store.lock:
            cfg = load_json(config_path, {})
            if not isinstance(cfg, dict):
                cfg = {}
            cfg["install_root"] = path
            write_json_atomic(config_path, cfg)
        return {"ok": True, "install_root": path}

    def catalog_games(self, q):
        """Catálogo público de Omnia, mediado por el servicio local y con caché offline."""
        try:
            result = online_catalog.list_games(q)
            online_catalog.add_local_art(result.get("items"))
            return {**result, "baseUrl": online_catalog.PUBLIC_ORIGIN}
        except (TypeError, ValueError):
            raise ApiError(400, "Parámetros de catálogo no válidos")

    def catalog_game(self, q):
        result = online_catalog.game_detail(q.get("slug", ""))
        if not result.get("ok") and not result.get("offline"):
            raise ApiError(400, result.get("warning", "Juego no válido"))
        online_catalog.add_local_art([result.get("data")])
        return {**result, "baseUrl": online_catalog.PUBLIC_ORIGIN}

    def catalog_platforms(self, q):
        return {**online_catalog.list_platforms(), "baseUrl": online_catalog.PUBLIC_ORIGIN}

    def catalog_rom_identifiers(self, q):
        return {**online_catalog.list_rom_identifiers(q.get("platform", "")), "baseUrl": online_catalog.PUBLIC_ORIGIN}

    def catalog_install_packages(self, q):
        return {**online_catalog.list_install_packages(q.get("slug", "")), "baseUrl": online_catalog.PUBLIC_ORIGIN}

    def installation_start(self, q):
        body = q.get("_body") if isinstance(q.get("_body"), dict) else {}
        slug, package_id, destination = body.get("slug"), body.get("packageId"), body.get("destination")
        if not all(isinstance(value, str) for value in (slug, package_id, destination)):
            raise ApiError(400, "faltan datos del paquete o carpeta de destino")
        try:
            return {"ok": True, "job": self.package_installs.start(slug, package_id, destination)}
        except package_installs.PackageInstallError as exc:
            raise ApiError(400, str(exc))

    def installation_cancel(self, q):
        body = q.get("_body") if isinstance(q.get("_body"), dict) else {}
        job_id = body.get("jobId")
        if isinstance(job_id, str) and self._store_installs().owns(job_id):
            if not self._store_installs().cancel(job_id):
                raise ApiError(404, "la instalación no está activa")
            return {"ok": True}
        if not isinstance(job_id, str) or not self.package_installs.cancel(job_id):
            raise ApiError(404, "la instalación no está activa")
        return {"ok": True}

    def installation_pause(self, q):
        body = q.get("_body") if isinstance(q.get("_body"), dict) else {}
        job_id = body.get("jobId")
        if not isinstance(job_id, str) or not self.package_installs.pause(job_id):
            raise ApiError(409, "la instalación no se puede pausar en este momento")
        return {"ok": True}

    def installation_resume(self, q):
        body = q.get("_body") if isinstance(q.get("_body"), dict) else {}
        job_id = body.get("jobId")
        if not isinstance(job_id, str) or not self.package_installs.resume(job_id):
            raise ApiError(409, "la instalación no está pausada")
        return {"ok": True}

    def installation_update(self, q):
        body = q.get("_body") if isinstance(q.get("_body"), dict) else {}
        game_id = body.get("gameId")
        if not isinstance(game_id, str):
            raise ApiError(400, "juego no válido")
        running = {game.get("id") for game in self.running_list()}
        try:
            return {"ok": True, "job": self.package_installs.start_update(game_id, lambda gid: gid in running)}
        except package_installs.PackageInstallError as exc:
            raise ApiError(409 if "Cierra el juego" in str(exc) else 400, str(exc))

    def installation_dismiss(self, q):
        body = q.get("_body") if isinstance(q.get("_body"), dict) else {}
        if body.get("all") is True:
            return {"ok": True, "dismissed": self.package_installs.dismiss(only_failed=True) + self._store_installs().dismiss(only_failed=True)}
        job_id = body.get("jobId")
        if isinstance(job_id, str) and self._store_installs().owns(job_id):
            return {"ok": True, "dismissed": self._store_installs().dismiss(job_id)}
        if not isinstance(job_id, str) or not self.package_installs.dismiss(job_id):
            raise ApiError(404, "ese trabajo no existe o sigue en curso")
        return {"ok": True, "dismissed": 1}

    def installation_retry(self, q):
        body = q.get("_body") if isinstance(q.get("_body"), dict) else {}
        job_id = body.get("jobId")
        if not isinstance(job_id, str):
            raise ApiError(400, "trabajo no válido")
        if self._store_installs().owns(job_id):
            raise ApiError(409, "Vuelve a instalarlo desde la pantalla Tiendas.")
        running = {game.get("id") for game in self.running_list()}
        try:
            return {"ok": True, "job": self.package_installs.retry(job_id, lambda gid: gid in running)}
        except package_installs.PackageInstallError as exc:
            raise ApiError(409 if "Cierra el juego" in str(exc) else 400, str(exc))

    def installation_remove(self, q):
        body = q.get("_body") if isinstance(q.get("_body"), dict) else {}
        game_id = body.get("gameId")
        if not isinstance(game_id, str):
            raise ApiError(400, "juego no válido")
        if any(game.get("id") == game_id for game in self.running_list()):
            raise ApiError(409, "Cierra el juego antes de desinstalarlo.")
        try:
            if not self.package_installs.uninstall(game_id, body.get("removeFiles") is not False):
                raise ApiError(404, "la instalación de Omnia no existe")
        except package_installs.PackageInstallError as exc:
            raise ApiError(400, str(exc))
        return {"ok": True, "removed": True}

    def system_status(self, q):
        now = time.monotonic()
        cache = getattr(self, "_system_cache", None)
        if cache is None or now - cache[0] > 5.0:                 # supera el sondeo de 3 s
            config = load_json(self.store.dir / "config.json", {})
            monitor = config.get("monitor_disks")
            if monitor is None:
                monitor = config.get("monitor_disk")
            cache = (now, system.snapshot(monitor=monitor))
            self._system_cache = cache
        return {**cache[1], "live": system.live()}       # la carga en vivo no se cachea (CPU se mide entre llamadas)

    def audio_status(self, q):
        source = getattr(self, "audio", None)
        return source.snapshot() if source else {"available": False, "active": False, "bands": []}

    def _detector(self, g):
        return self.detectors_by_src.get(g.get("auto")) or Detector()

    def _processes(self):
        snapshot = getattr(self, "process_snapshot", None)
        if snapshot is None:
            return self.scan_fn()
        snapshot.scan_fn = self.scan_fn
        return snapshot.get()

    def _is_running(self, g, p, cmdlines):
        return self._detector(g).is_running(g, p, cmdlines)

    def library(self, q):
        revision = self.store.revision * 1_000_000 + getattr(getattr(self, "bus", None), "game_revision", 0)
        try:
            if int(q.get("since", "-1")) == revision:
                return {"revision": revision, "unchanged": True}
        except ValueError:
            raise ApiError(400, "revisión no válida")
        fav, hid = self.store.state.get("game_fav", []), self.store.state.get("game_hidden", [])
        cmds = self._processes()
        out = []
        config = load_json(self.store.dir / "config.json", {})
        language = config.get("language", "es")
        if language not in {"es", "en"}:
            language = "es"
        games = list(self.store.games())
        merged_copies = self._rom_copies(games, config)
        installed_slugs = {x.get("catalogSlug") for x in games if x.get("installPackageId") and x.get("catalogSlug")}
        install_records = {r.get("gameId"): r for r in (self.package_installs.installed() if getattr(self, "package_installs", None) else []) if isinstance(r, dict)}
        for g in games:
            if g["id"] in merged_copies["hidden"]:
                continue                                          # volcado que solo es la copia de un juego que ya aparece (ver _rom_copies)
            ports = [(p, games_refresh.port_installed(p)) for p in g.get("ports", [])]
            ports = [(p, installed) for p, installed in ports if installed and library_paths.port_visible(g, p, config)]
            if ports:
                snap = dict(self.sessions.snapshot(g["id"]) if self.sessions else {"lastPlayed": 0, "totalSecs": 0, "plays": 0, "playingSince": 0})
                ext = g.get("played") or {}                       # historial local importado o registrado en Omnia
                snap["lastPlayed"] = max(snap["lastPlayed"], int(ext.get("last", 0) or 0))
                snap["totalSecs"] = max(snap["totalSecs"], int(ext.get("secs", 0) or 0))
                platform = g.get("platform", "")
                platform_accents = {"n64": "#d9a441", "sw1": "#e8604f", "sw2": "#58a6f0", "pc": "#6fc3c9"}
                port_rows = []
                for p, installed in ports:
                    running = self._is_running(g, p, cmds)
                    port_rows.append({"id": p["id"], "name": p["name"], "running": running,
                                      "chips": [_library_label(label, language) for label in (p.get("chips") or [])],
                                      "description": _library_label(p.get("s", ""), language),
                                      "canLaunch": installed, "canBackup": bool(p.get("saves")) or bool(self._descriptor_info(g, p).get("spec"))})
                desc = next((i for i in (self._descriptor_info(g, p) for p, _ in ports) if i), {})
                session = (self.store.state.get("sessions") or {}).get(g["id"]) or {}
                btime = self.store.state.get("backups", {}).get(g["id"], 0)
                out.append({"id": g["id"], "name": g["name"], "src": g.get("src", ""), "platform": g.get("platform", ""),
                            "catalogSlug": g.get("catalogSlug", ""), "installPackageId": g.get("installPackageId", ""),
                            "installPath": g.get("installPath", ""), "installVersion": g.get("installVersion", ""),
                            "sub": _library_label(g.get("sub", ""), language), "variant": g.get("variant", ""), "description": g.get("s", ""),
                            "chips": [_library_label(label, language) for label in (g.get("chips") or [])],
                            "pal": g.get("pal") or ["#10150f", "#1f3328", "#18271f", "#0d1510", platform_accents.get(platform, "#e6d9a0")],
                            "acc": g.get("acc") or platform_accents.get(platform, "#e6d9a0"), "font": g.get("font", "Hanken Grotesk"),
                            "added": int(g.get("added", 0) or 0), "lastSessionSecs": int(session.get("last_secs", 0) or 0),
                            "lastBackup": int(btime or 0), "lastPlayed": snap["lastPlayed"], "totalSecs": snap["totalSecs"],
                            "plays": snap["plays"], "playingSince": snap["playingSince"], "portCount": len(ports),
                            "ports": port_rows, "folder": self._folder(ports), "romCopy": merged_copies["by_primary"].get(g["id"]),
                            "portAvailable": self._port_available(g, installed_slugs),
                            "updateAvailable": self._update_available(g, install_records),
                            "folderActions": desc.get("actions", []), "requirements": desc.get("requirements", []),
                            "lastExit": (self.store.state.get("last_exit") or {}).get(g["id"]),
                            "running": any(row["running"] for row in port_rows),
                            **self._art(g, self.store.state),
                            "fav": g["id"] in fav, "hidden": g["id"] in hid})
        out.sort(key=lambda x: (-x["lastPlayed"], x["name"].casefold()))
        return {"games": out, "revision": revision, "unchanged": False}

    def _update_check_enabled(self) -> bool:
        cfg = load_json(self.store.dir / "config.json", {})
        return not isinstance(cfg, dict) or cfg.get("update_check", True) is not False

    def _update_available(self, g, records) -> dict | None:
        """«Actualización disponible»: un port instalado desde el catálogo cuya ficha tiene un paquete publicado más nuevo."""
        slug, package_id = g.get("catalogSlug", ""), g.get("installPackageId", "")
        if not slug or not package_id or not self._update_check_enabled():
            return None
        record = records.get(g.get("id"), {})
        packages = (self.store.state.get("catalog_packages") or {}).get(slug) or []
        pick = package_installs.pick_update(packages, package_id, str(record.get("archiveFormat") or ""),
                                            str(record.get("publishedAt") or ""), str(record.get("sourceName") or ""))
        if not pick:
            return None
        return {"slug": slug, "packageId": pick["id"], "title": pick.get("title", ""), "version": pick.get("version", ""),
                "current": g.get("installVersion", ""), "sizeBytes": pick.get("sizeBytes", 0),
                "licenseName": pick.get("licenseName", ""), "sourceName": pick.get("sourceName", "")}

    def _port_available(self, g, installed_slugs) -> dict | None:
        """«Port disponible»: un volcado/ROM enlazado a una ficha que tiene un paquete publicado y cuyo port aún no está instalado."""
        slug = g.get("catalogSlug", "")
        if g.get("auto") != "roms" or not slug or slug in installed_slugs:
            return None
        state = self.store.state
        if not online_catalog.platform_compatible(g.get("platform"), (state.get("catalog_platforms") or {}).get(slug)):
            return None
        packages = (state.get("catalog_packages") or {}).get(slug) or []
        if not packages:
            return None
        pick = max(packages, key=lambda row: str(row.get("createdAt") or ""))     # el más reciente (a igual fecha, el primero)
        return {"slug": slug, "packageId": pick["id"], "title": pick.get("title", ""), "version": pick.get("version", ""),
                "sizeBytes": pick.get("sizeBytes", 0), "licenseName": pick.get("licenseName", ""), "sourceName": pick.get("sourceName", ""),
                "count": len(packages)}

    def _rom_copies(self, games, config) -> dict:
        """Une un volcado `.nup` o una carpeta exefs+romfs (que ningún emulador puede ejecutar) con el port del mismo juego: no aparecen dos entradas.

        Si la ficha del catálogo es la misma y el port se ve en la biblioteca, el volcado deja de listarse y el juego principal
        lleva `romCopy` («tu copia»). Si no hay port, el volcado sigue visible (más adelante ofrecerá instalar uno)."""
        platforms_known = self.store.state.get("catalog_platforms") or {}

        def slug_of(g):
            slug = g.get("catalogSlug", "")
            return slug if slug and online_catalog.platform_compatible(g.get("platform"), platforms_known.get(slug)) else ""
        primaries = {}
        for g in games:
            if g.get("auto") == "roms":
                continue
            visible = [p for p in g.get("ports", []) if games_refresh.port_installed(p) and library_paths.port_visible(g, p, config)]
            if visible and slug_of(g):
                primaries.setdefault(slug_of(g), g)
        hidden, by_primary = set(), {}
        for g in games:
            if g.get("auto") != "roms" or not slug_of(g) or slug_of(g) not in primaries:
                continue
            roms_ports = [p["rom"] for p in g.get("ports", []) if isinstance(p.get("rom"), dict)]
            if not roms_ports or any(os.path.splitext(r.get("path", ""))[1].lower() != ".nup" and not os.path.isdir(r.get("path", ""))
                                     for r in roms_ports):
                continue                                           # una ROM con emulador posible se mantiene como entrada propia
            hidden.add(g["id"])
            primary = primaries[slug_of(g)]
            copy = {"name": g["name"], "path": roms_ports[0].get("path", ""), "id": g["id"], "buildId": roms_ports[0].get("buildId", "")}
            info = next((i for i in (self._descriptor_info(primary, port) for port in primary.get("ports", [])) if i), {})
            if descriptor.build_id_prefixes(info.get("data") or {}):
                copy["compat"] = descriptor.compatibility(info["data"], copy["buildId"])       # ok | mismatch | unknown (un .nup no se lee)
            by_primary.setdefault(primary["id"], copy)
        return {"hidden": hidden, "by_primary": by_primary}

    @staticmethod
    def _folder(ports) -> str:
        """Carpeta local del juego si Omnia la conoce y existe (para «Abrir carpeta»); si no, cadena vacía."""
        for p, _installed in ports:
            chk = os.path.expanduser(p.get("check") or "")
            for cand in (p.get("folder"), p.get("cwd"), chk if os.path.isdir(chk) else os.path.dirname(chk)):
                if cand and os.path.isabs(os.path.expanduser(cand)) and os.path.isdir(os.path.expanduser(cand)):
                    return os.path.realpath(os.path.expanduser(cand))
        return ""

    def game_metadata(self, q):
        game_id, slug = str(q.get("id", "")), str(q.get("slug", ""))
        source, product = str(q.get("store", "")), str(q.get("product", ""))
        if game_id:
            game = self.store.find_game(game_id)
            if not game:
                raise ApiError(404, "juego desconocido")
        elif re.fullmatch(r"[a-z0-9][a-z0-9-]{0,119}", slug):
            game = {"catalogSlug": slug}
        elif (source in {"steam", "gog"} and re.fullmatch(r"[0-9]{1,10}", product)
              or source == "epic" and re.fullmatch(r"[A-Za-z0-9][A-Za-z0-9._-]{0,119}", product)):
            game = {"id": f"{source}-{product}", "store_id": {"store": source, "id": product}}
        else:
            return {"metadata": {}}
        locale = "en" if q.get("lang") == "en" else "es"
        metadata = library_metadata.game_metadata(game, locale)
        store_info = library_metadata.store_identity(game)
        if store_info.get("store") == "epic":
            epic = self._stores().get("epic")
            if epic:
                metadata = {**metadata, **epic.game_metadata(str(store_info.get("id") or ""))}
        if game.get("installPackageId") and game.get("catalogSlug"):
            rows = (self.store.state.get("catalog_packages") or {}).get(game["catalogSlug"]) or []
            package = next((p for p in rows if p.get("id") == game["installPackageId"]), None)
            if package and package.get("sizeBytes"):
                metadata = {**metadata, "downloadBytes": package["sizeBytes"]}
        return {"metadata": metadata}

    def game_activity(self, q):
        """Historial reciente de un juego (últimas sesiones, más nuevas primero) y sus totales."""
        gid = str(q.get("id", ""))
        game = self.store.find_game(gid)
        if not game:
            raise ApiError(404, "juego desconocido")
        s = (self.store.state.get("sessions") or {}).get(gid) or {}
        snap = self.sessions.snapshot(gid) if self.sessions else {
            "lastPlayed": int((self.store.state.get("last_played") or {}).get(gid, 0)),
            "totalSecs": int(s.get("total_secs", 0)), "plays": int(s.get("count", 0)), "playingSince": 0}
        ext = game.get("played") or {}
        snap = {**snap, "lastPlayed": max(snap["lastPlayed"], int(ext.get("last", 0) or 0)),
                "totalSecs": max(snap["totalSecs"], int(ext.get("secs", 0) or 0))}
        hist = [h for h in (self.store.state.get("history") or []) if isinstance(h, dict) and h.get("id") == gid]
        sessions = [{"start": int(h.get("start", 0)), "end": int(h.get("end", 0)), "secs": int(h.get("secs", 0))} for h in reversed(hist)][:30]
        return {"sessions": sessions, "totalSecs": snap["totalSecs"], "plays": snap["plays"], "lastPlayed": snap["lastPlayed"],
                "lastSecs": int(s.get("last_secs", 0) or 0), "added": int(game.get("added", 0) or 0), "playingSince": snap["playingSince"]}

    @staticmethod
    def _art(g, state=None):
        slug = (g.get("art") or {}).get("slug") or g["id"]
        out = {}
        selected = ((state or {}).get("art") or {}).get(g["id"], {})
        custom = ((state or {}).get("art_custom") or {}).get(g["id"], {})
        fallback = ((state or {}).get("lookup_art") or {}).get(g["id"]) or {}
        for kind in art.KINDS:
            mine = (custom.get(kind) or {}).get("file", "")
            if mine and os.path.isfile(mine):                  # arte elegido a mano por el usuario: manda sobre el del catálogo
                out[kind] = "file://" + mine
                continue
            if g.get("catalogSlug") and online_catalog.platform_compatible(
                    g.get("platform"), ((state or {}).get("catalog_platforms") or {}).get(g.get("catalogSlug"))):
                remote = (((state or {}).get("catalog_art") or {}).get(g.get("catalogSlug")) or {})
                aliases = {"portada": "grid", "fondo": "hero", "logo": "logo"}
                url = remote.get(aliases.get(kind, ""), "")
                if isinstance(url, str) and url.startswith(online_catalog.PUBLIC_ORIGIN + "/api/v1/artwork/"):
                    out[kind] = online_catalog.local_or_remote(url)
                    continue
            if kind == "fondo" and kind not in selected:
                f = art.highest_resolution(slug, kind)
            else:
                f = art.cached(slug, kind, index=max(0, int(selected.get(kind, 0) or 0)))
            if f:
                out[kind] = "file://" + f
                continue
            steam_url = online_catalog.game_art_urls(g).get(kind)        # Steam y Heroic sin arte propio: arte público de su tienda
            cached_steam = online_catalog.cached_artwork_path(steam_url) if steam_url else None
            if cached_steam:
                out[kind] = "file://" + str(cached_steam)
                continue
            mine = ((g.get("art") or {}).get("local") or {}).get(kind) if isinstance((g.get("art") or {}).get("local"), dict) else None
            if isinstance(mine, str) and os.path.isfile(mine) and not os.path.islink(mine):      # Lutris: su propia carátula en disco
                out[kind] = "file://" + mine
                continue
            if fallback.get("title") == g.get("name"):
                url = (fallback.get("assets") or {}).get(kind)
                cached = online_catalog.cached_artwork_path(url) if url else None
                if cached:
                    out[kind] = cached.as_uri()
        return out

    def refresh(self, q):
        return games_refresh.refresh(self.store, self.detectors)

    def _mangohud_env(self):
        cfg = load_json(self.store.dir / "config.json", {})
        if not cfg.get("mangohud_enabled", False):
            return {}
        if not shutil.which("mangohud"):
            raise ApiError(503, "MangoHud no está instalado. Instálalo desde el gestor de paquetes y vuelve a intentarlo.")
        return {"OMNIA_MANGOHUD": "1", "MANGOHUD": "1", "MANGOHUD_DLSYM": "1",
                "MANGOHUD_CONFIGFILE": str(mangohud.ensure(self.store.dir))}

    def toggle(self, key, q):
        gid = q.get("id", "")
        if not self.store.find_game(gid):
            raise ApiError(404, "juego desconocido")
        return {"ok": True, "on": self.store.toggle(key, gid)}

    def launch(self, q):
        g, p = self.store.find_port(q.get("id", ""), q.get("port", ""))
        if not g or not p:
            raise ApiError(404, "juego o port desconocido")
        installed = {x.get("catalogSlug") for x in self.store.games() if x.get("installPackageId") and x.get("catalogSlug")}
        if self._port_available(g, installed):
            raise ApiError(409, "Este juego necesita instalar su port. Pulsa «Instalar port» en Big Mode o en la app de escritorio.")
        if not library_paths.port_visible(g, p, load_json(self.store.dir / "config.json", {})):
            raise ApiError(409, "La carpeta de este juego se retiró de las rutas de Omnia.")
        if not games_refresh.port_installed(p):
            raise ApiError(409, "no está instalado")
        if self._is_running(g, p, self._processes()):
            raise ApiError(409, "ya está en ejecución")
        if isinstance(p.get("rom"), dict):          # ROM importada: el emulador se elige o se rehace en este momento
            try:
                p = manual.resolve_rom_launch(p, self._roots())
            except manual.ManualError as e:
                raise ApiError(409, str(e))
            with self.store.lock:
                games = [dict(x) for x in self.store.games()]
                for game in games:
                    if game.get("id") == g["id"]:
                        game["ports"] = [p if q.get("id") == p["id"] else q for q in game.get("ports", [])]
                        game["variant"] = p.get("name", game.get("variant", ""))
                self.store.set_games(games)
        # Steam/Lutris/Heroic suelen delegar el juego a un cliente ya abierto; el entorno de
        # este proceso no llega al juego. Los ejecutables directos sí se envuelven con MangoHud.
        with self.store.lock:
            self.store.state.get("last_exit", {}).pop(g["id"], None)             # un aviso de cierre del intento anterior ya no vale
        if g.get("auto") not in {"steam", "lutris", "heroic"} and g.get("src") not in {"Steam", "Lutris", "Heroic"}:
            env = self._mangohud_env()
            proc = self.launch_fn(p, g["id"], env=env) if env else self.launch_fn(p, g["id"])
        else:
            proc = self.launch_fn(p, g["id"])
        self._watch_exit(g, p, proc)
        return {"ok": True}

    def _watch_exit(self, g, p, proc):
        """Si el port declara `exit_codes` en su descriptor, guarda el mensaje que corresponde al código con que cerró el juego
        (p. ej. «no encontró tu copia») para mostrarlo en su ficha. Un código «ok» o 0 no es un aviso."""
        if not hasattr(proc, "wait") or not callable(proc.wait):
            return
        data = self._descriptor_info(g, p).get("data") or {}
        if not isinstance(data.get("exit_codes"), dict):
            return

        def run():
            try:
                code = proc.wait()
            except Exception:
                return
            message = descriptor.exit_message(data, code)
            if code and message and message != "ok":
                with self.store.lock:
                    self.store.state.setdefault("last_exit", {})[g["id"]] = {"code": int(code), "message": message, "t": int(time.time())}
                    self.store.save_state()
                self.bus.games_changed()
        threading.Thread(target=run, name="omnia-exit-watch", daemon=True).start()

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
        # Para accesos directos de juegos Vulkan (p. ej. un AppImage), el entorno pasa al proceso
        # del juego. Excluir los gestores para no dibujar el HUD sobre sus propias ventanas.
        name = (a.name + " " + a.id).casefold()
        launchers = ("steam", "lutris", "heroic", "gamescope", "epic games", "gog galaxy", "battle.net")
        if a.group == "Juegos" and not any(item in name for item in launchers):
            env = self._mangohud_env()
            if env:
                env.pop("OMNIA_MANGOHUD", None)
                self.app_launch_fn(a, env=env)
            else: self.app_launch_fn(a)
        else:
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
        cmds = self._processes() if cmds is None else cmds
        return [g for g in self.store.games()
                if any(games_refresh.port_installed(p) and self._is_running(g, p, cmds) for p in g.get("ports", []))]

    def running_games(self) -> list:
        """Nombres de los juegos en marcha que activan el modo juego (los de la nube no consumen este equipo)."""
        return [g.get("name", g["id"]) for g in self.running_list() if not g.get("cloud")]

    # --- partidas y explorador de carpetas
    def _roots(self):
        return self.fs_roots if self.fs_roots is not None else fsbrowse.allowed_roots()

    def library_roots(self, q):
        """Carpetas externas configuradas explícitamente por el usuario."""
        cfg = load_json(self.store.dir / "config.json", {})
        roots = cfg.get("external_roots", []) if isinstance(cfg, dict) else []
        roots = [os.path.realpath(os.path.expanduser(p)) for p in roots
                 if isinstance(p, str) and os.path.isdir(os.path.expanduser(p))]
        return {"roots": sorted(set(roots), key=str.casefold)}

    def library_roots_set(self, q):
        """Añade o retira una carpeta de biblioteca sin tocar archivos ni instalaciones."""
        body = q.get("_body") if isinstance(q.get("_body"), dict) else {}
        action, raw = body.get("action"), body.get("path")
        if action not in {"add", "remove"} or not isinstance(raw, str) or len(raw) > 4096:
            raise ApiError(400, "acción o ruta de biblioteca no válida")
        path = os.path.realpath(os.path.expanduser(raw.strip()))
        if not os.path.isdir(path):
            raise ApiError(400, "elige una carpeta existente")
        # No permitir registrar como biblioteca un punto de montaje genérico: el usuario debe
        # elegir una carpeta concreta dentro de su home o de una unidad montada.
        allowed = [os.path.realpath(Path.home()), os.path.realpath("/mnt"),
                   os.path.realpath("/media"), os.path.realpath("/run/media")]
        if not any(path.startswith(root.rstrip(os.sep) + os.sep) for root in allowed):
            raise ApiError(403, "la carpeta debe estar dentro de tu carpeta personal o una unidad montada")
        config_path = self.store.dir / "config.json"
        with self.store.lock:
            cfg = load_json(config_path, {})
            if not isinstance(cfg, dict):
                cfg = {}
            roots = [os.path.realpath(os.path.expanduser(p)) for p in cfg.get("external_roots", [])
                     if isinstance(p, str) and os.path.isdir(os.path.expanduser(p))]
            if action == "add":
                roots.append(path)
            else:
                roots = [p for p in roots if p != path]
            roots = sorted(set(roots), key=str.casefold)
            cfg["excluded_external_roots"] = library_paths.update_excluded(cfg, roots)
            cfg["external_roots"] = roots
            from .store import write_json_atomic
            write_json_atomic(config_path, cfg)

        def rescan():                       # las ROMs de la carpeta aparecen sin esperar al siguiente refresco periódico
            try:
                games_refresh.refresh(self.store, self.detectors)
                self.bus.games_changed()
            except Exception:
                pass
        threading.Thread(target=rescan, name="omnia-roms-rescan", daemon=True).start()
        return {"ok": True, "roots": roots}

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

    def _descriptor_info(self, g, p) -> dict:
        """Datos del `recomplauncher.json` de un port instalado (partidas, carpetas, copia aceptada y requisitos), ya filtrados a
        las carpetas permitidas. {} si el juego no tiene descriptor. Se guarda en caché según la fecha del archivo."""
        root = descriptor.find_root(g, p)
        if not root:
            return {}
        try:
            stamp = (root / descriptor.NAME).stat().st_mtime_ns
        except OSError:
            return {}
        cache = self.__dict__.setdefault("_descriptor_cache", {})
        hit = cache.get(str(root))
        if hit and hit[0] == stamp and time.monotonic() - hit[2] < 20:
            return hit[1]
        data = descriptor.load(root)
        ok = lambda path: bool(path) and self._allowed(path)
        spec = descriptor.saves_spec(root, data)
        spec = {k: ([x for x in v if ok(x)] if isinstance(v, list) else v) for k, v in spec.items()}
        if not spec.get("files") and not spec.get("dirs"):
            spec = {}
        named = {name: path for name, path in descriptor.folders(root, data).items() if ok(path)}
        info = {"root": str(root), "data": data, "spec": spec, "folders": named,
                "actions": [a for a in descriptor.actions(root, data) if a["folder"] in named],
                "requirements": descriptor.requirements(data)}
        cache[str(root)] = (stamp, info, time.monotonic())
        return info

    def _saves_cfg(self, g, p):
        """Dónde están las partidas y a dónde van los respaldos. Lo que el usuario eligió manda sobre lo de la biblioteca;
        va aparte (state) para que sobreviva a que la biblioteca se regenere (Steam, Heroic, Lutris)."""
        ov = (self.store.state.get("saves") or {}).get(g["id"]) or {}
        spec = ov.get("spec") or p.get("saves") or self._descriptor_info(g, p).get("spec") or {}
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

    def game_catalog_link(self, q):
        """Asocia o desasocia un juego local con una ficha del catálogo, solo por petición del usuario."""
        body = q.get("_body") if isinstance(q.get("_body"), dict) else {}
        game_id, slug = body.get("id"), body.get("slug", "")
        if not isinstance(game_id, str) or not game_id or not isinstance(slug, str):
            raise ApiError(400, "juego o ficha de catálogo no válidos")
        slug = slug.strip().lower()
        if slug and not re.fullmatch(r"[a-z0-9][a-z0-9-]{0,119}", slug):
            raise ApiError(400, "identificador de catálogo no válido")
        if slug:
            result = online_catalog.game_detail(slug)
            remote = result.get("data") if isinstance(result.get("data"), dict) else {}
            if remote.get("slug") != slug:
                raise ApiError(404, "la ficha no existe en el catálogo disponible")
        with self.store.lock:
            games = [dict(game) for game in self.store.games()]
            game = next((row for row in games if row.get("id") == game_id), None)
            if not game:
                raise ApiError(404, "juego desconocido")
            if slug:
                names = [str(p.get("name") or p.get("slug")) for p in (remote.get("platforms") or []) if isinstance(p, dict)]
                if not online_catalog.platform_compatible(game.get("platform"), [p.get("slug") for p in (remote.get("platforms") or []) if isinstance(p, dict)]):
                    raise ApiError(409, "La ficha es de otra plataforma (" + ", ".join(names) + "); no corresponde a este juego.")
            if slug:
                game["catalogSlug"] = slug
            else:
                game.pop("catalogSlug", None)
            self.store.set_games(games)
        self.bus.games_changed()
        return {"ok": True, "id": game_id, "catalogSlug": slug}

    def game_suggest(self, q):
        path = str(q.get("path", ""))
        if templates.bedrock_on_linux_appimage(path):
            return {"name": "Minecraft Bedrock", "kind": "port", "template": "bedrock-on-linux",
                    "platform": "pc", "recognized": "BedrockOnLinux · Minecraft Bedrock"}
        recognized = port_catalog.identify(path) if path else None
        if recognized:
            return {"name": recognized["game"], "kind": "port", "template": recognized["template"],
                    "platform": recognized["platform"], "recognized": recognized["port"]}
        suffix = os.path.splitext(path)[1].lower()
        return {"name": os.path.basename(path).rsplit(".", 1)[0] if "." in os.path.basename(path) else os.path.basename(path),
                "kind": "windows" if suffix == ".exe" else "native", "platform": "pc", "recognized": ""}

    def rom_scan(self, q):
        try:
            return roms.scan(q.get("path", ""), self._roots())
        except roms.RomScanError as e:
            raise ApiError(400, str(e))

    def rom_add(self, q):
        body = q.get("_body") if isinstance(q.get("_body"), dict) else {}
        path, name = body.get("path"), body.get("name")
        system, emulator = body.get("system"), body.get("emulator")
        catalog_slug = body.get("catalogSlug", "")
        emulator = emulator or ""                    # sin emulador: se elige al jugar
        if not all(isinstance(value, str) for value in (path, name, system, emulator)):
            raise ApiError(400, "ruta, nombre, plataforma o emulador no válidos")
        if catalog_slug and not re.fullmatch(r"[a-z0-9][a-z0-9-]{0,119}", catalog_slug):
            raise ApiError(400, "identificador de catálogo no válido")
        candidate = roms.inspect_file(path, self._roots(), include_emulators=False, system=system)
        if not candidate:
            raise ApiError(400, "la ROM ya no es válida o no se reconoce su formato")
        if candidate["system"] != system:
            raise ApiError(400, "la plataforma de la ROM cambió; vuelve a analizar la carpeta")
        for existing in self.store.games():
            for existing_port in existing.get("ports", []):
                if not isinstance(existing_port, dict):
                    continue
                check_path = existing_port.get("check", "")
                check = os.path.realpath(os.path.expanduser(check_path)) if isinstance(check_path, str) and check_path else ""
                argv = existing_port.get("launch") or []
                if check == candidate["path"] or (isinstance(argv, list) and candidate["path"] in argv):
                    raise ApiError(409, f"Esta ROM ya está en la biblioteca como {existing.get('name', 'juego desconocido')}.")
        try:
            game = manual.add_rom_game(self.store, {"name": name.strip(), "path": candidate["path"],
                                                     "system": system, "emulator": emulator,
                                                     "catalogSlug": catalog_slug}, self._roots())
        except manual.ManualError as e:
            raise ApiError(400, str(e))
        return {"ok": True, "id": game["id"], "name": game["name"]}

    def game_remove(self, q):
        if not games_refresh.unlink(self.store, q.get("id", "")):
            raise ApiError(404, "juego desconocido")
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
                    raise ApiError(400, f"«{key}» debe ser una lista de rutas")
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
                raise ApiError(403, f"carpeta fuera de las permitidas: {path}")
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

    # --- artwork del catálogo público de Omnia (el núcleo no recibe ni guarda claves de proveedores)
    def art_browse(self, q):
        """Opciones de arte de un juego: la imagen actual del catálogo (solo en la página 0) y una página de SteamGridDB que sirve el backend."""
        g = self.store.find_game(q.get("id", ""))
        if not g:
            raise ApiError(404, "juego desconocido")
        kind = q.get("kind", "")
        if kind not in art.KINDS:
            raise ApiError(400, "tipo de arte no válido")
        try:
            page = int(q.get("page", "0"))
            if page < 0 or page > 20:
                raise ValueError
        except ValueError:
            raise ApiError(400, "página no válida")
        slug = g.get("catalogSlug")
        if not slug:
            raise ApiError(409, "Este juego no tiene artwork publicado en el catálogo Omnia.")
        alias = {"portada": "grid", "fondo": "hero", "logo": "logo"}[kind]
        items, warning, linked, more = [], "", True, False
        try:
            if page == 0:
                remote = online_catalog.fetch_artwork(slug)
                current = (((self.store.state.get("catalog_art") or {}).get(slug) or {}).get(alias) or "")
                items += [{"id": "actual", "url": row["url"], "thumb": row["url"], "w": 0, "h": 0, "by": "Omnia", "cur": row["url"] == current or not current}
                          for row in remote if row.get("kind") == alias][:1]
        except online_catalog.CatalogError as e:
            warning = str(e)
        try:
            options = online_catalog.fetch_art_options(slug, kind, page)
            linked, more = options["linked"], options["hasMore"]
            have = {i["url"] for i in items}
            items += [{"id": str(o.get("id") or ""), "url": o["url"], "thumb": o["thumb"], "w": o.get("width") or 0, "h": o.get("height") or 0,
                       "by": o.get("author") or "SteamGridDB", "style": o.get("style") or "", "cur": False}
                      for o in options["items"] if o["url"] not in have]
        except online_catalog.CatalogError as e:
            warning = warning or str(e)
        if not items and warning:
            raise ApiError(502, warning)
        return {"items": items, "page": page, "more": more, "linked": linked, "warning": warning, "sgid": 1 if items else 0}

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
            if not g.get("catalogSlug"):
                raise ApiError(409, "Este juego no tiene artwork publicado en el catálogo Omnia.")
            remote = online_catalog.fetch_artwork(g["catalogSlug"])
            alias = {"portada": "grid", "fondo": "hero", "logo": "logo"}.get(kind)
            items = [{"url": row["url"], "thumb": row["url"]} for row in remote if row.get("kind") == alias]
            result = {"items": items}
            if index >= len(result["items"]):
                raise ApiError(400, "opción de arte fuera de rango")
            with self.store.lock:
                aliases = {"portada": "grid", "fondo": "hero", "logo": "logo"}
                self.store.state.setdefault("catalog_art", {}).setdefault(g["catalogSlug"], {})[aliases[kind]] = result["items"][index]["url"]
                (self.store.state.get("art_custom") or {}).get(g["id"], {}).pop(kind, None)       # elegir del catálogo anula la imagen propia
                self.store.save_state()
            self.bus.games_changed()
            self._notify_selected_art(g["id"], kind)
            return {"ok": True, "kind": kind}
        except ValueError:
            raise ApiError(400, "edición, página u opción de arte no válida")
        except art.ArtError as e:
            raise ApiError(502, str(e))
        except online_catalog.CatalogError as e:
            raise ApiError(502, str(e))

    USER_ART_MAX = 25 * 1024 * 1024
    USER_ART_KINDS = {"portada": (200, 20000), "fondo": (400, 20000), "logo": (32, 20000)}

    def art_tmp(self, q):
        """Carpeta donde la interfaz deja la imagen ya encuadrada antes de enviarla a `/art/local` (se crea si no existe)."""
        folder = paths.cache_dir() / "user-art-tmp"
        folder.mkdir(parents=True, exist_ok=True)
        return {"dir": str(folder)}

    def art_local(self, q):
        """Usa una imagen del propio usuario como portada, fondo o logo de un juego. La interfaz ya la dejó encuadrada (Rellenar o Ajustar);
        aquí solo se valida (archivo normal dentro de las carpetas permitidas, PNG/JPEG/WebP, ≤ 25 MiB, dimensiones razonables) y se
        copia a la caché de Omnia: el original no se toca ni se vuelve a leer."""
        body = q.get("_body") if isinstance(q.get("_body"), dict) else {}
        g = self.store.find_game(str(body.get("id") or ""))
        kind, path = str(body.get("kind") or ""), str(body.get("path") or "")
        if not g:
            raise ApiError(404, "juego desconocido")
        if kind not in self.USER_ART_KINDS:
            raise ApiError(400, "tipo de arte no válido")
        real = os.path.realpath(os.path.expanduser(path))
        if not path or os.path.islink(os.path.expanduser(path)) or not os.path.isfile(real) or not self._allowed(real):
            raise ApiError(403, "elige una imagen dentro de tus carpetas")
        return self._save_user_art(g, kind, real)

    def art_choose(self, q):
        """Usa como arte de un juego una de las opciones de SteamGridDB que ofrece el backend: se descarga una vez (solo del CDN
        público de SteamGridDB, ≤ 25 MiB, PNG/JPEG/WebP), se verifica y queda como arte propio de ese juego."""
        body = q.get("_body") if isinstance(q.get("_body"), dict) else {}
        g = self.store.find_game(str(body.get("id") or ""))
        kind, url = str(body.get("kind") or ""), str(body.get("url") or "")
        if not g:
            raise ApiError(404, "juego desconocido")
        if kind not in self.USER_ART_KINDS:
            raise ApiError(400, "tipo de arte no válido")
        try:
            raw = online_catalog.download_option_image(url, opener=package_installs._safe_package_opener().open)
        except online_catalog.CatalogError as e:
            raise ApiError(502, str(e))
        folder = paths.cache_dir() / "user-art-tmp"
        folder.mkdir(parents=True, exist_ok=True)
        tmp = folder / f"opcion-{int(time.time() * 1000)}.bin"
        tmp.write_bytes(raw)
        try:
            return self._save_user_art(g, kind, str(tmp))
        finally:
            tmp.unlink(missing_ok=True)

    def _save_user_art(self, g, kind, real):
        try:
            size = os.path.getsize(real)
        except OSError:
            raise ApiError(404, "no se pudo leer la imagen")
        if size <= 0 or size > self.USER_ART_MAX:
            raise ApiError(413, "la imagen debe pesar menos de 25 MiB")
        width, height = art.image_dimensions(Path(real))
        low, high = self.USER_ART_KINDS[kind]
        if not width or not height or min(width, height) < low // 4 or max(width, height) > high:
            raise ApiError(400, "no es una imagen PNG, JPEG o WebP válida, o sus dimensiones no son razonables")
        with open(real, "rb") as stream:
            head = stream.read(16)
        ext = ".png" if head.startswith(b"\x89PNG") else (".webp" if head[:4] == b"RIFF" and head[8:12] == b"WEBP" else ".jpg")
        safe = re.sub(r"[^A-Za-z0-9._-]+", "-", g["id"])[:80] or "juego"
        folder = paths.cache_dir() / "user-art" / safe
        folder.mkdir(parents=True, exist_ok=True)
        stamp = int(time.time() * 1000)
        target = folder / f"{kind}-{stamp}{ext}"
        shutil.copyfile(real, target)
        if os.path.dirname(real) == str(paths.cache_dir() / "user-art-tmp"):       # la imagen encuadrada que dejó la interfaz: ya no hace falta
            try:
                os.unlink(real)
            except OSError:
                pass
        with self.store.lock:
            entry = self.store.state.setdefault("art_custom", {}).setdefault(g["id"], {})
            previous = (entry.get(kind) or {}).get("file")
            entry[kind] = {"file": str(target), "at": stamp}
            self.store.save_state()
        if previous and previous != str(target):
            try:
                os.unlink(previous)
            except OSError:
                pass
        self._notify_selected_art(g["id"], kind)
        self.bus.games_changed()
        return {"ok": True, "kind": kind}

    def art_reset(self, q):
        """Quita la imagen propia (de un tipo o de todos) y vuelve a la del catálogo; el vigilante de arte la vuelve a elegir."""
        body = q.get("_body") if isinstance(q.get("_body"), dict) else {}
        g = self.store.find_game(str(body.get("id") or ""))
        if not g:
            raise ApiError(404, "juego desconocido")
        kinds = [str(body["kind"])] if body.get("kind") else list(self.USER_ART_KINDS)
        if any(k not in self.USER_ART_KINDS for k in kinds):
            raise ApiError(400, "tipo de arte no válido")
        aliases = {"portada": "grid", "fondo": "hero", "logo": "logo"}
        with self.store.lock:
            custom = (self.store.state.get("art_custom") or {}).get(g["id"], {})
            for kind in kinds:
                old = (custom.pop(kind, None) or {}).get("file")
                if old:
                    try:
                        os.unlink(old)
                    except OSError:
                        pass
                slug = g.get("catalogSlug")
                if slug:
                    ((self.store.state.get("catalog_art") or {}).get(slug) or {}).pop(aliases[kind], None)
                    (self.store.state.get("catalog_art_checked") or {}).pop(slug, None)       # se vuelve a pedir la elegida por defecto
                (self.store.state.get("art") or {}).get(g["id"], {}).pop(kind, None)
            self.store.save_state()
        self.bus.games_changed()
        self.bus.selection_changed()
        return {"ok": True}

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
        self._notify_selected_art(g["id"], kind)
        return {"ok": True, "index": index}

    # --- mando
    def pad_gate(self) -> bool:
        """¿Se entregan los botones del mando a la estantería? No con un juego abierto ni con el escritorio tapado."""
        now = time.time()
        if now - self._gate_t > 1.0:
            if hasattr(self, "process_snapshot"):
                self.process_snapshot.at = 0.0
            cmds = self._processes()
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
            game_since = int(q.get("gameSince", -1))
            pad_since = int(q.get("padSince", -1))
        except ValueError:
            raise ApiError(400, "parámetros no válidos")
        r = self.bus.wait(since, wait, game_since if game_since >= 0 else None,
                          pad_since if pad_since >= 0 else None)
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

    def toggle_menu(self, power: bool = False) -> None:
        """Compatibilidad D-Bus con versiones anteriores; el atajo del menú quedó inactivo."""
        return

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
        self.package_installs.shutdown()
        self.httpd.shutdown()
        self.httpd.server_close()

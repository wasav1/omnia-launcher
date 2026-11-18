"""Servicio omnia-core: API local + refresco periódico de la biblioteca. Corre como servicio de systemd --user."""
import argparse
import logging
import os
import signal
import threading
import time

from . import __version__, art, audio, gamemode, pad, paths, security
from .sessions import Sessions
from .dbus import DesktopService
from .api import Api
from .games import refresh as games_refresh
from .games.registry import default_detectors
from .store import Store, load_json

log = logging.getLogger("omnia")


def load_config() -> dict:
    cfg = load_json(paths.config_dir() / "config.json", {})
    return cfg if isinstance(cfg, dict) else {}


def art_worker(store, stop: threading.Event, pause: float = 1.5, bus=None):
    """Descarga en segundo plano el arte que falte, con pausa entre juegos. Solo si hay clave de SteamGridDB."""
    warned = False
    pending = []
    scan_at = 0.0
    seen_revision = -1
    while not stop.is_set():
        key = art.load_key()
        if key:
            if not art.key_permissions_ok() and not warned:
                log.warning("la clave de SteamGridDB es legible por otros usuarios: chmod 600 %s", art.key_path())
                warned = True
            now = time.monotonic()
            if now >= scan_at or seen_revision != store.revision:
                pending = list(store.games())
                scan_at, seen_revision = now + 60, store.revision
            if pending and not stop.is_set():
                g = pending.pop(0)
                slug = (g.get("art") or {}).get("slug") or g.get("id", "")
                if not all(art.cached(slug, k) or (art.art_dir(slug, k) / art.NONE_MARK).exists() for k in art.KINDS):
                    try:
                        got = art.fetch_game(art.Client(key), g)
                        if got:
                            with store.lock:
                                store.revision += 1
                            log.info("arte de %s: %s", g.get("name"), ", ".join(got))
                            if bus and "fondo" in got and store.state.get("selected_game") == g.get("id"):
                                bus.selection_changed()
                    except art.ArtError as e:
                        log.warning("arte de %s: %s", g.get("name"), e)
                stop.wait(pause)
            else:
                stop.wait(60)
        else:
            stop.wait(60)


def gamemode_worker(api, mode, sessions, stop: threading.Event, every: float = 0.35):
    """Un sondeo frecuente de juegos en marcha alimenta UI, modo juego e historial. Al parar el servicio,
    el modo juego suelta lo congelado y las sesiones en curso se cierran."""
    previous = None
    try:
        while not stop.wait(every):
            try:
                running = api.running_list()
                running_ids = frozenset(g["id"] for g in running)
                changed = previous is not None and running_ids != previous
                previous = running_ids
                changed = sessions.update({g["id"]: g.get("name", g["id"]) for g in running}) or changed
                if changed:
                    api.bus.games_changed()
                if mode.update([g.get("name", g["id"]) for g in running if not g.get("cloud")]):
                    api.bus.set_gamemode(mode.status())
            except Exception:
                log.exception("fallo en el modo juego o en el historial")
    finally:
        mode.shutdown()
        sessions.shutdown()
        api.bus.set_gamemode(mode.status())


def main(argv=None, detectors=None, stop: threading.Event | None = None) -> int:
    cfg = load_config()
    ap = argparse.ArgumentParser(prog="omnia-core")
    ap.add_argument("--port", type=int, default=int(cfg.get("port", 47831)))
    ap.add_argument("--refresh", type=int, default=int(cfg.get("refresh_secs", 30)), help="segundos entre refrescos")
    ap.add_argument("--version", action="version", version=__version__)
    args = ap.parse_args(argv)
    logging.basicConfig(level=logging.INFO, format="%(levelname)s %(message)s")   # el journal añade la hora

    stop = stop or threading.Event()
    if threading.current_thread() is threading.main_thread():
        for sig in (signal.SIGTERM, signal.SIGINT):
            signal.signal(sig, lambda *_: stop.set())

    store = Store()
    token = security.new_token()
    dets = detectors if detectors is not None else default_detectors()
    try:
        backup_root = (cfg.get("saves") or {}).get("backup_root") if isinstance(cfg.get("saves"), dict) else None
        api = Api(store, token, dets, port=args.port, **({"backup_root": backup_root} if isinstance(backup_root, str) and backup_root else {}))
    except OSError as e:
        log.error("no se pudo abrir el puerto %d: %s", args.port, e)
        return 1
    api.serve()
    mode = gamemode.new(cfg)
    resumed = mode.freezer.resume()                 # si el servicio murió con algo congelado, se reanuda al arrancar
    if resumed:
        log.warning("modo juego: reanudados %d procesos que quedaron congelados", resumed)
    api.gamemode = mode
    spectrum = audio.AudioSpectrum(log.info)
    api.audio = spectrum
    spectrum.start()
    sessions = Sessions(store)
    closed = sessions.recover()                     # sesiones que quedaron abiertas si el servicio murió en mitad de una partida
    if closed:
        log.warning("historial: cerradas %d sesiones que quedaron abiertas", closed)
    api.sessions = sessions
    threading.Thread(target=art_worker, args=(store, stop, 1.5, api.bus), daemon=True).start()
    gm_thread = threading.Thread(target=gamemode_worker, args=(api, mode, sessions, stop), name="omnia-gamemode")
    gm_thread.start()
    reader = pad.PadReader(api.bus, gate=api.pad_gate, log=log.info)
    reader.start()
    dbus = DesktopService(api.set_desktop_state, on_menu=api.toggle_menu, name=os.environ.get("OMNIA_DBUS_NAME") or cfg.get("dbus_name", "org.omnia.Core"))
    if dbus.start():
        log.info("D-Bus: escuchando el estado del escritorio en %s", dbus.name)
    log.info("omnia-core %s escuchando en 127.0.0.1:%d", __version__, api.port)
    try:
        while True:
            try:
                r = games_refresh.refresh(store, dets)
                log.info("biblioteca: %d juegos (+%d, -%d)", r["total"], r["added"], r["removed"])
            except Exception:
                log.exception("fallo al refrescar la biblioteca")      # un detector roto no tumba el servicio
            if stop.wait(max(5, args.refresh)):
                break
    finally:
        stop.set()
        spectrum.stop()
        gm_thread.join(5)                           # suelta lo congelado y el perfil antes de salir
        reader.stop()
        dbus.stop()
        api.stop()
        try:
            (paths.runtime_dir() / "token").unlink()
        except OSError:
            pass
        log.info("omnia-core detenido")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

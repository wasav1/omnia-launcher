"""Servicio omnia-core: API local + refresco periódico de la biblioteca. Corre como servicio de systemd --user."""
import argparse
import logging
import os
import signal
import threading

from . import __version__, art, gamemode, pad, paths, security
from .dbus import DesktopService
from .api import Api
from .games import refresh as games_refresh
from .games.registry import default_detectors
from .store import Store, load_json

log = logging.getLogger("omnia")


def load_config() -> dict:
    cfg = load_json(paths.config_dir() / "config.json", {})
    return cfg if isinstance(cfg, dict) else {}


def art_worker(store, stop: threading.Event, pause: float = 1.5):
    """Descarga en segundo plano el arte que falte, con pausa entre juegos. Solo si hay clave de SteamGridDB."""
    warned = False
    while not stop.is_set():
        key = art.load_key()
        if key:
            if not art.key_permissions_ok() and not warned:
                log.warning("la clave de SteamGridDB es legible por otros usuarios: chmod 600 %s", art.key_path())
                warned = True
            client = art.Client(key)
            for g in store.games():
                slug = (g.get("art") or {}).get("slug") or g.get("id", "")
                if all(art.cached(slug, k) for k in art.KINDS):
                    continue
                if stop.is_set():
                    return
                try:
                    got = art.fetch_game(client, g)
                    if got:
                        log.info("arte de %s: %s", g.get("name"), ", ".join(got))
                except art.ArtError as e:
                    log.warning("arte de %s: %s", g.get("name"), e)
                stop.wait(pause)
        stop.wait(60)


def gamemode_worker(api, mode, stop: threading.Event, every: float = 2.0):
    """Entra y sale del modo juego según los juegos en marcha. Al parar el servicio, deja todo como estaba."""
    try:
        while not stop.wait(every):
            try:
                if mode.update(api.running_games()):
                    api.bus.set_gamemode(mode.status())
            except Exception:
                log.exception("fallo en el modo juego")
    finally:
        mode.shutdown()
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
        api = Api(store, token, dets, port=args.port)
    except OSError as e:
        log.error("no se pudo abrir el puerto %d: %s", args.port, e)
        return 1
    api.serve()
    mode = gamemode.new(cfg)
    resumed = mode.freezer.resume()                 # si el servicio murió con algo congelado, se reanuda al arrancar
    if resumed:
        log.warning("modo juego: reanudados %d procesos que quedaron congelados", resumed)
    api.gamemode = mode
    threading.Thread(target=art_worker, args=(store, stop), daemon=True).start()
    gm_thread = threading.Thread(target=gamemode_worker, args=(api, mode, stop), name="omnia-gamemode")
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

"""Servicio omnia-core: API local + refresco periódico de la biblioteca. Corre como servicio de systemd --user."""
import argparse
import logging
import signal
import threading

from . import __version__, paths, security
from .api import Api
from .games import refresh as games_refresh
from .games.registry import default_detectors
from .store import Store, load_json

log = logging.getLogger("omnia")


def load_config() -> dict:
    cfg = load_json(paths.config_dir() / "config.json", {})
    return cfg if isinstance(cfg, dict) else {}


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
        api.stop()
        try:
            (paths.runtime_dir() / "token").unlink()
        except OSError:
            pass
        log.info("omnia-core detenido")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

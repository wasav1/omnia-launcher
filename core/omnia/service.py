"""Servicio omnia-core: API local + refresco periódico de la biblioteca. Corre como servicio de systemd --user."""
import argparse
import logging
import os
import signal
import threading
import time

from . import __version__, audio, discord, gamemode, importer, mangohud, online_catalog, pad, paths, security
from .api import Api
from .dbus import DesktopService
from .games import refresh as games_refresh
from .games.legacy_recomp import migrate_installed_ports, repair_launch_args
from .games.registry import default_detectors
from .sessions import Sessions
from .store import Store, load_json

log = logging.getLogger("omnia")


def load_config() -> dict:
    cfg = load_json(paths.config_dir() / "config.json", {})
    return cfg if isinstance(cfg, dict) else {}


def auto_link_catalog(store, items) -> int:
    """Enlaza juegos sin ficha (o con una de otra plataforma) con la ficha de igual nombre y plataforma."""
    changed = 0
    with store.lock:
        games = [dict(g) for g in store.games()]
        platforms = store.state.get("catalog_platforms") or {}
        for game in games:
            current = game.get("catalogSlug", "")
            if current and online_catalog.platform_compatible(game.get("platform"), platforms.get(current)):
                continue            # ya tiene una ficha válida (puede ser una elección manual del usuario)
            is_rom = any(isinstance(q, dict) and isinstance(q.get("rom"), dict) for q in game.get("ports", []))
            slug = online_catalog.match_local_game(game, items, fuzzy=is_rom)
            if slug and slug != current:
                game["catalogSlug"] = slug
                changed += 1
        if changed:
            store.set_games(games)
    return changed


def search_candidates(store, items) -> list:
    """Suma a las primeras páginas del catálogo las fichas que coinciden por nombre con cada juego aún sin ficha válida.

    El catálogo tiene más de mil fichas y solo se descargan las primeras páginas, así que un juego local que no esté entre ellas
    (p. ej. una ROM de N64) nunca se enlazaba. La búsqueda por nombre lo resuelve con una petición pequeña por juego (con caché)."""
    seen = {str(i.get("slug")) for i in items if isinstance(i, dict)}
    out = list(items)
    platforms = store.state.get("catalog_platforms") or {}
    for game in list(store.games()):
        current = game.get("catalogSlug", "")
        if current and online_catalog.platform_compatible(game.get("platform"), platforms.get(current)):
            continue
        for query in _search_queries(game.get("name")):
            try:
                body = online_catalog.list_games({"q": query, "pageSize": 30})
            except online_catalog.CatalogError:
                continue
            for item in body.get("items") or []:
                if isinstance(item, dict) and item.get("slug") and str(item["slug"]) not in seen:
                    seen.add(str(item["slug"]))
                    out.append(item)
    return out


def _search_queries(name) -> list:
    """Consultas por nombre: el catálogo busca la frase tal cual, así que «Zelda Ocarina of Time» (sin los dos puntos del título
    oficial) no la encuentra; también se prueba con las últimas palabras («Ocarina of Time»). La coincidencia final sigue siendo exacta."""
    words = str(name or "").split()
    if not words:
        return []
    out = [" ".join(words)]
    for size in (4, 3):
        if len(words) > size and " ".join(words[-size:]) not in out:
            out.append(" ".join(words[-size:]))
    return out


def link_roms_by_id(store, index: dict) -> int:
    """Enlaza ROMs detectadas con su ficha por el ID de cabecera ({(tipo, ID): slug}); no pisa una ficha válida."""
    changed = 0
    with store.lock:
        games = [dict(g) for g in store.games()]
        platforms = store.state.get("catalog_platforms") or {}
        for game in games:
            current = game.get("catalogSlug", "")
            if current and online_catalog.platform_compatible(game.get("platform"), platforms.get(current)):
                continue
            for port in game.get("ports", []):
                rom = port.get("rom") if isinstance(port, dict) else None
                key = (str((rom or {}).get("internalIdType", "")), str((rom or {}).get("internalId", "")).upper())
                slug = index.get(key)
                if slug and slug != current:
                    game["catalogSlug"] = slug
                    changed += 1
                    break
        if changed:
            store.set_games(games)
    return changed


def rom_identifier_index(store) -> dict:
    """Descarga (con caché) los índices de IDs de las plataformas de las ROMs que hay en la biblioteca."""
    types = {str((p.get("rom") or {}).get("internalIdType", "")) for g in store.games() for p in g.get("ports", [])
             if isinstance(p, dict) and isinstance(p.get("rom"), dict)}
    index = {}
    for kind in sorted(t for t in types if t):
        for item in online_catalog.list_rom_identifiers(kind).get("items", []):
            slug = ((item.get("game") or {}).get("slug") or "") if isinstance(item, dict) else ""
            if slug:
                index[(str(item.get("type", "")), str(item.get("identifier", "")).upper())] = slug
    return index


PACKAGE_RECHECK_SECS = 6 * 60 * 60


def refresh_packages(store, slug: str, retry_at: dict, bus=None) -> bool:
    """Guarda los paquetes instalables publicados de una ficha (solo lo que la interfaz muestra); True si cambiaron.

    Se consulta cada 6 h por ficha y, si falla (sin red), a la hora. Es lo que permite marcar «Port disponible» sin
    preguntar al catálogo en cada refresco de la biblioteca."""
    now = time.time()
    checked = store.state.get("catalog_packages_checked") or {}
    if now - int(checked.get(slug, 0) or 0) < PACKAGE_RECHECK_SECS or now < retry_at.get(slug, 0):
        return False
    try:
        body = online_catalog.list_install_packages(slug)
    except online_catalog.CatalogError as e:
        log.debug("paquetes de %s: %s", slug, e)
        retry_at[slug] = now + 60 * 60
        return False
    if body.get("offline"):
        retry_at[slug] = now + 60 * 60
        return False
    rows = [{"id": i["id"], "title": i.get("title", ""), "version": i.get("version", ""), "sizeBytes": i.get("sizeBytes", 0),
             "archiveFormat": i.get("archiveFormat", ""), "createdAt": i.get("createdAt", ""), "licenseName": i.get("licenseName", ""), "sourceName": i.get("sourceName", "")}
            for i in body.get("items", []) if isinstance(i, dict) and i.get("platformSlug") == "pc" and isinstance(i.get("id"), str)]
    with store.lock:
        packages = store.state.setdefault("catalog_packages", {})
        changed = packages.get(slug) != rows
        packages[slug] = rows
        store.state.setdefault("catalog_packages_checked", {})[slug] = int(now)
        store.save_state()
    if changed and bus:
        bus.games_changed()
    return changed


def sync_steam_art(game, retry_at: dict) -> bool:
    """Descarga a la caché el arte público de un juego de Steam (portada, banner, logo) o de Heroic (portada y fondo de GOG/Epic); True si bajó alguna imagen.

    Las que fallan (un corte de red, o un 404 porque el juego no tiene esa imagen) se reintentan a los 30 min."""
    urls = online_catalog.game_art_urls(game)
    downloaded = False
    for url in urls.values():
        if online_catalog.cached_artwork_path(url) or time.time() < retry_at.get(url, 0):
            continue
        try:
            online_catalog.store_artwork(url)
            downloaded = True
        except (online_catalog.CatalogError, OSError, KeyError) as e:
            log.debug("arte de Steam %s: %s", url, e)
            retry_at[url] = time.time() + 30 * 60
    return downloaded


def art_priority(games: list, state: dict) -> list:
    """Orden en que el vigilante de arte revisa los juegos: primero los que aún no tienen su arte.

    Son los enlazados a una ficha que nunca se ha consultado y los de Steam cuyas imágenes públicas no están en la caché.
    El vigilante vuelve a construir la lista cada minuto; con muchos juegos no llegaba al final, y un juego recién instalado o
    recién añadido a Steam (el último de la biblioteca) se quedaba sin arte durante mucho tiempo."""
    checked = state.get("catalog_art_checked") or {}

    def missing(game) -> bool:
        if game.get("catalogSlug") and not int(checked.get(game["catalogSlug"], 0) or 0):
            return True
        urls = online_catalog.game_art_urls(game)
        return any(not online_catalog.cached_artwork_path(url) for url in urls.values())

    return sorted(games, key=lambda g: 0 if missing(g) else 1)


def art_worker(store, stop: threading.Event, pause: float = 1.5, bus=None):
    """Sincroniza periódicamente el artwork aprobado del catálogo público de Omnia."""
    pending = []
    with store.lock:        # fichas revisadas sin arte (p. ej. antes de que el catálogo lo publicara): se vuelven a consultar al arrancar
        checked = store.state.get("catalog_art_checked") or {}
        for known in [k for k in checked if not (store.state.get("catalog_art") or {}).get(k)]:
            checked.pop(known, None)
    with store.lock:        # fichas sin paquetes (aún no publicados): se vuelven a consultar al arrancar
        pk_checked = store.state.get("catalog_packages_checked") or {}
        cached = store.state.get("catalog_packages") or {}
        for known in [k for k in pk_checked if not cached.get(k) or any("createdAt" not in row for row in cached[k])]:
            pk_checked.pop(known, None)      # (las filas antiguas sin fecha de publicación se renuevan para poder avisar de actualizaciones)
    scan_at = 0.0
    seen_revision = -1
    catalog_retry_at = {}
    steam_retry_at = {}
    package_retry_at = {}
    link_at = 0.0
    while not stop.is_set():
        now = time.monotonic()
        if now >= link_at:
            link_at = now + 60 * 60
            try:
                items = []
                for page in range(1, 6):
                    body = online_catalog.list_games({"page": page, "pageSize": 30})
                    items += body.get("items") or []
                    if page >= int((body.get("meta") or {}).get("totalPages") or 1):
                        break
                items = search_candidates(store, items)
                ids = rom_identifier_index(store)
                changed = link_roms_by_id(store, ids) if ids else 0
                changed += auto_link_catalog(store, items) if items else 0
                if changed:
                    scan_at = 0.0
                    if bus:
                        bus.games_changed()
            except Exception as e:      # el enlace automático nunca debe tumbar el servicio
                log.debug("enlace automático con el catálogo: %s", e)
                link_at = now + 5 * 60
        if seen_revision != store.revision:
            link_at = min(link_at, now + 10)        # juegos nuevos (p. ej. ROMs recién detectadas): enlazarlos pronto
        if now >= scan_at or seen_revision != store.revision:
            pending = art_priority(list(store.games()), store.state)
            scan_at, seen_revision = now + 60, store.revision
        if pending and not stop.is_set():
            g = pending.pop(0)
            if sync_steam_art(g, steam_retry_at):
                if bus:
                    bus.games_changed()
            catalog_slug = g.get("catalogSlug", "")
            if catalog_slug:
                last_checked = int((store.state.get("catalog_art_checked") or {}).get(catalog_slug, 0) or 0)
                # Sin las plataformas de la ficha (juegos revisados antes de guardarlas) se vuelve a consultar ya,
                # para poder descartar el arte de una ficha de otra consola.
                platforms_known = catalog_slug in (store.state.get("catalog_platforms") or {})
                no_art_yet = not (store.state.get("catalog_art") or {}).get(catalog_slug)      # sin arte aún: se reintenta cada 15 min
                if (not last_checked or not platforms_known or time.time() - last_checked >= (15 * 60 if no_art_yet else 24 * 60 * 60)) \
                        and time.time() >= catalog_retry_at.get(catalog_slug, 0):
                    try:
                        entry = online_catalog.fetch_entry(catalog_slug)
                        found = {row["kind"]: row["url"] for row in entry["artwork"]}
                        online_catalog.prefetch_artwork(found.values())
                        with store.lock:
                            if entry["platforms"]:
                                store.state.setdefault("catalog_platforms", {})[catalog_slug] = entry["platforms"]
                                link_at = 0.0       # con la plataforma conocida puede haber un enlace mejor
                            art_map = store.state.setdefault("catalog_art", {})
                            if found and art_map.get(catalog_slug) != found:
                                art_map[catalog_slug] = found
                            store.state.setdefault("catalog_art_checked", {})[catalog_slug] = int(time.time())
                            store.save_state()
                            if bus and store.state.get("selected_game") == g.get("id"):
                                bus.selection_changed()
                        catalog_retry_at[catalog_slug] = time.time() + (15 * 60 if not found else 24 * 60 * 60)
                    except online_catalog.CatalogError as e:
                        log.debug("arte del catálogo para %s: %s", g.get("name"), e)
                        catalog_retry_at[catalog_slug] = time.time() + 60 * 60
            if catalog_slug:
                refresh_packages(store, catalog_slug, package_retry_at, bus)
            stop.wait(pause)
        else:
            stop.wait(pause if pending else 30)


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
                presence = getattr(api, "discord", None)
                if presence is not None:
                    current = running[0] if running else None
                    presence.set_game(current.get("name", current["id"]) if current else None,
                                      (sessions.active.get(current["id"]) or {}).get("start") if current else None)
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
    # Omnia Backend now serves approved artwork, so an old user-specific provider
    # credential is no longer used. Remove the obsolete secret during the upgrade.
    legacy_art_key = paths.config_dir() / "steamgriddb.key"
    try:
        legacy_art_key.unlink()
        log.info("se retiró una clave de artwork obsoleta; Omnia usa su backend público")
    except FileNotFoundError:
        pass
    except OSError as exc:
        log.warning("no se pudo retirar la clave de artwork obsoleta: %s", exc)
    try:
        migrated_ports = migrate_installed_ports(store)
        if migrated_ports:
            log.info("biblioteca: importados %d ports locales desde una instalación previa", migrated_ports)
    except Exception:
        log.exception("no se pudieron importar los ports locales existentes")
    try:
        repaired = repair_launch_args(store)
        if repaired:
            log.info("biblioteca: corregido el comando de lanzamiento de %d ports (argumentos de su descriptor)", repaired)
    except Exception:
        log.exception("no se pudo corregir el comando de lanzamiento de los ports")
    try:
        migrated, size = importer.migrate_legacy_art(store)
        if migrated:
            log.info("arte: recuperadas %d imágenes seleccionadas de Estantería (%d MiB)", migrated, round(size / 1024 / 1024))
    except Exception:
        log.exception("no se pudo recuperar el arte seleccionado de Estantería")
    token = security.new_token()
    dets = detectors if detectors is not None else default_detectors(store)
    try:
        backup_root = (cfg.get("saves") or {}).get("backup_root") if isinstance(cfg.get("saves"), dict) else None
        api = Api(store, token, dets, port=args.port, **({"backup_root": backup_root} if isinstance(backup_root, str) and backup_root else {}))
    except OSError as e:
        log.error("no se pudo abrir el puerto %d: %s", args.port, e)
        return 1
    api.serve()
    try:        # el archivo de estilo de MangoHud se mantiene al día siempre: un MANGOHUD_CONFIGFILE global puede apuntar a él
        mangohud.ensure(store.dir)
    except Exception as e:
        log.debug("MangoHud.conf: %s", e)
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
    presence = discord.DiscordPresence(api.discord_settings)
    api.discord = presence
    presence.start()
    threading.Thread(target=art_worker, args=(store, stop, 1.5, api.bus), daemon=True).start()
    gm_thread = threading.Thread(target=gamemode_worker, args=(api, mode, sessions, stop), name="omnia-gamemode")
    gm_thread.start()
    reader = pad.PadReader(api.bus, gate=api.pad_gate, log=log.info)
    reader.configure(cfg.get("pads") if isinstance(cfg.get("pads"), dict) else {})       # apodo, iconos, zona muerta y vibración de cada mando
    api.pad_reader = reader
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
        presence.stop()
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

"""Importación única de ports locales desde instalaciones antiguas de RecompLauncher.

Este módulo no detecta instalaciones en ejecución, no lanza RecompLauncher y no consulta
su catálogo ni sus servidores de artwork. Solo lee los datos antiguos una vez para
convertirlos en entradas normales de la biblioteca de Omnia.
"""
import json
import os
import re
from pathlib import Path

APP_ID = "com.recomplauncher.app"
FLATPAK_ID = "com.recomplauncher.RecompLauncher"
PLATFORMS = {"n64": "n64", "switch": "sw1", "switch2": "sw2", "switch-2": "sw2"}

# Datos conocidos que no se conservan en algunos manifiestos de ports antiguos.
KNOWN_PORTS = (
    ("longshot", {"game": "The Legend of Zelda: Ocarina of Time", "platform": "sw2",
                   "s": "Port nativo de The Legend of Zelda: Ocarina of Time (remake de Switch 2) para PC, con Longshot.",
                   "saves": {"glob": "~/.local/share/longshot/save/*/slot_*", "name": "Ranura {n}"}}),
    ("savagewind", {"game": "The Legend of Zelda: Breath of the Wild", "platform": "sw1"}),
    ("totk", {"game": "The Legend of Zelda: Tears of the Kingdom", "platform": "sw1"}),
)


def _norm(value: str) -> str:
    return re.sub(r"[^a-z0-9]", "", str(value).lower())


def known_port(game_id: str) -> dict:
    normalized = _norm(game_id)
    return next((dict(value) for key, value in KNOWN_PORTS if key in normalized), {})


def data_dirs(home: Path | None = None) -> list[Path]:
    user_home = Path(home) if home else Path.home()
    base = os.environ.get("XDG_DATA_HOME", "")
    xdg = Path(base) if base and os.path.isabs(base) else user_home / ".local/share"
    return [xdg / APP_ID, user_home / ".var/app" / FLATPAK_ID / "data" / APP_ID]


def _load(path: Path) -> dict:
    try:
        with open(path, encoding="utf-8") as stream:
            data = json.load(stream)
        return data if isinstance(data, dict) else {}
    except (OSError, ValueError):
        return {}


def migrate_installed_ports(store, dirs=None) -> int:
    """Importa una vez ports ya instalados y guarda rutas locales directas a AppRun.

    No mueve, elimina ni modifica los archivos existentes. Tras importar, Omnia es la
    fuente de verdad de esos juegos y no vuelve a leer las rutas de origen.
    """
    with store.lock:
        migrations = store.state.setdefault("migrations", {})
        if migrations.get("recomplauncher_ports_to_omnia_v1"):
            return 0

    sources = [Path(directory) for directory in dirs] if dirs is not None else data_dirs()
    installed_entries, catalog = [], {}
    source_found = False
    for directory in sources:
        document = _load(directory / "library.json")
        installed = document.get("installed")
        if not isinstance(installed, dict) or not installed:
            continue
        source_found = True
        cached_apps = _load(directory / "cache/pc-catalog.json").get("apps") or []
        if isinstance(cached_apps, list):
            catalog.update({str(item.get("id")): item for item in cached_apps
                            if isinstance(item, dict) and item.get("id")})
        installed_entries.extend((key, entry) for key, entry in installed.items() if isinstance(entry, dict))

    if not source_found:
        # No dejar consultas de compatibilidad en cada arranque de una instalación limpia.
        with store.lock:
            store.state.setdefault("migrations", {})["recomplauncher_ports_to_omnia_v1"] = True
            store.save_state()
        return 0

    games = store.games()
    by_id = {str(game.get("id")): game for game in games if isinstance(game, dict)}
    imported, seen = 0, set()
    for key, entry in installed_entries:
        legacy_id = str(entry.get("id") or key)
        if not re.fullmatch(r"[A-Za-z0-9._-]{1,80}", legacy_id) or legacy_id in seen:
            continue
        seen.add(legacy_id)
        try:
            root = Path(str(entry.get("path") or "")).expanduser().resolve(strict=True)
            if not root.is_dir():
                continue
            candidate = Path(str(entry.get("exe") or "AppRun")).expanduser()
            executable = (candidate if candidate.is_absolute() else root / candidate).resolve(strict=True)
            executable.relative_to(root)
            if not executable.is_file() or not os.access(executable, os.X_OK):
                continue
        except (OSError, RuntimeError, ValueError):
            continue

        game_id = "recomp-" + legacy_id
        previous = by_id.get(game_id, {})
        port_name = str(entry.get("name") or catalog.get(legacy_id, {}).get("name") or legacy_id)[:160]
        known = known_port(legacy_id)
        metadata = catalog.get(legacy_id, {})
        game_name = str(known.get("game") or metadata.get("game") or port_name)[:160]
        platform = known.get("platform") or PLATFORMS.get(str(metadata.get("origin") or "").lower(), "pc")
        description = str(metadata.get("blurb") or known.get("s") or previous.get("s") or "")[:1000]
        version = str(entry.get("version") or "")[:80]
        port = {
            "id": f"recomp-{legacy_id}-main",
            "name": port_name,
            "chips": ["Port nativo"],
            "launch": [str(executable)],
            "cwd": str(root),
            "check": str(executable),
            "proc": str(root) + os.sep,
            "s": f"Versión {version}" if version else "Port instalado",
        }
        if known.get("saves"):
            port["saves"] = {**known["saves"], "glob": os.path.expanduser(known["saves"]["glob"])}
        game = {**previous, "id": game_id, "name": game_name,
                "variant": port_name if port_name != game_name else previous.get("variant", ""),
                "sub": "PC · Port nativo", "platform": platform, "s": description,
                "src": "Omnia", "chips": list(metadata.get("tags") or previous.get("chips") or [])[:4],
                "art": previous.get("art") or {"slug": game_id, "sgdb": game_name}, "ports": [port]}
        # Ya es una entrada ordinaria de Omnia, no una entrada ligada a un detector.
        game.pop("auto", None)
        game.pop("recomp_art", None)
        if entry.get("last_played") or entry.get("played_secs"):
            game["played"] = {"last": int(entry.get("last_played") or 0),
                              "secs": int(entry.get("played_secs") or 0)}
        by_id[game_id] = game
        imported += 1

    if imported:
        ordered = [by_id.pop(str(game.get("id"))) for game in games if str(game.get("id")) in by_id]
        store.set_games(ordered + list(by_id.values()))
    with store.lock:
        store.state.setdefault("migrations", {})["recomplauncher_ports_to_omnia_v1"] = True
        store.save_state()
    return imported

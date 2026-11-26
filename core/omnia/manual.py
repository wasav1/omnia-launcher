"""Juegos manuales: los que Omnia no detecta sola (ports, emuladores, juegos de Windows sueltos, nativos).

Se guardan en la biblioteca SIN el campo `auto`, así que los refrescos de los detectores nunca los tocan. Usan el mismo
formato que el prototipo, de modo que el historial, el modo juego, el arte y las partidas funcionan igual con ellos.
"""
import os
import re
import shutil
from pathlib import Path

from . import roms, templates

KINDS = {"port": "Port nativo", "emulator": "Emulador", "windows": "Juego de Windows", "native": "Juego nativo"}
PLATFORMS = {"gopher64": "n64"}


class ManualError(Exception):
    pass


def slug(name: str) -> str:
    return re.sub(r"[^a-z0-9]+", "-", name.lower()).strip("-")[:48] or "juego"


def _inside(path: str, roots) -> bool:
    real = os.path.realpath(path)
    return any(real == str(r) or real.startswith(str(r).rstrip("/") + "/") for r in map(os.path.realpath, roots))


def add_game(store, data: dict, roots, gopher64=None, which=shutil.which, identity=None, catalog_slug="", art_title="") -> dict:
    name = str(data.get("name", "")).strip()
    if not name or len(name) > 80:
        raise ManualError("Pon un nombre al juego (hasta 80 letras).")
    tpl = str(data.get("template", "")) or ""
    kind = templates.TEMPLATES[tpl]["kind"] if tpl in templates.TEMPLATES else str(data.get("kind", ""))
    if kind not in KINDS:
        raise ManualError("Tipo de juego no válido.")
    exe, rom = str(data.get("exe", "")), str(data.get("rom", ""))
    for p in (exe, rom):
        if p and not _inside(p, roots):
            raise ManualError("Ese archivo está fuera de las carpetas permitidas.")
    try:
        if tpl:
            built = templates.build(tpl, exe=exe, rom=rom, gopher64=gopher64)
            if any(arg.startswith("/") and not _inside(arg, roots) for arg in built["launch"]):
                raise ManualError("El lanzador asociado está fuera de las carpetas permitidas.")
        else:
            if not exe or not os.path.isfile(exe):
                raise ManualError("Elige el ejecutable del juego.")
            install = os.path.dirname(exe)
            if kind == "windows":
                if not which("umu-run"):
                    raise ManualError("Falta umu-launcher para ejecutar juegos de Windows.")
                prefix = str(Path.home() / "Juegos/PC/_Prefijos" / slug(name))
                launch = ["env", "GAMEID=umu-0", "PROTONPATH=GE-Proton", "WINEPREFIX=" + prefix, "umu-run", exe]
            else:
                if not os.access(exe, os.X_OK):
                    raise ManualError("El archivo elegido no es ejecutable.")
                launch = [exe]
            built = {"launch": launch, "cwd": install, "check": exe, "proc": os.path.basename(exe), "saves": None,
                     "suggest": templates.suggest_dirs(install)}
    except templates.TemplateError as e:
        raise ManualError(str(e))
    saves = data.get("saves") if isinstance(data.get("saves"), dict) else built["saves"]
    with store.lock:
        games = store.games()
        base = "manual-" + slug(name)
        gid, n = base, 2
        while any(g.get("id") == gid for g in games):
            gid, n = f'{base}-{n:d}', n + 1
        port = {"id": gid + "-main", "name": templates.TEMPLATES[tpl]["name"] if tpl else KINDS[kind], "chips": [KINDS[kind]],
                "launch": built["launch"], "check": built["check"], "proc": built["proc"]}
        if built["cwd"]:
            port["cwd"] = built["cwd"]
        if saves:
            port["saves"] = saves
        if isinstance(data.get("backup_dir"), str) and data["backup_dir"]:
            port["backup_dir"] = data["backup_dir"]
        platform = str(data.get("platform", PLATFORMS.get(tpl, "pc")))
        if platform not in {"pc", "sw1", "sw2", *roms.SYSTEMS.keys()}:
            raise ManualError("Plataforma no válida.")
        entry = {"id": gid, "name": name, "sub": KINDS[kind], "platform": platform, "src": "Manual",
                 "art": {"slug": gid, "sgdb": art_title or name}, "ports": [port]}
        if identity:
            entry["detectedIdentity"] = identity
        if catalog_slug:
            entry["catalogSlug"] = catalog_slug
        store.set_games(games + [entry])
    return entry


def _rom_launch(system: str, emulator: str, path: str, roots) -> tuple[list, dict | None, str]:
    """Comando de lanzamiento de una ROM con un emulador detectado: (argv, partidas, nombre del emulador)."""
    try:
        launch, emulator_name = roms.launch_command(system, emulator, path, roots)
        saves = None
        # Gopher64 needs Omnia's save/launch template, but a user may instead
        # select a detected RetroArch core for N64. Keep the chosen emulator.
        if system == "n64" and emulator in {"gopher64", "gopher64-flatpak"}:
            gopher = templates.gopher64_install()
            built = templates.build("gopher64", rom=path, gopher64=gopher)
            launch, saves = built["launch"], built["saves"]
            emulator_name = "Gopher64" if emulator == "gopher64" else "Gopher64 (Flatpak)"
    except roms.RomScanError as exc:
        raise ManualError(str(exc)) from exc
    except templates.TemplateError as exc:
        raise ManualError(str(exc)) from exc
    return launch, saves, emulator_name


def resolve_rom_launch(port: dict, roots, which=shutil.which) -> dict:
    """Completa en el momento de jugar el emulador de una ROM importada sin él (o cuyo emulador desapareció).

    Devuelve una copia del port con `launch`, `saves` y `name` listos. Prefiere el emulador guardado si sigue instalado.
    """
    rom = port.get("rom") if isinstance(port.get("rom"), dict) else None
    if not rom:
        return port
    system, path = str(rom.get("system", "")), str(rom.get("path", ""))
    choices = roms.available_emulators(system, which=which)
    if not choices:
        name = roms.SYSTEMS.get(system, {}).get("name", system)
        raise ManualError(f"No hay ningún emulador de {name} instalado. Instala {roms.emulator_hint(system)} y vuelve a pulsar Jugar.")
    ids = [item["id"] for item in choices]
    chosen = rom.get("emulator") if rom.get("emulator") in ids else ids[0]
    launch, saves, emulator_name = _rom_launch(system, chosen, path, roots)
    resolved = {**port, "launch": launch, "name": emulator_name, "rom": {**rom, "emulator": chosen}}
    if saves:
        resolved["saves"] = saves
    return resolved


def add_rom_game(store, data: dict, roots) -> dict:
    """Registra una ROM confirmada. El emulador es opcional: sin él se elige al jugar; nunca ejecuta comandos de la petición."""
    name = str(data.get("name", "")).strip()
    path = data.get("path")
    system = data.get("system")
    emulator = data.get("emulator") or ""
    if not name or len(name) > 80 or not isinstance(path, str) or not isinstance(system, str) or not isinstance(emulator, str):
        raise ManualError("Nombre, ROM, plataforma o emulador no válidos.")
    candidate = roms.inspect_file(path, roots, include_emulators=False, system=system)
    if not candidate or candidate["system"] != system:
        raise ManualError("La ROM ya no es válida o cambió de plataforma.")
    launch, saves, emulator_name = [], None, "Emulador por elegir"
    if emulator:
        launch, saves, emulator_name = _rom_launch(system, emulator, candidate["path"], roots)
    with store.lock:
        games = store.games()
        base = "manual-" + slug(name)
        gid, n = base, 2
        while any(game.get("id") == gid for game in games):
            gid, n = f"{base}-{n:d}", n + 1
        port = {"id": gid + "-main", "name": emulator_name, "chips": ["ROM", candidate["systemName"]],
                "launch": launch, "check": candidate["path"], "proc": candidate["path"],
                "cwd": os.path.dirname(candidate["path"]),
                "rom": {"path": candidate["path"], "system": system, "emulator": emulator,
                        "internalId": candidate.get("internalId", ""), "internalIdType": candidate.get("internalIdType", "")}}
        if saves:
            port["saves"] = saves
        entry = {"id": gid, "name": name, "variant": emulator_name, "sub": "ROM · " + candidate["systemName"],
                 "platform": roms.platform_for(system, candidate.get("internalIdType", "")), "src": "ROM local", "art": {"slug": gid, "sgdb": name}, "ports": [port]}
        catalog_slug = data.get("catalogSlug")
        if isinstance(catalog_slug, str) and catalog_slug:
            entry["catalogSlug"] = catalog_slug
        store.set_games(games + [entry])
    return entry


def remove_game(store, gid: str) -> bool:
    """Solo se quitan juegos manuales: los detectados reaparecerían en el siguiente refresco."""
    with store.lock:
        games = store.games()
        g = next((x for x in games if x.get("id") == gid), None)
        if not g or g.get("auto") or not gid.startswith("manual-"):
            return False
        store.set_games([x for x in games if x.get("id") != gid])
        st = store.state
        for key in ("game_fav", "game_hidden"):
            st[key] = [x for x in (st.get(key) or []) if x != gid]
        for key in ("saves", "sessions", "last_played", "backups"):
            (st.get(key) or {}).pop(gid, None)
        store.save_state()
    return True


def migrate_bedrock_on_linux(store) -> int:
    """Corrige entradas antiguas de Minecraft que se guardaron como ejecutables Windows genéricos."""
    changed = 0
    with store.lock:
        games = store.games()
        for game in games:
            for port in game.get("ports", []):
                check = str(port.get("check", ""))
                if not templates.bedrock_on_linux_appimage(check):
                    continue
                built = templates.build("bedrock-on-linux", exe=check)
                port.update({key: built[key] for key in ("launch", "cwd", "check", "proc")})
                port.update(name=templates.TEMPLATES["bedrock-on-linux"]["name"], chips=[KINDS["port"]])
                game["sub"] = KINDS["port"]
                changed += 1
        if changed:
            store.set_games(games)
    return changed

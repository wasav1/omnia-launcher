"""Reconocimiento local, de solo lectura, de ROMs y discos de varias consolas.

Se leen solo cabeceras pequeñas y nombres de archivo; no se calculan hashes ni se sube contenido.
El usuario elige el emulador detectado y confirma cada juego antes de importarlo.
"""
from __future__ import annotations

import os
import re
import shutil
import subprocess
from pathlib import Path

SYSTEMS = {
    "n64": {"name": "Nintendo 64", "extensions": {".z64", ".n64", ".v64"}},
    "nes": {"name": "Nintendo Entertainment System", "extensions": {".nes"}},
    "snes": {"name": "Super Nintendo", "extensions": {".sfc", ".smc"}},
    "gb": {"name": "Game Boy", "extensions": {".gb"}},
    "gbc": {"name": "Game Boy Color", "extensions": {".gbc"}},
    "gba": {"name": "Game Boy Advance", "extensions": {".gba"}},
    "nds": {"name": "Nintendo DS", "extensions": {".nds", ".dsi", ".srl"}},
    "gcwii": {"name": "GameCube / Wii", "extensions": {".iso", ".gcm", ".gcz", ".rvz", ".wbfs", ".wia"}},
    "3ds": {"name": "Nintendo 3DS", "extensions": {".3ds", ".cci", ".cxi", ".cia"}},
    "switch": {"name": "Nintendo Switch", "extensions": {".nsp", ".xci", ".nup"}},
    "ps1": {"name": "PlayStation", "extensions": {".bin", ".cue", ".chd", ".pbp", ".iso"}},
    "ps2": {"name": "PlayStation 2", "extensions": {".bin", ".chd", ".cue", ".cso", ".iso"}},
    "psp": {"name": "PlayStation Portable", "extensions": {".cso", ".pbp", ".iso"}},
}
EXTENSIONS: dict[str, list[str]] = {}
for _system, _info in SYSTEMS.items():
    for _extension in sorted(_info["extensions"]):
        EXTENSIONS.setdefault(_extension, []).append(_system)
MAGICS = {b"\x80\x37\x12\x40", b"\x37\x80\x40\x12", b"\x40\x12\x37\x80"}
MAX_DIRECTORIES = 2000
MAX_FILES = 20000
MAX_FILE_BYTES = 64 * 1024 * 1024 * 1024
MAX_N64_BYTES = 128 * 1024 * 1024
MAX_HEADER_BYTES = 0x400
FLATPAK_G64 = "io.github.gopher64.gopher64"

_RETROARCH_CORES = {
    "nes": ("mesen_libretro.so", "nestopia_libretro.so", "fceumm_libretro.so"),
    "snes": ("snes9x_libretro.so", "bsnes_libretro.so"),
    "gb": ("gambatte_libretro.so", "sameboy_libretro.so"),
    "gbc": ("gambatte_libretro.so", "sameboy_libretro.so"),
    "gba": ("mgba_libretro.so", "vba_next_libretro.so"),
}


class RomScanError(Exception):
    pass


def _inside(path: str, roots) -> bool:
    real = os.path.realpath(path)
    return any(real == root or real.startswith(root.rstrip(os.sep) + os.sep) for root in roots)


def systems_for_suffix(suffix: str) -> list[str]:
    return list(EXTENSIONS.get(str(suffix).lower(), []))


_SWITCH_BRACKET = re.compile(r"\[(0[0-9A-Fa-f]{15})\]")
_MAX_PFS0_HEADER = 256 * 1024


def switch_title_id(path: str) -> tuple[str, str]:
    """Title ID (16 hex) de un NSP/XCI y de dónde sale: ("", "") si no se puede saber.

    NSP: el contenedor PFS0 lleva un ticket (.tik) cuyo nombre empieza por el Title ID; solo se lee el índice. XCI y NSP
    sin ticket: se usa el ID entre corchetes del nombre del archivo, p. ej. «Juego [01007EF00011E000].xci».
    """
    name = os.path.basename(path)
    if Path(path).suffix.lower() == ".nsp":
        try:
            with open(path, "rb") as stream:
                head = stream.read(0x10)
                if head[:4] == b"PFS0":
                    count = int.from_bytes(head[4:8], "little")
                    strings = int.from_bytes(head[8:12], "little")
                    size = 0x10 + 24 * count + strings
                    if 0 < count <= 8192 and size <= _MAX_PFS0_HEADER:
                        table = head + stream.read(size - 0x10)
                        names = table[0x10 + 24 * count:size]
                        for index in range(count):
                            offset = int.from_bytes(table[0x10 + 24 * index + 16:0x10 + 24 * index + 20], "little")
                            end = names.find(b"\0", offset)
                            entry = names[offset:end if end >= 0 else len(names)].decode("ascii", "ignore")
                            stem = entry.rsplit(".", 1)[0] if entry.lower().endswith(".tik") else ""
                            if re.fullmatch(r"[0-9A-Fa-f]{32}", stem):
                                return stem[:16].upper(), "ticket"
        except OSError:
            pass
    found = _SWITCH_BRACKET.search(name)
    return (found.group(1).upper(), "name") if found else ("", "")


_MAX_NPDM = 64 * 1024


def _npdm_program_id(path: str) -> str:
    """Program ID (16 hex) del `main.npdm` de un exefs: sección ACI0 (+0x10). «» si el archivo no es un NPDM válido."""
    try:
        with open(path, "rb") as stream:
            data = stream.read(_MAX_NPDM)
    except OSError:
        return ""
    if len(data) < 0x80 or data[:4] != b"META":
        return ""
    offset = int.from_bytes(data[0x70:0x74], "little")
    if offset + 0x18 > len(data) or data[offset:offset + 4] != b"ACI0":
        return ""
    return f"{int.from_bytes(data[offset + 0x10:offset + 0x18], 'little'):016X}"


def _nso_build_id(path: str) -> str:
    """Build ID (40 hex) del `exefs/main` (NSO0, module id en +0x40); identifica la versión exacta del ejecutable del juego."""
    try:
        with open(path, "rb") as stream:
            head = stream.read(0x60)
    except OSError:
        return ""
    if len(head) < 0x60 or head[:4] != b"NSO0":
        return ""
    return head[0x40:0x54].hex()


def inspect_dump_folder(path: str, roots=None) -> dict | None:
    """Carpeta de volcado de Switch/Switch 2 (`exefs/main` + `romfs/`): Title ID de su NPDM y build ID de su NSO.

    No sigue enlaces ni recorre el contenido: solo lee la cabecera de dos archivos pequeños. Las actualizaciones y el contenido
    descargable (Title ID que no termina en 000) no se importan como juego."""
    safe_roots = [os.path.realpath(os.path.expanduser(str(r))) for r in (roots or [str(Path.home())]) if isinstance(r, (str, os.PathLike))]
    real = os.path.realpath(os.path.expanduser(str(path or "")))
    if not _inside(real, safe_roots) or not os.path.isdir(real):
        return None
    exefs, romfs = os.path.join(real, "exefs"), os.path.join(real, "romfs")
    main = os.path.join(exefs, "main")
    try:
        if (os.path.islink(exefs) or os.path.islink(romfs) or os.path.islink(main) or not os.path.isdir(romfs)
                or not os.path.isfile(main)):
            return None
        size = os.stat(main).st_size
    except OSError:
        return None
    title_id = _npdm_program_id(os.path.join(exefs, "main.npdm"))
    build_id = _nso_build_id(main)
    if not title_id or not build_id or not is_base_switch_title(title_id):
        return None
    return {"path": real, "fileName": os.path.basename(real), "name": os.path.basename(real), "internalTitle": "", "format": "folder",
            "system": "switch", "internalId": title_id, "internalIdType": switch_kind(title_id), "buildId": build_id, "region": "",
            "systemName": SYSTEMS["switch"]["name"], "size": size, "confidence": "header", "emulators": [], "systemChoices": ["switch"]}


def platform_for(system: str, internal_id_type: str = "") -> str:
    """Plataforma de la biblioteca de Omnia para una ROM (Switch/Switch 2 se distinguen por su Title ID)."""
    if system == "switch":
        return "sw2" if internal_id_type == "switch2" else "sw1"
    return system


def switch_kind(title_id: str) -> str:
    """«switch» o «switch2» (los Title ID de Switch 2 empiezan por 04, como en RecompLauncher)."""
    return "switch2" if title_id.startswith("04") else "switch"


def is_base_switch_title(title_id: str) -> bool:
    """Un juego base termina en 000; las actualizaciones (800) y el contenido descargable (otros) no se importan solos."""
    return title_id[-3:] == "000"


def _title(raw: bytes, maximum: int = 48) -> str:
    return " ".join("".join(c if c.isprintable() else " " for c in raw.decode("ascii", "ignore")).split())[:maximum]


def title_from_header(head: bytes, system: str | None = None) -> tuple[str, str] | None:
    """Devuelve el título que expone una cabecera fiable y su plataforma; None si no es ROM reconocible."""
    if system in (None, "n64") and len(head) >= 0x40 and head[:4] in MAGICS:
        magic = head[:4]
        normalized = bytearray(head[:0x40])
        if magic == b"\x37\x80\x40\x12":
            normalized = bytearray(b"".join(normalized[i:i + 2][::-1] for i in range(0, len(normalized), 2)))
        elif magic == b"\x40\x12\x37\x80":
            normalized = bytearray(b"".join(normalized[i:i + 4][::-1] for i in range(0, len(normalized), 4)))
        fmt = {b"\x80\x37\x12\x40": "z64", b"\x37\x80\x40\x12": "v64", b"\x40\x12\x37\x80": "n64"}[magic]
        return _title(bytes(normalized[0x20:0x34]), 40), fmt
    if system in (None, "gcwii") and len(head) >= 0x60:
        wii_magic = head[0x18:0x1C]
        gamecube_magic = head[0x1C:0x20]
        if wii_magic == b"\x5d\x1c\x9e\xa3":
            return _title(head[0x20:0x60], 64), "wii-header"
        if gamecube_magic == b"\xc2\x33\x9f\x3d":
            return _title(head[0x20:0x60], 64), "gamecube-header"
    if system in (None, "gb", "gbc") and len(head) >= 0x150:
        gameboy_title = _title(head[0x134:0x144], 16)
        if gameboy_title and any(head[0x104:0x134]):
            return gameboy_title, "gb-header"
    if system in (None, "gba") and len(head) >= 0xB0:
        gba_title = _title(head[0xA0:0xAC], 12)
        if gba_title and any(head[0x04:0xA0]):
            return gba_title, "gba-header"
    if system in (None, "nds") and len(head) >= 0x10:
        nds_title = _title(head[0x00:0x0C], 12)
        game_code = head[0x0C:0x10]
        if nds_title and all(0x20 <= byte <= 0x5A for byte in game_code):
            return nds_title, "nds-header"
    if system in (None, "nes") and len(head) >= 16 and head[:4] == b"NES\x1a":
        return "", "ines-header"
    return None


def _core_roots() -> list[Path]:
    roots = [Path("/usr/lib/libretro"), Path("/usr/lib64/libretro"), Path("/usr/lib/retroarch/cores"),
             Path.home() / ".config/retroarch/cores", Path.home() / ".var/app/org.libretro.RetroArch/config/retroarch/cores"]
    return [path for path in roots if path.is_dir()]


def _find_retroarch_core(system: str) -> str:
    for filename in _RETROARCH_CORES.get(system, ()):
        for root in _core_roots():
            candidate = root / filename
            if candidate.is_file():
                return str(candidate)
    return ""


EMULATOR_HINTS = {
    "n64": "Gopher64 o RetroArch", "nes": "RetroArch", "snes": "RetroArch", "gb": "RetroArch", "gbc": "RetroArch",
    "gba": "RetroArch (mGBA)", "nds": "melonDS", "gcwii": "Dolphin", "3ds": "Azahar", "switch": "Ryujinx o Suyu",
    "ps1": "DuckStation", "ps2": "PCSX2", "psp": "PPSSPP",
}


def emulator_hint(system: str) -> str:
    return EMULATOR_HINTS.get(system, "un emulador compatible")


def available_emulators(system: str, which=shutil.which, run=subprocess.run) -> list[dict]:
    """Devuelve solo emuladores disponibles y compatibles con el sistema detectado."""
    choices = []
    if system == "n64":
        binary = which("gopher64")
        if binary:
            choices.append({"id": "gopher64", "label": "Gopher64"})
        elif which("flatpak"):
            try:
                result = run(["flatpak", "info", FLATPAK_G64], capture_output=True, timeout=5)
                if result.returncode == 0:
                    choices.append({"id": "gopher64-flatpak", "label": "Gopher64 (Flatpak)"})
            except (OSError, subprocess.TimeoutExpired):
                pass
    core = _find_retroarch_core(system)
    if core and which("retroarch"):
        choices.append({"id": "retroarch", "label": "RetroArch"})
    bins = {
        "nds": (("melonDS", "melonDS"), ("melonds", "melonDS")),
        "gcwii": (("dolphin", "Dolphin"), ("dolphin-emu", "Dolphin")),
        "3ds": (("azahar", "Azahar"), ("citra", "Citra")),
        "switch": (("ryujinx", "Ryujinx"), ("yuzu", "Yuzu"), ("suyu", "Suyu")),
        "ps1": (("duckstation-qt", "DuckStation"), ("duckstation", "DuckStation")),
        "ps2": (("pcsx2-qt", "PCSX2"), ("pcsx2", "PCSX2")),
        "psp": (("PPSSPPQt", "PPSSPP"), ("ppsspp", "PPSSPP"), ("PPSSPP", "PPSSPP")),
    }
    for binary, label in bins.get(system, ()):
        if which(binary):
            choices.append({"id": binary, "label": label})
            break
    return choices


def launch_command(system: str, emulator: str, rom: str, roots=None, which=shutil.which) -> tuple[list[str], str]:
    """Construye un argv sin shell y exige que el emulador corresponda a la lista detectada."""
    candidate = inspect_file(rom, roots, include_emulators=False, system=system)
    if not candidate or candidate["system"] != system:
        raise RomScanError("La ROM no está en una carpeta permitida o cambió de formato.")
    if emulator not in {item["id"] for item in available_emulators(system, which=which)}:
        raise RomScanError("El emulador elegido ya no está disponible o no corresponde a esta ROM.")
    if emulator == "gopher64":
        return [which("gopher64"), "--fullscreen", rom], "Gopher64"
    if emulator == "gopher64-flatpak":
        return [which("flatpak"), "run", "--env=MANGOHUD=1", FLATPAK_G64, "--fullscreen", rom], "Gopher64 (Flatpak)"
    if emulator == "retroarch":
        core = _find_retroarch_core(system)
        if not core:
            raise RomScanError("No se encontró el núcleo de RetroArch para esta plataforma.")
        return [which("retroarch"), "-L", core, rom], "RetroArch"
    exe = which(emulator)
    if not exe:
        raise RomScanError("No se encontró el emulador elegido.")
    if emulator in {"dolphin", "dolphin-emu"}:
        return [exe, "-b", "-e", rom], "Dolphin"
    if emulator in {"duckstation", "duckstation-qt"}:
        return [exe, "-fullscreen", "--", rom], "DuckStation"
    if emulator in {"pcsx2", "pcsx2-qt"}:
        return [exe, "-fullscreen", "--", rom], "PCSX2"
    return [exe, rom], next(item["label"] for item in available_emulators(system, which=which) if item["id"] == emulator)


def inspect_file(path: str, roots=None, include_emulators: bool = True, which=shutil.which, system: str | None = None) -> dict | None:
    """Revalida el archivo y devuelve plataforma, nombre sugerido, evidencia y emuladores instalados."""
    safe_roots = [os.path.realpath(os.path.expanduser(str(r))) for r in (roots or [str(Path.home())]) if isinstance(r, (str, os.PathLike))]
    real = os.path.realpath(os.path.expanduser(str(path or "")))
    suffix = Path(real).suffix.lower()
    systems = systems_for_suffix(suffix)
    if not systems or not _inside(real, safe_roots):
        return None
    if system is not None and system not in systems:
        return None
    if system is None:
        detected = _disc_system(real) if suffix in {".iso", ".bin"} else ""
        preferred = [detected] if detected in systems else [sid for sid in systems if sid != "gcwii"] if suffix == ".iso" else systems
        system = preferred[0]
        if not detected and include_emulators:
            system = next((choice for choice in preferred if available_emulators(choice, which=which)), system)
    try:
        stat = os.stat(real, follow_symlinks=False)
        if not os.path.isfile(real) or stat.st_size < 16 or stat.st_size > MAX_FILE_BYTES or (system == "n64" and stat.st_size > MAX_N64_BYTES):
            return None
        with open(real, "rb") as stream:
            head = stream.read(MAX_HEADER_BYTES)
    except OSError:
        return None
    parsed = title_from_header(head, system)
    disc_id = _playstation_disc_id(real) if system in {"ps1", "ps2"} else None
    if system == "n64" and (not parsed or parsed[1] not in {"z64", "v64", "n64"}):
        return None
    if suffix == ".nes" and (not parsed or parsed[1] != "ines-header"):
        return None
    title = ""
    internal_id = ""
    internal_id_type = ""
    switch_origin = ""
    region = ""
    if parsed:
        candidate, evidence = parsed
        if (system == "n64" and evidence in {"z64", "v64", "n64"}) or (system in {"gb", "gbc"} and evidence == "gb-header") or (system == "gba" and evidence == "gba-header") or (system == "nds" and evidence == "nds-header"):
            title = candidate
        elif system == "gcwii" and evidence in {"gamecube-header", "wii-header"}:
            title = candidate
            internal_id = _title(head[:6], 6).upper()
            region = _region_from_console_code(head[:6])
            internal_id_type = "wii" if evidence == "wii-header" else "gamecube"
        if system == "n64" and evidence in {"z64", "v64", "n64"}:
            normalized = bytearray(head[:0x40])
            if head[:4] == b"\x37\x80\x40\x12":
                normalized = bytearray(b"".join(normalized[i:i + 2][::-1] for i in range(0, len(normalized), 2)))
            elif head[:4] == b"\x40\x12\x37\x80":
                normalized = bytearray(b"".join(normalized[i:i + 4][::-1] for i in range(0, len(normalized), 4)))
            internal_id = _title(bytes(normalized[0x3B:0x3F]), 4).upper()
            region = _region_from_console_code(normalized[0x3B:0x3F])
            internal_id_type = "n64"
        elif system == "gba" and evidence == "gba-header":
            internal_id = _title(head[0xAC:0xB0], 4).upper()
            internal_id_type = "gba"
        elif system == "nds" and evidence == "nds-header":
            internal_id = _title(head[0x0C:0x10], 4).upper()
            internal_id_type = "nds"
    if system == "switch":
        title_id, origin = switch_title_id(real)
        if title_id:
            if not is_base_switch_title(title_id):
                return None                              # actualización o DLC: no es un juego
            internal_id, internal_id_type = title_id, switch_kind(title_id)
        elif suffix == ".nup":
            internal_id_type = "switch2"                 # un .nup sin Title ID en el nombre se toma por un volcado de Switch 2
        # confianza «header» solo si el ID salió del ticket; por nombre queda como «extension»
        switch_origin = origin
    if disc_id and disc_id[0] == system:
        internal_id = disc_id[1]
        internal_id_type = system
        region = disc_id[2]
    emulators = available_emulators(system, which=which) if include_emulators else []
    return {"path": real, "fileName": os.path.basename(real), "name": title or Path(real).stem,
            "internalTitle": title, "format": suffix[1:], "system": system,
            "internalId": internal_id, "internalIdType": internal_id_type, "region": region,
            "systemName": SYSTEMS[system]["name"], "size": stat.st_size,
            "confidence": "header" if title or (internal_id and (system != "switch" or switch_origin == "ticket")) or (parsed and parsed[1] == "ines-header") else "extension",
            "emulators": emulators, "systemChoices": systems}


def _region_from_console_code(code: bytes) -> str:
    if not code:
        return ""
    marker = chr(code[-1]).upper() if 0 <= code[-1] < 128 else ""
    if marker in {"E", "N"}:
        return "USA"
    if marker in {"P", "D", "F", "I", "S", "U", "X", "Y"}:
        return "Europa"
    if marker == "J":
        return "Japón"
    return ""


def _disc_system(path: str) -> str:
    """Identifica discos Nintendo y PlayStation leyendo cabeceras/metadata pequeñas."""
    try:
        with open(path, "rb") as stream:
            header = stream.read(0x20)
    except OSError:
        return ""
    if len(header) >= 0x20 and header[0x18:0x1C] == b"\x5d\x1c\x9e\xa3":
        return "gcwii"
    if len(header) >= 0x20 and header[0x1C:0x20] == b"\xc2\x33\x9f\x3d":
        return "gcwii"
    playstation_id = _playstation_disc_id(path)
    if playstation_id:
        return playstation_id[0]
    return ""


def _playstation_disc_id(path: str) -> tuple[str, str, str] | None:
    """Lee SYSTEM.CNF de una ISO/BIN PS1 o PS2 sin extraer ni enviar el disco.

    Admite ISO 9660 normal (2048 bytes/sector) y BIN raw (2352 bytes/sector con
    cabecera de 16 o 24 bytes). Recorre solo la entrada raíz y limita lecturas.
    """
    if Path(path).suffix.lower() == ".cue":
        for track in _cue_tracks(path):
            result = _playstation_disc_id(track)
            if result:
                return result
        return None
    try:
        with open(path, "rb") as stream:
            for sector_size, data_offset in ((2048, 0), (2352, 24), (2352, 16)):
                stream.seek(16 * sector_size + data_offset)
                pvd = stream.read(2048)
                if len(pvd) < 190 or pvd[0] != 1 or pvd[1:6] != b"CD001":
                    continue
                root = pvd[156:190]
                root_lba = int.from_bytes(root[2:6], "little")
                root_bytes = min(int.from_bytes(root[10:14], "little"), 64 * 1024)
                if not root_lba or not root_bytes:
                    continue
                for offset in range(0, root_bytes, sector_size if sector_size == 2048 else 2048):
                    stream.seek((root_lba * sector_size) + data_offset + offset)
                    directory = stream.read(min(2048, root_bytes - offset))
                    cursor = 0
                    while cursor + 33 <= len(directory):
                        record_len = directory[cursor]
                        if record_len == 0:
                            break
                        record = directory[cursor:cursor + record_len]
                        if len(record) < 34:
                            break
                        name_len = record[32]
                        name = record[33:33 + name_len].split(b";", 1)[0].upper()
                        if name == b"SYSTEM.CNF":
                            lba = int.from_bytes(record[2:6], "little")
                            length = min(int.from_bytes(record[10:14], "little"), 4096)
                            if not lba or not length:
                                return None
                            stream.seek(lba * sector_size + data_offset)
                            cnf = stream.read(length).decode("ascii", "ignore").upper()
                            match = re.search(r"BOOT2?\s*=\s*CDROM[0-9]*:\s*[/\\]?\s*([A-Z]{4})[_-]?(\d{3})[.]?(\d{2})", cnf)
                            if not match:
                                return None
                            prefix, disc, version = match.groups()
                            game_id = f"{prefix}{disc}{version}"
                            system = "ps2" if re.search(r"^\s*BOOT2\s*=", cnf, re.M) else "ps1"
                            region = "Europe" if prefix.startswith(("SLES", "SCES", "SLED", "SCED")) else "Japón" if prefix.startswith(("SLPS", "SCPS", "SLPM")) else "USA" if prefix.startswith(("SLUS", "SCUS")) else ""
                            return system, game_id, region
                        cursor += max(record_len, 1)
    except (OSError, ValueError):
        return None
    return None


def _cue_tracks(path: str) -> list[str]:
    """Resuelve pistas FILE de un CUE, permitiendo solo archivos dentro de su carpeta."""
    try:
        if os.path.getsize(path) > 64 * 1024:
            return []
        with open(path, "r", encoding="utf-8", errors="replace") as stream:
            cue = stream.read(64 * 1024)
    except OSError:
        return []
    folder = os.path.realpath(os.path.dirname(path))
    tracks = []
    for quoted, bare in re.findall(r'^\s*FILE\s+(?:"([^"]+)"|(\S+))\s+\S+', cue, re.I | re.M):
        name = quoted or bare
        candidate = os.path.realpath(os.path.join(folder, name))
        if _inside(candidate, [folder]) and os.path.isfile(candidate):
            tracks.append(candidate)
    return list(dict.fromkeys(tracks))


def scan(folder: str, roots=None) -> dict:
    """Recorre un árbol elegido, sin seguir enlaces, con límites y sin leer ROMs completas."""
    root = os.path.realpath(os.path.expanduser(str(folder or "")))
    safe_roots = [os.path.realpath(os.path.expanduser(str(r))) for r in (roots or [str(Path.home())]) if isinstance(r, (str, os.PathLike))]
    if not os.path.isdir(root) or not _inside(root, safe_roots):
        raise RomScanError("Elige una carpeta permitida que exista.")
    stack = [(root, 0)]
    seen_dirs = seen_files = 0
    items = []
    truncated = False
    emulators = {system: available_emulators(system) for system in SYSTEMS}
    while stack:
        current, depth = stack.pop()
        seen_dirs += 1
        if seen_dirs > MAX_DIRECTORIES:
            truncated = True
            break
        dump = inspect_dump_folder(current, safe_roots)
        if dump:                                        # carpeta de volcado (exefs + romfs): es un juego, no se recorre por dentro
            dump["emulators"] = emulators["switch"]
            dump["systemOptions"] = [{"id": "switch", "name": SYSTEMS["switch"]["name"], "emulators": emulators["switch"]}]
            items.append(dump)
            continue
        try:
            with os.scandir(current) as entries:
                dirs, files = [], []
                for entry in entries:
                    if entry.name.startswith("."):
                        continue
                    try:
                        if entry.is_dir(follow_symlinks=False):
                            if depth < 10:
                                dirs.append(entry.path)
                        elif entry.is_file(follow_symlinks=False) and Path(entry.name).suffix.lower() in EXTENSIONS:
                            files.append(entry.path)
                    except OSError:
                        continue
                cue_tracks = {track for cue in files if Path(cue).suffix.lower() == ".cue" for track in _cue_tracks(cue)}
                files = [path for path in files if not (Path(path).suffix.lower() == ".bin" and os.path.realpath(path) in cue_tracks)]
                for path in files:
                    seen_files += 1
                    if seen_files > MAX_FILES:
                        truncated = True
                        break
                    candidates = systems_for_suffix(Path(path).suffix)
                    detected = _disc_system(path) if Path(path).suffix.lower() in {".iso", ".bin", ".cue"} else ""
                    preferred = [detected] if detected in candidates else [sid for sid in candidates if sid != "gcwii"] if Path(path).suffix.lower() == ".iso" else candidates
                    default_system = next((sid for sid in preferred if emulators[sid]), preferred[0] if preferred else "")
                    item = inspect_file(path, safe_roots, include_emulators=False, system=default_system)
                    if item:
                        item["emulators"] = emulators[item["system"]]
                        item["systemOptions"] = [{"id": sid, "name": SYSTEMS[sid]["name"], "emulators": emulators[sid]} for sid in item["systemChoices"]]
                        items.append(item)
                if truncated:
                    break
                stack.extend((path, depth + 1) for path in reversed(sorted(dirs, key=str.casefold)))
        except OSError:
            continue
    items.sort(key=lambda item: (item["systemName"].casefold(), item["name"].casefold(), item["fileName"].casefold()))
    return {"items": items, "directoriesVisited": seen_dirs, "filesVisited": seen_files,
            "truncated": truncated, "root": root}

"""Plantillas: lo que Omnia sabe de dónde guardan sus partidas los emuladores y ports conocidos, y sugerencias de carpetas.

Una plantilla solo afirma lo que está comprobado. Donde no se sabe (p. ej. Savage Wind) devuelve `saves: None` y Omnia
ofrece candidatas para que el usuario confirme en el explorador.
"""
import array
import hashlib
import os
import re
import shutil
import subprocess
from pathlib import Path

FLATPAK_G64 = "io.github.gopher64.gopher64"


class TemplateError(Exception):
    pass


TEMPLATES = {
    "gopher64": {"name": "Emulador N64 (Gopher64)", "kind": "emulator", "needs": "rom", "ext": [".z64", ".n64", ".v64"]},
    "bedrock-on-linux": {"name": "Minecraft Bedrock (BedrockOnLinux)", "kind": "port", "needs": "exe", "ext": [".exe", ".appimage"]},
    "longshot": {"name": "Longshot (port de Zelda: Ocarina of Time)", "kind": "port", "needs": "exe", "ext": []},
    "hookshot": {"name": "Hookshot (port de Zelda: Ocarina of Time)", "kind": "port", "needs": "exe", "ext": []},
    "nx2navi": {"name": "NX2navi (port de Zelda: Ocarina of Time)", "kind": "port", "needs": "exe", "ext": []},
    "savagewind": {"name": "Savage Wind (port de Zelda: Breath of the Wild)", "kind": "port", "needs": "exe", "ext": []},
    "totkrecomp": {"name": "TOTK Recomp (port de Zelda: Tears of the Kingdom)", "kind": "port", "needs": "exe", "ext": []},
}


def catalog() -> list:
    return [{"id": k, **v} for k, v in TEMPLATES.items()]


def bedrock_on_linux_appimage(exe: str):
    """Devuelve el AppImage de BedrockOnLinux asociado al ejecutable instalado, si es una instalación reconocida."""
    path = Path(exe)
    if path.name.startswith("BedrockOnLinux-") and path.suffix.casefold() == ".appimage":
        return path if path.is_file() and os.access(path, os.X_OK) else None
    if path.name.casefold() != "minecraft.windows.exe" or not path.is_file():
        return None
    game_root = next((p for p in path.parents if p.name == "Minecraft"), None)
    if game_root is None or not any((p / ".bedrock-on-linux-install.json").is_file() for p in path.parents):
        return None
    return next((candidate for parent in game_root.parents
                 for candidate in sorted(parent.glob("BedrockOnLinux-*.AppImage"))
                 if candidate.is_file() and os.access(candidate, os.X_OK)), None)


# ---------------------------------------------------------------- Gopher64 (N64)
def rom_hashes(rom) -> set:
    """SHA-256 de la ROM tal cual y normalizada a otro orden de bytes: Gopher64 nombra la partida con el de su formato."""
    data = Path(rom).read_bytes()
    out = {hashlib.sha256(data).hexdigest().upper()}
    head = data[:4]
    if head == b"\x37\x80\x40\x12":                                  # v64: intercambiado de 16 bits
        a = array.array("H")
        a.frombytes(data[: len(data) // 2 * 2])
        a.byteswap()
        out.add(hashlib.sha256(a.tobytes()).hexdigest().upper())
    elif head == b"\x40\x12\x37\x80":                                # n64: little endian de 32 bits
        a = array.array("I")
        a.frombytes(data[: len(data) // 4 * 4])
        a.byteswap()
        out.add(hashlib.sha256(a.tobytes()).hexdigest().upper())
    return out


def gopher64_install(which=shutil.which, run=subprocess.run) -> dict:
    """Cómo está instalado Gopher64: nativo o Flatpak (con su carpeta de partidas). Lanza TemplateError si no está."""
    home = Path.home()
    if which("gopher64"):
        return {"argv": ["gopher64"], "saves": str(home / ".local/share/gopher64/saves")}
    if which("flatpak"):
        try:
            if run(["flatpak", "info", FLATPAK_G64], capture_output=True, timeout=10).returncode == 0:
                return {"argv": ["flatpak", "run", "--env=MANGOHUD=1", FLATPAK_G64],
                        "saves": str(home / ".var/app" / FLATPAK_G64 / "data/gopher64/saves")}
        except (OSError, subprocess.TimeoutExpired):
            pass
    raise TemplateError("Gopher64 no está instalado (ni nativo ni como Flatpak).")


# ---------------------------------------------------------------- construir un juego desde una plantilla
def build(template_id: str, exe: str = "", rom: str = "", gopher64=None) -> dict:
    """Devuelve {launch, cwd, check, proc, saves|None, suggest} para añadir un juego manual."""
    if template_id not in TEMPLATES:
        raise TemplateError("plantilla desconocida")
    home = str(Path.home())
    if template_id == "gopher64":
        if not rom or not os.path.isfile(rom):
            raise TemplateError("Elige la ROM del juego.")
        g = gopher64 or gopher64_install()
        return {"launch": g["argv"] + ["--fullscreen", rom], "cwd": "", "check": rom, "proc": os.path.basename(rom),
                "saves": {"files": ["{}/*-{}.*".format(g["saves"], h) for h in sorted(rom_hashes(rom))], "name": "Partida"},
                "suggest": []}
    if template_id == "bedrock-on-linux":
        appimage = bedrock_on_linux_appimage(exe)
        if appimage is not None and appimage == Path(exe):
            return {"launch": [str(appimage), "play"], "cwd": str(appimage.parent), "check": exe,
                    "proc": "Minecraft.Windows.exe", "saves": None, "suggest": []}
        if not exe or os.path.basename(exe).casefold() != "minecraft.windows.exe" or not os.path.isfile(exe):
            raise TemplateError("Elige un AppImage ejecutable de BedrockOnLinux o el Minecraft.Windows.exe de su instalación.")
        game_root = next((p for p in Path(exe).parents if p.name == "Minecraft"), None)
        if game_root is None or not any((p / ".bedrock-on-linux-install.json").is_file() for p in Path(exe).parents):
            raise TemplateError("No parece una instalación de Minecraft creada por BedrockOnLinux.")
        if appimage is None:
            raise TemplateError("No encontré el AppImage BedrockOnLinux junto a la carpeta Minecraft.")
        return {"launch": [str(appimage), "play"], "cwd": str(game_root), "check": exe,
                "proc": "Minecraft.Windows.exe", "saves": None, "suggest": suggest_dirs(str(game_root))}
    if not exe or not os.path.isfile(exe):
        raise TemplateError("Elige el ejecutable del port.")
    if not os.access(exe, os.X_OK):
        raise TemplateError("El archivo elegido no es ejecutable.")
    install = os.path.dirname(exe)
    base = {"launch": [exe], "cwd": install, "check": exe, "proc": os.path.basename(exe), "suggest": suggest_dirs(install)}
    saves = {
        "longshot": {"glob": home + "/.local/share/longshot/save/*/slot_*", "name": "Ranura {n}"},
        "hookshot": {"glob": home + "/.local/share/hookshot/save/*", "name": "Cuenta {n}"},
        "nx2navi": {"glob": install + "/profile/save/*/slot_*", "name": "Ranura {n}"},
        "totkrecomp": {"files": [install + "/profile/**/*.sav"], "name": "Partida"},
        "savagewind": None,                                           # «ubicación sin comprobar»: el usuario confirma una candidata
    }[template_id]
    return {**base, "saves": saves}


# ---------------------------------------------------------------- sugerencias de carpetas
SAVE_NAMES = {"save", "saves", "savedata", "savegame", "savegames", "profile", "profiles", "slots", "userdata", "saved"}
SAVE_EXTS = {".sav", ".save", ".dat", ".sl2", ".bin", ".srm", ".eep", ".fla", ".mpk", ".json"}


def suggest_dirs(root, max_depth: int = 4, limit: int = 8) -> list:
    """Carpetas dentro de la instalación de un juego que parecen guardar partidas (por nombre y por el tipo de archivos)."""
    root, found = str(root), []
    if not root or not os.path.isdir(root):
        return found
    base_depth = root.rstrip("/").count("/")
    for cur, dirs, files in os.walk(root):
        if cur.count("/") - base_depth >= max_depth:
            dirs[:] = []
            continue
        dirs[:] = [d for d in dirs if not d.startswith(".")]
        name = os.path.basename(cur).lower()
        n_save = sum(1 for f in files if os.path.splitext(f)[1].lower() in SAVE_EXTS)
        if name in SAVE_NAMES and n_save:
            try:
                mt = max(os.path.getmtime(os.path.join(cur, f)) for f in files)
            except (OSError, ValueError):
                mt = 0
            found.append({"path": cur, "label": os.path.relpath(cur, root), "score": 2 + (n_save > 1), "mtime": mt})
    return sorted(found, key=lambda x: (-x["score"], -x["mtime"]))[:limit]


def _words(text: str) -> set:
    return {w for w in re.findall(r"[a-z0-9]+", re.sub(r"([a-z])([A-Z])", r"\1 \2", text).lower()) if len(w) >= 3}


def proton_prefix(manifest_path: str, appid: str) -> Path | None:
    """Prefijo de Proton de un juego de Steam, a partir de la ruta de su appmanifest (steamapps/appmanifest_<id>.acf)."""
    lib = Path(manifest_path).parent
    p = lib / "compatdata" / str(appid) / "pfx/drive_c/users/steamuser"
    return p if p.is_dir() else None


def steam_suggestions(name: str, appid: str, manifest_path: str, steam_root: str | None = None, limit: int = 8) -> list:
    """Candidatas a carpeta de partidas de un juego de Steam: la caché de Steam Cloud y, en el prefijo de Proton, las
    carpetas cuyo nombre se parece al del juego. Solo sugiere: el usuario confirma. No propone el prefijo entero (enorme)."""
    out, tokens = [], _words(name)
    root = Path(steam_root) if steam_root else Path.home() / ".local/share/Steam"
    for ud in sorted((root / "userdata").glob(f"*/{appid}/remote")) if (root / "userdata").is_dir() else []:
        if ud.is_dir() and any(ud.iterdir()):
            out.append({"path": str(ud), "label": "Steam Cloud (caché local)", "score": 5, "mtime": ud.stat().st_mtime})
    pfx = proton_prefix(manifest_path, appid) if manifest_path else None
    if pfx:
        for sub, bonus in (("Documents/My Games", 2), ("Documents", 0), ("Saved Games", 2), ("AppData/Roaming", 0),
                           ("AppData/Local", 0), ("AppData/LocalLow", 1)):
            d = pfx / sub
            if not d.is_dir():
                continue
            for c in sorted(d.iterdir()):
                if not c.is_dir() or c.name.startswith("."):
                    continue
                # un nivel de empresa en medio es habitual (AppData/LocalLow/<Empresa>/<Juego>): se miran los dos niveles
                try:
                    children = [x for x in sorted(c.iterdir()) if x.is_dir() and not x.name.startswith(".")][:60]
                except OSError:
                    children = []
                for cand in [c] + children:
                    hit = len(tokens & _words(cand.name))
                    if hit or (sub == "Saved Games" and cand.name.lower() in SAVE_NAMES):
                        out.append({"path": str(cand), "label": str(cand.relative_to(pfx)), "score": hit + bonus,
                                    "mtime": cand.stat().st_mtime})
    best = {}
    for x in out:                                  # la misma carpeta puede salir por dos caminos: se queda con la mejor puntuación
        if x["path"] not in best or x["score"] > best[x["path"]]["score"]:
            best[x["path"]] = x
    return sorted(best.values(), key=lambda x: (-x["score"], -x["mtime"]))[:limit]

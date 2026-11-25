"""Steam: juegos con appmanifest_*.acf completamente instalados."""
import re
from pathlib import Path

from .base import Detector
from .vdf import parse_vdf

SKIP = re.compile(r"proton|steam linux runtime|steamworks|steamvr|redistributable", re.IGNORECASE)
FULLY_INSTALLED = 4      # bit StateFlags de Steam


def steam_roots(home: Path | None = None) -> list:
    h = Path(home) if home else Path.home()
    cands = [h / ".local/share/Steam", h / ".steam/steam", h / ".var/app/com.valvesoftware.Steam/.local/share/Steam"]
    seen, out = set(), []
    for c in cands:
        r = c.resolve()
        if c.is_dir() and r not in seen:
            seen.add(r)
            out.append(c)
    return out


def library_dirs(root: Path) -> list:
    dirs = [root / "steamapps"]
    vdf = root / "steamapps" / "libraryfolders.vdf"
    try:
        data = parse_vdf(vdf.read_text(encoding="utf-8", errors="replace")).get("libraryfolders", {})
    except OSError:
        data = {}
    for v in data.values():
        if isinstance(v, dict) and v.get("path"):
            d = Path(v["path"]) / "steamapps"
            if d.is_dir() and d not in dirs:
                dirs.append(d)
    return [d for d in dirs if d.is_dir()]


def download_jobs(home: Path | None = None) -> list:
    """Read Steam's active download counters without managing its queue."""
    jobs = {}
    for root in steam_roots(home):
        for library in library_dirs(root):
            for manifest in library.glob("appmanifest_*.acf"):
                try:
                    app = parse_vdf(manifest.read_text(encoding="utf-8", errors="replace")).get("AppState", {})
                    appid, title = app["appid"], app["name"]
                    flags = int(app.get("StateFlags", 0))
                    total = int(app.get("BytesToDownload", 0))
                    done = int(app.get("BytesDownloaded", 0))
                    stage_total = int(app.get("BytesToStage", 0))
                    staged = int(app.get("BytesStaged", 0))
                except (OSError, KeyError, ValueError, TypeError, AttributeError):
                    continue
                if not re.fullmatch(r"[0-9]{1,10}", appid) or SKIP.search(title):
                    continue
                # Downloading / preallocating / committing / staging are Steam's active transfer flags.
                active = flags & (1048576 | 65536 | 131072 | 2097152)
                if not active:
                    continue
                progress = (min(99, max(0, done + staged) * 100 // (total + stage_total))
                            if total + stage_total > 0 else 0)
                status = "finalizing" if active & (131072 | 2097152) and done >= total else "downloading"
                jobs[appid] = {"id": f"steam-transfer-{appid}", "name": title, "status": status,
                               "progress": progress, "source": "steam", "external": True,
                               "destination": str(library)}
    return list(jobs.values())


class SteamDetector(Detector):
    name = "steam"
    label = "Steam"

    def __init__(self, home: Path | None = None):
        self.home = home

    def detect(self) -> list:
        games, seen = [], set()
        for root in steam_roots(self.home):
            for lib in library_dirs(root):
                for acf in sorted(lib.glob("appmanifest_*.acf")):
                    g = self._game(acf, lib)
                    if g and g["id"] not in seen:
                        seen.add(g["id"])
                        games.append(g)
        return games

    def is_running(self, game: dict, port: dict, cmdlines: list) -> bool:
        """Steam arranca el juego bajo su propio árbol: se reconoce por `reaper SteamLaunch AppId=<id> --`."""
        appid = game["id"].removeprefix("steam-")
        tag = f"SteamLaunch AppId={appid} "
        return any(tag in c and "reaper" in c for c in cmdlines)

    @staticmethod
    def _game(acf: Path, lib: Path):
        try:
            st = parse_vdf(acf.read_text(encoding="utf-8", errors="replace")).get("AppState", {})
            appid, name = st["appid"], st["name"]
            flags = int(st.get("StateFlags", 0))
        except (OSError, KeyError, ValueError):
            return None
        if not appid.isdigit() or SKIP.search(name) or not flags & FULLY_INSTALLED:
            return None
        if not (lib / "common" / st.get("installdir", "")).is_dir():
            return None          # carpeta del juego borrada: no cuenta como instalado
        return {"id": "steam-" + appid, "name": name, "sub": "PC · Steam", "platform": "pc", "src": "Steam",
                "auto": "steam", "art": {"slug": "steam-" + appid, "sgdb": name},
                "ports": [{"id": f"steam-{appid}-main", "name": "Steam", "chips": ["Steam"],
                           "launch": ["steam", "steam://rungameid/" + appid], "check": str(acf), "proc": "",
                           "folder": str(lib / "common" / st.get("installdir", ""))}]}

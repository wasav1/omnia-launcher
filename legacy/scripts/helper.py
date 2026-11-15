#!/usr/bin/env python3
"""Ayudante de la estantería de juegos (widget de Plasma).

Sirve en 127.0.0.1:47831 lo que el widget QML no puede hacer solo:
  - biblioteca de juegos (orden por último jugado, partidas reales, disco, ajustes)
  - lanzar juegos, respaldar partidas, abrir la carpeta de partidas
  - detectar qué juego está corriendo y cuánto duró la sesión
  - leer el mando (/dev/input/js*) y enviar las pulsaciones por long-poll
  - niveles de audio reales (PipeWire) para las ondas
  - arte desde SteamGridDB (consulta, descarga, caché y cambio de opción)
Solo biblioteca estándar de Python. Escucha únicamente en localhost.
"""
import array
import math, glob, json, os, re, struct, subprocess, sys, tarfile, threading, time
import urllib.parse, urllib.request
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

HOME = os.path.expanduser("~")
CFG = os.path.join(HOME, ".config", "estanteria")
DATA = os.path.join(HOME, ".local", "share", "estanteria")
ART = os.path.join(DATA, "arte")
LIB_FILE = os.path.join(CFG, "library.json")
STATE_FILE = os.path.join(CFG, "state.json")
KEY_FILE = os.path.join(HOME, ".config", "steamgriddb.key")
PORT = 47831
SGDB = "https://www.steamgriddb.com/api/v2"
UA = "estanteria-juegos/1.0"
N_OPCIONES = {"portada": 6, "fondo": 6, "logo": 4}

lock = threading.RLock()
ui = {"plat": "all", "menu": 0, "q": ""}
state = {"last_played": {}, "sessions": {}, "art": {}, "backups": {}, "apps_used": {}, "apps_fav": None, "game_fav": [], "game_hidden": []}
running = {}          # id -> epoch de inicio
disk_cache = {}       # id -> bytes
art_busy = set()
pad = {"enabled": False, "seq": 0, "events": [], "cv": threading.Condition(), "connected": False, "name": ""}
audio = {"on_until": 0.0, "levels": [0.0, 0.0, 0.0, 0.0], "bands": [0.0] * 16, "ok": False}


def log(*a):
    print(time.strftime("%H:%M:%S"), *a, flush=True)


def expand(p):
    return os.path.expanduser(p) if isinstance(p, str) else p


# ---------------------------------------------------------------- biblioteca / estado
def load_json(path, default):
    try:
        with open(path) as f:
            return json.load(f)
    except Exception:
        return default


def save_state():
    with lock:
        tmp = STATE_FILE + ".tmp"
        os.makedirs(CFG, exist_ok=True)
        with open(tmp, "w") as f:
            json.dump(state, f, indent=1)
        os.replace(tmp, STATE_FILE)


def library():
    return load_json(LIB_FILE, {"games": []}).get("games", [])


def find_game(gid):
    for g in library():
        if g["id"] == gid:
            return g
    return None


SAVE_KINDS = {"eep": "Partida (EEPROM)", "sra": "Partida (SRAM)", "fla": "Partida (Flash)", "mpk": "Controller Pak", "srm": "Partida"}


def save_files(p):
    """Partidas guardadas como ARCHIVOS (emuladores): lista de rutas que coinciden con saves.files (patrones)."""
    fs = []
    for pat in (p.get("saves") or {}).get("files", []) or []:
        for f in sorted(glob.glob(expand(pat))):
            if os.path.isfile(f) and f not in fs:
                fs.append(f)
    return fs


def save_slots(p):
    """Partidas reales de un puerto: una entrada por carpeta que coincide con el glob (o por archivo con saves.files)."""
    if (p.get("saves") or {}).get("files"):
        out = []
        for f in save_files(p):
            try:
                mt = os.path.getmtime(f)
            except OSError:
                mt = 0
            out.append({"name": SAVE_KINDS.get(os.path.splitext(f)[1].lstrip(".").lower(), "Partida"), "mtime": mt, "used": mt > 0})
        return out
    pat = expand((p.get("saves") or {}).get("glob", ""))
    out = []
    if not pat:
        return out
    for d in sorted(glob.glob(pat)):
        if not os.path.isdir(d):
            continue
        newest = 0.0
        for root, _, files in os.walk(d):
            for fn in files:
                try:
                    newest = max(newest, os.path.getmtime(os.path.join(root, fn)))
                except OSError:
                    pass
        m = re.search(r"(\d+)$", os.path.basename(d))
        n = int(m.group(1)) + 1 if m else len(out) + 1
        out.append({"name": (p["saves"].get("name") or "Ranura {n}").format(n=n), "mtime": newest, "used": newest > 0})
    return out


def ini_values(p):
    a = p.get("ajustes") or {}
    path = expand(a.get("file", ""))
    vals = {}
    try:
        with open(path) as f:
            for line in f:
                if "=" in line:
                    k, v = line.strip().split("=", 1)
                    vals[k.strip()] = v.strip()
    except Exception:
        return []
    return [{"k": k, "v": vals[k]} for k in a.get("keys", []) if k in vals]


def art_files(slug, kind):
    d = os.path.join(ART, slug, kind)
    try:
        fs = [f for f in os.listdir(d) if re.match(r"\d+\.", f)]
    except OSError:
        return []
    return sorted(fs, key=lambda f: int(f.split(".")[0]))


_artc = {}


def art_pick_stable(g, kind):
    """Juegos con arte "lite" (importaciones masivas): la ruta se refresca como mucho cada 120 s, para que la descarga
    en segundo plano no cambie la biblioteca cada pocos segundos (la estantería se reconstruiría entera cada vez)."""
    if not (g.get("art") or {}).get("lite"):
        return art_pick(g, kind)
    key = (g["id"], kind)
    now = time.time()
    c = _artc.get(key)
    if c and now - c[0] < 120:
        return c[1]
    v = art_pick(g, kind)
    _artc[key] = (now, v)
    return v


def art_pick(g, kind):
    a = g.get("art") or {}
    slug = a.get("slug")
    if not slug:
        return ""
    fs = art_files(slug, kind)
    if not fs:
        return ""
    with lock:
        over = (state["art"].get(g["id"]) or {}).get(kind)
    idx = over if over is not None else max(0, int(a.get(kind, 1)) - 1)
    idx = min(idx, len(fs) - 1)
    return "file://" + os.path.join(ART, slug, kind, fs[idx])


def port_installed(p):
    chk = expand(p.get("check")) or (expand(p["launch"][0]) if p.get("launch") else "")
    return bool(p.get("launch")) and bool(chk) and os.path.exists(chk)


def fmt_bytes(n):
    return ("%.1f GB" % (n / 1e9)).replace(".", ",") if n >= 1e9 else ("%.0f MB" % (n / 1e6))


def port_view(p):
    pid = p["id"]
    slots = save_slots(p)
    newest_save = max([x["mtime"] for x in slots] or [0])
    with lock:
        lp = max(state["last_played"].get(pid, 0), newest_save)
        sess = dict(state["sessions"].get(pid, {}))
        last_backup = state["backups"].get(pid, 0)
        run = pid in running
        disk = disk_cache.get(pid)
    return {
        "id": pid, "name": p["name"], "s": p.get("s", ""), "chips": p.get("chips", []),
        "installed": port_installed(p), "canLaunch": port_installed(p), "running": run,
        "lastPlayed": lp, "lastSessionSecs": sess.get("last_secs", 0), "totalSecs": sess.get("total_secs", 0),
        "saves": slots, "canBackup": bool(slots), "lastBackup": last_backup,
        "disk": fmt_bytes(disk) if disk else "", "ajustes": ini_values(p),
    }


def game_toggle(key, gid):
    with lock:
        l = list(state.get(key) or [])
        if gid in l:
            l.remove(gid)
        else:
            l.append(gid)
        state[key] = l
    save_state()
    return {"ok": True, "on": gid in l}


def game_view(g):
    ports = [port_view(p) for p in g.get("ports", [])]
    inst = [p for p in ports if p["installed"]]
    best = max(inst, key=lambda p: p["lastPlayed"]) if inst else None
    return {
        "id": g["id"], "name": g["name"], "sub": g.get("sub", ""), "src": g.get("src", ""), "added": g.get("added", 0), "platform": g["platform"], "year": g.get("year", 0),
        "s": g.get("s", ""), "font": g.get("font", "Marcellus SC"), "pal": g.get("pal", []), "acc": g.get("acc", "#e6d9a0"),
        "chips": g.get("chips", []), "ports": inst, "portCount": len(inst),
        "lastPort": inst.index(best) if best else 0,
        "lastPlayed": best["lastPlayed"] if best else 0,
        "running": any(p["running"] for p in inst),
        "portada": art_pick_stable(g, "portada"), "fondo": art_pick_stable(g, "fondo"), "logo": art_pick_stable(g, "logo"),
        "artLoading": (g.get("art") or {}).get("slug") in art_busy and not (g.get("art") or {}).get("lite"),
        "installed": bool(inst),
        "fav": g["id"] in (state.get("game_fav") or []), "hidden": g["id"] in (state.get("game_hidden") or []),
    }


def library_view():
    games = [v for v in (game_view(g) for g in library()) if v["installed"]]
    games.sort(key=lambda v: -v["lastPlayed"])
    return games


def all_ports():
    for g in library():
        for p in g.get("ports", []):
            yield g, p


def find_port(gid, pid):
    g = find_game(gid)
    if not g:
        return None, None
    for p in g.get("ports", []):
        if p["id"] == pid or (not pid and p is g["ports"][0]):
            return g, p
    return g, None


# ---------------------------------------------------------------- entorno gráfico
# Si Xwayland se reinicia, cambia el archivo de autorización (XAUTHORITY). El ayudante vive más que la sesión gráfica, así que
# lo que lanza (Steam, juegos de Wine/Proton...) fallaría con "Unable to open a connection to X". Se refresca desde el
# entorno del gestor de usuario de systemd (que KWin mantiene al día) y, si falta, desde la línea de Xwayland.
_DISPLAY_KEYS = ("DISPLAY", "XAUTHORITY", "WAYLAND_DISPLAY")
_denv = {"t": 0.0}


def _display_env_actual():
    out = {}
    try:
        r = subprocess.run(["systemctl", "--user", "show-environment"], capture_output=True, text=True, timeout=4)
        for ln in r.stdout.splitlines():
            k, _, v = ln.partition("=")
            if k in _DISPLAY_KEYS and v:
                out[k] = v
    except Exception:
        pass
    if "XAUTHORITY" not in out:
        try:
            for d in os.listdir("/proc"):
                if not d.isdigit():
                    continue
                try:
                    with open("/proc/%s/cmdline" % d, "rb") as f:
                        a = f.read().split(b"\0")
                except OSError:
                    continue
                if a and os.path.basename(a[0].decode("utf-8", "ignore")) == "Xwayland" and b"-auth" in a:
                    out["XAUTHORITY"] = a[a.index(b"-auth") + 1].decode("utf-8", "ignore")
                    if a[1:2] and a[1].startswith(b":"):
                        out.setdefault("DISPLAY", a[1].decode())
                    break
        except Exception:
            pass
    return out


def refresh_display_env(force=False):
    """Actualiza os.environ (lo heredan todos los procesos que lanza el ayudante). Máx. una consulta por segundo."""
    now = time.time()
    if not force and now - _denv["t"] < 1.0:
        return
    _denv["t"] = now
    cur = _display_env_actual()
    cambios = [(k, os.environ.get(k), v) for k, v in cur.items() if os.environ.get(k) != v]
    for k, _old, v in cambios:
        os.environ[k] = v
    if cambios:
        log("entorno gráfico actualizado:", ", ".join("%s=%s" % (k, v) for k, _o, v in cambios))


def display_env_worker():
    while True:
        try:
            refresh_display_env(force=True)
        except Exception as e:
            log("entorno gráfico:", e)
        time.sleep(3)


# ---------------------------------------------------------------- acciones
def do_launch(gid, pid):
    g, p = find_port(gid, pid)
    if not p or not port_installed(p):
        return {"ok": False, "error": "Este port aún no está instalado."}
    cmd = [expand(c) for c in p["launch"]]
    refresh_display_env()
    try:
        subprocess.Popen(cmd, cwd=expand(p.get("cwd")) or None, start_new_session=True,
                         stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    except Exception as e:
        return {"ok": False, "error": str(e)}
    with lock:
        state["last_played"][p["id"]] = time.time()
    save_state()
    log("lanzado", gid, p["id"])
    return {"ok": True}


def do_backup(gid, pid):
    g, p = find_port(gid, pid)
    if not p:
        return {"ok": False}
    if (p.get("saves") or {}).get("files"):
        files = save_files(p)
        if not files:
            return {"ok": False, "error": "No hay partidas."}
        dest = expand(p.get("backup_dir")) or os.path.join(HOME, "Respaldo-Sistema", "partidas")
        os.makedirs(dest, exist_ok=True)
        out = os.path.join(dest, "%s-%s.tar.gz" % (p["id"], time.strftime("%Y%m%d-%H%M%S")))
        with tarfile.open(out, "w:gz") as tf:
            for f in files:
                tf.add(f, arcname=p["id"] + "/" + os.path.basename(f))
        with lock:
            state["backups"][p["id"]] = time.time()
        save_state()
        log("respaldo", out)
        return {"ok": True, "file": out}
    pat = expand((p.get("saves") or {}).get("glob", ""))
    slots = [d for d in sorted(glob.glob(pat)) if os.path.isdir(d)]
    if not slots:
        return {"ok": False, "error": "No hay partidas."}
    dest = expand(p.get("backup_dir")) or os.path.join(HOME, "Respaldo-Sistema", "partidas")
    os.makedirs(dest, exist_ok=True)
    out = os.path.join(dest, "%s-%s.tar.gz" % (p["id"], time.strftime("%Y%m%d-%H%M%S")))
    parent = os.path.dirname(slots[0])
    with tarfile.open(out, "w:gz") as tf:
        tf.add(parent, arcname=os.path.basename(os.path.dirname(parent)) + "/" + os.path.basename(parent))
    with lock:
        state["backups"][p["id"]] = time.time()
    save_state()
    log("respaldo", out)
    return {"ok": True, "file": out}


def do_open_saves(gid, pid):
    g, p = find_port(gid, pid)
    if not p:
        return {"ok": False}
    if (p.get("saves") or {}).get("files"):
        fl = save_files(p)
        folder = os.path.dirname(fl[0]) if fl else os.path.dirname(expand((p["saves"]["files"][0])))
        slots = None
    else:
        slots = [d for d in sorted(glob.glob(expand((p.get("saves") or {}).get("glob", "")))) if os.path.isdir(d)]
        folder = os.path.dirname(slots[0]) if slots else expand(p.get("disk_dir") or HOME)
    subprocess.Popen(["xdg-open", folder], start_new_session=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    return {"ok": True}


def do_art_cycle(gid, kind, d):
    g = find_game(gid)
    if not g or kind not in ("portada", "fondo", "logo"):
        return {"ok": False}
    slug = (g.get("art") or {}).get("slug")
    fs = art_files(slug, kind) if slug else []
    if not fs:
        return {"ok": False, "error": "Sin opciones de arte."}
    with lock:
        cur = (state["art"].setdefault(gid, {})).get(kind)
        if cur is None:
            cur = max(0, int((g.get("art") or {}).get(kind, 1)) - 1)
        state["art"][gid][kind] = (cur + d) % len(fs)
    save_state()
    return {"ok": True}


# ---------------------------------------------------------------- selección manual de arte (SteamGridDB)
ART_RUTAS = {
    "portada": "/grids/game/%d?dimensions=600x900,342x482,660x930&types=static&nsfw=false&humor=false",
    "fondo": "/heroes/game/%d?types=static&nsfw=false&humor=false",
    "logo": "/logos/game/%d?types=static&nsfw=false&humor=false",
}
_sgcand = {}


def sg_candidates(name):
    c = _sgcand.get(name.lower())
    if c and time.time() - c[0] < 600:
        return c[1]
    res = sgdb_get("/search/autocomplete/" + urllib.parse.quote(name), sgdb_key()).get("data", [])[:8]
    out = []
    for x in res:
        try:
            yy = time.gmtime(x["release_date"]).tm_year
        except Exception:
            yy = 0
        out.append({"id": x["id"], "name": x["name"], "year": yy})
    _sgcand[name.lower()] = (time.time(), out)
    return out


def do_art_browse(gid, kind, page, sgid, q):
    g = find_game(gid)
    if not g or kind not in ART_RUTAS or not sgdb_key():
        return {"ok": False, "error": "Sin clave de SteamGridDB o juego desconocido."}
    a = g.get("art") or {}
    try:
        cands = sg_candidates(q or a.get("sgdb") or g["name"])
        if not sgid:
            with lock:
                sgid = (state.get("art_sg") or {}).get(gid)
            if not sgid and cands:
                sgid = cands[0]["id"]
                for x in cands:
                    if a.get("year") and x["year"] == a["year"] and x["name"].lower().startswith((a.get("sgdb") or g["name"]).lower()[:18]):
                        sgid = x["id"]
                        break
        if not sgid:
            return {"ok": True, "sgid": 0, "games": cands, "items": [], "page": page, "more": False}
        d = sgdb_get(ART_RUTAS[kind] % int(sgid) + "&page=%d" % page, sgdb_key())
        with lock:
            src = ((state.get("art_src") or {}).get(gid) or {}).get(kind) or {}
            cur_idx = (state["art"].get(gid) or {}).get(kind)
        usada = src.get("url") if (src and src.get("idx") == cur_idx) else ""
        items = [{"url": it["url"], "thumb": it.get("thumb") or it["url"], "w": it.get("width", 0), "h": it.get("height", 0),
                  "style": it.get("style", ""), "by": (it.get("author") or {}).get("name", ""),
                  "cur": bool(usada) and it["url"] == usada} for it in d.get("data", [])]
        if page == 0:                       # la imagen en uso va de primera
            items.sort(key=lambda x: not x["cur"])
        return {"ok": True, "sgid": int(sgid), "games": cands, "items": items, "page": page,
                "more": (page + 1) * d.get("limit", 50) < d.get("total", 0)}
    except Exception as e:
        log("arte: explorar error", e)
        return {"ok": False, "error": str(e)}


def do_art_pick(gid, kind, url, sgid):
    g = find_game(gid)
    host = urllib.parse.urlparse(url).hostname or ""
    if not g or kind not in ART_RUTAS or not host.endswith("steamgriddb.com"):
        return {"ok": False, "error": "Petición no válida."}
    slug = (g.get("art") or {}).get("slug")
    if not slug:
        return {"ok": False, "error": "El juego no tiene carpeta de arte."}
    fs = art_files(slug, kind)
    n = (int(fs[-1].split(".")[0]) + 1) if fs else 1
    ext = os.path.splitext(urllib.parse.urlparse(url).path)[1] or ".png"
    os.makedirs(os.path.join(ART, slug, kind), exist_ok=True)
    try:
        sgdb_download(url, os.path.join(ART, slug, kind, "%d%s" % (n, ext)))
    except Exception as e:
        return {"ok": False, "error": str(e)}
    with lock:
        state["art"].setdefault(gid, {})[kind] = len(art_files(slug, kind)) - 1
        state.setdefault("art_src", {}).setdefault(gid, {})[kind] = {"url": url, "idx": len(art_files(slug, kind)) - 1}
        if sgid:
            state.setdefault("art_sg", {})[gid] = int(sgid)
    save_state()
    _artc.pop((gid, kind), None)
    return {"ok": True}


# ---------------------------------------------------------------- SteamGridDB
def sgdb_key():
    try:
        return open(KEY_FILE).read().strip()
    except Exception:
        return ""


def sgdb_get(path, key):
    req = urllib.request.Request(SGDB + path, headers={"Authorization": "Bearer " + key, "User-Agent": UA})
    with urllib.request.urlopen(req, timeout=30) as r:
        return json.load(r)


def sgdb_download(url, dest):
    req = urllib.request.Request(url, headers={"User-Agent": UA})
    with urllib.request.urlopen(req, timeout=60) as r, open(dest, "wb") as f:
        f.write(r.read())


def fetch_art(g):
    """Consulta SteamGridDB y deja hasta N opciones por tipo en ~/.local/share/estanteria/arte/<slug>/"""
    a = g.get("art") or {}
    slug, name = a.get("slug"), a.get("sgdb")
    key = sgdb_key()
    if not (slug and name and key) or slug in art_busy:
        return
    art_busy.add(slug)
    try:
        log("arte: buscando", name)
        res = sgdb_get("/search/autocomplete/" + urllib.parse.quote(name), key).get("data", [])
        if not res:
            log("arte: sin resultados para", name)
            return
        year = (g.get("art") or {}).get("year")
        pick = res[0]
        if year:
            for x in res:
                try:
                    yy = time.gmtime(x["release_date"]).tm_year
                except Exception:
                    yy = None
                if yy == year and x["name"].lower().startswith(name.lower()[:18]):
                    pick = x
                    break
        gid = pick["id"]
        log("arte: entrada", gid, pick["name"], year or "")
        rutas = {
            "portada": "/grids/game/%d?dimensions=600x900&types=static&nsfw=false&humor=false" % gid,
            "fondo": "/heroes/game/%d?types=static&nsfw=false&humor=false" % gid,
            "logo": "/logos/game/%d?types=static&nsfw=false&humor=false" % gid,
        }
        lite = bool((g.get("art") or {}).get("lite"))
        for kind, ruta in rutas.items():
            os.makedirs(os.path.join(ART, slug, kind), exist_ok=True)
            try:
                items = sgdb_get(ruta, key).get("data", [])[:(({"portada": 2, "fondo": 1, "logo": 1}).get(kind, 1) if lite else N_OPCIONES[kind])]
            except Exception as e:
                log("arte:", kind, "error", e)
                continue
            for i, it in enumerate(items, 1):
                ext = os.path.splitext(urllib.parse.urlparse(it["url"]).path)[1] or ".png"
                try:
                    sgdb_download(it["url"], os.path.join(ART, slug, kind, "%d%s" % (i, ext)))
                except Exception as e:
                    log("arte: descarga", kind, i, "error", e)
        if lite and not art_files(slug, "logo"):
            try: open(os.path.join(ART, slug, ".sin-logo"), "w").close()
            except Exception: pass
        log("arte: listo", name)
    except Exception as e:
        log("arte: error", name, e)
    finally:
        art_busy.discard(slug)


def art_worker():
    """Al arrancar: completa el arte que falte de los juegos de la biblioteca."""
    time.sleep(3)
    try:
        os.setpriority(os.PRIO_PROCESS, threading.get_native_id(), 12)      # prioridad baja para este hilo
    except Exception:
        pass
    visto = set()
    for g in library():
        a = g.get("art") or {}
        slug = a.get("slug")
        if slug and slug not in visto and (not art_files(slug, "portada") or (a.get("lite") and not art_files(slug, "logo") and not os.path.exists(os.path.join(ART, slug, ".sin-logo")))):
            visto.add(slug)
            fetch_art(g)
            if a.get("lite"):
                time.sleep(2.0)       # importaciones masivas: sin prisa, para no saturar SteamGridDB ni el equipo



# ---------------------------------------------------------------- GeForce NOW: solo los juegos con acceso directo en el escritorio
def _slug(t):
    import unicodedata
    t = unicodedata.normalize("NFKD", t).encode("ascii", "ignore").decode().lower()
    return re.sub(r"[^a-z0-9]+", "-", t).strip("-") or "juego"


def _read_desktop(path):
    d = {}
    try:
        for ln in open(path, encoding="utf-8", errors="ignore"):
            if ln.startswith("[") and ln.strip() != "[Desktop Entry]":
                break
            if "=" in ln and not ln.startswith("#"):
                k, v = ln.split("=", 1)
                d.setdefault(k.strip(), v.strip())
    except OSError:
        pass
    return d


def gfn_sync():
    """Los juegos de GeForce NOW de la estantería = accesos directos .desktop del escritorio que lanzan GeForce NOW.
    Se añaden los nuevos y se quitan los que ya no existen. El lanzador general de GeForce NOW (id 'gfn') no se muestra."""
    desk = os.path.join(HOME, "Escritorio")
    want = {}
    for f in sorted(glob.glob(os.path.join(desk, "*.desktop"))):
        d = _read_desktop(f)
        if "geforcenow" not in (d.get("Exec", "") + d.get("Name", "")).lower().replace(" ", ""):
            continue
        name = re.sub(r"\s*[\(\[]?\s*(en\s+)?(nvidia\s+)?(geforce\s*now|gfn)\s*[\)\]]?\s*$", "", d.get("Name", os.path.basename(f)[:-8]), flags=re.I).strip()
        if not name or name.lower() in ("geforce now", "nvidia geforce now"):
            continue                       # el acceso al launcher en sí no es un juego
        want["gfn-" + _slug(name)] = (name, f)
    lib = load_json(LIB_FILE, {"games": []})
    games = lib.get("games", [])
    cur = {g["id"]: g for g in games}
    changed = False
    keep = []
    for g in games:
        if g["id"] == "gfn" or (g["id"].startswith("gfn-") and g["id"] not in want):
            changed = True
            continue
        keep.append(g)
    new = []
    for gid, (name, f) in want.items():
        if gid in cur:
            c0 = cur[gid]
            if c0.get("platform") != "pc" or c0.get("src") != "GeForce NOW":
                c0["platform"] = "pc"; c0["src"] = "GeForce NOW"; c0["sub"] = "PC · GeForce NOW"; changed = True
            for p in cur[gid].get("ports", []):
                if p.get("launch") != ["gio", "launch", f]:
                    p["launch"] = ["gio", "launch", f]; p["check"] = f; changed = True
            continue
        g = {"id": gid, "name": name, "sub": "PC · GeForce NOW", "platform": "pc", "src": "GeForce NOW", "year": 0, "added": int(time.time()),
             "s": "En la nube con GeForce NOW", "font": "Rajdhani",
             "pal": ["#10200a", "#3d6b1d", "#2c4f14", "#0c1707", "#b6e36a"], "acc": "#b6e36a",
             "art": {"slug": gid, "sgdb": name, "year": None, "portada": 1, "fondo": 1, "lite": True},
             "ports": [{"id": gid + "-gfn", "name": "GeForce NOW", "s": "Juego en la nube", "chips": ["Nube"],
                        "launch": ["gio", "launch", f], "check": f, "proc": "geforcenow"}]}
        keep.append(g); new.append(g); changed = True
    if changed:
        lib["games"] = keep
        _write_atomic(LIB_FILE, lib)
        log("gfn: biblioteca sincronizada,", len(want), "juegos; nuevos:", [g["name"] for g in new])
        for g in new:
            threading.Thread(target=fetch_art, args=(g,), daemon=True).start()


def gfn_worker():
    time.sleep(2)
    while True:
        try:
            gfn_sync()
        except Exception as e:
            log("gfn sync:", e)
        time.sleep(15)


def pc_worker():
    """Detecta solos los juegos de ~/Juegos/PC (Steam por appmanifest, carpetas con .exe) cada 60 s."""
    time.sleep(8)
    script = os.path.join(os.path.dirname(os.path.abspath(__file__)), "importar-pc.py")
    while True:
        try:
            r = subprocess.run([sys.executable, script, "--aplicar", "--silencioso"], capture_output=True, text=True, timeout=120)
            if r.stdout.strip():
                log("pc:", r.stdout.strip().replace("\n", " | ")[:300])
                for g in library():
                    if g.get("auto") == "pc" and not art_files((g.get("art") or {}).get("slug", ""), "portada"):
                        threading.Thread(target=fetch_art, args=(g,), daemon=True).start()
            if r.stderr.strip():
                log("pc error:", r.stderr.strip()[-200:])
        except Exception as e:
            log("pc worker:", e)
        time.sleep(60)


# ---------------------------------------------------------------- salida de audio (para el modo mando)
def _pactl(*a):
    env = dict(os.environ, LC_ALL="C")
    return subprocess.run(["pactl"] + list(a), capture_output=True, text=True, timeout=8, env=env).stdout


def audio_outputs():
    """Dispositivos de salida: una entrada por sink (y por puerto disponible si el sink tiene varios)."""
    try:
        default = _pactl("get-default-sink").strip()
        sinks = json.loads(_pactl("-f", "json", "list", "sinks"))
    except Exception as e:
        log("audio_outputs:", e)
        return {"ok": False, "items": []}
    items = []
    for sk in sinks:
        d = (sk.get("properties") or {}).get("device.description") or sk.get("description") or sk["name"]
        ports = [p for p in sk.get("ports", []) if p.get("availability") != "not available"]
        multi = len(ports) > 1
        shown = ports if (multi or (ports and ports[0].get("description") not in (None, "", "(null)"))) else [None]
        for p in shown:
            lab = d
            if p and p.get("description") not in (None, "", "(null)"):
                lab = d + " · " + p["description"]
            cur = sk["name"] == default and (not p or not multi or sk.get("active_port") == p["name"])
            items.append({"sink": sk["name"], "port": p["name"] if p and multi else "", "label": lab, "current": cur,
                          "kind": "hdmi" if "hdmi" in sk["name"] else ("usb" if "usb" in sk["name"] else ("bt" if "bluez" in sk["name"] else "analog"))})
    return {"ok": True, "items": items}


def audio_set(sink, port=""):
    try:
        _pactl("set-default-sink", sink)
        if port:
            _pactl("set-sink-port", sink, port)
        for ln in _pactl("list", "short", "sink-inputs").splitlines():      # lo que ya suena pasa al nuevo dispositivo
            if ln.strip():
                _pactl("move-sink-input", ln.split()[0], sink)
        log("audio: salida ->", sink, port)
        return {"ok": True}
    except Exception as e:
        return {"ok": False, "error": str(e)}


def library_refresh():
    """Botón «actualizar»: vuelve a detectar a mano los juegos de PC (Steam, Hydra, ...) y los accesos de GeForce NOW."""
    script = os.path.join(os.path.dirname(os.path.abspath(__file__)), "importar-pc.py")
    new = gone = 0
    try:
        r = subprocess.run([sys.executable, script, "--aplicar"], capture_output=True, text=True, timeout=90)
        m = re.search(r"nuevos: (\d+) \| a quitar: (\d+)", r.stdout)
        if m:
            new, gone = int(m.group(1)), int(m.group(2))
        if r.stderr.strip():
            log("refresh error:", r.stderr.strip()[-200:])
        for g in library():
            if g.get("auto") == "pc" and not art_files((g.get("art") or {}).get("slug", ""), "portada"):
                threading.Thread(target=fetch_art, args=(g,), daemon=True).start()
    except Exception as e:
        return {"ok": False, "error": str(e)}
    try:
        before = {g["id"] for g in library()}
        gfn_sync()
        after = {g["id"] for g in library()}
        new += len(after - before)
        gone += len(before - after)
    except Exception as e:
        log("refresh gfn:", e)
    log("refresh: +%d -%d" % (new, gone))
    return {"ok": True, "new": new, "gone": gone}

# ---------------------------------------------------------------- vigilancia de procesos
def scan_procs():
    cmds = []
    for p in os.listdir("/proc"):
        if p.isdigit():
            try:
                with open("/proc/%s/cmdline" % p, "rb") as f:
                    cmds.append(f.read().replace(b"\0", b" ").decode("utf-8", "ignore"))
            except OSError:
                pass
    return cmds



# ---------------------------------------------------------------- modo juego
# Al lanzar un juego: congela (SIGSTOP) apps en segundo plano, apaga el efecto Glass y sube el perfil de energía.
# Al cerrarse el último juego todo vuelve a como estaba. Discord NO se toca (voz/mensajes). Los juegos de GeForce NOW (nube) no lo activan.
# Desactivar: config.json {"game_mode": false}; excluir un juego: "game_mode": false en su entrada de library.json.
GM_FILE = os.path.join(HOME, ".cache", "estanteria", "gamemode.json")
GM_PROFILE = "/sys/firmware/acpi/platform_profile"
GM_FREEZE = ("motrix", "aria2c", "qbittorrent")          # siempre
GM_FREEZE_STEAM = ("steam", "steamwebhelper")            # salvo si el juego es de Steam
_gm = {"on": False, "games": set(), "frozen": [], "profile": None, "glass": False}
_gm_lock = threading.RLock()


def _comm(pid):
    try:
        with open("/proc/%d/comm" % pid) as f:
            return f.read().strip()
    except OSError:
        return ""


def _gm_save():
    try:
        os.makedirs(os.path.dirname(GM_FILE), exist_ok=True)
        if _gm["on"]:
            _write_atomic(GM_FILE, {"frozen": _gm["frozen"], "profile": _gm["profile"], "glass": _gm["glass"]})
        elif os.path.exists(GM_FILE):
            os.remove(GM_FILE)
    except Exception as e:
        log("gamemode save:", e)


def _gm_glass(load):
    try:
        m = "loadEffect" if load else "unloadEffect"
        subprocess.run(["gdbus", "call", "--session", "--dest", "org.kde.KWin", "--object-path", "/Effects",
                        "--method", "org.kde.kwin.Effects." + m, "glass"], capture_output=True, timeout=6)
    except Exception as e:
        log("gamemode glass:", e)


def _gm_restore(frozen, profile, glass):
    for pid, comm in frozen:
        if _comm(pid) == comm:
            try: os.kill(pid, 18)          # SIGCONT
            except OSError: pass
    if profile:
        try:
            with open(GM_PROFILE) as f: cur = f.read().strip()
            if cur == "performance":
                with open(GM_PROFILE, "w") as f: f.write(profile)
        except OSError as e:
            log("gamemode perfil:", e)
    if glass:
        _gm_glass(True)


def game_mode_start(g, p):
    cfg = load_json(os.path.join(CFG, "config.json"), {})
    if cfg.get("game_mode") is False or g.get("game_mode") is False:
        return
    if g.get("src") == "GeForce NOW" or "geforcenow" in (p.get("proc") or ""):
        return                                                  # nube: la app queda abierta siempre
    with _gm_lock:
        _gm["games"].add(p["id"])
        if _gm["on"]:
            return
        _gm["on"] = True
        steam_game = g.get("src") == "Steam" or "steam" in json.dumps(p.get("launch", "")).lower()
        names = GM_FREEZE if steam_game else GM_FREEZE + GM_FREEZE_STEAM
        me = os.getuid(); frozen = []
        for d in os.listdir("/proc"):
            if not d.isdigit(): continue
            pid = int(d)
            comm = _comm(pid)
            if comm in names:
                try:
                    if os.stat("/proc/%d" % pid).st_uid != me: continue
                    os.kill(pid, 19)       # SIGSTOP
                    frozen.append([pid, comm])
                except OSError:
                    pass
        _gm["frozen"] = frozen
        try:
            with open(GM_PROFILE) as f: prev = f.read().strip()
            if prev != "performance":
                with open(GM_PROFILE, "w") as f: f.write("performance")
                _gm["profile"] = prev
        except OSError as e:
            log("gamemode perfil:", e)
        _gm_glass(False); _gm["glass"] = True
        _gm_save()
        log("modo juego ON:", g.get("name"), "| congelados:", sorted(set(c for _, c in frozen)), "| perfil previo:", _gm["profile"])


def game_mode_end(pid):
    with _gm_lock:
        _gm["games"].discard(pid)
        if not _gm["on"] or _gm["games"]:
            return
        fr, pr, gl = _gm["frozen"], _gm["profile"], _gm["glass"]
        _gm.update({"on": False, "frozen": [], "profile": None, "glass": False})
        _gm_restore(fr, pr, gl)
        _gm_save()
        log("modo juego OFF")


def game_mode_recover():
    """Si el ayudante se reinició con el modo juego activo: devuelve todo a su estado normal (el monitor lo reactivará si el juego sigue)."""
    try:
        d = load_json(GM_FILE, None)
        if d:
            _gm_restore([tuple(x) for x in d.get("frozen", [])], d.get("profile"), d.get("glass"))
            os.remove(GM_FILE)
            log("modo juego: recuperado tras reinicio")
    except Exception as e:
        log("gamemode recover:", e)


def game_mode_status():
    with _gm_lock:
        return {"on": _gm["on"], "games": sorted(_gm["games"]), "frozen": sorted(set(c for _, c in _gm["frozen"])), "profile_prev": _gm["profile"], "glass_off": _gm["glass"]}


def monitor_worker():
    while True:
        try:
            cmds = scan_procs()
            now = time.time()
            for g, p in all_ports():
                pat = p.get("proc")
                if not pat:
                    continue
                pid = p["id"]
                alive = any(pat in c for c in cmds)
                with lock:
                    was = pid in running
                    if alive and not was:
                        running[pid] = now
                        state["last_played"][pid] = now
                        log("en ejecución:", pid)
                        threading.Thread(target=emit, args=("GAMESTART",), daemon=True).start()
                        threading.Thread(target=game_mode_start, args=(g, p), daemon=True).start()
                    elif was and not alive:
                        start = running.pop(pid)
                        secs = int(now - start)
                        if secs > 20:
                            ss = state["sessions"].setdefault(pid, {})
                            ss["last_secs"] = secs
                            ss["total_secs"] = ss.get("total_secs", 0) + secs
                        log("terminó:", pid, secs, "s")
                        threading.Thread(target=emit, args=("GAMEEND",), daemon=True).start()
                        threading.Thread(target=game_mode_end, args=(pid,), daemon=True).start()
                        threading.Thread(target=save_state, daemon=True).start()
        except Exception as e:
            log("monitor error", e)
        time.sleep(1.5)


def disk_worker():
    while True:
        for g, p in all_ports():
            d = expand(p.get("disk_dir"))
            if d and os.path.isdir(d):
                try:
                    out = subprocess.run(["du", "-sb", d], capture_output=True, text=True, timeout=300).stdout.split()
                    with lock:
                        disk_cache[p["id"]] = int(out[0])
                except Exception:
                    pass
        time.sleep(6 * 3600)


# ---------------------------------------------------------------- mando
def default_bindings():
    """Asignación por defecto (mando Xbox estándar). Se puede sobrescribir en ~/.config/estanteria/config.json -> "bindings"."""
    b = {}
    for n, k in {"0": "A", "1": "B", "2": "X", "3": "Y", "4": "LB", "5": "RB"}.items():
        b["b:" + n] = k
    for n, k in {"11": "l", "12": "r", "13": "u", "14": "d"}.items():
        b["b:" + n] = k
    b.update({"a:6:-": "l", "a:6:+": "r", "a:7:-": "u", "a:7:+": "d",
              "a:0:-": "l", "a:0:+": "r", "a:1:-": "u", "a:1:+": "d",
              "a:2:+": "LT", "a:5:+": "RT"})
    b["b:7"] = "MENU"
    return b


DIRS = ("l", "r", "u", "d")


def find_js():
    for p in sorted(glob.glob("/sys/class/input/js*")):
        try:
            name = open(p + "/device/name").read().strip()
        except OSError:
            name = ""
        return "/dev/input/" + os.path.basename(p), name
    return None, ""


_lk = {"t": 0.0, "v": False}


def is_locked():
    """True mientras kscreenlocker_greet muestra la pantalla de bloqueo (consulta cacheada 1 s)."""
    now = time.time()
    if now - _lk["t"] > 1.0:
        _lk["t"] = now
        try:
            _lk["v"] = subprocess.run(["pgrep", "-x", "kscreenlocker_greet"], capture_output=True, timeout=2).returncode == 0
        except Exception:
            _lk["v"] = False
    return _lk["v"]


LOCK_DIR = os.path.join(HOME, ".cache", "estanteria")


def _write_atomic(path, obj):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    tmp = path + ".tmp"
    with open(tmp, "w") as f:
        json.dump(obj, f)
    os.replace(tmp, path)


def pad_push(k, force=False):
    with pad["cv"]:
        if not force and not pad["enabled"]:       # con un juego abierto pero minimizado (escritorio a la vista) el mando sigue activo
            return
        pad["seq"] += 1
        pad["events"].append({"seq": pad["seq"], "k": k, "t": time.time()})
        pad["events"] = pad["events"][-60:]
        pad["cv"].notify_all()
        if k.startswith("LK:"):
            # La pantalla de bloqueo (kscreenlocker_greet) no tiene red: lee este archivo.
            try:
                _write_atomic(os.path.join(LOCK_DIR, "lock-events.json"),
                              {"seq": pad["seq"], "events": pad["events"][-20:]})
            except Exception as e:
                log("lock-events:", e)


def lock_state_worker():
    """Datos del último juego para la pantalla de bloqueo (archivo, sin red): id, nombre, paleta y arte de fondo.
    Se refresca cada 60 s y justo al bloquearse (kscreenlocker_greet aparece)."""
    last_lock = False
    t_write = 0.0
    while True:
        try:
            lk = is_locked()
            if (lk and not last_lock) or time.time() - t_write > 60:
                g = library_view()
                if g:
                    best = g[0]
                    _write_atomic(os.path.join(LOCK_DIR, "lock-state.json"),
                                  {"id": best["id"], "name": best["name"], "pal": best.get("pal", []),
                                   "fondo": best.get("fondo", ""), "t": time.time()})
                    t_write = time.time()
            last_lock = lk
        except Exception as e:
            log("lock-state:", e)
        time.sleep(1)


def pad_route(k):
    """MENU (botón Start) abre el Big Menu aunque haya otras ventanas, pero nunca mientras corre un juego."""
    if is_locked():
        pad_push("LK:" + k, force=True)      # pantalla de bloqueo propia: recibe los botones en bruto
        return
    if k in ("MENU", "POWER", "CTX"):
        if not running or pad["enabled"]:          # con un juego a la vista no; con el juego minimizado sí (Big Menú)
            emit("PADSTART" if k == "MENU" else k)
    else:
        pad_push(k)


def pad_worker():
    cfg = load_json(os.path.join(CFG, "config.json"), {})
    if cfg.get("bindings"):
        # con calibración se usa solo ese mapa (más el stick izquierdo, que es estándar)
        bind = {"a:0:-": "l", "a:0:+": "r", "a:1:-": "u", "a:1:+": "d"}
        bind.update(cfg["bindings"])
        bind.setdefault("b:11", "MENU")   # Start en este mando (si no, calibrar)
        bind.setdefault("b:10", "CTX")    # Back/Select: menú contextual del juego
    else:
        bind = default_bindings()
    THR = 17000
    while True:
        dev, name = find_js()
        if not dev:
            pad["connected"] = False
            time.sleep(2)
            continue
        try:
            fd = os.open(dev, os.O_RDONLY | os.O_NONBLOCK)
        except OSError:
            time.sleep(2)
            continue
        pad["connected"], pad["name"] = True, name
        log("mando:", name, dev)
        rest = {}
        axstate = {}
        held = {}
        try:
            while True:
                try:
                    data = os.read(fd, 8 * 16)
                except BlockingIOError:
                    data = b""
                now = time.time()
                for i in range(0, len(data) - 7, 8):
                    _, val, typ, num = struct.unpack("IhBB", data[i:i + 8])
                    init = typ & 0x80
                    typ &= 0x7F
                    if typ == 2 and init:
                        # reposo del eje; la cruceta (ejes 6 y 7) siempre reposa en 0 y nunca en +máx: si el mando se abrió con una
                        # dirección pulsada, el valor inicial NO es el reposo (si no, esa dirección queda invertida/muerta)
                        rest[num] = 0 if (num in (6, 7) or val > THR) else val
                        continue
                    if init:
                        continue
                    if typ == 1:
                        key = bind.get("b:%d" % num)
                        if val:
                            log("boton", num, "->", key or "(sin asignar)")
                            if key:
                                pad_route(key)
                                if key in DIRS:
                                    held[("b", num)] = [key, now + 0.4]
                        else:
                            held.pop(("b", num), None)
                    elif typ == 2:
                        d = val - rest.get(num, 0)
                        for sign, on in (("-", d < -THR), ("+", d > THR)):
                            st = (num, sign)
                            if on and not axstate.get(st):
                                axstate[st] = True
                                key = bind.get("a:%d:%s" % (num, sign))
                                log("eje", num, sign, "->", key or "(sin asignar)")
                                if key:
                                    pad_push(key)
                                    if key in DIRS:
                                        held[("a", num, sign)] = [key, now + 0.4]
                            elif not on and axstate.get(st):
                                axstate[st] = False
                                held.pop(("a", num, sign), None)
                for h in held.values():
                    if now >= h[1]:
                        h[1] = now + 0.15
                        pad_push(h[0])
                time.sleep(0.02)
        except OSError:
            pass
        finally:
            try:
                os.close(fd)
            except OSError:
                pass
            pad["connected"] = False
            log("mando desconectado")
        time.sleep(1)


# ---------------------------------------------------------------- audio (ondas reales)
BANDS = True          # espectro de 16 bandas (apagado: las ondas usan los 4 niveles, más ligeros)
bpeak_state = [120.0]


def audio_worker():
    proc = None
    lp1 = lp2 = lp3 = 0.0
    peak = [1e-3] * 4
    while True:
        want = time.time() < audio["on_until"]
        if want and proc is None:
            try:
                proc = subprocess.Popen(["parec", "--device=@DEFAULT_MONITOR@", "--rate=8000", "--channels=1",
                                         "--format=s16le", "--latency-msec=40"],
                                        stdout=subprocess.PIPE, stderr=subprocess.DEVNULL)
                audio["ok"] = True
            except Exception as e:
                audio["ok"] = False
                log("audio:", e)
                time.sleep(5)
                continue
        if not want:
            if proc:
                proc.kill()
                proc.wait()
                proc = None
            audio["levels"] = [0.0, 0.0, 0.0, 0.0]
            audio["bands"] = [0.0] * 16
            time.sleep(0.3)
            continue
        data = proc.stdout.read(800)   # 50 ms
        if not data:
            proc.kill()
            proc = None
            time.sleep(1)
            continue
        s = array.array("h")
        s.frombytes(data[: len(data) // 2 * 2])
        e = [0.0, 0.0, 0.0, 0.0]
        for x in s:
            lp1 += 0.10 * (x - lp1)    # ~130 Hz
            lp2 += 0.45 * (x - lp2)    # ~700 Hz
            lp3 += 0.85 * (x - lp3)    # ~2.5 kHz
            e[0] += lp1 * lp1
            b2 = lp2 - lp1
            e[1] += b2 * b2
            b3 = lp3 - lp2
            e[2] += b3 * b3
            b4 = x - lp3
            e[3] += b4 * b4
        n = max(1, len(s))
        out = []
        for i in range(4):
            r = (e[i] / n) ** 0.5
            peak[i] = max(r, peak[i] * 0.995, 200.0)
            out.append(min(1.0, r / peak[i]))
        audio["levels"] = out
        # 16 bandas logarítmicas (Goertzel, 50 Hz - 3,6 kHz) para el ecualizador
        try:
            n = len(s)
            if BANDS and n >= 200:
                win = [0.5 - 0.5 * math.cos(2 * math.pi * i / (n - 1)) for i in range(n)]
                xs = [s[i] * win[i] for i in range(n)]
                bs = []
                for b in range(16):
                    f = 50.0 * (3600.0 / 50.0) ** (b / 15.0)
                    c = 2.0 * math.cos(2 * math.pi * f / 8000.0)
                    q1 = q2 = 0.0
                    for v in xs:
                        q0 = c * q1 - q2 + v
                        q2 = q1
                        q1 = q0
                    p = (q1 * q1 + q2 * q2 - c * q1 * q2) ** 0.5 / n
                    bs.append(p * (1.0 + b * 0.09))           # realce suave hacia agudos
                bpk = max(bs)
                bpeak = max(bpk, bpeak_state[0] * 0.992, 120.0)
                bpeak_state[0] = bpeak
                audio["bands"] = [round(min(1.0, (v / bpeak) ** 0.8), 3) for v in bs]
        except Exception as ex:
            log("bandas:", ex)


# ---------------------------------------------------------------- estadísticas extra
def stats():
    out = {}
    try:
        st = os.statvfs(os.path.join(HOME, "Juegos"))
        tot = st.f_blocks * st.f_frsize
        out["disk"] = {"used": tot - st.f_bavail * st.f_frsize, "total": tot}
    except Exception:
        pass
    try:
        for b in glob.glob("/sys/class/power_supply/BAT*"):
            out["bat"] = {"pct": int(open(b + "/capacity").read()), "status": open(b + "/status").read().strip()}
            break
        out["ac"] = any(open(a + "/online").read().strip() == "1" for a in glob.glob("/sys/class/power_supply/AC*") + glob.glob("/sys/class/power_supply/ADP*"))
    except Exception:
        pass
    try:
        fr = [int(open(f).read()) for f in glob.glob("/sys/devices/system/cpu/cpu[0-9]*/cpufreq/scaling_cur_freq")]
        if fr:
            out["ghz"] = round(sum(fr) / len(fr) / 1e6, 2)
    except Exception:
        pass
    return out


# ---------------------------------------------------------------- aplicaciones (Big Menu)
try:
    import gi
    gi.require_version("Gio", "2.0")
    from gi.repository import Gio, GLib
    HAVE_GIO = True
except Exception as _e:
    HAVE_GIO = False

FAV_DEF = ["org.kde.dolphin", "steam", "org.kde.konsole", "firefox", "org.kde.kate", "net.lutris.Lutris", "com.discordapp"]


def grupo_app(cats):
    c = set((cats or "").split(";"))
    if c & {"Settings", "DesktopSettings", "HardwareSettings"}:
        return "Configuración"
    if c & {"Game"}:
        return "Juegos"
    if c & {"AudioVideo", "Audio", "Video", "Player", "Recorder"}:
        return "Multimedia"
    if c & {"Development", "IDE"}:
        return "Desarrollo"
    if c & {"Network", "WebBrowser", "InstantMessaging", "Chat", "Email", "P2P", "FileTransfer"}:
        return "Internet"
    if c & {"Office", "Spreadsheet", "WordProcessor", "Presentation"}:
        return "Oficina"
    if c & {"System", "Monitor", "PackageManager", "Security"}:
        return "Sistema"
    return "Utilidades"


def icon_de(ai):
    ic = ai.get_icon()
    if ic is None:
        return "application-x-executable"
    try:
        if hasattr(ic, "get_names"):
            return ic.get_names()[0]
        if hasattr(ic, "get_file"):
            return "file://" + ic.get_file().get_path()
    except Exception:
        pass
    return "application-x-executable"


def apps_list():
    if not HAVE_GIO:
        return []
    out = []
    ids = set()
    for ai in Gio.AppInfo.get_all():
        try:
            if not ai.should_show():
                continue
            aid = ai.get_id() or ""
            if not aid or aid in ids:
                continue
            ids.add(aid)
            base = aid[:-8] if aid.endswith(".desktop") else aid
            cats = ai.get_categories() if hasattr(ai, "get_categories") else ""
            out.append({"id": aid, "name": ai.get_name(), "icon": icon_de(ai), "group": grupo_app(cats),
                        "generic": (ai.get_generic_name() or "") if hasattr(ai, "get_generic_name") else "",
                        "keywords": " ".join(ai.get_keywords() or []) if hasattr(ai, "get_keywords") else "",
                        "base": base})
        except Exception:
            continue
    with lock:
        if state.get("apps_fav") is None:
            state["apps_fav"] = [a["id"] for a in out if any(a["base"].lower().startswith(f.lower()) for f in FAV_DEF)]
            save_state()
        fav = set(state["apps_fav"])
        used = dict(state["apps_used"])
    for a in out:
        a["fav"] = a["id"] in fav
        a["used"] = used.get(a["id"], 0)
    out.sort(key=lambda a: a["name"].lower())
    return out


def app_launch(aid):
    if not HAVE_GIO:
        return {"ok": False, "error": "Sin soporte de Gio"}
    ai = Gio.DesktopAppInfo.new(aid)
    if ai is None:
        return {"ok": False, "error": "Aplicación no encontrada"}
    fn = ai.get_filename()
    refresh_display_env()
    try:
        # scope propio: la app sobrevive a reinicios del ayudante
        subprocess.Popen(["systemd-run", "--user", "--scope", "--collect", "--quiet", "gio", "launch", fn],
                         start_new_session=True, stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    except Exception:
        subprocess.Popen(["gio", "launch", fn], start_new_session=True,
                         stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    with lock:
        state["apps_used"][aid] = state["apps_used"].get(aid, 0) + 1
    save_state()
    log("app lanzada", aid)
    return {"ok": True}


def app_fav(aid):
    with lock:
        favs = list(state.get("apps_fav") or [])
        if aid in favs:
            favs.remove(aid)
        else:
            favs.append(aid)
        state["apps_fav"] = favs
    save_state()
    return {"ok": True}


def emit(k):
    """Evento para el widget que no depende de que el mando esté 'activo' (p. ej. la tecla Windows)."""
    with pad["cv"]:
        pad["seq"] += 1
        pad["events"].append({"seq": pad["seq"], "k": k, "t": time.time()})
        pad["events"] = pad["events"][-60:]
        pad["cv"].notify_all()


DBUS_XML = '<node><interface name="org.wsaenz.Estanteria"><method name="BigMenu"/></interface></node>'


def dbus_worker():
    """Servicio DBus org.wsaenz.Estanteria: KWin llama a BigMenu() al pulsar la tecla Windows sola."""
    if not HAVE_GIO:
        return

    def on_call(conn, sender, path, iface, method, params, inv):
        if method == "BigMenu":
            emit("MENU")
        inv.return_value(None)

    def bus_acquired(conn, name):
        ni = Gio.DBusNodeInfo.new_for_xml(DBUS_XML)
        conn.register_object("/org/wsaenz/Estanteria", ni.interfaces[0], on_call, None, None)

    Gio.bus_own_name(Gio.BusType.SESSION, "org.wsaenz.Estanteria", Gio.BusNameOwnerFlags.NONE, bus_acquired, None, None)
    GLib.MainLoop().run()


# ---------------------------------------------------------------- energía y sesión
POWER_CMDS = {
    "lock": ["loginctl", "lock-session"],
    "suspend": ["systemctl", "suspend"],
    "logout": ["gdbus", "call", "--session", "--dest", "org.kde.Shutdown", "--object-path", "/Shutdown", "--method", "org.kde.Shutdown.logout"],
    "reboot": ["systemctl", "reboot"],
    "shutdown": ["systemctl", "poweroff"],
}


def do_power(action):
    cmd = POWER_CMDS.get(action)
    if not cmd:
        return {"ok": False, "error": "acción desconocida"}
    log("energía:", action)
    try:
        subprocess.Popen(cmd, start_new_session=True, stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    except Exception as e:
        return {"ok": False, "error": str(e)}
    return {"ok": True}


# ---------------------------------------------------------------- panel superior
TOP_PANEL = 218


def panel_hiding(mode):
    """mode: 'autohide' oculta el panel (Plasma lo desliza hacia arriba); 'none' lo devuelve."""
    script = 'var p = panelById(%d); if (p) p.hiding = "%s";' % (TOP_PANEL, mode)
    try:
        subprocess.run(["gdbus", "call", "--session", "--dest", "org.kde.plasmashell", "--object-path", "/PlasmaShell",
                        "--method", "org.kde.PlasmaShell.evaluateScript", script],
                       capture_output=True, timeout=8)
    except Exception as e:
        log("panel:", e)


# ---------------------------------------------------------------- HTTP
_tint = {"want": "", "cur": "", "t": None, "menu": False}
GLASS_BLUR = 8          # desenfoque normal de Glass
GLASS_BLUR_MENU = 1     # desenfoque mientras el Big Menú está abierto
_glass_lock = threading.Lock()
def _glass_write(tint, strength):
    with _glass_lock:
        try:
            subprocess.run(["kwriteconfig6", "--file", "kwinrc", "--group", "Effect-blurplus", "--key", "TintColor", tint], timeout=5)
            subprocess.run(["kwriteconfig6", "--file", "kwinrc", "--group", "Effect-blurplus", "--key", "BlurStrength", str(strength)], timeout=5)
            subprocess.run(["busctl", "--user", "call", "org.kde.KWin", "/Effects", "org.kde.kwin.Effects", "reconfigureEffect", "s", "glass"], timeout=5, capture_output=True)
        except Exception as e:
            log("glass error", e)

def set_menu_glass(on):
    """Con el Big Menú abierto: sin película (tinte transparente) y desenfoque mínimo; al cerrar vuelve lo normal."""
    _tint["menu"] = bool(on)
    if on:
        _glass_write("#00000000", GLASS_BLUR_MENU)
    else:
        c = _tint["want"] or _tint["cur"] or "#781d131a"
        _tint["cur"] = c
        _glass_write(c, GLASS_BLUR)

def _tint_apply():
    c = _tint["want"]
    if _tint["menu"] or not c or c == _tint["cur"]:
        return
    _tint["cur"] = c
    try:
        subprocess.run(["kwriteconfig6", "--file", "kwinrc", "--group", "Effect-blurplus", "--key", "TintColor", c], timeout=5)
        subprocess.run(["busctl", "--user", "call", "org.kde.KWin", "/Effects", "org.kde.kwin.Effects", "reconfigureEffect", "s", "glass"], timeout=5, capture_output=True)
    except Exception as e:
        log("tint error", e)

def set_tint(c):
    """Tinte de Glass segun el juego seleccionado (#AARRGGBB). Con retardo para no recargar KWin al navegar rapido."""
    if not re.fullmatch(r"#[0-9a-fA-F]{8}", c or ""):
        return
    r, g, b = int(c[3:5], 16), int(c[5:7], 16), int(c[7:9], 16)
    m = max(r, g, b, 1)
    f = min(1.0, 0x26 / m)          # siempre oscuro: el canal mas alto <= 0x1c
    mean = (r + g + b) / 3 * f
    r, g, b = [mean + (x * f - mean) * 0.6 for x in (r, g, b)]   # menos saturado
    c = "#78%02x%02x%02x" % (int(r), int(g), int(b))
    _tint["want"] = c
    if _tint["t"]:
        _tint["t"].cancel()
    _tint["t"] = threading.Timer(0.5, _tint_apply)
    _tint["t"].daemon = True
    _tint["t"].start()

class H(BaseHTTPRequestHandler):
    def log_message(self, *a):
        pass

    def send(self, obj, code=200):
        b = json.dumps(obj).encode()
        self.send_response(code)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(b)))
        self.send_header("Cache-Control", "no-store")
        self.end_headers()
        self.wfile.write(b)

    def route(self):
        u = urllib.parse.urlparse(self.path)
        q = {k: v[0] for k, v in urllib.parse.parse_qs(u.query).items()}
        p = u.path
        if p == "/health":
            return {"ok": True, "pad": pad["connected"], "padName": pad["name"], "key": bool(sgdb_key())}
        if p == "/library":
            return {"games": library_view(), "pad": pad["connected"], "padName": pad["name"], "plat": ui["plat"],
                    "anyRunning": bool(running), "audioOk": audio["ok"]}
        if p == "/log":
            log("qml:", q.get("m", ""))
            return {"ok": True}
        if p == "/game/fav":
            return game_toggle("game_fav", q.get("id", ""))
        if p == "/game/hide":
            return game_toggle("game_hidden", q.get("id", ""))
        if p == "/apps":
            log("apps pedido")
            return {"apps": apps_list()}
        if p == "/app/launch":
            return app_launch(q.get("id", ""))
        if p == "/app/fav":
            return app_fav(q.get("id", ""))
        if p == "/ui":
            if "plat" in q:
                ui["plat"] = q["plat"]
            if "menu" in q:
                ui["menu"] = int(q["menu"])
            return {"plat": ui["plat"], "menu": ui["menu"], "q": ui["q"]}
        if p == "/tint":
            if "menu" in q:
                threading.Thread(target=set_menu_glass, args=(q.get("menu") == "1",), daemon=True).start()
            else:
                set_tint(q.get("c", ""))
            return {"ok": True}
        if p == "/power":
            return do_power(q.get("a", ""))
        if p == "/gamemode":
            # pruebas / manual: ?on=1 activa (juego simulado "manual"), ?on=0 desactiva; sin parámetros devuelve el estado
            if q.get("on") == "1":
                game_mode_start({"name": "manual"}, {"id": "manual", "proc": ""})
            elif q.get("on") == "0":
                game_mode_end("manual")
            return game_mode_status()
        if p == "/menu/prep":
            # prepara el Big Menú (Glass sin película + ocultar panel) ANTES de animar, para que la animación no tropiece
            op = q.get("open") == "1"
            ts = [threading.Thread(target=set_menu_glass, args=(op,), daemon=True),
                  threading.Thread(target=panel_hiding, args=("autohide" if op else "none",), daemon=True)]
            for t in ts: t.start()
            for t in ts: t.join(10)
            return {"ok": True}
        if p == "/panel":
            threading.Thread(target=panel_hiding, args=("autohide" if q.get("hide") == "1" else "none",), daemon=True).start()
            return {"ok": True}
        if p == "/search":
            ui["q"] = q.get("q", "")
            emit("Q:" + ui["q"])
            return {"ok": True}
        if p == "/search/open":
            emit("SEARCH")
            return {"ok": True}
        if p == "/emit":
            k = q.get("k", "")
            if k in ("l", "r", "u", "d", "A", "B", "X", "Y", "LB", "RB", "LT", "RT", "MENU", "POWER", "CTX", "PADSTART", "SEARCH"):
                emit(k)
            elif k.startswith("LK:") and k[3:] in ("l", "r", "u", "d", "A", "B", "X", "Y", "MENU", "POWER"):
                pad_push(k, force=True)      # pruebas de la pantalla de bloqueo
            return {"ok": True}
        if p == "/plat":
            emit("PLAT:" + q.get("k", "all"))
            return {"ok": True}
        if p == "/menu":
            emit("MENU")
            return {"ok": True}
        if p == "/stats":
            return stats()
        if p == "/launch":
            return do_launch(q.get("id", ""), q.get("port", ""))
        if p == "/backup":
            return do_backup(q.get("id", ""), q.get("port", ""))
        if p == "/open":
            return do_open_saves(q.get("id", ""), q.get("port", ""))
        if p == "/art/browse":
            return do_art_browse(q.get("id", ""), q.get("kind", ""), int(q.get("page", "0")), int(q.get("sgid", "0") or 0), q.get("q", ""))
        if p == "/art/pick":
            return do_art_pick(q.get("id", ""), q.get("kind", ""), q.get("url", ""), int(q.get("sgid", "0") or 0))
        if p == "/art/cycle":
            return do_art_cycle(q.get("id", ""), q.get("kind", ""), int(q.get("dir", "1")))
        if p == "/art/fetch":
            g = find_game(q.get("id", ""))
            if g:
                threading.Thread(target=fetch_art, args=(g,), daemon=True).start()
            return {"ok": bool(g)}
        if p == "/pad":
            pad["enabled"] = q.get("on", "0") == "1"
            return {"ok": True, "enabled": pad["enabled"]}
        if p == "/library/refresh":
            return library_refresh()
        if p == "/audio/outputs":
            return audio_outputs()
        if p == "/audio/set":
            return audio_set(q.get("sink", ""), q.get("port", ""))
        if p == "/levels":
            audio["on_until"] = time.time() + 3
            return {"levels": [round(x, 3) for x in audio["levels"]], "bands": audio["bands"], "ok": audio["ok"]}
        if p == "/events":
            since = int(q.get("since", "0"))
            if since < 0:
                with pad["cv"]:
                    return {"seq": pad["seq"], "events": [], "padOn": pad["connected"], "padName": pad.get("name", ""), "padEnabled": pad["enabled"]}
            wait = min(25, float(q.get("wait", "20")))
            end = time.time() + wait
            with pad["cv"]:
                if since > pad["seq"]:
                    since = pad["seq"]
                while True:
                    ev = [e for e in pad["events"] if e["seq"] > since]
                    if ev or time.time() >= end:
                        return {"seq": pad["seq"], "events": ev, "padOn": pad["connected"], "padName": pad.get("name", ""), "padEnabled": pad["enabled"]}
                    pad["cv"].wait(timeout=max(0.05, end - time.time()))
        return {"error": "ruta desconocida"}

    def do_GET(self):
        try:
            self.send(self.route())
        except (BrokenPipeError, ConnectionResetError):
            pass
        except Exception as e:
            log("http error", e)
            try:
                self.send({"error": str(e)}, 500)
            except Exception:
                pass

    do_POST = do_GET


def main():
    os.makedirs(CFG, exist_ok=True)
    os.makedirs(ART, exist_ok=True)
    with lock:
        state.update(load_json(STATE_FILE, {}))
        for k in ("last_played", "sessions", "art", "backups", "apps_used"):
            state.setdefault(k, {})
        state.setdefault("apps_fav", None)
    game_mode_recover()
    threading.Thread(target=panel_hiding, args=("none",), daemon=True).start()
    for fn in (display_env_worker, monitor_worker, disk_worker, pad_worker, audio_worker, art_worker, dbus_worker, lock_state_worker, gfn_worker, pc_worker):
        threading.Thread(target=fn, daemon=True).start()
    srv = ThreadingHTTPServer(("127.0.0.1", PORT), H)
    srv.daemon_threads = True
    log("estanteria-helper escuchando en 127.0.0.1:%d" % PORT)
    try:
        srv.serve_forever()
    except KeyboardInterrupt:
        pass


if __name__ == "__main__":
    if len(sys.argv) > 1 and sys.argv[1] == "art":
        for g in library():
            fetch_art(g)
    else:
        main()

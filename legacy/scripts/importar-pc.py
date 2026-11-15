#!/usr/bin/env python3
"""Detecta los juegos de PC de ~/Juegos/PC y los sincroniza con la estantería (library.json).
  - Steam/steamapps/appmanifest_*.acf  -> juegos de Steam (se lanzan con steam://rungameid/ID)
  - Hydra/ Lutris/ Heroic/ <carpeta>   -> cada subcarpeta con un .exe es un juego de Windows (se lanza con umu-run / Proton)
Uso:  importar-pc.py            (solo muestra lo que haría)
      importar-pc.py --aplicar  (añade juegos nuevos y quita los que ya no existen; solo toca entradas con "auto": "pc")
Correcciones manuales: ~/.config/estanteria/pc-overrides.json
  {"Nombre de la carpeta": {"exe": "ruta/relativa.exe", "name": "Nombre bonito", "ignore": true}}"""
import colorsys, hashlib, json, os, re, sys, unicodedata

HOME = os.path.expanduser("~")
ROOT = "/var/home/wsaenz/Juegos/PC"
LIB = os.path.join(HOME, ".config/estanteria/library.json")
OVR = os.path.join(HOME, ".config/estanteria/pc-overrides.json")
PREFIX_DIR = os.path.join(ROOT, "_Prefijos")
EXE_ROOTS = ["Hydra", "Lutris"]   # Heroic se lee de sus propios installed.json
HEROIC_CFG = os.path.join(HOME, ".var/app/com.heroicgameslauncher.hgl/config/heroic")
SKIP_APPIDS_NAME = re.compile(r"proton|steam linux runtime|steamworks|steamvr|redistributable", re.I)
BAD_EXE = re.compile(r"(unins|uninst|setup|install|redist|vcredist|vc_redist|dxsetup|dotnet|directx|crash|report|eac|easyanticheat|battleye|"
                     r"benchmark|config|updater|update|patch|helper|service|launcherhelper|webhelper|cef|7z|unrar|ue4prereq|prereq|oalinst|"
                     r"notification|bootstrap|dxwebsetup|physx|quicksfv|cleanup|register|activation)", re.I)
SCENE = re.compile(r"[-_ .\[(]+(steamgg(\.net)?|gog|codex|goldberg|fitgirl|dodi|elamigos|repack|rune|tenoke|razor1911|skidrow|plaza|cpy|"
                   r"flt|darksiders|empress|drm[- ]?free|portable|build[ _.]?\d+|v?\d+(\.\d+){1,}.*)\b.*$", re.I)


def slug(t):
    t = unicodedata.normalize("NFKD", t).encode("ascii", "ignore").decode().lower()
    return re.sub(r"[^a-z0-9]+", "-", t).strip("-") or "juego"


def limpio(folder):
    n = re.sub(r"\[[^\]]*\]|\([^)]*\)", " ", folder)
    n = SCENE.sub("", n).strip(" -_.")
    if " " not in n:
        n = re.sub(r"[_.]+", " ", n)
    n = re.sub(r"\s+", " ", n).strip()
    return n or folder


def palette(title):
    h = int(hashlib.sha1(title.encode()).hexdigest()[:6], 16) / 0xFFFFFF
    def hx(hh, ss, vv):
        r, g, b = colorsys.hsv_to_rgb(hh % 1, ss, vv); return "#%02x%02x%02x" % (int(r * 255), int(g * 255), int(b * 255))
    return [hx(h, .5, .13), hx(h, .5, .46), hx(h, .5, .34), hx(h, .6, .10), hx(h + .02, .28, .96)]


def exes(d, depth=3):
    out = []
    base = d.rstrip("/").count("/")
    for r, ds, fs in os.walk(d):
        if r.count("/") - base >= depth:
            ds[:] = []
        ds[:] = [x for x in ds if not x.startswith(".") and x.lower() not in ("redist", "_commonredist", "directx", "__installer", "uninstall")]
        for f in fs:
            if f.lower().endswith(".exe"):
                out.append(os.path.join(r, f))
    return out


def best_exe(d, name):
    key = slug(name).replace("-", "")
    best, bs = None, -1e9
    for p in exes(d):
        b = os.path.basename(p)
        if BAD_EXE.search(b):
            continue
        s = os.path.getsize(p) / 1e6                      # los ejecutables del juego suelen ser grandes
        s -= 40 * (p.count("/") - d.rstrip("/").count("/") - 1)    # penaliza profundidad
        st = slug(b[:-4]).replace("-", "")
        if st and (st in key or key.startswith(st[:6])):
            s += 200                                       # nombre parecido al de la carpeta
        if "shipping" in b.lower() or "win64" in p.lower():
            s += 25
        if s > bs:
            best, bs = p, s
    return best


def steam_games():
    out = []
    import glob
    # solo las carpetas steamapps de la biblioteca (NO recorrer "common"/"compatdata": miles de archivos y tarda minutos)
    acfs = glob.glob(os.path.join(ROOT, "Steam", "steamapps", "appmanifest_*.acf")) + glob.glob(os.path.join(ROOT, "Steam", "*", "steamapps", "appmanifest_*.acf"))
    for acf in sorted(acfs):
        t = open(acf, encoding="utf-8", errors="ignore").read()
        g = lambda k: (re.search(r'"%s"\s+"([^"]*)"' % k, t) or [None, ""])[1]
        aid, name, inst = g("appid"), g("name"), g("installdir")
        if not aid or not name or SKIP_APPIDS_NAME.search(name):
            continue
        try:
            if not int(g("StateFlags") or 0) & 4:            # 4 = instalado por completo
                continue
        except ValueError:
            continue
        out.append({"id": "pc-steam-" + aid, "name": name, "platform": "pc", "src": "Steam",
                    "launch": ["steam", "steam://rungameid/" + aid], "check": acf, "proc": inst or name,
                    "disk_dir": os.path.join(os.path.dirname(acf), "common", inst), "chips": ["Steam"], "s": "Biblioteca de Steam", "folder": acf})
    return out


def heroic_title(runner, aid):
    """El installed.json de GOG/Amazon no trae el título: se busca en la caché de la biblioteca de Heroic."""
    fich = {"legendary": ("legendary_library.json", "library"), "gog": ("gog_library.json", "games"), "nile": ("nile_library.json", "library")}[runner]
    try:
        d = json.load(open(os.path.join(HEROIC_CFG, "store_cache", fich[0])))
        for x in d.get(fich[1], []):
            if str(x.get("app_name")) == str(aid) and x.get("title"):
                return x["title"]
    except Exception:
        pass
    return ""


def gog_exe(path):
    """Ejecutable principal de un juego de GOG (goggame-<id>.info -> playTasks)."""
    try:
        for f in glob.glob(os.path.join(path, "goggame-*.info")):
            for t in json.load(open(f)).get("playTasks", []):
                if t.get("isPrimary") and t.get("path"):
                    return t["path"].replace("\\", "/")
    except Exception:
        pass
    try:
        e = best_exe(path, os.path.basename(path))
        return os.path.relpath(e, path) if e else ""
    except Exception:
        return ""


def heroic_games(ovr):
    """Juegos instalados en Heroic (Epic/legendary, GOG, Amazon/nile): se lanzan por Heroic."""
    out = []
    fuentes = [("legendary", "legendaryConfig/legendary/installed.json"), ("gog", "gog_store/installed.json"),
               ("nile", "nile_store/installed.json")]
    for runner, rel in fuentes:
        try:
            d = json.load(open(os.path.join(HEROIC_CFG, rel)))
        except Exception:
            continue
        items = d.get("installed", []) if isinstance(d, dict) and "installed" in d else (list(d.values()) if isinstance(d, dict) else d)
        for v in items:
            if not isinstance(v, dict) or v.get("is_dlc"):
                continue
            aid = v.get("app_name") or v.get("appName")
            path = v.get("install_path") or v.get("install", {}).get("install_path")
            title = v.get("title") or heroic_title(runner, aid) or os.path.basename(str(path or "").rstrip("/")) or aid
            if not aid or not path or not os.path.isdir(path) or ovr.get(aid, {}).get("ignore"):
                continue
            name = ovr.get(aid, {}).get("name") or title
            exe = v.get("executable") or gog_exe(path) or ""
            out.append({"id": "pc-heroic-" + slug(name), "name": name, "platform": "pc", "src": "Heroic",
                        "launch": ["flatpak", "run", "com.heroicgameslauncher.hgl", "heroic://launch/%s/%s" % (runner, aid)],
                        "check": path, "proc": os.path.basename(exe.replace("\\", "/")) or name, "disk_dir": path,
                        "chips": ["Heroic", {"legendary": "Epic", "gog": "GOG", "nile": "Amazon"}[runner]],
                        "s": "Heroic (%s)" % {"legendary": "Epic", "gog": "GOG", "nile": "Amazon"}[runner], "folder": path})
    return out


def exe_games(ovr):
    out = []
    for root in EXE_ROOTS:
        rd = os.path.join(ROOT, root)
        if not os.path.isdir(rd):
            continue
        for f in sorted(os.listdir(rd)):
            d = os.path.join(rd, f)
            if not os.path.isdir(d) or f.startswith((".", "_")) or ovr.get(f, {}).get("ignore"):
                continue
            o = ovr.get(f, {})
            name = o.get("name") or limpio(f)
            exe = os.path.join(d, o["exe"]) if o.get("exe") else best_exe(d, name)
            if not exe or not os.path.exists(exe):
                continue
            gid = "pc-" + slug(name)
            pre = os.path.join(PREFIX_DIR, slug(name))
            out.append({"id": gid, "name": name, "platform": "pc", "src": root,
                        "launch": ["env", "GAMEID=umu-0", "PROTONPATH=GE-Proton", "WINEPREFIX=" + pre, "umu-run", exe],
                        "cwd": os.path.dirname(exe), "check": exe, "proc": os.path.basename(exe), "disk_dir": d,
                        "chips": ["Windows", "Proton"], "s": "Windows con Proton (umu)", "folder": d})
    return out


def entry(c):
    pal = palette(c["name"])
    port = {"id": c["id"] + "-main", "name": c["src"], "s": c["s"], "chips": c["chips"],
            "launch": c["launch"], "check": c["check"], "proc": c["proc"], "disk_dir": c["disk_dir"]}
    if c.get("cwd"):
        port["cwd"] = c["cwd"]
    sub = "PC · " + c["src"]
    return {"id": c["id"], "name": c["name"], "sub": sub, "platform": c["platform"], "year": 0, "s": c["s"], "src": c["src"], "added": int(__import__("time").time()),
            "font": "Rajdhani", "pal": pal, "acc": pal[4], "auto": "pc",
            "art": {"slug": c["id"], "sgdb": c["name"], "year": None, "portada": 1, "fondo": 1, "lite": True}, "ports": [port]}


def main():
    apply = "--aplicar" in sys.argv
    quiet = "--silencioso" in sys.argv
    ovr = json.load(open(OVR)) if os.path.exists(OVR) else {}
    want = {c["id"]: c for c in steam_games() + heroic_games(ovr) + exe_games(ovr)}
    lib = json.load(open(LIB))
    games = lib["games"]
    have = {g["id"]: g for g in games}
    fix = 0
    for i, c in want.items():
        g = have.get(i)
        if g and g.get("auto") == "pc" and (g.get("platform") != "pc" or g.get("src") != c["src"] or g.get("sub") != "PC · " + c["src"]):
            g["platform"] = "pc"; g["src"] = c["src"]; g["sub"] = "PC · " + c["src"]
            for p in g.get("ports", []):
                p["name"] = c["src"]
            fix += 1
    new = [c for i, c in want.items() if i not in have]
    gone = [g for g in games if g.get("auto") == "pc" and g["id"] not in want]
    # el id puede cambiar si el usuario renombra: mismo "launch" ya registrado => no duplicar
    known_launch = {tuple(p.get("launch", [])) for g in games for p in g.get("ports", [])}
    new = [c for c in new if tuple(c["launch"]) not in known_launch]
    if not quiet or new or gone:
        print("Juegos de PC detectados: %d | nuevos: %d | a quitar: %d" % (len(want), len(new), len(gone)))
        for c in new:
            print("  + %-40s [%s] %s" % (c["name"], c["src"], c["launch"][-1]))
        for g in gone:
            print("  - %s" % g["name"])
    if apply and fix and not (new or gone):
        tmp = LIB + ".tmp"; json.dump(lib, open(tmp, "w"), ensure_ascii=False, indent=1); os.replace(tmp, LIB)
    if apply and (new or gone):
        gone_ids = {g["id"] for g in gone}
        lib["games"] = [g for g in games if g["id"] not in gone_ids] + [entry(c) for c in new]
        tmp = LIB + ".tmp"
        json.dump(lib, open(tmp, "w"), ensure_ascii=False, indent=1)
        os.replace(tmp, LIB)
        print("Biblioteca actualizada.")
    elif not apply and (new or gone):
        print("(simulación: usa --aplicar para escribirlo)")


main()

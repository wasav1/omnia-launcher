#!/usr/bin/env python3
"""Importa a la biblioteca de la estantería las ROM de N64 de una carpeta, lanzadas con Gopher64.
- Detecta REPETIDOS por contenido (hash tras normalizar el orden de bytes z64/v64/n64) y por título (normalizado, sin región/etiquetas).
- Omite lo que ya está en la biblioteca (Majora's Mask, Star Fox 64...) y no repite entre sí.
- Añade al FINAL de library.json (después de los juegos que ya había), por orden alfabético.
Uso:  python3 importar-roms.py [carpeta] [--aplicar]      (sin --aplicar solo informa)"""
import hashlib, json, os, re, sys, array, colorsys, unicodedata

LIB = os.path.expanduser("~/.config/estanteria/library.json")
DEFAULT_DIR = "/var/home/wsaenz/Juegos/Nintendo/N64/ROMS"
EXT = (".z64", ".n64", ".v64")
FLATPAK = ["flatpak", "run", "--env=MANGOHUD=1", "io.github.gopher64.gopher64", "--fullscreen"]

def norm_hash(path):
    """sha1 del contenido normalizado a big endian (z64). Devuelve (hash, formato)."""
    with open(path, "rb") as f:
        data = f.read()
    head = data[:4]
    fmt = "z64"
    if head == b"\x37\x80\x40\x12":
        fmt = "v64"; a = array.array("H"); a.frombytes(data[: len(data) // 2 * 2]); a.byteswap(); data = a.tobytes()
    elif head == b"\x40\x12\x37\x80":
        fmt = "n64"; a = array.array("I"); a.frombytes(data[: len(data) // 4 * 4]); a.byteswap(); data = a.tobytes()
    elif head != b"\x80\x37\x12\x40":
        fmt = "?"
    return hashlib.sha1(data).hexdigest(), fmt

def clean_title(fn):
    base = os.path.splitext(fn)[0]
    t = re.sub(r"\s*[\(\[][^\)\]]*[\)\]]", "", base)          # fuera (U) [!] (V1.1) ...
    t = t.replace("_", "'")
    t = re.sub(r"\s+", " ", t).strip(" -")
    m = re.match(r"^(.*?), (The|A|An)( - .*)?$", t)            # "Legend of Zelda, The - X" -> "The Legend of Zelda - X"
    if m:
        t = "%s %s%s" % (m.group(2), m.group(1), m.group(3) or "")
    return t

# mismo juego con distinto nombre regional/de archivo
ALIAS = {"2000supercross": "2000jeremymcgrathsupercross"}

def key_of(title):
    t = unicodedata.normalize("NFKD", title).encode("ascii", "ignore").decode().lower()
    t = re.sub(r"\b(the|a|an)\b", " ", t)
    k = "".join(sorted(re.sub(r"[^a-z0-9 ]", " ", t).split()))      # sin orden de palabras: "007 - GoldenEye" == "GoldenEye 007"
    return ALIAS.get(k, k)

def score(fn, fmt):
    s = 0
    tags = " ".join(re.findall(r"[\(\[][^\)\]]*[\)\]]", fn))
    if re.search(r"\((U|USA|JU|UE)\)", tags): s += 3
    elif re.search(r"\((E|EU|Europe|J|Japan)\)", tags): s += 1
    if "[!]" in tags or "(!)" in tags: s += 2
    if re.search(r"\[(b|f|h|o|t|T)[^\]]*\]", tags): s -= 6        # volcados malos, hacks, traducciones
    if fmt == "z64": s += 1
    m = re.search(r"V(\d)\.(\d)", tags)
    if m: s += 0.1 * int(m.group(2))
    return s

def slug_of(title):
    t = unicodedata.normalize("NFKD", title).encode("ascii", "ignore").decode().lower()
    return re.sub(r"[^a-z0-9]+", "-", t).strip("-")

def palette(title):
    h = int(hashlib.sha1(title.encode()).hexdigest()[:6], 16) / 0xFFFFFF
    def hx(hh, ss, vv):
        r, g, b = colorsys.hsv_to_rgb(hh % 1, ss, vv); return "#%02x%02x%02x" % (int(r*255), int(g*255), int(b*255))
    return [hx(h, .55, .13), hx(h, .55, .46), hx(h, .5, .34), hx(h, .6, .10), hx(h + .02, .28, .96)]

def main():
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    apply = "--aplicar" in sys.argv
    folder = args[0] if args else DEFAULT_DIR
    lib = json.load(open(LIB))
    games = lib["games"]
    # lo que ya existe: hashes de las ROM de N64 ya enlazadas y títulos de juegos n64
    have_hash, have_keys, have_ids = {}, {}, {g["id"] for g in games}
    for g in games:
        if g.get("platform") != "n64":
            continue
        have_keys[key_of(g["name"])] = g["name"]
        for p in g.get("ports", []):
            rom = (p.get("launch") or [""])[-1]
            if rom.lower().endswith(EXT) and os.path.exists(rom):
                have_hash[norm_hash(rom)[0]] = g["name"]
    cand = []
    for fn in sorted(os.listdir(folder)):
        if not fn.lower().endswith(EXT):
            continue
        path = os.path.join(folder, fn)
        h, fmt = norm_hash(path)
        cand.append({"fn": fn, "path": path, "hash": h, "fmt": fmt, "title": clean_title(fn), "score": score(fn, fmt)})
    rep = ["ROM encontradas: %d" % len(cand)]
    # 1) ya en la biblioteca
    keep = []
    for c in cand:
        k = key_of(c["title"])
        if c["hash"] in have_hash:
            rep.append("YA EXISTE (mismo contenido que '%s'): %s" % (have_hash[c["hash"]], c["fn"])); continue
        hit = [n for kk, n in have_keys.items() if kk and (kk == k or kk in k)]
        if hit:
            rep.append("YA EXISTE (título '%s'): %s" % (hit[0], c["fn"])); continue
        keep.append(c)
    # 2) repetidos por contenido y por título entre las candidatas
    byhash, tmp = {}, []
    for c in sorted(keep, key=lambda c: -c["score"]):
        if c["hash"] in byhash:
            rep.append("REPETIDA (mismo contenido que %s): %s" % (byhash[c["hash"]]["fn"], c["fn"])); continue
        byhash[c["hash"]] = c; tmp.append(c)
    bykey, final = {}, []
    for c in tmp:
        k = key_of(c["title"])
        if k in bykey:
            rep.append("REPETIDA (mismo título que %s): %s" % (bykey[k]["fn"], c["fn"])); continue
        bykey[k] = c; final.append(c)
    final.sort(key=lambda c: c["title"].lower())
    new = []
    for c in final:
        sl = slug_of(c["title"]); gid = "n64-" + sl
        if gid in have_ids:
            rep.append("ID EN USO: %s" % c["fn"]); continue
        have_ids.add(gid)
        pal = palette(c["title"])
        new.append({
            "id": gid, "name": c["title"], "sub": "Nintendo 64", "platform": "n64", "year": 0,
            "s": "Emulado con Gopher64", "font": "Orbitron", "pal": pal, "acc": pal[4],
            "art": {"slug": "n64-" + sl, "sgdb": c["title"], "year": None, "portada": 1, "fondo": 1, "lite": True},
            "ports": [{"id": gid + "-gopher64", "name": "Gopher64", "s": "Emulador N64 · pantalla completa", "chips": ["Emulador", "Pantalla completa"],
                       "launch": FLATPAK + [c["path"]], "check": c["path"], "proc": c["fn"], "disk_dir": c["path"]}],
        })
    rep.append("A AÑADIR: %d juegos" % len(new))
    print("\n".join(rep))
    out = os.path.expanduser("~/.config/estanteria/roms-import-informe.txt")
    open(out, "w").write("\n".join(rep) + "\n\nJUEGOS:\n" + "\n".join(n["name"] for n in new) + "\n")
    if apply:
        # los ya existentes de gopher64 usaban proc="gopher64" (se marcarían todos como "en ejecución"): usar el nombre de su ROM
        for g in games:
            for p in g.get("ports", []):
                if p.get("proc") == "gopher64" and p.get("launch"):
                    p["proc"] = os.path.basename(p["launch"][-1])
        lib["games"] = games + new
        json.dump(lib, open(LIB, "w"), indent=1, ensure_ascii=False)
        print("Guardado en", LIB, "(copia previa: library.json.antes-roms.bak). Informe:", out)

if __name__ == "__main__":
    main()

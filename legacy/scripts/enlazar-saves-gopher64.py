#!/usr/bin/env python3
"""Enlaza cada juego de Gopher64 con sus partidas (archivos NOMBRE-<SHA256 de la ROM>.eep/.mpk/.sra/.fla en el directorio de saves del Flatpak)."""
import hashlib, array, json, os
LIB = os.path.expanduser("~/.config/estanteria/library.json")
SAVES = "/var/home/wsaenz/.var/app/io.github.gopher64.gopher64/data/gopher64/saves"
BACKUPS = "/var/home/wsaenz/Juegos/Nintendo/N64/Partidas-Gopher64"
def hashes(rom):
    d = open(rom, "rb").read()
    hs = {hashlib.sha256(d).hexdigest().upper()}
    h = d[:4]
    if h == b"\x37\x80\x40\x12":
        a = array.array("H"); a.frombytes(d[: len(d) // 2 * 2]); a.byteswap(); hs.add(hashlib.sha256(a.tobytes()).hexdigest().upper())
    elif h == b"\x40\x12\x37\x80":
        a = array.array("I"); a.frombytes(d[: len(d) // 4 * 4]); a.byteswap(); hs.add(hashlib.sha256(a.tobytes()).hexdigest().upper())
    return hs
lib = json.load(open(LIB)); n = 0
for g in lib["games"]:
    for p in g.get("ports", []):
        l = p.get("launch") or []
        if "io.github.gopher64.gopher64" not in l:
            continue
        rom = l[-1]
        if not os.path.exists(rom):
            continue
        p["saves"] = {"files": [SAVES + "/*-" + h + ".*" for h in sorted(hashes(rom))], "name": "Partida"}
        p["backup_dir"] = BACKUPS
        n += 1
os.makedirs(BACKUPS, exist_ok=True)
json.dump(lib, open(LIB, "w"), indent=1, ensure_ascii=False)
print("enlazados:", n)

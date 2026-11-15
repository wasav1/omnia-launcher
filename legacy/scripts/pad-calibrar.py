#!/usr/bin/env python3
"""Calibra el mando: te pide cada botón y guarda la asignación en ~/.config/estanteria/config.json.
Uso (en el host):  python3 ~/.local/share/estanteria/pad-calibrar.py"""
import glob, json, os, select, struct, sys, time
CFG = os.path.expanduser("~/.config/estanteria/config.json")
js = sorted(glob.glob("/dev/input/js*"))
if not js:
    sys.exit("No hay mando conectado (/dev/input/js*).")
fd = os.open(js[0], os.O_RDONLY | os.O_NONBLOCK)
PEDIR = [("A", "A"), ("B", "B"), ("X", "X"), ("Y", "Y"), ("LB (bumper izquierdo)", "LB"), ("RB (bumper derecho)", "RB"),
         ("LT (gatillo izquierdo)", "LT"), ("RT (gatillo derecho)", "RT"),
         ("Cruceta IZQUIERDA", "l"), ("Cruceta DERECHA", "r"), ("Cruceta ARRIBA", "u"), ("Cruceta ABAJO", "d")]
rest = {}
def leer_todo(t=0.05):
    out = []
    r, _, _ = select.select([fd], [], [], t)
    while r:
        try:
            d = os.read(fd, 8 * 16)
        except BlockingIOError:
            break
        for i in range(0, len(d) - 7, 8):
            _, val, typ, num = struct.unpack("IhBB", d[i:i + 8])
            init = typ & 0x80
            typ &= 0x7F
            if typ == 2 and init:
                rest[num] = val
            elif not init:
                out.append((typ, num, val))
        r, _, _ = select.select([fd], [], [], 0)
    return out
leer_todo(0.3)
bind = {}
print("Calibración del mando. Pulsa lo que se pide (un toque) y espera al siguiente.\n")
for texto, clave in PEDIR:
    print("  -> Pulsa", texto, "...", end=" ", flush=True)
    leer_todo(0.5)
    hecho = False
    t0 = time.time()
    while not hecho and time.time() - t0 < 30:
        for typ, num, val in leer_todo(0.1):
            if typ == 1 and val:
                bind["b:%d" % num] = clave
                print("botón", num); hecho = True; break
            if typ == 2:
                d = val - rest.get(num, 0)
                if abs(d) > 17000:
                    s = "+" if d > 0 else "-"
                    bind["a:%d:%s" % (num, s)] = clave
                    print("eje", num, s); hecho = True; break
    if not hecho:
        print("(omitido)")
    time.sleep(0.6)
    leer_todo(0.3)
cfg = {}
try:
    cfg = json.load(open(CFG))
except Exception:
    pass
cfg["bindings"] = bind
os.makedirs(os.path.dirname(CFG), exist_ok=True)
json.dump(cfg, open(CFG, "w"), indent=1)
print("\nGuardado en", CFG, "\nReinicia el ayudante:  systemctl --user restart estanteria-helper.service")

"""Mando por evdev, sin dependencias (el prototipo leía /dev/input/js0, la API antigua).

  discover()   mandos conectados, leyendo /proc/bus/input/devices
  PadLogic     lógica pura: botones y ejes -> teclas lógicas («l r u d A B X Y LB RB LT RT START SELECT MODE»)
  PadReader    hilo que lee los dispositivos, detecta altas/bajas (Bluetooth) y envía las teclas al EventBus
`python -m omnia.pad --monitor` imprime los eventos crudos para calibrar un mando nuevo.
La etiqueta del botón (A/B/X/Y) sigue la del mando: en Nintendo A es el botón derecho; confirmar es siempre «A».
"""
import fcntl
import os
import re
import select
import struct
import sys
import threading
import time
from dataclasses import dataclass
from pathlib import Path

EV_KEY, EV_ABS = 1, 3
EVENT = struct.Struct("@llHHi")           # struct input_event: tiempo (16 B) + tipo + código + valor
ABSINFO = struct.Struct("6i")             # value, minimum, maximum, fuzz, flat, resolution
EVIOCGABS = lambda a: 0x80184540 + a      # _IOR('E', 0x40 + abs, struct input_absinfo)

# códigos del kernel (linux/input-event-codes.h)
BTN_SOUTH, BTN_EAST, BTN_NORTH, BTN_WEST = 0x130, 0x131, 0x133, 0x134
BTN_TL, BTN_TR, BTN_SELECT, BTN_START, BTN_MODE = 0x136, 0x137, 0x13A, 0x13B, 0x13C
ABS_X, ABS_Y, ABS_Z, ABS_RZ, ABS_GAS, ABS_BRAKE, ABS_HAT0X, ABS_HAT0Y = 0, 1, 2, 5, 9, 10, 0x10, 0x11

COMMON = {BTN_TL: "LB", BTN_TR: "RB", BTN_SELECT: "SELECT", BTN_START: "START", BTN_MODE: "MODE"}
BUTTONS = {   # posición física -> etiqueta del mando
    # Xbox por Bluetooth (medido con un mando real): X llega como 0x133 y Y como 0x134, al revés que los nombres NORTH/WEST
    "xbox": {BTN_SOUTH: "A", BTN_EAST: "B", BTN_NORTH: "X", BTN_WEST: "Y", **COMMON},
    "ps": {BTN_SOUTH: "A", BTN_EAST: "B", BTN_WEST: "X", BTN_NORTH: "Y", **COMMON},      # cruz, círculo, cuadrado, triángulo
    "switch": {BTN_EAST: "A", BTN_SOUTH: "B", BTN_NORTH: "X", BTN_WEST: "Y", **COMMON},
}


@dataclass
class Device:
    name: str
    path: str
    layout: str


def layout_for(name: str) -> str:
    n = name.lower()
    if "nintendo" in n or "pro controller" in n or "joy-con" in n:
        return "switch"
    if any(s in n for s in ("playstation", "dualsense", "dualshock", "sony", "wireless controller")) and "xbox" not in n:
        return "ps"
    return "xbox"


def discover(devices_file: str = "/proc/bus/input/devices", dev_dir: str = "/dev/input") -> list:
    """Mandos: dispositivos con manejador jsN y eventN."""
    try:
        text = Path(devices_file).read_text(errors="replace")
    except OSError:
        return []
    out = []
    for block in text.split("\n\n"):
        name = re.search(r'N: Name="([^"]*)"', block)
        h = re.search(r"H: Handlers=(.*)", block)
        if not (name and h):
            continue
        ev, js = re.search(r"\bevent(\d+)\b", h.group(1)), re.search(r"\bjs\d+\b", h.group(1))
        if ev and js:
            out.append(Device(name.group(1), f"{dev_dir}/event{ev.group(1)}", layout_for(name.group(1))))
    return out


class PadLogic:
    """Traduce eventos de evdev a teclas lógicas. Sin E/S ni reloj propio: el tiempo se pasa como argumento."""
    REPEAT_FIRST, REPEAT_NEXT = 0.40, 0.12
    STICK, TRIGGER = 0.5, 0.5

    def __init__(self, layout: str = "xbox"):
        self.buttons = BUTTONS.get(layout, BUTTONS["xbox"])
        self.src = {}                  # origen («stickx», «hatx», …) -> dirección activa o None
        self.held = {}                 # dirección -> instante del próximo repetido
        self.trig = {"LT": False, "RT": False}

    @staticmethod
    def _dir(source, v):
        horizontal = source in ("stickx", "hatx")
        if v <= -PadLogic.STICK:
            return "l" if horizontal else "u"
        if v >= PadLogic.STICK:
            return "r" if horizontal else "d"
        return None

    def _set_source(self, source, d, now):
        self.src[source] = d
        active = {x for x in self.src.values() if x}
        out = []
        for k in active - set(self.held):          # dirección nueva: se emite ya y se programa el repetido
            self.held[k] = now + self.REPEAT_FIRST
            out.append(k)
        for k in set(self.held) - active:
            del self.held[k]
        return out

    def feed(self, etype: int, code: int, value, now: float) -> list:
        """value: botones 0/1; ejes ya normalizados a [-1, 1] (gatillos a [0, 1])."""
        if etype == EV_KEY:
            return [self.buttons[code]] if value == 1 and code in self.buttons else []
        if etype != EV_ABS:
            return []
        if code in (ABS_X, ABS_Y):
            return self._set_source("stickx" if code == ABS_X else "sticky", self._dir("stickx" if code == ABS_X else "sticky", value), now)
        if code in (ABS_HAT0X, ABS_HAT0Y):
            s = "hatx" if code == ABS_HAT0X else "haty"
            return self._set_source(s, self._dir(s, value), now)
        trig = {ABS_Z: "LT", ABS_BRAKE: "LT", ABS_RZ: "RT", ABS_GAS: "RT"}.get(code)
        if trig:
            on = value >= self.TRIGGER
            fired = on and not self.trig[trig]
            self.trig[trig] = on
            return [trig] if fired else []
        return []

    def tick(self, now: float) -> list:
        """Repite la dirección mantenida (para recorrer una lista larga sin soltar la cruceta)."""
        out = []
        for k, due in list(self.held.items()):
            if now >= due:
                out.append(k)
                self.held[k] = now + self.REPEAT_NEXT
        return out


def normalize(code: int, raw: int, info: tuple) -> float:
    """Normaliza un eje con su absinfo (value, min, max, fuzz, flat, res). Los gatillos van de 0 a 1; el resto de -1 a 1."""
    _, lo, hi, _, _, _ = info
    if hi == lo:
        return 0.0
    if code in (ABS_Z, ABS_RZ, ABS_GAS, ABS_BRAKE) and lo >= 0:
        return (raw - lo) / (hi - lo)
    if code in (ABS_HAT0X, ABS_HAT0Y):
        return float(max(-1, min(1, raw)))
    mid = (hi + lo) / 2
    return max(-1.0, min(1.0, (raw - mid) / ((hi - lo) / 2)))


class PadReader(threading.Thread):
    """Lee todos los mandos conectados y empuja las teclas al bus. `gate()` decide si se entregan (p. ej. no con un juego abierto)."""

    def __init__(self, bus, gate=lambda: True, devices_file="/proc/bus/input/devices", log=lambda *a: None, dev_dir="/dev/input"):
        super().__init__(daemon=True, name="omnia-pad")
        self.bus, self.gate, self.devices_file, self.log, self.dev_dir = bus, gate, devices_file, log, dev_dir
        self.stop_event = threading.Event()
        self.open = {}          # fd -> (Device, PadLogic, {código: absinfo})

    def _open(self, dev: Device):
        fd = os.open(dev.path, os.O_RDONLY | os.O_NONBLOCK)
        info = {}
        for code in (ABS_X, ABS_Y, ABS_Z, ABS_RZ, ABS_GAS, ABS_BRAKE, ABS_HAT0X, ABS_HAT0Y):
            try:
                info[code] = ABSINFO.unpack(fcntl.ioctl(fd, EVIOCGABS(code), bytes(ABSINFO.size)))
            except OSError:
                pass
        if ABS_GAS in info or ABS_BRAKE in info:
            # Xbox por Bluetooth: los gatillos son GAS/BRAKE y ABS_Z/ABS_RZ son el stick derecho (no se usa para navegar)
            info.pop(ABS_Z, None)
            info.pop(ABS_RZ, None)
        self.open[fd] = (dev, PadLogic(dev.layout), info)

    def _rescan(self):
        have = {d.path for d, _, _ in self.open.values()}
        for dev in discover(self.devices_file, self.dev_dir):
            if dev.path not in have:
                try:
                    self._open(dev)
                    self.log(f"mando conectado: {dev.name} ({dev.layout})")
                except OSError as e:
                    self.log(f"no se pudo abrir {dev.path}: {e}")
        now_paths = {d.path for d in discover(self.devices_file, self.dev_dir)}
        for fd, (dev, _, _) in list(self.open.items()):
            if dev.path not in now_paths:
                self._close(fd)
        first = next(iter(self.open.values()), None)
        self.bus.set_pad(bool(first), first[0].name if first else "", first[0].layout if first else "")

    def _close(self, fd):
        dev = self.open.pop(fd)[0]
        try:
            os.close(fd)
        except OSError:
            pass
        self.log(f"mando desconectado: {dev.name}")

    def _emit(self, keys):
        if keys and self.gate():
            for k in keys:
                self.bus.push(k)

    def run(self):
        last_scan = 0.0
        while not self.stop_event.is_set():
            now = time.monotonic()
            if now - last_scan > 2.0:
                self._rescan()
                last_scan = now
            if not self.open:
                self.stop_event.wait(0.5)
                continue
            ready, _, _ = select.select(list(self.open), [], [], 0.05)
            for fd in ready:
                try:
                    data = os.read(fd, EVENT.size * 32)
                except BlockingIOError:
                    continue
                except OSError:
                    self._close(fd)
                    continue
                _, logic, info = self.open[fd]
                for i in range(0, len(data) - EVENT.size + 1, EVENT.size):
                    _, _, etype, code, value = EVENT.unpack_from(data, i)
                    if etype == EV_ABS and code in info:
                        self._emit(logic.feed(etype, code, normalize(code, value, info[code]), time.monotonic()))
                    elif etype == EV_KEY:
                        self._emit(logic.feed(etype, code, value, time.monotonic()))
            now = time.monotonic()
            for _, logic, _ in self.open.values():
                self._emit(logic.tick(now))
        for fd in list(self.open):
            self._close(fd)

    def stop(self):
        self.stop_event.set()


def monitor(seconds: float = 20.0) -> int:
    """Imprime los eventos crudos de los mandos (para calibrar un mando nuevo)."""
    devs = discover()
    if not devs:
        print("No hay ningún mando conectado.")
        return 1
    fds = {}
    for d in devs:
        try:
            fds[os.open(d.path, os.O_RDONLY | os.O_NONBLOCK)] = d
            print(f"Leyendo {d.name} ({d.path}) — {d.layout}")
        except OSError as e:
            print(f"No se pudo abrir {d.path}: {e}")
    end = time.time() + seconds
    while time.time() < end and fds:
        for fd in select.select(list(fds), [], [], 0.2)[0]:
            data = os.read(fd, EVENT.size * 32)
            for i in range(0, len(data) - EVENT.size + 1, EVENT.size):
                _, _, t, c, v = EVENT.unpack_from(data, i)
                if t in (EV_KEY, EV_ABS):
                    print('{} code=0x{:X} value={:d}'.format("KEY" if t == EV_KEY else "ABS", c, v), flush=True)
    return 0


if __name__ == "__main__":
    sys.exit(monitor(float(sys.argv[2])) if len(sys.argv) > 2 and sys.argv[1] == "--monitor" else monitor())

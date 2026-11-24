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
import subprocess
import sys
import threading
import time
from dataclasses import dataclass
from pathlib import Path

EV_KEY, EV_ABS, EV_FF = 1, 3, 0x15
EVENT = struct.Struct("@llHHi")           # struct input_event: tiempo (16 B) + tipo + código + valor
ABSINFO = struct.Struct("6i")             # value, minimum, maximum, fuzz, flat, resolution
EVIOCGABS = lambda a: 0x80184540 + a      # _IOR('E', 0x40 + abs, struct input_absinfo)

# códigos del kernel (linux/input-event-codes.h)
BTN_SOUTH, BTN_EAST, BTN_NORTH, BTN_WEST = 0x130, 0x131, 0x133, 0x134
BTN_TL, BTN_TR, BTN_SELECT, BTN_START, BTN_MODE = 0x136, 0x137, 0x13A, 0x13B, 0x13C
ABS_X, ABS_Y, ABS_Z, ABS_RZ, ABS_GAS, ABS_BRAKE, ABS_HAT0X, ABS_HAT0Y = 0, 1, 2, 5, 9, 10, 0x10, 0x11
ABS_RX, ABS_RY = 3, 4
BTN_THUMBL, BTN_THUMBR = 0x13D, 0x13E
FF_RUMBLE = 0x50
EVIOCSFF = 0x40304580                       # _IOW('E', 0x80, struct ff_effect): 48 bytes en 64 bits
EVIOCRMFF = 0x40044581                      # _IOW('E', 0x81, int)
FAMILIES = ("xbox", "ps", "switch", "deck")

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
    layout: str            # cómo llegan los botones (xbox | ps | switch): decide la etiqueta lógica A/B/X/Y
    family: str = ""       # qué iconos mostrar (xbox | ps | switch | deck)
    vendor: str = ""
    product: str = ""
    uniq: str = ""         # identificador único (en Bluetooth, la dirección MAC): sirve para encontrar su batería


# Fabricante USB/Bluetooth -> familia de iconos. Es más fiable que el nombre (mandos genéricos, nombres traducidos).
VENDOR_FAMILY = {"054c": "ps", "057e": "switch", "28de": "deck", "045e": "xbox"}


def layout_for(name: str) -> str:
    n = name.lower()
    if "nintendo" in n or "pro controller" in n or "joy-con" in n:
        return "switch"
    if any(s in n for s in ("playstation", "dualsense", "dualshock", "sony", "wireless controller")) and "xbox" not in n:
        return "ps"
    return "xbox"


def family_for(name: str, vendor: str = "") -> str:
    """Familia de iconos: primero por fabricante; si no es conocido, por el nombre; en último caso, estilo Xbox."""
    known = VENDOR_FAMILY.get(vendor.lower())
    if known:
        return known
    n = name.lower()
    if "steam" in n or "valve" in n or "deck" in n:
        return "deck"
    return layout_for(name)


def _read(path: Path) -> str:
    try:
        return path.read_text().strip()
    except OSError:
        return ""


def read_battery(uniq: str = "", base: str = "/sys/class/power_supply"):
    """Batería de un mando: {"level": 0-100, "charging": bool} o None si el sistema no la expone.

    Los mandos aparecen en /sys/class/power_supply como baterías de ámbito «Device» (DualSense, DualShock 4,
    Switch Pro por el kernel; muchos Xbox por BlueZ). Se elige la que lleva la dirección del mando en su nombre;
    si no hay coincidencia pero hay una sola batería de periférico, se usa esa. Nunca se confunde con la del portátil.
    """
    try:
        entries = sorted(Path(base).iterdir())
    except OSError:
        return None
    found = []
    for entry in entries:
        if _read(entry / "type") != "Battery" or _read(entry / "scope") != "Device":
            continue
        try:
            level = int(_read(entry / "capacity"))
        except ValueError:
            continue
        found.append((entry.name.lower(), {"level": max(0, min(100, level)),
                                           "charging": _read(entry / "status").lower() == "charging"}))
    if not found:
        return None
    if uniq:
        for name, value in found:
            if uniq.lower() in name:
                return value
    return found[0][1] if len(found) == 1 else None


_MAC_PATH = re.compile(r"^[0-9A-F]{2}(_[0-9A-F]{2}){5}$")


def read_battery_dbus(uniq: str, run=subprocess.run):
    """Batería de un mando Bluetooth que el kernel no expone en sysfs (p. ej. Xbox por BLE), vía UPower o BlueZ.

    Usa `busctl` (viene con systemd), sin dependencias nuevas. UPower da el porcentaje y, si lo sabe, si carga; BlueZ solo
    el porcentaje. Solo se aceptan direcciones MAC bien formadas, que es lo único que acaba en la ruta del bus.
    """
    mac = uniq.upper().replace(":", "_")
    if not _MAC_PATH.match(mac):
        return None

    def get(service, path, interface, prop):
        try:
            out = run(["busctl", "--system", "get-property", service, path, interface, prop],
                      capture_output=True, text=True, timeout=2)
        except (OSError, subprocess.SubprocessError):
            return None
        if out.returncode != 0:
            return None
        parts = out.stdout.split()
        return parts[1] if len(parts) == 2 else None

    base = f"/org/freedesktop/UPower/devices/gaming_input_dev_{mac}"
    percent = get("org.freedesktop.UPower", base, "org.freedesktop.UPower.Device", "Percentage")
    if percent is not None:
        state = get("org.freedesktop.UPower", base, "org.freedesktop.UPower.Device", "State")
        try:
            return {"level": max(0, min(100, int(float(percent)))), "charging": state == "1"}
        except ValueError:
            pass
    percent = get("org.bluez", f"/org/bluez/hci0/dev_{mac}", "org.bluez.Battery1", "Percentage")
    try:
        return {"level": max(0, min(100, int(percent))), "charging": False} if percent is not None else None
    except ValueError:
        return None


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
        uniq = re.search(r'U: Uniq=(\S*)', block)
        ids = re.search(r"I: Bus=\w+ Vendor=(\w+) Product=(\w+)", block)
        vendor, product = (ids.group(1).lower(), ids.group(2).lower()) if ids else ("", "")
        ev, js = re.search(r"\bevent(\d+)\b", h.group(1)), re.search(r"\bjs\d+\b", h.group(1))
        if ev and js:
            family = family_for(name.group(1), vendor)
            # el Steam Deck envía los botones como un Xbox; Sony y Nintendo conservan su disposición
            layout = family if family in ("ps", "switch") else layout_for(name.group(1))
            out.append(Device(name.group(1), f"{dev_dir}/event{ev.group(1)}", layout, family, vendor, product,
                              uniq.group(1).lower() if uniq else ""))
    return out


class PadLogic:
    """Traduce eventos de evdev a teclas lógicas. Sin E/S ni reloj propio: el tiempo se pasa como argumento."""
    REPEAT_FIRST, REPEAT_NEXT = 0.40, 0.12
    STICK, TRIGGER = 0.5, 0.5

    def __init__(self, layout: str = "xbox", deadzone: float = 0.15):
        self.buttons = BUTTONS.get(layout, BUTTONS["xbox"])
        self.set_deadzone(deadzone)
        self.src = {}                  # origen («stickx», «hatx», …) -> dirección activa o None
        self.held = {}                 # dirección -> instante del próximo repetido
        self.trig = {"LT": False, "RT": False}

    def set_deadzone(self, deadzone: float) -> None:
        """La zona muerta del stick fija también cuánto hay que inclinarlo para navegar: 0,35 + zona muerta (con 0,15, el 0,5 de siempre)."""
        self.stick = max(0.4, min(0.9, 0.35 + float(deadzone)))

    def _dir(self, source, v):
        horizontal = source in ("stickx", "hatx")
        if v <= -self.stick:
            return "l" if horizontal else "u"
        if v >= self.stick:
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


def ff_rumble_effect(strong: float, weak: float, ms: int, effect_id: int = -1) -> bytes:
    """struct ff_effect (48 bytes) de tipo FF_RUMBLE con motores fuerte y débil entre 0 y 1."""
    mag = lambda v: max(0, min(65535, int(round(float(v) * 65535))))
    length = max(1, min(5000, int(ms)))
    return struct.pack("<HhHHHHH2xHH28x", FF_RUMBLE, effect_id, 0, 0, 0, length, 0, mag(strong), mag(weak))


def rumble_device(path: str, strong: float, weak: float, ms: int) -> None:
    """Hace vibrar un mando ya detectado (el hilo que llama es el que espera a que termine). OSError si no lo admite."""
    ms = max(1, min(1500, int(ms)))
    fd = os.open(path, os.O_RDWR | os.O_NONBLOCK)
    try:
        buf = bytearray(ff_rumble_effect(strong, weak, ms))
        fcntl.ioctl(fd, EVIOCSFF, buf, True)                      # el núcleo escribe en el campo «id» el efecto asignado
        effect_id = struct.unpack_from("<h", buf, 2)[0]
        os.write(fd, EVENT.pack(0, 0, EV_FF, effect_id, 1))
        time.sleep(ms / 1000 + 0.05)
        try:
            fcntl.ioctl(fd, EVIOCRMFF, effect_id)
        except OSError:
            pass
    finally:
        os.close(fd)


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

    def __init__(self, bus, gate=lambda: True, devices_file="/proc/bus/input/devices", log=lambda *a: None, dev_dir="/dev/input",
                 power_dir="/sys/class/power_supply", dbus_battery=read_battery_dbus):
        super().__init__(daemon=True, name="omnia-pad")
        self.bus, self.gate, self.devices_file, self.log, self.dev_dir = bus, gate, devices_file, log, dev_dir
        self.power_dir, self.dbus_battery = power_dir, dbus_battery
        self._dbus_cache = {}       # dirección -> (instante, valor): el bus se consulta cada 20 s como máximo
        self.stop_event = threading.Event()
        self.open = {}          # fd -> (Device, PadLogic, {código: absinfo})
        self.uniq_by_path = {}
        self.allinfo = {}       # fd -> {código: absinfo} de todos los ejes (para la pantalla de prueba)
        self.state = {}         # fd -> {"buttons": {códigos pulsados}, "axes": {código: valor normalizado}}
        self.settings = {}      # clave del mando (dirección o nombre) -> {nickname, family, deadzone, haptics}
        self.haptic = rumble_device
        self._haptic_at = 0.0

    def _open(self, dev: Device):
        fd = os.open(dev.path, os.O_RDONLY | os.O_NONBLOCK)
        info = {}
        for code in (ABS_X, ABS_Y, ABS_RX, ABS_RY, ABS_Z, ABS_RZ, ABS_GAS, ABS_BRAKE, ABS_HAT0X, ABS_HAT0Y):
            try:
                info[code] = ABSINFO.unpack(fcntl.ioctl(fd, EVIOCGABS(code), bytes(ABSINFO.size)))
            except OSError:
                pass
        self.allinfo[fd] = dict(info)
        self.state[fd] = {"buttons": set(), "axes": {}}
        info.pop(ABS_RX, None)                  # la navegación solo usa el stick izquierdo, la cruceta y los gatillos
        info.pop(ABS_RY, None)
        if ABS_GAS in info or ABS_BRAKE in info:
            # Xbox por Bluetooth: los gatillos son GAS/BRAKE y ABS_Z/ABS_RZ son el stick derecho (no se usa para navegar)
            info.pop(ABS_Z, None)
            info.pop(ABS_RZ, None)
        self.open[fd] = (dev, PadLogic(dev.layout, self.settings_for(dev).get("deadzone", 0.15)), info)
        self.uniq_by_path[dev.path] = dev.uniq

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
        battery = read_battery(first[0].uniq, self.power_dir) if first else None
        if first and battery is None and first[0].uniq:
            battery = self._battery_from_bus(first[0].uniq)
        self.bus.set_pad(bool(first), first[0].name if first else "", first[0].layout if first else "",
                         self.effective_family(first[0]) if first else "", battery)

    # --- ajustes por mando, estado en vivo y vibración (pantalla «Mandos» de Big Mode) ------------------------------------------------
    @staticmethod
    def key_of(dev: Device) -> str:
        return dev.uniq or dev.name

    def settings_for(self, dev: Device) -> dict:
        return self.settings.get(self.key_of(dev)) or {}

    def effective_family(self, dev: Device) -> str:
        forced = self.settings_for(dev).get("family")
        return forced if forced in FAMILIES else dev.family

    def configure(self, settings: dict) -> None:
        """Aplica los ajustes guardados (también a los mandos ya abiertos)."""
        self.settings = settings if isinstance(settings, dict) else {}
        for dev, logic, _ in list(self.open.values()):
            logic.set_deadzone(self.settings_for(dev).get("deadzone", 0.15))

    def snapshot(self) -> list:
        """Mandos abiertos con su estado actual: botones pulsados (etiquetas), sticks, gatillos y cruceta (−1…1; gatillos 0…1)."""
        out = []
        for fd, (dev, _, _) in list(self.open.items()):
            st, info = self.state.get(fd) or {"buttons": set(), "axes": {}}, self.allinfo.get(fd) or {}
            cfg = self.settings_for(dev)
            dz = float(cfg.get("deadzone", 0.15))
            labels = dict(BUTTONS.get(dev.layout, BUTTONS["xbox"]))
            labels.update({BTN_THUMBL: "LS", BTN_THUMBR: "RS"})
            axes = st["axes"]
            val = lambda code: axes.get(code, 0.0)
            zone = lambda v: 0.0 if abs(v) < dz else round(v, 3)
            xbox_bt = ABS_GAS in info or ABS_BRAKE in info
            right = (ABS_Z, ABS_RZ) if xbox_bt else (ABS_RX, ABS_RY)
            trig = (ABS_GAS, ABS_BRAKE) if xbox_bt else (ABS_Z, ABS_RZ)
            out.append({"id": dev.path, "key": self.key_of(dev), "name": dev.name, "nickname": cfg.get("nickname", ""),
                        "family": self.effective_family(dev), "detectedFamily": dev.family, "layout": dev.layout,
                        "battery": read_battery(dev.uniq, self.power_dir) if dev.uniq else None, "deadzone": dz,
                        "haptics": bool(cfg.get("haptics", False)),
                        "buttons": sorted(labels[c] for c in st["buttons"] if c in labels),
                        "lx": zone(val(ABS_X)), "ly": zone(val(ABS_Y)), "rx": zone(val(right[0])), "ry": zone(val(right[1])),
                        "lt": round(max(0.0, val(trig[0])), 3), "rt": round(max(0.0, val(trig[1])), 3),
                        "hatx": round(val(ABS_HAT0X)), "haty": round(val(ABS_HAT0Y))})
        return out

    def rumble(self, path: str, strong: float = 0.7, weak: float = 0.7, ms: int = 350) -> None:
        """Vibra un mando ya detectado (la ruta debe ser una de las abiertas). OSError si no admite vibración."""
        if path not in {d.path for d, _, _ in self.open.values()}:
            raise OSError("mando desconocido")
        self.haptic(path, strong, weak, ms)

    def _haptic_pulse(self, key: str):
        """Vibración suave al pulsar en la interfaz (solo en mandos con «vibración» activada)."""
        pulse = {"A": (0.0, 0.30, 35), "LT": (0.2, 0.0, 30), "RT": (0.2, 0.0, 30)}.get(key)
        now = time.monotonic()
        if not pulse or now - self._haptic_at < 0.12:
            return
        for dev, _, _ in list(self.open.values()):
            if self.settings_for(dev).get("haptics"):
                self._haptic_at = now
                threading.Thread(target=lambda p=dev.path: self._safe_haptic(p, *pulse), daemon=True).start()
                break

    def _safe_haptic(self, path, strong, weak, ms):
        try:
            self.haptic(path, strong, weak, ms)
        except OSError:
            pass

    def _battery_from_bus(self, uniq: str):
        now = time.monotonic()
        cached = self._dbus_cache.get(uniq)
        if cached is None or now - cached[0] > 20.0:
            cached = (now, self.dbus_battery(uniq))
            self._dbus_cache[uniq] = cached
        return cached[1]

    def _close(self, fd):
        dev = self.open.pop(fd)[0]
        self.allinfo.pop(fd, None)
        self.state.pop(fd, None)
        try:
            os.close(fd)
        except OSError:
            pass
        self.log(f"mando desconectado: {dev.name}")

    def _emit(self, keys):
        if keys and self.gate():
            for k in keys:
                self.bus.push(k)
                self._haptic_pulse(k)

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
                st, allinfo = self.state.get(fd), self.allinfo.get(fd, {})
                for i in range(0, len(data) - EVENT.size + 1, EVENT.size):
                    _, _, etype, code, value = EVENT.unpack_from(data, i)
                    if st is not None:                       # estado en vivo para la pantalla de prueba de mandos
                        if etype == EV_KEY:
                            (st["buttons"].add if value else st["buttons"].discard)(code)
                        elif etype == EV_ABS and code in allinfo:
                            st["axes"][code] = normalize(code, value, allinfo[code])
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

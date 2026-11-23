"""Datos del equipo para el panel «Sistema»: procesador, discos, batería, perfil térmico y ventiladores.

Solo lee /proc y /sys (la carga, las temperaturas y la VRAM las da KDE por KSysGuard en la UI). Las rutas son
parámetros para poder probarlo con árboles falsos.
"""
from __future__ import annotations

import glob
import json
import os
import re
import subprocess
import time
from pathlib import Path


def _read(path: str) -> str:
    try:
        return Path(path).read_text().strip()
    except OSError:
        return ""


def short_cpu_name(model: str) -> str:
    """'Intel(R) Core(TM) i5-10300H CPU @ 2.50GHz' -> 'i5-10300H'; 'AMD Ryzen 7 5800X 8-Core Processor' -> 'Ryzen 7 5800X'."""
    m = re.search(r"\b(i[3579]-\w+|Core\s*Ultra\s*\d+\s*\w+)", model, re.IGNORECASE)
    if m:
        return m.group(1)
    m = re.search(r"(Ryzen\s+\d+\s+\w+)", model, re.IGNORECASE)
    if m:
        return m.group(1)
    m = re.search(r"(EPYC\s+\w+|Threadripper\s+\w+)", model, re.IGNORECASE)
    if m:
        return m.group(1)
    return re.sub(r"\s+", " ", re.sub(r"\((?:R|TM)\)|\bCPU\b|@.*$|\bProcessor\b", "", model)).strip()[:24]


def cpu(proc: str = "/proc", sys_root: str = "/sys") -> dict:
    out: dict = {}
    for line in _read(f"{proc}/cpuinfo").splitlines():
        if line.lower().startswith("model name"):
            out["model"] = short_cpu_name(line.partition(":")[2].strip())
            break
    freqs = []
    for f in glob.glob(f"{sys_root}/devices/system/cpu/cpu[0-9]*/cpufreq/scaling_cur_freq"):
        v = _read(f)
        if v.isdigit():
            freqs.append(int(v))
    if freqs:
        out["ghz"] = round(sum(freqs) / len(freqs) / 1e6, 2)
    return out


def fs_type(path: str, proc: str = "/proc") -> str:
    """Tipo de sistema de archivos que contiene `path` (mayor prefijo de /proc/mounts)."""
    real = os.path.realpath(path)
    best, kind = "", ""
    for line in _read(f"{proc}/mounts").splitlines():
        parts = line.split()
        if len(parts) < 3:
            continue
        mnt = parts[1].replace("\\040", " ")
        if (real == mnt or real.startswith(mnt.rstrip("/") + "/")) and len(mnt) >= len(best):
            best, kind = mnt, parts[2]
    return kind


def games_dir(home: str | None = None, configured: str = "") -> str:
    home = home or os.path.expanduser("~")
    for c in ([os.path.expanduser(configured)] if configured else []) + [f"{home}/Juegos", f"{home}/Games"]:
        if os.path.isdir(c):
            return c
    return home


def disk(path: str, proc: str = "/proc") -> dict:
    try:
        st = os.statvfs(path)
    except OSError:
        return {}
    total = st.f_blocks * st.f_frsize
    if total <= 0:
        return {}
    return {"used": total - st.f_bavail * st.f_frsize, "total": total, "fs": fs_type(path, proc), "path": path}


def battery(sys_root: str = "/sys") -> dict:
    out: dict = {}
    for b in sorted(glob.glob(f"{sys_root}/class/power_supply/BAT*")):
        pct = _read(b + "/capacity")
        if pct.isdigit():
            out["bat"] = {"pct": int(pct), "status": _read(b + "/status")}
            break
    supplies = glob.glob(f"{sys_root}/class/power_supply/AC*") + glob.glob(f"{sys_root}/class/power_supply/ADP*")
    out["ac"] = any(_read(a + "/online") == "1" for a in supplies)
    return out


def platform_profile(sys_root: str = "/sys") -> str:
    """Perfil térmico/energético ACPI expuesto por el firmware, si existe."""
    profile = _read(f"{sys_root}/firmware/acpi/platform_profile").lower()
    labels = {"quiet": "Silencioso", "balanced": "Equilibrado", "low-power": "Ahorro", "performance": "Rendimiento"}
    return labels.get(profile, profile.replace("-", " ").capitalize() if profile else "No disponible")


def fan_speeds(sys_root: str = "/sys") -> list[dict]:
    """Lecturas de ventilador válidas; varios firmwares reportan cero cuando no ofrecen RPM."""
    out = []
    for path in sorted(glob.glob(f"{sys_root}/class/hwmon/hwmon*/fan*_input")):
        raw = _read(path)
        if not raw.isdigit() or int(raw) <= 0:
            continue
        name = _read(path[:-6] + "_label")
        if not name:
            match = re.search(r"fan(\d+)_input$", path)
            name = "Ventilador " + (match.group(1) if match else "")
        out.append({"name": name, "rpm": int(raw)})
    return out


_cpu_prev: tuple | None = None
_gpu_cache = (0.0, (None, None))


def _cpu_times(proc: str):
    first = _read(f"{proc}/stat").split("\n", 1)[0].split()
    if len(first) < 5 or first[0] != "cpu":
        return None
    vals = [int(x) for x in first[1:9] if x.isdigit()]
    idle = vals[3] + (vals[4] if len(vals) > 4 else 0)       # idle + iowait
    return sum(vals), idle


def cpu_percent(proc: str = "/proc"):
    """Uso de CPU desde la lectura anterior (None en la primera llamada)."""
    global _cpu_prev
    now = _cpu_times(proc)
    prev, _cpu_prev = _cpu_prev, now
    if not now or not prev or now[0] <= prev[0]:
        return None
    return round(100 * (1 - (now[1] - prev[1]) / (now[0] - prev[0])), 1)


def memory(proc: str = "/proc") -> dict:
    info = {}
    for line in _read(f"{proc}/meminfo").splitlines():
        k, _, v = line.partition(":")
        m = re.match(r"\s*(\d+)", v)
        if m:
            info[k] = int(m.group(1)) * 1024
    total, avail = info.get("MemTotal", 0), info.get("MemAvailable", info.get("MemFree", 0))
    return {"ram_total": total, "ram_used": max(0, total - avail)} if total else {}


def _hwmon_temp(names: tuple, prefer: tuple = (), sys_root: str = "/sys"):
    """°C de un sensor hwmon cuyo `name` esté en `names`; entre sus lecturas prefiere la etiqueta que contenga alguna de `prefer`."""
    best = None
    for hw in sorted(glob.glob(f"{sys_root}/class/hwmon/hwmon*")):
        if _read(f"{hw}/name").strip() not in names:
            continue
        for path in sorted(glob.glob(f"{hw}/temp*_input")):
            raw = _read(path).strip()
            if not raw.lstrip("-").isdigit():
                continue
            value = int(raw) / 1000.0
            label = _read(path.replace("_input", "_label")).strip().lower()
            if any(p in label for p in prefer):
                return round(value, 1)
            best = best if best is not None else round(value, 1)
    return best


def cpu_temperature(sys_root: str = "/sys"):
    """Temperatura del procesador: coretemp (Intel, «Package id 0») o k10temp/zenpower (AMD, «Tctl»/«Tdie»); None si no hay sensor."""
    return _hwmon_temp(("coretemp", "k10temp", "zenpower", "cpu_thermal"), ("package", "tctl", "tdie"), sys_root)


def _number(text):
    """Número de una celda de nvidia-smi («28», «55.31») o None."""
    try:
        return float(str(text).strip())
    except ValueError:
        return None


def gpu_stats(sys_root: str = "/sys", run=subprocess.run, ttl: float = 2.0, now=time.monotonic):
    """(uso %, temperatura °C) de la GPU: sysfs/hwmon de AMD/Intel si existe; si no, una sola consulta a nvidia-smi. Se cachea unos segundos."""
    global _gpu_cache
    t = now()
    if t - _gpu_cache[0] < ttl:
        return _gpu_cache[1]
    value, temp = None, None
    for path in sorted(glob.glob(f"{sys_root}/class/drm/card*/device/gpu_busy_percent")):
        raw = _read(path)
        if raw.isdigit():
            value = float(raw)
            temp = _hwmon_temp(("amdgpu",), ("edge",), sys_root)
            break
    if value is None:
        try:
            out = run(["nvidia-smi", "--query-gpu=utilization.gpu,temperature.gpu", "--format=csv,noheader,nounits"],
                      capture_output=True, text=True, timeout=1.5)
            first = out.stdout.strip().splitlines()[0] if out.returncode == 0 and out.stdout.strip() else ""
            parts = [x.strip() for x in first.split(",")]
            value = _number(parts[0]) if parts else None
            temp = _number(parts[1]) if len(parts) > 1 else None             # el controlador puede dar decimales («55.31»)
        except (OSError, subprocess.SubprocessError, ValueError, IndexError):
            value = temp = None
    _gpu_cache = (t, (value, temp))
    return value, temp


def gpu_percent(sys_root: str = "/sys", run=subprocess.run, ttl: float = 2.0, now=time.monotonic):
    """Uso de la GPU (ver `gpu_stats`)."""
    return gpu_stats(sys_root, run, ttl, now)[0]


def live(proc: str = "/proc", sys_root: str = "/sys") -> dict:
    """Carga en vivo para la barra superior de la biblioteca: CPU %, GPU %, RAM y las temperaturas de CPU y GPU."""
    out = dict(memory(proc))
    c, (g, gt) = cpu_percent(proc), gpu_stats(sys_root)
    ct = cpu_temperature(sys_root)
    for key, value in (("cpu_pct", c), ("gpu_pct", g), ("cpu_temp", ct), ("gpu_temp", gt)):
        if value is not None:
            out[key] = value
    return out


def snapshot(games: str = "", proc: str = "/proc", sys_root: str = "/sys", home: str | None = None, monitor=None) -> dict:
    out = {"cpu": cpu(proc, sys_root)}
    if isinstance(monitor, list):
        selected = [selected_volume(item) for item in monitor]
        out["disks"] = []
        for item, volume in zip(monitor, selected):
            d = disk(volume["path"], proc) if volume else {"label": item.get("label", "Disco"), "available": False}
            if volume:
                d["label"] = volume["label"]
            out["disks"].append(d)
        if out["disks"]:
            out["disk"] = out["disks"][0]  # compatibilidad con layouts anteriores
    else:
        selected = selected_volume(monitor) if monitor else None
        d = disk(selected["path"], proc) if selected else ({} if monitor else disk(games_dir(home, games), proc))
        if d and selected:
            d["label"] = selected["label"]
        elif monitor:
            d = {"label": monitor.get("label", "Disco"), "available": False}
        if d:
            out["disk"] = d
    out.update(battery(sys_root))
    out["profile"] = platform_profile(sys_root)
    out["fans"] = fan_speeds(sys_root)
    return out


_volume_cache = (0, [])

def selected_volume(selected):
    """Resuelve UUID de nuevo: si el disco se desconecta, nunca muestra otro volumen."""
    global _volume_cache
    now = time.monotonic()
    if now - _volume_cache[0] > 15:
        try:
            data = json.loads(subprocess.check_output(["lsblk", "-J", "-o", "NAME,LABEL,UUID,MODEL,MOUNTPOINTS"], text=True, timeout=3))
            entries = []
            def visit(nodes, model=""):
                for n in nodes:
                    current_model = (n.get("model") or model).strip()
                    mounts = [p for p in n.get("mountpoints", []) if p and p.startswith("/")]
                    if mounts:
                        entries.append({"uuid": n.get("uuid") or "", "path": min(mounts, key=len),
                                        "label": n.get("label") or f"{current_model or 'Disco'} · {n['name']}"})
                    visit(n.get("children", []), current_model)
            visit(data["blockdevices"])
            _volume_cache = (now, entries)
        except (OSError, ValueError, subprocess.SubprocessError):
            _volume_cache = (now, [])
    return next((v for v in _volume_cache[1] if (v["uuid"] == selected["uuid"] if selected.get("uuid") else v["path"] == selected.get("path"))), None)

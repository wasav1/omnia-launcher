"""Datos del equipo para el panel «Sistema»: modelo y frecuencia de la CPU, disco de los juegos y batería.

Solo lee /proc y /sys (la carga, las temperaturas y la VRAM las da KDE por KSysGuard en la UI). Las rutas son
parámetros para poder probarlo con árboles falsos.
"""
from __future__ import annotations

import glob
import os
import re
from pathlib import Path


def _read(path: str) -> str:
    try:
        return Path(path).read_text().strip()
    except OSError:
        return ""


def short_cpu_name(model: str) -> str:
    """'Intel(R) Core(TM) i5-10300H CPU @ 2.50GHz' -> 'i5-10300H'; 'AMD Ryzen 7 5800X 8-Core Processor' -> 'Ryzen 7 5800X'."""
    m = re.search(r"\b(i[3579]-\w+|Core\s*Ultra\s*\d+\s*\w+)", model, re.I)
    if m:
        return m.group(1)
    m = re.search(r"(Ryzen\s+\d+\s+\w+)", model, re.I)
    if m:
        return m.group(1)
    m = re.search(r"(EPYC\s+\w+|Threadripper\s+\w+)", model, re.I)
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


def snapshot(games: str = "", proc: str = "/proc", sys_root: str = "/sys", home: str | None = None) -> dict:
    out = {"cpu": cpu(proc, sys_root)}
    d = disk(games_dir(home, games), proc)
    if d:
        out["disk"] = d
    out.update(battery(sys_root))
    return out

"""Perfil de energía del sistema con `powerprofilesctl` (power-profiles-daemon, sin sudo) y estado del tope de CPU.

Omnia solo cambia el perfil cuando el usuario lo pide (Ajustes o el Menú rápido de Big Mode). El tope de frecuencia
del procesador lo manejan los scripts del usuario (p. ej. su control térmico al jugar): aquí solo se lee para mostrarlo.
"""
import re
import shutil
import subprocess
from pathlib import Path

PROFILES = ("power-saver", "balanced", "performance")
_LIST_TIMEOUT = 4


class PowerProfileError(Exception):
    pass


def _run(args, run=subprocess.run):
    tool = shutil.which("powerprofilesctl")
    if not tool:
        raise PowerProfileError("powerprofilesctl no está instalado (paquete power-profiles-daemon).")
    try:
        done = run([tool, *args], capture_output=True, text=True, timeout=_LIST_TIMEOUT)
    except (OSError, subprocess.SubprocessError) as exc:
        raise PowerProfileError(f"No se pudo usar powerprofilesctl: {exc}") from exc
    if done.returncode != 0:
        raise PowerProfileError((done.stderr or done.stdout or "powerprofilesctl falló").strip()[:300])
    return done.stdout


def parse_list(text: str):
    """Salida de `powerprofilesctl list` → (perfiles disponibles en orden, perfil activo)."""
    available, current = [], ""
    for line in (text or "").splitlines():
        match = re.match(r"^\s*(\*)?\s*([a-z-]+):\s*$", line)
        if match and match.group(2) in PROFILES:
            available.append(match.group(2))
            if match.group(1):
                current = match.group(2)
    ordered = [p for p in PROFILES if p in available]
    return ordered, current


def status(run=subprocess.run) -> dict:
    """{available, profiles, current, error}. Nunca lanza: si no hay daemon, `available` es False."""
    try:
        profiles, current = parse_list(_run(["list"], run))
        return {"available": bool(profiles), "profiles": profiles, "current": current, "error": ""}
    except PowerProfileError as exc:
        return {"available": False, "profiles": [], "current": "", "error": str(exc)}


def set_profile(profile: str, run=subprocess.run) -> dict:
    if profile not in PROFILES:
        raise PowerProfileError("Perfil de energía desconocido.")
    _run(["set", profile], run)
    return status(run)


def _khz(path: Path) -> int:
    try:
        return int(path.read_text().strip())
    except (OSError, ValueError):
        return 0


def cpu_cap(sys_root: str = "/sys") -> dict:
    """{limit_mhz, max_mhz, capped}: frecuencia máxima permitida ahora frente a la del procesador (CPU 0)."""
    base = Path(sys_root) / "devices/system/cpu/cpu0/cpufreq"
    limit, top = _khz(base / "scaling_max_freq"), _khz(base / "cpuinfo_max_freq")
    return {"limit_mhz": limit // 1000, "max_mhz": top // 1000, "capped": bool(limit and top and limit < top - 50_000)}

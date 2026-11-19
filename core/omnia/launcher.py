"""Lanzamiento de juegos como unidades transitorias de systemd --user.

Cada juego va en su propio scope, fuera del cgroup del servicio: sobrevive a reinicios de omnia-core sin
depender de KillMode=process, y systemd puede listar y detener lo que Omnia lanzó (systemctl --user status).
"""
import os
import re
import shutil
import subprocess
import time
from pathlib import Path


def _unit_name(gid: str) -> str:
    return 'omnia-game-{}-{:d}'.format(re.sub(r"[^A-Za-z0-9]+", "-", gid)[:40].strip("-"), int(time.time()))


def build_command(argv: list, gid: str) -> list:
    if shutil.which("systemd-run"):
        return ["systemd-run", "--user", "--scope", "--quiet", "--collect", "--unit=" + _unit_name(gid), "--"] + list(argv)
    return list(argv)


def _longshot_play(argv: list, cwd: str | None) -> list:
    """Longshot's game-folder wrapper uses --launch (opens its UI); use --play to start the game."""
    if not argv or Path(argv[0]).name != "longshot":
        return argv
    wrapper = Path(os.path.expanduser(argv[0]))
    marker = wrapper.parent / "longshot_version.txt"
    try:
        builder = next((line.partition("=")[2].strip() for line in marker.read_text(errors="replace").splitlines()
                        if line.startswith("builder=") and line.partition("=")[2].strip()), "")
    except OSError:
        return argv
    if not builder or not os.path.isfile(builder) or not os.access(builder, os.X_OK):
        return argv
    game_dir = os.path.abspath(os.path.expanduser(cwd or str(wrapper.parent)))
    return [builder, "--play", game_dir]


def launch(port: dict, gid: str, env: dict | None = None) -> subprocess.Popen:
    argv = port.get("launch") or []
    if not argv or not all(isinstance(a, str) for a in argv):
        raise ValueError("el port no tiene un comando de lanzamiento válido")
    cwd = os.path.expanduser(port.get("cwd") or "") or None
    argv = _longshot_play(argv, cwd)
    process_env = {**os.environ, **(env or {})}
    # AppImage normally mounts its SquashFS through fusermount, whose setuid
    # elevation is blocked by omnia.service's NoNewPrivileges=true. Extract to
    # a temporary directory instead; this keeps the service hardening enabled.
    process_env["APPIMAGE_EXTRACT_AND_RUN"] = "1"
    if process_env.pop("OMNIA_MANGOHUD", "") == "1":
        mangohud = shutil.which("mangohud")
        if not mangohud:
            raise ValueError("MangoHud no está instalado. Instálalo desde el gestor de paquetes y vuelve a intentarlo.")
        argv = [mangohud, "--dlsym", *argv]
    return subprocess.Popen(build_command([os.path.expanduser(a) if a.startswith("~/") else a for a in argv], gid),
                            cwd=cwd, env=process_env, start_new_session=True,
                            stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)

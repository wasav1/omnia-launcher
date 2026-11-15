"""Lanzamiento de juegos como unidades transitorias de systemd --user.

Cada juego va en su propio scope, fuera del cgroup del servicio: sobrevive a reinicios de omnia-core sin
depender de KillMode=process, y systemd puede listar y detener lo que Omnia lanzó (systemctl --user status).
"""
import os
import re
import shutil
import subprocess
import time


def _unit_name(gid: str) -> str:
    return "omnia-game-%s-%d" % (re.sub(r"[^A-Za-z0-9]+", "-", gid)[:40].strip("-"), int(time.time()))


def build_command(argv: list, gid: str) -> list:
    if shutil.which("systemd-run"):
        return ["systemd-run", "--user", "--scope", "--quiet", "--collect", "--unit=" + _unit_name(gid), "--"] + list(argv)
    return list(argv)


def launch(port: dict, gid: str, env: dict | None = None) -> subprocess.Popen:
    argv = port.get("launch") or []
    if not argv or not all(isinstance(a, str) for a in argv):
        raise ValueError("el port no tiene un comando de lanzamiento válido")
    cwd = os.path.expanduser(port.get("cwd") or "") or None
    return subprocess.Popen(build_command([os.path.expanduser(a) if a.startswith("~/") else a for a in argv], gid),
                            cwd=cwd, env={**os.environ, **(env or {})}, start_new_session=True,
                            stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)

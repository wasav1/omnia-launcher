"""Salida de audio (botón del altavoz): lista los dispositivos de PipeWire/PulseAudio y cambia el predeterminado.

Usa `pactl`. La petición solo puede elegir entre los dispositivos y puertos que `pactl` lista: nunca se pasa texto
arbitrario a la orden. Lo que ya suena se mueve al nuevo dispositivo.
"""
from __future__ import annotations

import json
import os
import shutil
import subprocess


class AudioOutError(Exception):
    pass


def _pactl(*args, run=subprocess.run) -> str:
    if not shutil.which("pactl") and run is subprocess.run:
        raise AudioOutError("pactl no está instalado (paquete pipewire-pulse o pulseaudio-utils)")
    try:
        r = run(["pactl", *args], capture_output=True, text=True, timeout=8, env=dict(os.environ, LC_ALL="C"))
    except (OSError, subprocess.SubprocessError) as e:
        raise AudioOutError(str(e))
    if r.returncode:
        detail = (r.stderr or r.stdout or "").strip()
        raise AudioOutError(detail or f"pactl terminó con código {r.returncode}")
    return r.stdout


def kind_of(name: str) -> str:
    n = name.lower()
    return "hdmi" if "hdmi" in n else ("usb" if "usb" in n else ("bt" if "bluez" in n else "analog"))


def list_outputs(run=subprocess.run) -> list:
    """Una entrada por dispositivo (y por puerto disponible si tiene varios): {sink, port, label, current, kind}."""
    default = _pactl("get-default-sink", run=run).strip()
    try:
        sinks = json.loads(_pactl("-f", "json", "list", "sinks", run=run) or "[]")
    except ValueError:
        raise AudioOutError("respuesta de pactl no válida")
    items = []
    for sk in sinks:
        name = sk.get("name", "")
        if not name:
            continue
        desc = (sk.get("properties") or {}).get("device.description") or sk.get("description") or name
        ports = [p for p in sk.get("ports", []) if p.get("availability") != "not available"]
        multi = len(ports) > 1
        shown = ports if (multi or (ports and ports[0].get("description") not in (None, "", "(null)"))) else [None]
        for p in shown:
            label = desc
            if p and p.get("description") not in (None, "", "(null)"):
                label = desc + " · " + p["description"]
            current = name == default and (not p or not multi or sk.get("active_port") == p["name"])
            items.append({"sink": name, "port": p["name"] if p and multi else "", "label": label,
                          "current": current, "kind": kind_of(name)})
    return items


def set_output(sink: str, port: str = "", run=subprocess.run) -> None:
    """Cambia la salida predeterminada. Lanza AudioOutError si (sink, port) no es uno de los listados."""
    valid = [i for i in list_outputs(run) if i["sink"] == sink and i["port"] == (port or "")]
    if not valid:
        raise AudioOutError("dispositivo de audio no válido")
    _pactl("set-default-sink", sink, run=run)
    if port:
        _pactl("set-sink-port", sink, port, run=run)
    for line in _pactl("list", "short", "sink-inputs", run=run).splitlines():      # lo que ya suena pasa al nuevo dispositivo
        parts = line.split()
        if parts and parts[0].isdigit():
            _pactl("move-sink-input", parts[0], sink, run=run)

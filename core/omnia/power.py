"""Energía y sesión (Big Menu): bloquear, suspender, cerrar sesión, reiniciar y apagar.

Solo existen las cinco acciones de la lista; la petición nunca aporta el comando. La confirmación de las tres
destructivas (cerrar sesión, reiniciar, apagar) la pide la UI antes de llamar.
"""
from __future__ import annotations

import subprocess

COMMANDS = {
    "lock": ["loginctl", "lock-session"],
    "suspend": ["systemctl", "suspend"],
    "logout": ["gdbus", "call", "--session", "--dest", "org.kde.Shutdown", "--object-path", "/Shutdown",
               "--method", "org.kde.Shutdown.logout"],
    "reboot": ["systemctl", "reboot"],
    "shutdown": ["systemctl", "poweroff"],
}
CONFIRM = frozenset({"logout", "reboot", "shutdown"})


def run(action: str, spawn=subprocess.Popen) -> bool:
    """Ejecuta la acción sin esperar. False si la acción no existe."""
    cmd = COMMANDS.get(action)
    if not cmd:
        return False
    spawn(cmd, start_new_session=True, stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    return True

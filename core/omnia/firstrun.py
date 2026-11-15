"""omnia-first-run: primer arranque de Omnia en la sesión del usuario.

Lo lanza un autostart de XDG en cada inicio de sesión de KDE y solo actúa la primera vez:
  1. Explica qué va a cambiar en KDE (Win+D, dos scripts de KWin) y pide consentimiento con un cuadro de diálogo.
  2. Si aceptas, aplica `omnia-setup` (reversible con `omnia-setup --undo`). Si no, no toca nada y no vuelve a preguntar.
  3. Habilita y arranca los servicios de usuario (omnia-core y omnia-ui).
El resultado se guarda en ~/.config/omnia/first-run.json. Un paquete de pacman no puede hacer nada de esto: corre como
root y sin sesión de usuario.
"""
import argparse
import shutil
import subprocess
import sys
import time
from pathlib import Path

from . import paths, setup
from .store import load_json, write_json_atomic

SERVICES = ("omnia.service", "omnia-ui.service")
MARKER = "first-run.json"
TITLE = "Omnia"


def message(todo: list) -> str:
    items = "\n".join("• " + t for t in todo)
    return ("Omnia necesita configurar KDE para funcionar como escritorio de juegos:\n\n%s\n\n"
            "Es reversible: puedes deshacerlo cuando quieras con «omnia-setup --undo»." % items)


def kdialog_ask(text: str):
    """True/False según la respuesta; None si no hay kdialog."""
    if not shutil.which("kdialog"):
        return None
    r = subprocess.run(["kdialog", "--title", TITLE, "--yes-label", "Configurar", "--no-label", "Ahora no", "--yesno", text])
    return r.returncode == 0


def systemctl_enable(services=SERVICES) -> bool:
    try:
        r = subprocess.run(["systemctl", "--user", "enable", "--now", *services], capture_output=True, text=True, timeout=30)
    except (OSError, subprocess.TimeoutExpired):
        return False
    return r.returncode == 0


def notify(text: str) -> None:
    if shutil.which("kdialog"):
        subprocess.run(["kdialog", "--title", TITLE, "--passivepopup", text, "6"], check=False)


def run(config: Path, backend, ask=kdialog_ask, enable=systemctl_enable, script_src=None, force=False, yes=False,
        services=True, say=print) -> str:
    """Devuelve el resultado: «applied», «declined», «error», «already» (nada que cambiar) o «done» (ya se había hecho)."""
    config = Path(config)
    marker = config / MARKER
    if marker.exists() and not force:
        return "done"
    result, detail = "already", ""
    try:
        todo = setup.plan(backend, config)
        if todo:
            answer = True if yes else ask(message(todo))
            if answer is None:
                result = "declined"
                detail = "sin kdialog: no se pudo pedir consentimiento. Ejecuta «omnia-setup» en una terminal."
            elif answer:
                setup.apply(backend, config, script_src)
                result = "applied"
            else:
                result = "declined"
    except setup.SetupError as e:
        result, detail = "error", str(e)
    if result == "declined":
        say("Configuración de KDE omitida. Cuando quieras: omnia-setup")
    if result == "error":
        say("Error en la configuración: %s" % detail)
    started = enable() if services else None
    write_json_atomic(marker, {"done": True, "setup": result, "detail": detail, "services": started,
                               "when": time.strftime("%Y-%m-%d %H:%M:%S")})
    return result


def main(argv=None, backend=None, config: Path | None = None, **kw) -> int:
    ap = argparse.ArgumentParser(prog="omnia-first-run", description=__doc__.split("\n\n")[0])
    ap.add_argument("--force", action="store_true", help="repetir aunque ya se hubiera hecho")
    ap.add_argument("--yes", "-y", action="store_true", help="aceptar sin preguntar")
    ap.add_argument("--no-services", action="store_true", help="no habilitar los servicios de usuario")
    ap.add_argument("--script-src", type=Path)
    a = ap.parse_args(argv)
    result = run(Path(config) if config else paths.config_dir(), backend or setup.KdeBackend(),
                 script_src=a.script_src or setup.find_script_src(), force=a.force, yes=a.yes,
                 services=not a.no_services, **kw)
    if result == "applied":
        notify("Listo. Win+D muestra tu escritorio de Omnia. Para revertirlo: omnia-setup --undo")
    return 2 if result == "error" else 0


if __name__ == "__main__":
    sys.exit(main())

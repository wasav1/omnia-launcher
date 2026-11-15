"""omnia-setup: configura KDE Plasma para Omnia en la sesión del usuario (idempotente y reversible).

Qué hace:
  1. Se asegura de que el script de KWin `omnia-showdesktop` esté instalado y activado.
  2. Quita `Meta+D` al «Mostrar escritorio» nativo de KWin (que oculta la estantería de Omnia) y se la da al atajo
     «Omnia: mostrar escritorio», que minimiza las ventanas sin ocultar el escritorio de Omnia.
Antes de tocar nada guarda el estado original en ~/.config/omnia/setup-backup.json; `--undo` lo restaura.
Un paquete de pacman no puede hacer esto (corre como root, sin sesión): se ejecuta en la primera sesión del usuario.

Códigos de salida: 0 correcto · 2 error · 3 falta consentimiento (sin terminal y sin --yes).
"""
import argparse
import json
import re
import shutil
import subprocess
import sys
import time
from pathlib import Path

from . import paths
from .store import load_json, write_json_atomic

SCRIPT_ID = "omnia-showdesktop"
META_D = 0x10000000 | 0x44                   # Qt::META | Qt::Key_D
NATIVE = ("kwin", "Show Desktop")            # acción nativa de KWin
OURS = ("kwin", "OmniaShowDesktop")          # acción del script de Omnia
BACKUP_NAME = "setup-backup.json"


class SetupError(Exception):
    pass


class KdeBackend:
    """Habla con KDE: KGlobalAccel y KWin por D-Bus (busctl), configuración con kwriteconfig6."""

    def _run(self, *cmd) -> str:
        try:
            p = subprocess.run(cmd, capture_output=True, text=True, timeout=15)
        except (OSError, subprocess.TimeoutExpired) as e:
            raise SetupError("no se pudo ejecutar %s: %s" % (cmd[0], e))
        if p.returncode != 0:
            raise SetupError("%s falló: %s" % (" ".join(cmd[:3]), (p.stderr or p.stdout).strip()))
        return p.stdout.strip()

    def _accel(self, method: str, *args) -> str:
        return self._run("busctl", "--user", "call", "org.kde.kglobalaccel", "/kglobalaccel",
                         "org.kde.KGlobalAccel", method, *args)

    @staticmethod
    def _aid(action) -> list:
        """Elementos del actionId (as): componente, acción y dos nombres «amigables» vacíos (no dependen del idioma)."""
        return ["4", action[0], action[1], "", ""]

    def shortcut_keys(self, action) -> list:
        out = self._accel("shortcut", "as", *self._aid(action)).split()      # «ai N k1 k2 …»
        return [int(x) for x in out[2:]] if len(out) >= 2 and out[0] == "ai" else []

    def set_shortcut_keys(self, action, keys: list) -> None:
        # busctl exige UNA sola cadena de firma para todos los argumentos: «asai» (actionId + teclas)
        self._accel("setForeignShortcut", "asai", *self._aid(action), str(len(keys)), *[str(k) for k in keys])

    def action_exists(self, action) -> bool:
        out = self._run("busctl", "--user", "call", "org.kde.kglobalaccel", "/component/" + action[0],
                        "org.kde.kglobalaccel.Component", "shortcutNames")
        return '"%s"' % action[1] in out

    def plugin_enabled(self, name: str) -> bool:
        return self._run("kreadconfig6", "--file", "kwinrc", "--group", "Plugins", "--key", name + "Enabled") == "true"

    def set_plugin_enabled(self, name: str, on: bool) -> None:
        self._run("kwriteconfig6", "--file", "kwinrc", "--group", "Plugins", "--key", name + "Enabled",
                  "true" if on else "false")

    def reload_kwin(self) -> None:
        self._run("busctl", "--user", "call", "org.kde.KWin", "/KWin", "org.kde.KWin", "reconfigure")

    def script_installed(self, name: str) -> bool:
        return any((Path(d) / name / "metadata.json").is_file() for d in
                   (Path.home() / ".local/share/kwin/scripts", "/usr/share/kwin/scripts"))

    def install_script(self, src: Path) -> None:
        self._run("kpackagetool6", "--type", "KWin/Script", "--install", str(src))


def _backup_file(config: Path) -> Path:
    return config / BACKUP_NAME


def plan(be, config: Path) -> list:
    """Lista de acciones que `apply` haría ahora (vacía si ya está todo hecho)."""
    todo = []
    if not be.plugin_enabled(SCRIPT_ID):
        todo.append("Activar el script de KWin «Omnia: mostrar escritorio»")
    if META_D in be.shortcut_keys(NATIVE):
        todo.append("Quitar Meta+D al «Mostrar escritorio» nativo de KWin (se guarda para poder restaurarlo)")
    if not be.shortcut_keys(OURS):
        todo.append("Asignar Meta+D a «Omnia: mostrar escritorio» (minimiza las ventanas sin ocultar tu escritorio)")
    return todo


def apply(be, config: Path, script_src: Path | None = None, wait: float = 5.0) -> list:
    """Aplica la configuración. Devuelve lo que hizo. Idempotente: si ya está todo, no hace nada."""
    config = Path(config)
    todo = plan(be, config)
    if not todo:
        return []
    bf = _backup_file(config)
    if not bf.exists():       # el estado ORIGINAL se guarda solo la primera vez: repetir el setup no lo pisa
        write_json_atomic(bf, {"version": 1, "saved": time.strftime("%Y-%m-%d %H:%M:%S"),
                               "native_keys": be.shortcut_keys(NATIVE),
                               "plugin_was_enabled": be.plugin_enabled(SCRIPT_ID),
                               "we_installed_script": False})
    backup = load_json(bf, {})
    if not be.script_installed(SCRIPT_ID):
        if not script_src or not Path(script_src).is_dir():
            raise SetupError("el script de KWin «%s» no está instalado y no se indicó --script-src" % SCRIPT_ID)
        be.install_script(Path(script_src))
        backup["we_installed_script"] = True
        write_json_atomic(bf, backup)
    be.set_plugin_enabled(SCRIPT_ID, True)
    be.reload_kwin()
    end = time.time() + wait
    while not be.action_exists(OURS):          # el atajo existe cuando KWin carga el script
        if time.time() > end:
            raise SetupError("KWin no registró el atajo de Omnia (¿falló el script?)")
        time.sleep(0.25)
    native = be.shortcut_keys(NATIVE)
    if META_D in native:
        be.set_shortcut_keys(NATIVE, [k for k in native if k != META_D])     # conserva sus otras teclas
    if not be.shortcut_keys(OURS):
        be.set_shortcut_keys(OURS, [META_D])
    return todo


def undo(be, config: Path) -> list:
    """Devuelve KDE al estado guardado. Sin copia de seguridad no toca nada."""
    bf = _backup_file(Path(config))
    backup = load_json(bf, None)
    if not backup:
        return []
    done = []
    if be.action_exists(OURS) and be.shortcut_keys(OURS):
        be.set_shortcut_keys(OURS, [])
        done.append("Quitado Meta+D a «Omnia: mostrar escritorio»")
    keys = backup.get("native_keys", [])
    if keys != be.shortcut_keys(NATIVE):
        be.set_shortcut_keys(NATIVE, keys)
        done.append("Restaurado el «Mostrar escritorio» nativo de KWin")
    if not backup.get("plugin_was_enabled", False) and be.plugin_enabled(SCRIPT_ID):
        be.set_plugin_enabled(SCRIPT_ID, False)
        be.reload_kwin()
        done.append("Desactivado el script de KWin de Omnia")
    bf.unlink()
    return done


def find_script_src() -> Path | None:
    """Origen del script cuando se corre desde el repositorio (en el paquete ya está en /usr/share/kwin/scripts)."""
    p = Path(__file__).resolve().parents[2] / "kwin" / SCRIPT_ID
    return p if p.is_dir() else None


def main(argv=None, backend=None, config: Path | None = None) -> int:
    ap = argparse.ArgumentParser(prog="omnia-setup", description=__doc__.split("\n\n")[0])
    ap.add_argument("--yes", "-y", action="store_true", help="aplicar sin preguntar")
    ap.add_argument("--dry-run", action="store_true", help="solo mostrar lo que se haría")
    ap.add_argument("--undo", action="store_true", help="restaurar la configuración original de KDE")
    ap.add_argument("--status", action="store_true", help="indicar si la configuración ya está aplicada")
    ap.add_argument("--script-src", type=Path, help="carpeta del script de KWin (si no está instalado)")
    a = ap.parse_args(argv)
    be, cfg = backend or KdeBackend(), Path(config) if config else paths.config_dir()
    try:
        if a.undo:
            done = undo(be, cfg)
            print("\n".join("· " + d for d in done) if done else "No hay nada que deshacer.")
            return 0
        todo = plan(be, cfg)
        if a.status:
            print("Configurado." if not todo else "Pendiente:\n" + "\n".join("· " + t for t in todo))
            return 0 if not todo else 1
        if not todo:
            print("Todo está configurado.")
            return 0
        print("Omnia va a cambiar tu configuración de KDE:\n" + "\n".join("· " + t for t in todo))
        if a.dry_run:
            return 0
        if not a.yes:
            if not sys.stdin.isatty():
                print("Hace falta tu consentimiento: ejecuta «omnia-setup --yes».", file=sys.stderr)
                return 3
            if input("¿Continuar? [s/N] ").strip().lower() not in ("s", "si", "sí", "y", "yes"):
                print("Cancelado: no se cambió nada.")
                return 0
        apply(be, cfg, a.script_src or find_script_src())
        print("Listo. Para revertirlo: omnia-setup --undo")
        return 0
    except SetupError as e:
        print("Error: %s" % e, file=sys.stderr)
        return 2


if __name__ == "__main__":
    raise SystemExit(main())

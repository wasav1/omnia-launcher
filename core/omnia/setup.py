"""omnia-setup: configura KDE Plasma para Omnia en la sesión del usuario (idempotente y reversible).

Qué hace:
  1. Se asegura de que el script de KWin `omnia-showdesktop` esté instalado y activado.
  2. Quita `Meta+D` al «Mostrar escritorio» nativo de KWin (que oculta la estantería de Omnia) y se la da al atajo
     «Omnia: mostrar escritorio», que minimiza las ventanas sin ocultar el escritorio de Omnia.
  3. Retira el Big Menu anterior y restaura Meta en el lanzador nativo de Plasma.
Antes de tocar nada guarda el estado original en ~/.config/omnia/setup-backup.json; `--undo` lo restaura.
Un paquete de pacman no puede hacer esto (corre como root, sin sesión): se ejecuta en la primera sesión del usuario.

Códigos de salida: 0 correcto · 2 error · 3 falta consentimiento (sin terminal y sin --yes).
"""
import argparse
import subprocess
import sys
import time
from pathlib import Path

from . import paths
from .store import load_json, write_json_atomic

SCRIPT_ID = "omnia-showdesktop"
SCRIPTS = {"omnia-showdesktop": "Omnia: mostrar escritorio", "omnia-watch": "Omnia: vigilante de ventanas"}
META_D = 0x10000000 | 0x44                   # Qt::META | Qt::Key_D
NATIVE = ("kwin", "Show Desktop")            # acción nativa de KWin
OURS = ("kwin", "OmniaShowDesktop")          # acción del script de Omnia
LAUNCHER = ("plasmashell", "activate application launcher")    # el lanzador de Plasma (Meta y Alt+F1)
OMENU = ("kwin", "OmniaMenu")                                   # acción del script omnia-watch que abre el Big Menu
META_ALONE = 0x01000022                                         # Qt::Key_Meta: la tecla Windows sola
BACKUP_NAME = "setup-backup.json"
# Intento anterior que NO funciona en Plasma 6.8 (KWin no lo atiende): se limpia si quedó escrito.
OMNIA_META = "org.omnia.Core,/org/omnia/Core,org.omnia.Core,ToggleMenu"


class SetupError(Exception):
    pass


class KdeBackend:
    """Habla con KDE: KGlobalAccel y KWin por D-Bus (busctl), configuración con kwriteconfig6."""

    def _run(self, *cmd) -> str:
        try:
            p = subprocess.run(cmd, check=False, capture_output=True, text=True, timeout=15)
        except (OSError, subprocess.TimeoutExpired) as e:
            raise SetupError(f"no se pudo ejecutar {cmd[0]}: {e}")
        if p.returncode != 0:
            raise SetupError("{} falló: {}".format(" ".join(cmd[:3]), (p.stderr or p.stdout).strip()))
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
        return f'"{action[1]}"' in out

    def plugin_enabled(self, name: str) -> bool:
        return self._run("kreadconfig6", "--file", "kwinrc", "--group", "Plugins", "--key", name + "Enabled") == "true"

    def set_plugin_enabled(self, name: str, on: bool) -> None:
        self._run("kwriteconfig6", "--file", "kwinrc", "--group", "Plugins", "--key", name + "Enabled",
                  "true" if on else "false")

    def meta_shortcut(self) -> str:
        return self._run("kreadconfig6", "--file", "kwinrc", "--group", "ModifierOnlyShortcuts", "--key", "Meta")

    def set_meta_shortcut(self, value) -> None:
        """value=None borra la clave (vuelve al comportamiento predeterminado de Plasma)."""
        if value is None:
            self._run("kwriteconfig6", "--file", "kwinrc", "--group", "ModifierOnlyShortcuts", "--key", "Meta", "--delete")
        else:
            self._run("kwriteconfig6", "--file", "kwinrc", "--group", "ModifierOnlyShortcuts", "--key", "Meta", value)

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
    for name, label in SCRIPTS.items():
        if not be.plugin_enabled(name):
            todo.append(f"Activar el script de KWin «{label}»")
    if META_D in be.shortcut_keys(NATIVE):
        todo.append("Quitar Meta+D al «Mostrar escritorio» nativo de KWin (se guarda para poder restaurarlo)")
    if not be.shortcut_keys(OURS):
        todo.append("Asignar Meta+D a «Omnia: mostrar escritorio» (minimiza las ventanas sin ocultar tu escritorio)")
    if be.shortcut_keys(OMENU) or META_ALONE not in be.shortcut_keys(LAUNCHER):
        todo.append("Retirar el atajo del Big Menu anterior y devolver Meta al menú de Plasma")
    if be.meta_shortcut() == OMNIA_META:
        todo.append("Limpiar un ajuste anterior de la tecla Windows que no funcionaba")
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
                               "plugins_before": {n: be.plugin_enabled(n) for n in SCRIPTS},
                               "launcher_keys_before": be.shortcut_keys(LAUNCHER),
                               "we_installed_script": False})
    backup = load_json(bf, {})
    if "launcher_keys_before" not in backup and META_ALONE in be.shortcut_keys(LAUNCHER):
        backup["launcher_keys_before"] = be.shortcut_keys(LAUNCHER)      # copia hecha con una versión anterior
        write_json_atomic(bf, backup)
    for name in SCRIPTS:
        if not be.script_installed(name):
            src = Path(script_src) / name if script_src else None
            if not src or not src.is_dir():
                raise SetupError(f"el script de KWin «{name}» no está instalado y no se indicó --script-src")
            be.install_script(src)
            backup["we_installed_script"] = True
            write_json_atomic(bf, backup)
    for name in SCRIPTS:
        be.set_plugin_enabled(name, True)
    be.reload_kwin()
    end = time.time() + wait
    while not be.action_exists(OURS):      # los atajos existen cuando KWin carga los scripts
        if time.time() > end:
            raise SetupError("KWin no registró el atajo de Omnia (¿falló el script?)")
        time.sleep(0.25)
    native = be.shortcut_keys(NATIVE)
    if META_D in native:
        be.set_shortcut_keys(NATIVE, [k for k in native if k != META_D])     # conserva sus otras teclas
    if not be.shortcut_keys(OURS):
        be.set_shortcut_keys(OURS, [META_D])
    if be.shortcut_keys(OMENU):
        be.set_shortcut_keys(OMENU, [])
    launcher = be.shortcut_keys(LAUNCHER)
    if META_ALONE not in launcher:
        be.set_shortcut_keys(LAUNCHER, launcher + [META_ALONE])
    if be.meta_shortcut() == OMNIA_META:
        be.set_meta_shortcut(None)
        be.reload_kwin()
    return todo


def undo(be, config: Path) -> list:
    """Devuelve KDE al estado guardado. Sin copia de seguridad no toca nada."""
    bf = _backup_file(Path(config))
    backup = load_json(bf, None)
    if not backup:
        return []
    done = []
    if be.action_exists(OMENU) and be.shortcut_keys(OMENU):         # primero se libera la tecla: KDE no admite duplicados
        be.set_shortcut_keys(OMENU, [])
        done.append("Quitada la tecla Windows al Big Menu de Omnia")
    if "launcher_keys_before" in backup and backup["launcher_keys_before"] != be.shortcut_keys(LAUNCHER):
        be.set_shortcut_keys(LAUNCHER, backup["launcher_keys_before"])
        done.append("Restaurada la tecla Windows del menú de Plasma")
    if be.action_exists(OURS) and be.shortcut_keys(OURS):
        be.set_shortcut_keys(OURS, [])
        done.append("Quitado Meta+D a «Omnia: mostrar escritorio»")
    keys = backup.get("native_keys", [])
    if keys != be.shortcut_keys(NATIVE):
        be.set_shortcut_keys(NATIVE, keys)
        done.append("Restaurado el «Mostrar escritorio» nativo de KWin")
    before = backup.get("plugins_before") or {SCRIPT_ID: backup.get("plugin_was_enabled", False)}   # copias antiguas
    turned_off = False
    for name, label in SCRIPTS.items():
        if not before.get(name, False) and be.plugin_enabled(name):     # lo que no estaba activo antes de Omnia se apaga
            be.set_plugin_enabled(name, False)
            turned_off = True
            done.append(f"Desactivado el script de KWin «{label}»")
    if turned_off:
        be.reload_kwin()
    if be.meta_shortcut() == OMNIA_META:
        be.set_meta_shortcut(None)
        be.reload_kwin()
    bf.unlink()
    return done


def find_script_src() -> Path | None:
    """Carpeta con los scripts cuando se corre desde el repositorio (en el paquete ya están en /usr/share/kwin/scripts)."""
    p = Path(__file__).resolve().parents[2] / "kwin"
    return p if (p / SCRIPT_ID).is_dir() else None


def main(argv=None, backend=None, config: Path | None = None) -> int:
    ap = argparse.ArgumentParser(prog="omnia-setup", description=__doc__.split("\n\n")[0])
    ap.add_argument("--yes", "-y", action="store_true", help="aplicar sin preguntar")
    ap.add_argument("--dry-run", action="store_true", help="solo mostrar lo que se haría")
    ap.add_argument("--undo", action="store_true", help="restaurar la configuración original de KDE")
    ap.add_argument("--status", action="store_true", help="indicar si la configuración ya está aplicada")
    ap.add_argument("--script-src", type=Path, help="carpeta que contiene los scripts de KWin (si no están instalados)")
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
        print(f"Error: {e}", file=sys.stderr)
        return 2


if __name__ == "__main__":
    raise SystemExit(main())

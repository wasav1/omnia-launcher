#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
. "$ROOT/packaging/universal/distro.sh"
omnia_distro_detect
PREFIX="${HOME}/.local"
DATA="${HOME}/.local/share"
CONFIG_HOME="${XDG_CONFIG_HOME:-$HOME/.config}"
[[ "$CONFIG_HOME" == /* ]] || CONFIG_HOME="$HOME/.config"
CONFIG_OMNIA="$CONFIG_HOME/omnia"
DISTRO=""
NO_DEPS=0
CLI=0
UPDATE=0
PLASMA_RESTARTED=0

usage() { printf 'Uso: %s [--cli] [--check] [--no-deps] [--update]\n' "$0"; }
CHECK=0
while (($#)); do
  case "$1" in
    --check) CHECK=1 ;;
    --cli) CLI=1 ;;
    --no-deps) NO_DEPS=1 ;;
    --update) UPDATE=1; NO_DEPS=1 ;;
    -h|--help) usage; exit 0 ;;
    *) usage >&2; exit 2 ;;
  esac
  shift
done

if ((!CLI && !CHECK)); then
  exec bash "$ROOT/packaging/universal/launch-gui.sh"
fi

die() { printf 'Omnia: %s\n' "$*" >&2; exit 1; }
ensure_deps() {
  if bash "$ROOT/packaging/universal/check-dependencies.sh" --ensure; then return 0; fi
  if omnia_ostree_pending_packages; then
    die 'las dependencias se añadieron como capa rpm-ostree y aún no están activas. Reinicia el equipo y vuelve a ejecutar el instalador.'
  fi
  die 'no se pudieron instalar las dependencias necesarias (¿se canceló la autorización de KDE?).'
}
# La versión anterior (Estantería) escuchaba en el mismo puerto y respondía /health igual.
# Si sigue viva, omnia-core falla al abrir 47831 y la interfaz recibe respuestas incompatibles.
check_core() {
  local body="" i
  for i in 1 2 3 4 5 6 7 8 9 10; do
    body="$(python3 -c 'import urllib.request; print(urllib.request.urlopen("http://127.0.0.1:47831/health", timeout=1).read().decode())' 2>/dev/null || true)"
    [[ -n "$body" ]] && break
    sleep 0.3
  done
  if [[ "$body" == *'"padName"'* ]]; then
    printf 'Omnia: el puerto 47831 sigue ocupado por Estantería (estanteria-helper). Detenla y reinicia Omnia:\n  systemctl --user disable --now estanteria-helper.service\n  systemctl --user restart omnia.service\n' >&2
    return 1
  elif [[ -z "$body" ]]; then
    printf 'Omnia: omnia-core no responde en 127.0.0.1:47831. Revisa:\n  systemctl --user status omnia.service --no-pager\n  journalctl --user -u omnia.service -n 40 --no-pager\n' >&2
    return 1
  fi
}
restart_plasma_if_approved() {
  local answer=""
  if command -v kdialog >/dev/null && [[ -n "${DISPLAY:-}${WAYLAND_DISPLAY:-}" ]]; then
    if kdialog --title 'Omnia' --yesno 'Omnia está instalado. ¿Reiniciar Plasma ahora para cargar los componentes? Las ventanas del escritorio se cerrarán y volverán a abrir.'; then
      if systemctl --user restart plasma-plasmashell.service; then PLASMA_RESTARTED=1
      else printf 'Omnia: no pude reiniciar Plasma. Cierra sesión y vuelve a entrar para cargar los cambios.\n'; fi
    else
      printf 'Omnia: reinicio omitido. Cierra sesión y vuelve a entrar para cargar los cambios.\n'
    fi
  elif [[ -t 0 ]]; then
    read -r -p '¿Reiniciar Plasma ahora? Se cerrarán y volverán a abrir sus ventanas. [s/N] ' answer
    if [[ "$answer" == s || "$answer" == S ]]; then
      if systemctl --user restart plasma-plasmashell.service; then PLASMA_RESTARTED=1; fi
    else printf 'Omnia: reinicio omitido; cierra sesión para cargar los cambios.\n'; fi
  else
    printf 'Omnia: instalación lista. Cierra sesión y vuelve a entrar para cargar los componentes.\n'
  fi
}
((EUID != 0)) || die 'Ejecuta el instalador como usuario normal; KDE pedirá autorización cuando haga falta.'
qt6_dev_available() {
  local probe rc
  probe="$(mktemp -d)"
  rc=0
  cmake -S "$ROOT/plasma/tokenprovider" -B "$probe" >/dev/null 2>&1 || rc=$?
  rm -rf "$probe"
  return "$rc"
}
command -v plasmashell >/dev/null || die 'no encuentro plasmashell; este instalador requiere KDE Plasma 6.'
PLASMA_VERSION=""
if [[ "${KDE_SESSION_VERSION:-}" == 6 ]]; then
  PLASMA_VERSION="6 (sesión KDE)"
else
  PLASMA_VERSION="$(plasmashell --version 2>/dev/null | grep -oE '[0-9]+\.[0-9]+' | head -n1 || true)"
fi
[[ "$PLASMA_VERSION" == 6* ]] || die "se requiere Plasma 6 (detectado: ${PLASMA_VERSION:-desconocido})."
if ((!CHECK)); then
  command -v systemctl >/dev/null && systemctl --user show-environment >/dev/null 2>&1 || die 'se requiere una sesión KDE iniciada con systemd --user.'
fi
command -v python3 >/dev/null || die 'falta Python 3.11 o posterior.'
if ((UPDATE)) && [[ ! -f "${XDG_CONFIG_HOME:-$HOME/.config}/omnia/library.json" && ! -x "$HOME/.local/share/omnia/installer/omnia-installer" ]]; then
  die 'No se encontró una instalación existente de Omnia para actualizar.'
fi
PYVER="$(python3 -c 'import sys; print("%d.%d" % sys.version_info[:2])')"
python3 -c 'import sys; raise SystemExit(sys.version_info < (3,11))' || die "Omnia requiere Python >=3.11 (detectado: $PYVER)."

DISTRO="$OMNIA_DISTRO_ID"
PROFILE="$(omnia_distro_profile)"
packages=(cmake gcc-c++ qt6-declarative-devel)
case "$PROFILE" in
  arch) packages=(cmake gcc qt6-declarative) ;;
  fedora) packages=(cmake gcc-c++ qt6-qtdeclarative-devel) ;;
  opensuse) packages=(cmake gcc-c++ libQt6QuickControls2-devel qt6-declarative-devel) ;;
  debian) packages=(cmake g++ qt6-declarative-dev qt6-base-dev) ;;
  *) die "distro '$DISTRO' sin mapa de dependencias. Instala CMake, un compilador C++, Qt 6 Core/Qml y vuelve a ejecutar con --no-deps." ;;
esac
if omnia_is_ostree; then
  printf 'Omnia: detectado sistema OSTree (%s). Las dependencias se instalarán como capa con rpm-ostree; puede requerir reinicio.\n' "$DISTRO"
fi

if ((CHECK)); then
  printf 'Plasma %s · %s · Python %s\n' "$PLASMA_VERSION" "$DISTRO" "$PYVER"
  for tool in cmake c++; do command -v "$tool" >/dev/null || printf 'Falta herramienta: %s\n' "$tool"; done
  qt6_dev_available || printf 'Faltan módulos de desarrollo Qt 6.\n'
  bash "$ROOT/packaging/universal/check-dependencies.sh" --check
  exit 0
fi

if ((UPDATE)); then
  # MangoHud se incorporó en esta revisión. Si falta, el mismo comprobador pide
  # autorización y agrega solo los paquetes que aún no estén instalados.
  ensure_deps
elif ((NO_DEPS)); then
  bash "$ROOT/packaging/universal/check-dependencies.sh" --check \
    || die 'faltan dependencias y --no-deps está activo; instálalas o vuelve a ejecutar sin --no-deps.'
else
  ensure_deps
fi

if ((!UPDATE)) && { ! command -v cmake >/dev/null || ! command -v c++ >/dev/null || ! command -v kdialog >/dev/null || ! python3 -c "import gi" 2>/dev/null || ! qt6_dev_available; }; then
  ((NO_DEPS)) && die 'faltan cmake, compilador C++ o Qt 6 de desarrollo (--no-deps está activo).'
  printf 'Omnia necesita instalar dependencias de compilación Qt 6 para integrar el token de sesión de forma segura.\n'
  bash "$ROOT/packaging/universal/dependencies.sh" || die 'no se pudieron instalar las dependencias de compilación.'
  if ! command -v cmake >/dev/null || ! qt6_dev_available; then
    if omnia_ostree_pending_packages; then
      die 'las dependencias quedaron en una capa rpm-ostree pendiente. Reinicia el equipo y vuelve a ejecutar el instalador.'
    fi
    die 'no se pudieron preparar CMake y Qt 6 de desarrollo.'
  fi
fi

BUILD="$(mktemp -d)"
TXN_DIR=""
TXN_ACTIVE=0
TXN_COMMITTED=0
QML_STAGE=""
QML_BACKUP=""
SETUP_BACKUP_WAS_PRESENT=0
SERVICE_OMNIA_WAS_ACTIVE="$(systemctl --user is-active omnia.service 2>/dev/null || true)"
SERVICE_UI_WAS_ACTIVE="$(systemctl --user is-active omnia-ui.service 2>/dev/null || true)"
SERVICE_OLD_WAS_ACTIVE="$(systemctl --user is-active estanteria-helper.service 2>/dev/null || true)"
[[ -e "$CONFIG_OMNIA/setup-backup.json" ]] && SETUP_BACKUP_WAS_PRESENT=1

restore_service_state() {
  local unit="$1" was_active="$2"
  if [[ "$was_active" == active ]]; then
    systemctl --user start "$unit" >/dev/null 2>&1 || printf 'Omnia: no pude restaurar el servicio anterior %s.\n' "$unit" >&2
  else
    systemctl --user stop "$unit" >/dev/null 2>&1 || true
  fi
}

commit_install_transaction() {
  TXN_COMMITTED=1
  TXN_ACTIVE=0
  if [[ -d "$TXN_DIR" ]] && ! python3 "$ROOT/packaging/universal/install_transaction.py" discard "$TXN_DIR"; then
    printf 'Omnia: instalación aplicada, pero no pude borrar el respaldo %s.\n' "$TXN_DIR" >&2
  fi
}

finish_install_transaction() {
  local status=$?
  trap - EXIT
  if ((TXN_ACTIVE && !TXN_COMMITTED)); then
    if ((status == 0)); then status=1; fi
    printf 'Omnia: la instalación falló; restaurando los archivos anteriores.\n' >&2
    if (( ! SETUP_BACKUP_WAS_PRESENT )) && [[ -f "$CONFIG_OMNIA/setup-backup.json" && -x "$PREFIX/bin/omnia-setup" ]]; then
      "$PREFIX/bin/omnia-setup" --undo >/dev/null 2>&1 || printf 'Omnia: no pude revertir automáticamente los atajos de KDE.\n' >&2
    fi
    if python3 "$ROOT/packaging/universal/install_transaction.py" rollback "$TXN_DIR"; then
      TXN_ACTIVE=0
      if [[ -n "$QML_BACKUP" && -e "$QML_BACKUP" ]]; then rm -rf -- "$QML_BACKUP"; fi
      systemctl --user daemon-reload >/dev/null 2>&1 || true
      restore_service_state omnia.service "$SERVICE_OMNIA_WAS_ACTIVE"
      restore_service_state omnia-ui.service "$SERVICE_UI_WAS_ACTIVE"
      restore_service_state estanteria-helper.service "$SERVICE_OLD_WAS_ACTIVE"
      if ((PLASMA_RESTARTED)); then
        systemctl --user restart plasma-plasmashell.service >/dev/null 2>&1 || printf 'Omnia: reinicia Plasma para cargar los archivos restaurados.\n' >&2
      fi
    else
      printf 'Omnia: no pude completar la restauración; el respaldo sigue en %s.\n' "$TXN_DIR" >&2
    fi
  fi
  [[ -n "$QML_STAGE" ]] && rm -rf -- "$QML_STAGE"
  if ((TXN_COMMITTED)) && [[ -n "$QML_BACKUP" && -e "$QML_BACKUP" ]]; then rm -rf -- "$QML_BACKUP"; fi
  rm -rf -- "$BUILD"
  exit "$status"
}
trap finish_install_transaction EXIT

TXN_DIR="$DATA/.omnia-install-transaction-$$"
TXN_TARGETS=(
  "$DATA/omnia/ui" "$DATA/omnia/kwin" "$DATA/omnia/installer"
  "$DATA/omnia/omnia-layout.js" "$DATA/omnia/omnia-maintain.js"
  "$DATA/omnia/empty-desktop"
  "$DATA/omnia/assets/branding/omnia-logo.png" "$DATA/omnia/assets/branding/omnia-menu.svg"
  "$DATA/plasma/wallpapers/org.omnia.launcher" "$DATA/plasma/plasmoids/org.omnia.desktop"
  "$DATA/kwin/scripts/omnia-showdesktop" "$DATA/kwin/scripts/omnia-watch"
  "$PREFIX/lib/omnia" "$PREFIX/bin/omnia-core" "$PREFIX/bin/omnia-setup"
  "$PREFIX/bin/omnia-layout" "$PREFIX/bin/omnia-maintain" "$PREFIX/bin/omnia-settings" "$PREFIX/bin/omnia-uninstall"
  "$HOME/.config/systemd/user/omnia.service"
  "$HOME/.config/systemd/user/default.target.wants/omnia.service"
  "$HOME/.config/systemd/user/default.target.wants/omnia-ui.service"
  "$HOME/.config/systemd/user/default.target.wants/estanteria-helper.service"
  "$DATA/applications/org.omnia.settings.desktop" "$DATA/applications/org.omnia.uninstall.desktop"
  "$DATA/icons/hicolor/512x512/apps/org.omnia.uninstall.png"
  "$DATA/icons/hicolor/scalable/apps/org.omnia.menu.svg"
  "$CONFIG_OMNIA/config.json" "$CONFIG_OMNIA/library.json" "$CONFIG_OMNIA/state.json"
  "$CONFIG_OMNIA/steamgriddb.key" "$CONFIG_OMNIA/first-run.json" "$CONFIG_OMNIA/setup-backup.json"
  "$CONFIG_OMNIA/desktop-before-omnia.json" "$CONFIG_OMNIA/layout-backups" "$HOME/.config/omnia/layout-backups"
  "$CONFIG_OMNIA/MangoHud.conf" "$HOME/.config/omnia/MangoHud.conf"
  "$CONFIG_HOME/autostart/omnia-maintain.desktop" "$HOME/.config/autostart/omnia-maintain.desktop"
  "$CONFIG_HOME/kwinrc" "$CONFIG_HOME/kglobalshortcutsrc"
  "$CONFIG_HOME/plasma-org.kde.plasma.desktop-appletsrc" "$HOME/.config/plasma-org.kde.plasma.desktop-appletsrc"
)
python3 "$ROOT/packaging/universal/install_transaction.py" snapshot "$TXN_DIR" "${TXN_TARGETS[@]}"
TXN_ACTIVE=1
# Quiesce old processes before replacing modules they may import.
systemctl --user stop omnia.service omnia-ui.service estanteria-helper.service >/dev/null 2>&1 || true

if ((!UPDATE)); then
  cmake -S "$ROOT/plasma/tokenprovider" -B "$BUILD/tokenprovider" -DCMAKE_BUILD_TYPE=Release -DCMAKE_INSTALL_PREFIX="$DATA/omnia/ui"
  cmake --build "$BUILD/tokenprovider" --parallel "$(getconf _NPROCESSORS_ONLN 2>/dev/null || echo 2)"
  cmake --install "$BUILD/tokenprovider"
elif [[ -d "$PREFIX/lib/qt6/qml/org/omnia/session" && ! -d "$DATA/omnia/ui/session" ]]; then
  # Migración desde la versión que publicaba QML_IMPORT_PATH para toda la sesión.
  install -d "$DATA/omnia/ui/session"
  cp -a "$PREFIX/lib/qt6/qml/org/omnia/session/." "$DATA/omnia/ui/session/"
fi

install -d "$DATA/plasma/wallpapers/org.omnia.launcher" "$DATA/plasma/plasmoids/org.omnia.desktop" "$DATA/omnia/ui" "$DATA/omnia/kwin" "$PREFIX/lib/omnia" "$PREFIX/bin"
cp -a "$ROOT/plasma/wallpapers/org.omnia.launcher/." "$DATA/plasma/wallpapers/org.omnia.launcher/"
install -Dm644 "$ROOT/packaging/universal/omnia-layout.js" "$DATA/omnia/omnia-layout.js"
install -Dm644 "$ROOT/packaging/universal/omnia-maintain.js" "$DATA/omnia/omnia-maintain.js"
cp -a "$ROOT/plasma/applets/org.omnia.desktop/." "$DATA/plasma/plasmoids/org.omnia.desktop/"
# Una sola copia canónica compartida por el wallpaper y el applet; el cambio de árbol es atómico.
QML_STAGE="$DATA/omnia/.qml-stage-$$"
mkdir -p "$QML_STAGE"
cp -a "$ROOT/ui/qml/." "$QML_STAGE/"
mkdir -p "$QML_STAGE/fonts"
cp -a "$ROOT/assets/fonts/." "$QML_STAGE/fonts/"
if [[ -d "$DATA/omnia/ui/qml" ]]; then
  QML_BACKUP="$DATA/omnia/.qml-previous-$(date +%s)"
  mv "$DATA/omnia/ui/qml" "$QML_BACKUP"
fi
mv "$QML_STAGE" "$DATA/omnia/ui/qml"
cp -a "$ROOT/core/omnia" "$PREFIX/lib/omnia/"
cp -a "$ROOT/kwin/omnia-showdesktop" "$ROOT/kwin/omnia-watch" "$DATA/omnia/kwin/"
for script in omnia-showdesktop omnia-watch; do
  install -d "$DATA/kwin/scripts/$script"
  cp -a "$ROOT/kwin/$script/." "$DATA/kwin/scripts/$script/"
done
install -d "$HOME/.config/systemd/user"
sed "s|^ExecStart=/usr/bin/omnia-core|ExecStart=$PREFIX/bin/omnia-core|" \
  "$ROOT/packaging/systemd/omnia.service" > "$HOME/.config/systemd/user/omnia.service"
install -d "$PREFIX/bin"
cat > "$PREFIX/bin/omnia-core" <<EOF
#!/bin/sh
export PYTHONPATH="$PREFIX/lib/omnia\${PYTHONPATH:+:\$PYTHONPATH}"
exec python3 -m omnia.service "\$@"
EOF
chmod 755 "$PREFIX/bin/omnia-core"
cat > "$PREFIX/bin/omnia-setup" <<EOF
#!/bin/sh
export PYTHONPATH="$PREFIX/lib/omnia\${PYTHONPATH:+:\$PYTHONPATH}"
exec python3 -m omnia.setup --script-src "$DATA/omnia/kwin" "\$@"
EOF
chmod 755 "$PREFIX/bin/omnia-setup"
cat > "$PREFIX/bin/omnia-layout" <<EOF
#!/bin/sh
QDBUS=\$(command -v qdbus6 || command -v qdbus-qt6 || command -v qdbus) || exit 1
EMPTY_DESKTOP="$HOME/.local/share/omnia/empty-desktop"
mkdir -p "\$EMPTY_DESKTOP"
EMPTY_URL=\$(python3 -c 'from pathlib import Path; import sys; print(Path(sys.argv[1]).as_uri())' "\$EMPTY_DESKTOP")
SCRIPT=\$(python3 -c 'from pathlib import Path; import sys; print(Path(sys.argv[1]).read_text().replace("__OMNIA_EMPTY_DESKTOP_URL__", sys.argv[2]))' "$DATA/omnia/omnia-layout.js" "\$EMPTY_URL")
exec \$QDBUS org.kde.plasmashell /PlasmaShell org.kde.PlasmaShell.evaluateScript "\$SCRIPT"
EOF
chmod 755 "$PREFIX/bin/omnia-layout"
cat > "$PREFIX/bin/omnia-maintain" <<EOF
#!/usr/bin/env bash
sleep 6
QDBUS=\$(command -v qdbus6 || command -v qdbus-qt6 || command -v qdbus) || exit 1
EMPTY_DESKTOP="$HOME/.local/share/omnia/empty-desktop"
mkdir -p "\$EMPTY_DESKTOP"
EMPTY_URL=\$(python3 -c 'from pathlib import Path; import sys; print(Path(sys.argv[1]).as_uri())' "\$EMPTY_DESKTOP")
SCRIPT=\$(python3 -c 'from pathlib import Path; import sys; print(Path(sys.argv[1]).read_text().replace("__OMNIA_EMPTY_DESKTOP_URL__", sys.argv[2]))' "$DATA/omnia/omnia-maintain.js" "\$EMPTY_URL")
for attempt in {1..10}; do
  "\$QDBUS" org.kde.plasmashell /PlasmaShell org.kde.PlasmaShell.evaluateScript "\$SCRIPT" && exit 0
  sleep 2
done
exit 1
EOF
chmod 755 "$PREFIX/bin/omnia-maintain"
# Ajustes gráficos persistentes, independientes del instalador temporal.
install -d "$DATA/omnia/installer/packaging/universal" "$DATA/omnia/assets/branding" "$DATA/applications"
GUI_BINARY="${OMNIA_GUI_BINARY:-$ROOT/omnia-installer}"
if [[ ! -x "$GUI_BINARY" ]]; then
  cmake -S "$ROOT/packaging/universal/gui" -B "$BUILD/gui" -DCMAKE_BUILD_TYPE=Release
  cmake --build "$BUILD/gui" --parallel 2
  GUI_BINARY="$BUILD/gui/omnia-installer"
fi
install -m755 "$GUI_BINARY" "$DATA/omnia/installer/omnia-installer"
install -m644 "$ROOT/packaging/universal/installer_backend.py" "$DATA/omnia/installer/packaging/universal/installer_backend.py"
install -m644 "$ROOT/packaging/universal/route_inspection.py" "$DATA/omnia/installer/packaging/universal/route_inspection.py"
install -m644 "$ROOT/packaging/universal/candidate_import.py" "$DATA/omnia/installer/packaging/universal/candidate_import.py"
install -m644 "$ROOT/assets/branding/omnia-icon-bluegray.png" "$DATA/omnia/assets/branding/omnia-logo.png"
install -m644 "$ROOT/assets/branding/omnia-menu.svg" "$DATA/omnia/assets/branding/omnia-menu.svg"
install -d "$HOME/.local/share/icons/hicolor/scalable/apps"
install -m644 "$ROOT/assets/branding/omnia-menu.svg" "$HOME/.local/share/icons/hicolor/scalable/apps/org.omnia.menu.svg"
# El HUD de MangoHud es propio de Omnia para no sobrescribir la configuración global del usuario.
MANGOHUD_CONFIG="$HOME/.config/omnia/MangoHud.conf"
if [[ -f "$ROOT/docs/MangoHud.conf" ]]; then
  python3 "$ROOT/packaging/universal/mangohud_config.py" "$ROOT/docs/MangoHud.conf" "$MANGOHUD_CONFIG"
fi
cat > "$PREFIX/bin/omnia-settings" <<EOF
#!/bin/sh
export PYTHONPATH="$PREFIX/lib/omnia\${PYTHONPATH:+:\$PYTHONPATH}"
exec "$DATA/omnia/installer/omnia-installer" "$DATA/omnia/installer/packaging/universal/installer_backend.py" --settings
EOF
chmod 755 "$PREFIX/bin/omnia-settings"
python3 - "$PREFIX/bin/omnia-settings" "$DATA/omnia/assets/branding/omnia-logo.png" "$DATA/applications/org.omnia.settings.desktop" <<'PYDESKTOP'
import sys
from pathlib import Path
executable, icon, desktop = sys.argv[1:]
# Escape para Exec de desktop, independiente del shell.
quoted = '"' + executable.replace('\\', '\\\\').replace('"', '\\"').replace('`', '\\`').replace('$', '\\$').replace('%', '%%') + '"'
Path(desktop).write_text('[Desktop Entry]\nType=Application\nName=Omnia — Ajustes generales\nComment=Bibliotecas, monitor y SteamGridDB\nExec=' + quoted + '\nIcon=' + icon + '\nTerminal=false\nCategories=Settings;Game;\n')
PYDESKTOP
install -m755 "$ROOT/packaging/universal/omnia-uninstall" "$PREFIX/bin/omnia-uninstall"
install -Dm644 "$ROOT/assets/branding/omnia-uninstall-icon.png" "$DATA/icons/hicolor/512x512/apps/org.omnia.uninstall.png"
python3 - "$ROOT/packaging/xdg/org.omnia.uninstall.desktop" "$PREFIX/bin/omnia-uninstall" "$DATA/applications/org.omnia.uninstall.desktop" <<'PYUNINSTALL'
import sys
from pathlib import Path
source, executable, destination = sys.argv[1:]
quoted = '"' + executable.replace('\\', '\\\\').replace('"', '\\"').replace('`', '\\`').replace('$', '\\$').replace('%', '%%') + '"'
Path(destination).write_text(Path(source).read_text().replace('Exec=omnia-uninstall', 'Exec=' + quoted))
PYUNINSTALL
export PATH="$PREFIX/bin:$PATH"
export PYTHONPATH="$PREFIX/lib/omnia${PYTHONPATH:+:$PYTHONPATH}"
# Estantería (versión anterior) usaba el mismo puerto 47831; si sigue activa, Omnia no arranca.
systemctl --user disable --now estanteria-helper.service >/dev/null 2>&1 || true
# Evita que la implementación antigua de capa QML tape o duplique el applet nativo.
systemctl --user disable --now omnia-ui.service >/dev/null 2>&1 || true
systemctl --user daemon-reload
if ((UPDATE)); then
  if [[ -n "${OMNIA_SETTINGS:-}" ]] && ! python3 "$ROOT/packaging/universal/installer_backend.py" --configure "$OMNIA_SETTINGS"; then
    exit 1
  fi
  systemctl --user restart omnia.service
  check_core
  command -v kbuildsycoca6 >/dev/null && kbuildsycoca6 --noincremental >/dev/null 2>&1 || true
  printf 'Omnia se actualizó. Se conservaron la biblioteca y los ajustes.\n'
  restart_plasma_if_approved
  commit_install_transaction
  exit 0
fi
if [[ -n "${OMNIA_SETTINGS:-}" ]]; then
  if ! python3 "$ROOT/packaging/universal/installer_backend.py" --configure "$OMNIA_SETTINGS"; then
    exit 1
  fi
  python3 -m omnia.firstrun --yes --force --script-src "$DATA/omnia/kwin"
else
  python3 -m omnia.firstrun --script-src "$DATA/omnia/kwin"
fi
systemctl --user enable --now omnia.service
systemctl --user restart omnia.service
check_core
command -v kbuildsycoca6 >/dev/null && kbuildsycoca6 --noincremental >/dev/null 2>&1 || true
# QML types are cached by the running plasmashell; restart it after replacing shared Omnia QML/applet files.
restart_plasma_if_approved
# Respalda el layout de Plasma antes de cambiarlo.
if [[ -f "$HOME/.config/plasma-org.kde.plasma.desktop-appletsrc" ]]; then
  install -d "$HOME/.config/omnia/layout-backups"
  cp -p "$HOME/.config/plasma-org.kde.plasma.desktop-appletsrc" "$HOME/.config/omnia/layout-backups/plasma-$(date +%Y%m%d-%H%M%S).conf"
fi
# Guarda únicamente wallpaper/carpeta originales; el desinstalador no sustituye paneles del usuario.
python3 -m omnia.uninstall --capture-desktop
LAYOUT_APPLIED=0
if command -v qdbus6 >/dev/null || command -v qdbus-qt6 >/dev/null || command -v qdbus >/dev/null; then
  if "$PREFIX/bin/omnia-layout"; then
    LAYOUT_APPLIED=1
    for applet in org.omnia.header org.omnia.hero org.omnia.activity org.omnia.system org.omnia.carousel; do
      rm -rf "$DATA/plasma/plasmoids/$applet"
    done
    command -v kbuildsycoca6 >/dev/null && kbuildsycoca6 --noincremental >/dev/null 2>&1 || true
  else
    printf 'Omnia: no pude aplicar el layout ahora; ejecuta omnia-layout desde la sesión Plasma.\n' >&2
  fi
else
  printf 'Omnia: no encontré qdbus; los widgets quedaron instalados, pero el layout requiere aplicarse desde una sesión Plasma.\n' >&2
fi

cat <<EOF
Omnia se instaló en este usuario (Plasma $PLASMA_VERSION).
Se instaló el wallpaper pasivo y un único widget Omnia a pantalla completa, adaptado al display.
El clic derecho fuera de las tarjetas deja disponible el menú contextual nativo de Plasma; las tarjetas conservan el menú de Omnia. Si el wallpaper aún no está seleccionado, elige “Omnia Animated Background” en Fondo de escritorio.
Meta+D/Meta se configuran después con omnia-setup si el paquete de integración está presente.
EOF
if ((!LAYOUT_APPLIED)); then
  exit 1
fi
if ((LAYOUT_APPLIED)); then
  printf 'Omnia: layout aplicado automáticamente en los escritorios disponibles.\n'
else
  printf 'Omnia: el layout no se aplicó; ejecuta omnia-layout desde una terminal en la sesión Plasma.\n' >&2
fi
commit_install_transaction

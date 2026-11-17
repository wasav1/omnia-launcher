#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
PREFIX="${HOME}/.local"
DATA="${HOME}/.local/share"
QML="$PREFIX/lib/qt6/qml"
DISTRO=""
NO_DEPS=0
CLI=0

usage() { printf 'Uso: %s [--cli] [--check] [--no-deps]\n' "$0"; }
CHECK=0
while (($#)); do
  case "$1" in
    --check) CHECK=1 ;;
    --cli) CLI=1 ;;
    --no-deps) NO_DEPS=1 ;;
    -h|--help) usage; exit 0 ;;
    *) usage >&2; exit 2 ;;
  esac
  shift
done

if ((!CLI && !CHECK)); then
  exec bash "$ROOT/packaging/universal/launch-gui.sh"
fi

die() { printf 'Omnia: %s\n' "$*" >&2; exit 1; }
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
PYVER="$(python3 -c 'import sys; print("%d.%d" % sys.version_info[:2])')"
python3 -c 'import sys; raise SystemExit(sys.version_info < (3,11))' || die "Omnia requiere Python >=3.11 (detectado: $PYVER)."

if [[ -r /etc/os-release ]]; then . /etc/os-release; DISTRO="${ID:-unknown}"; fi
if [[ -e /run/ostree-booted ]]; then
  die 'Esta edición es inmutable (OSTree). Requiere un flujo específico; usa una edición KDE tradicional por ahora.'
fi
packages=(cmake gcc-c++ qt6-declarative-devel)
case "$DISTRO" in
  arch|cachyos|endeavouros|manjaro) packages=(cmake gcc qt6-declarative) ;;
  fedora|nobara) packages=(cmake gcc-c++ qt6-qtdeclarative-devel) ;;
  opensuse*|suse) packages=(cmake gcc-c++ libQt6QuickControls2-devel qt6-declarative-devel) ;;
  ubuntu|debian|linuxmint|pop|neon|tuxedo) packages=(cmake g++ qt6-declarative-dev qt6-base-dev) ;;
  *) die "distro '$DISTRO' sin mapa de dependencias. Instala CMake, un compilador C++, Qt 6 Core/Qml y vuelve a ejecutar con --no-deps." ;;
esac

if ((CHECK)); then
  printf 'Plasma %s · %s · Python %s\n' "$PLASMA_VERSION" "$DISTRO" "$PYVER"
  for tool in cmake c++; do command -v "$tool" >/dev/null || printf 'Falta herramienta: %s\n' "$tool"; done
  qt6_dev_available || printf 'Faltan módulos de desarrollo Qt 6.\n'
  bash "$ROOT/packaging/universal/check-dependencies.sh" --check
  exit 0
fi

if ((NO_DEPS)); then
  bash "$ROOT/packaging/universal/check-dependencies.sh" --check
else
  bash "$ROOT/packaging/universal/check-dependencies.sh" --ensure
fi

if ! command -v cmake >/dev/null || ! command -v c++ >/dev/null || ! command -v kdialog >/dev/null || ! python3 -c "import gi" 2>/dev/null || ! qt6_dev_available; then
  ((NO_DEPS)) && die 'faltan cmake, compilador C++ o Qt 6 de desarrollo (--no-deps está activo).'
  printf 'Omnia necesita instalar dependencias de compilación Qt 6 para integrar el token de sesión de forma segura.\n'
  bash "$ROOT/packaging/universal/dependencies.sh"
fi

BUILD="$(mktemp -d)"
trap 'rm -rf "$BUILD"' EXIT
cmake -S "$ROOT/plasma/tokenprovider" -B "$BUILD/tokenprovider" -DCMAKE_BUILD_TYPE=Release -DCMAKE_INSTALL_PREFIX="$PREFIX" -DCMAKE_INSTALL_LIBDIR=lib
cmake --build "$BUILD/tokenprovider" --parallel "$(getconf _NPROCESSORS_ONLN 2>/dev/null || echo 2)"
cmake --install "$BUILD/tokenprovider"

install -d "$DATA/plasma/wallpapers/org.omnia.launcher" "$DATA/plasma/plasmoids/org.omnia.desktop" "$DATA/omnia/ui/plasma-widgets" "$DATA/omnia/kwin" "$PREFIX/lib/omnia" "$PREFIX/bin"
cp -a "$ROOT/plasma/wallpapers/org.omnia.launcher/." "$DATA/plasma/wallpapers/org.omnia.launcher/"
install -Dm644 "$ROOT/packaging/universal/omnia-layout.js" "$DATA/omnia/omnia-layout.js"
cp -a "$ROOT/plasma/applets/org.omnia.desktop/." "$DATA/plasma/plasmoids/org.omnia.desktop/"
# Mantén sincronizada la ruta plana heredada además de las rutas nuevas: una instalación antigua dejó
# OmniaShell.qml directamente en ~/.local/share/omnia/ui y Plasma aún puede resolver ese URL.
cp -a "$ROOT/ui/qml/." "$DATA/omnia/ui/"
cp -a "$ROOT/ui/qml" "$DATA/omnia/ui/"
cp -a "$ROOT/ui/qml" "$DATA/omnia/ui/plasma-widgets/"
for old in "$DATA/omnia/ui/BigMenu.qml" "$DATA/omnia/ui/qml/BigMenu.qml" "$DATA/omnia/ui/plasma-widgets/qml/BigMenu.qml"; do
  [[ ! -f "$old" ]] || rm -- "$old"
done
cp -a "$ROOT/core/omnia" "$PREFIX/lib/omnia/"
cp -a "$ROOT/kwin/omnia-showdesktop" "$ROOT/kwin/omnia-watch" "$DATA/omnia/kwin/"
for script in omnia-showdesktop omnia-watch; do
  install -d "$DATA/kwin/scripts/$script"
  cp -a "$ROOT/kwin/$script/." "$DATA/kwin/scripts/$script/"
done
install -d "$HOME/.config/systemd/user"
sed "s|^ExecStart=/usr/bin/omnia-core|ExecStart=$PREFIX/bin/omnia-core|" \
  "$ROOT/packaging/systemd/omnia.service" > "$HOME/.config/systemd/user/omnia.service"
install -d "$HOME/.config/plasma-workspace/env"
cat > "$HOME/.config/plasma-workspace/env/omnia.sh" <<EOF
#!/bin/sh
export QML_IMPORT_PATH="$QML\${QML_IMPORT_PATH:+:\$QML_IMPORT_PATH}"
EOF
chmod 755 "$HOME/.config/plasma-workspace/env/omnia.sh"
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
QDBUS=\$(command -v qdbus6 || command -v qdbus) || exit 1
EMPTY_DESKTOP="$HOME/.local/share/omnia/empty-desktop"
mkdir -p "\$EMPTY_DESKTOP"
EMPTY_URL=\$(python3 -c 'from pathlib import Path; import sys; print(Path(sys.argv[1]).as_uri())' "\$EMPTY_DESKTOP")
SCRIPT=\$(python3 -c 'from pathlib import Path; import sys; print(Path(sys.argv[1]).read_text().replace("__OMNIA_EMPTY_DESKTOP_URL__", sys.argv[2]))' "$DATA/omnia/omnia-layout.js" "\$EMPTY_URL")
exec \$QDBUS org.kde.plasmashell /PlasmaShell org.kde.PlasmaShell.evaluateScript "\$SCRIPT"
EOF
chmod 755 "$PREFIX/bin/omnia-layout"
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
install -m644 "$ROOT/assets/branding/omnia-logo.png" "$DATA/omnia/assets/branding/omnia-logo.png"
install -m644 "$ROOT/assets/branding/omnia-menu.svg" "$DATA/omnia/assets/branding/omnia-menu.svg"
install -d "$HOME/.local/share/icons/hicolor/scalable/apps"
install -m644 "$ROOT/assets/branding/omnia-menu.svg" "$HOME/.local/share/icons/hicolor/scalable/apps/org.omnia.menu.svg"
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
export PATH="$PREFIX/bin:$PATH"
export PYTHONPATH="$PREFIX/lib/omnia${PYTHONPATH:+:$PYTHONPATH}"
# Evita que la implementación antigua de capa QML tape o duplique el applet nativo.
systemctl --user disable --now omnia-ui.service >/dev/null 2>&1 || true
systemctl --user daemon-reload
bash "$ROOT/packaging/universal/configure-qml.sh"
if [[ -n "${OMNIA_SETTINGS:-}" ]]; then
  systemctl --user stop omnia.service
  if ! python3 "$ROOT/packaging/universal/installer_backend.py" --configure "$OMNIA_SETTINGS"; then
    systemctl --user start omnia.service || true
    exit 1
  fi
  python3 -m omnia.firstrun --yes --force --script-src "$DATA/omnia/kwin"
else
  python3 -m omnia.firstrun --script-src "$DATA/omnia/kwin"
fi
systemctl --user enable --now omnia.service
systemctl --user restart omnia.service
command -v kbuildsycoca6 >/dev/null && kbuildsycoca6 --noincremental >/dev/null 2>&1 || true
# QML types are cached by the running plasmashell; restart it after replacing shared Omnia QML/applet files.
printf 'Omnia: reiniciando plasmashell para recargar los módulos QML (el escritorio parpadeará unos segundos)…\n'
if ! systemctl --user restart plasma-plasmashell.service; then
  printf 'Omnia: no pude reiniciar Plasma automáticamente. Ejecuta: systemctl --user restart plasma-plasmashell.service\n' >&2
fi
# Respalda el layout de Plasma antes de cambiarlo.
if [[ -f "$HOME/.config/plasma-org.kde.plasma.desktop-appletsrc" ]]; then
  install -d "$HOME/.config/omnia/layout-backups"
  cp -p "$HOME/.config/plasma-org.kde.plasma.desktop-appletsrc" "$HOME/.config/omnia/layout-backups/plasma-$(date +%Y%m%d-%H%M%S).conf"
fi
LAYOUT_APPLIED=0
if command -v qdbus6 >/dev/null || command -v qdbus >/dev/null; then
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

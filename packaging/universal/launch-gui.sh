#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
export PYTHONDONTWRITEBYTECODE=1
if [[ "${KDE_SESSION_VERSION:-}" != 6 ]]; then
  command -v kdialog >/dev/null && kdialog --error 'Omnia requiere una sesión KDE Plasma 6. Inicia esa sesión antes de instalar.'
  exit 1
fi
if ((EUID == 0)); then echo 'Abre el asistente como usuario normal, sin sudo.' >&2; exit 1; fi
. "$ROOT/packaging/universal/distro.sh"
omnia_distro_detect
if omnia_is_ostree; then
  printf 'Omnia: sistema OSTree detectado (%s); el asistente instalará dependencias con rpm-ostree.\n' "$OMNIA_DISTRO_ID"
fi
CONFIG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/omnia"
DATA_DIR="${XDG_DATA_HOME:-$HOME/.local/share}/omnia"
UPDATE_ONLY=0
if [[ "${1:-}" != --uninstall* && ( -f "$CONFIG_DIR/library.json" || -x "$DATA_DIR/installer/omnia-installer" ) ]]; then
  UPDATE_ONLY=1
fi
if [[ "${1:-}" != --uninstall* && $UPDATE_ONLY == 0 ]]; then
  bash "$ROOT/packaging/universal/check-dependencies.sh" --ensure
fi
if [[ -x "$ROOT/omnia-installer" ]]; then
  set +e
  export OMNIA_GUI_BINARY="$ROOT/omnia-installer"
  "$ROOT/omnia-installer" "$ROOT/packaging/universal/installer_backend.py" "$@"
  status=$?
  set -e
  [[ "$status" == 0 ]] && exit 0
fi
command -v kdialog >/dev/null || { echo 'Falta kdialog para abrir el asistente. Instala kdialog y las dependencias Qt 6.' >&2; exit 1; }
BUILD="$(mktemp -d)"
trap 'rm -rf "$BUILD"' EXIT
if ! cmake -S "$ROOT/packaging/universal/gui" -B "$BUILD" >"$BUILD/log" 2>&1; then
  kdialog --title 'Omnia Desktop Suite' --yesno 'Para abrir el asistente se necesitan Qt 6 Widgets, CMake y un compilador. Se instalarán dependencias mediante el gestor de paquetes, con autenticación de KDE. ¿Continuar?' || exit 1
  bash "$ROOT/packaging/universal/dependencies.sh" || { kdialog --error 'No se pudieron instalar las dependencias.'; exit 1; }
  cmake -S "$ROOT/packaging/universal/gui" -B "$BUILD" >>"$BUILD/log" 2>&1 || { kdialog --error 'No se pudo preparar la interfaz gráfica.'; exit 1; }
fi
cmake --build "$BUILD" --parallel 2 >>"$BUILD/log" 2>&1 || { kdialog --error 'No se pudo compilar la interfaz gráfica.'; exit 1; }
export OMNIA_GUI_BINARY="$BUILD/omnia-installer"
"$BUILD/omnia-installer" "$ROOT/packaging/universal/installer_backend.py" "$@"

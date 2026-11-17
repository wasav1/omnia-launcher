#!/usr/bin/env bash
# Solo eleva el gestor de paquetes de la distribución, nunca la interfaz.
set -euo pipefail
. /etc/os-release
DISTRO="${ID:-unknown}"
command -v pkexec >/dev/null || { echo 'Falta pkexec y el agente de autenticación de KDE.' >&2; exit 1; }
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
case "$DISTRO" in
 arch|cachyos|endeavouros|manjaro)
   mapfile -t packages < <(python3 -c 'import json,sys; print("\n".join(json.load(open(sys.argv[1]))["arch"]["depends"]))' "$ROOT/packaging/distros/profiles.json")
   ((${#packages[@]})) || { echo 'No se pudo leer el mapa de dependencias.' >&2; exit 1; }
   exec pkexec /usr/bin/pacman -S --needed --noconfirm "${packages[@]}" ;;
 fedora|nobara) exec pkexec /usr/bin/dnf install -y cmake gcc-c++ qt6-qtbase-devel qt6-qtdeclarative-devel qt6-qt5compat kf6-kirigami kdialog python3-gobject ;;
 opensuse*|suse) exec pkexec /usr/bin/zypper --non-interactive install cmake gcc-c++ qt6-base-devel qt6-declarative-devel qt6-qt5compat-imports kf6-kirigami libksysguard6-imports kdialog python3-gobject ;;
 ubuntu|debian|linuxmint|pop|neon|tuxedo)
   pkexec /usr/bin/apt-get update
   exec pkexec /usr/bin/apt-get install -y cmake g++ qt6-base-dev qt6-declarative-dev qml6-module-qt5compat-graphicaleffects qml6-module-org-kde-kirigami qml6-module-qtquick-controls qml6-module-qtquick-effects qml6-module-qtquick-shapes qml6-module-qtquick-layouts qml6-module-qtquick-window qml6-module-org-kde-ksysguard kdialog python3-gi ;;
 *) echo "Distribución sin mapa de dependencias: $DISTRO. Instala Qt 6 Widgets/Qml, CMake, C++, kdialog y PyGObject." >&2; exit 1 ;;
esac

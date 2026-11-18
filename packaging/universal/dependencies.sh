#!/usr/bin/env bash
# Solo eleva el gestor de paquetes de la distribución, nunca la interfaz.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
. "$ROOT/packaging/universal/distro.sh"
omnia_distro_detect
DISTRO="$OMNIA_DISTRO_ID"
PROFILE="$(omnia_distro_profile)"
command -v pkexec >/dev/null || { echo 'Falta pkexec y el agente de autenticación de KDE.' >&2; exit 1; }

case "$PROFILE" in
  arch)
    mapfile -t packages < <(python3 -c 'import json,sys; print("\n".join(json.load(open(sys.argv[1]))["arch"]["depends"]))' "$ROOT/packaging/distros/profiles.json")
    ((${#packages[@]})) || { echo 'No se pudo leer el mapa de dependencias.' >&2; exit 1; }
    exec pkexec /usr/bin/pacman -S --needed --noconfirm "${packages[@]}" ;;
  fedora)
    mapfile -t packages < <(python3 -c 'import json,sys; print("\n".join(json.load(open(sys.argv[1]))["fedora"]["depends"]))' "$ROOT/packaging/distros/profiles.json")
    ((${#packages[@]})) || { echo 'No se pudo leer el mapa de dependencias.' >&2; exit 1; }
    if (( OMNIA_OSTREE )); then
      # En OSTree no se puede tocar /usr: se prepara una capa con rpm-ostree.
      # --idempotent evita fallar si la petición ya estaba hecha (p. ej. tras un
      # intento anterior que dejó el deployment preparado).
      pkexec /usr/bin/rpm-ostree install --idempotent "${packages[@]}" || exit $?
      # Aplicar en vivo solo es seguro si el cambio son adiciones. Si reemplaza o
      # retira paquetes base (típico al superponer -devel sobre un Qt algo más
      # antiguo), apply-live exige --allow-replacement y conviene reiniciar.
      if rpm-ostree db diff --format=diff 2>/dev/null | grep -qE '^[-!]'; then
        printf 'Omnia: las dependencias se prepararon en un nuevo deployment. Reinicia el equipo para activarlas y vuelve a ejecutar el instalador.\n' >&2
        exit 0
      fi
      if rpm-ostree install --help 2>/dev/null | grep -q -- '--apply-live'; then
        pkexec /usr/bin/rpm-ostree apply-live || \
          printf 'Omnia: no se pudo aplicar en vivo; reinicia para activar las dependencias.\n' >&2
      else
        printf 'Omnia: las dependencias se prepararon en un nuevo deployment. Reinicia el equipo para activarlas.\n' >&2
      fi
      exit 0
    fi
    exec pkexec /usr/bin/dnf install -y "${packages[@]}" ;;
  opensuse)
    exec pkexec /usr/bin/zypper --non-interactive install cmake gcc-c++ qt6-base-devel qt6-declarative-devel qt6-qt5compat-imports kf6-kirigami libksysguard6-imports kdialog python3-gobject mangohud pciutils ;;
  debian)
    pkexec /usr/bin/apt-get update
    exec pkexec /usr/bin/apt-get install -y cmake g++ qt6-base-dev qt6-declarative-dev qml6-module-qt5compat-graphicaleffects qml6-module-org-kde-kirigami qml6-module-qtquick-controls qml6-module-qtquick-effects qml6-module-qtquick-shapes qml6-module-qtquick-layouts qml6-module-qtquick-window qml6-module-org-kde-ksysguard kdialog python3-gi mangohud pciutils ;;
  *)
    echo "Distribución sin mapa de dependencias: $DISTRO ($PROFILE). Instala Qt 6 Widgets/Qml, CMake, C++, kdialog y PyGObject." >&2
    exit 1 ;;
esac

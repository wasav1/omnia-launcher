#!/usr/bin/env bash
# Detección de distro y modo OSTree para el asistente de Omnia.
# Se puede "sourcear" desde install.sh, launch-gui.sh y dependencies.sh.
# Funciona tanto en el host como dentro de un sandbox Flatpak (donde /etc/os-release
# es del runtime): en ese caso se usa /run/host/os-release, que Flatpak expone.

OMNIA_DISTRO_ID=""
OMNIA_DISTRO_LIKE=""
OMNIA_DISTRO_PRETTY=""
OMNIA_OSTREE=0

_omnia_distro_read_os_release() {
  # Imprime el contenido del os-release "real" del host. OMNIA_OS_RELEASE permite
  # forzar un archivo (pruebas). Flatpak expone el del sistema anfitrión en
  # /run/host/os-release; dentro del sandbox /etc/os-release corresponde al
  # runtime y debe ignorarse.
  if [[ -n "${OMNIA_OS_RELEASE:-}" && -r "$OMNIA_OS_RELEASE" ]]; then
    cat "$OMNIA_OS_RELEASE"
  elif [[ -r /run/host/os-release && -n "${FLATPAK_ID:-}" ]]; then
    cat /run/host/os-release
  elif [[ -r /etc/os-release ]]; then
    cat /etc/os-release
  elif [[ -r /usr/lib/os-release ]]; then
    cat /usr/lib/os-release
  fi
}

omnia_distro_detect() {
  local release ostree=0
  release="$(_omnia_distro_read_os_release)"
  OMNIA_DISTRO_ID="$(printf '%s\n' "$release" | sed -n 's/^ID="\{0,1\}\([^"]*\)"\{0,1\}$/\1/p' | head -n1)"
  # Estos campos forman parte de la interfaz del archivo cuando otro script lo carga.
  # shellcheck disable=SC2034
  OMNIA_DISTRO_LIKE="$(printf '%s\n' "$release" | sed -n 's/^ID_LIKE="\{0,1\}\([^"]*\)"\{0,1\}$/\1/p' | head -n1)"
  # shellcheck disable=SC2034
  OMNIA_DISTRO_PRETTY="$(printf '%s\n' "$release" | sed -n 's/^PRETTY_NAME="\{0,1\}\([^"]*\)"\{0,1\}$/\1/p' | head -n1)"
  OMNIA_DISTRO_ID="${OMNIA_DISTRO_ID:-unknown}"

  # OSTree: señal canónica /run/ostree-booted; en Flatpak se replica en /run/host.
  if [[ -e /run/ostree-booted || -e /run/host/ostree-booted ]] ||
     printf '%s\n' "$release" | grep -q '^OSTREE_VERSION='; then
    ostree=1
  fi
  # Bazzite siempre es OSTree aunque no haya marcador.
  if [[ "$OMNIA_DISTRO_ID" == bazzite ]]; then ostree=1; fi
  OMNIA_OSTREE=$ostree
}

omnia_is_bazzite() {
  [[ "$OMNIA_DISTRO_ID" == bazzite ]]
}

omnia_is_ostree() {
  (( OMNIA_OSTREE == 1 ))
}

# Imprime "bazzite" | "fedora" | "arch" | ... según el perfil de dependencias.
omnia_distro_profile() {
  case "$OMNIA_DISTRO_ID" in
    bazzite|fedora|nobara) echo fedora ;;
    cachyos|arch|archlinux|endeavouros|manjaro) echo arch ;;
    opensuse*|suse) echo opensuse ;;
    ubuntu|debian|linuxmint|pop|neon|tuxedo) echo debian ;;
    *) echo "$OMNIA_DISTRO_ID" ;;
  esac
}

# ¿Hay paquetes pedidos a rpm-ostree que aún no están en el deployment activo?
# Se cumple cuando hace falta reiniciar para que la capa esté disponible.
omnia_ostree_pending_packages() {
  (( OMNIA_OSTREE == 1 )) || return 1
  command -v rpm-ostree >/dev/null 2>&1 || return 1
  rpm-ostree status --json 2>/dev/null | python3 -c '
import json, sys
try:
    data = json.load(sys.stdin)
except Exception:
    sys.exit(1)
deployments = data.get("deployments", [])
pending = any(d.get("requested-packages") or d.get("requested-local-packages") for d in deployments)
sys.exit(0 if pending else 1)
' 2>/dev/null
}

# Bazzite (y cualquier OSTree basado en Fedora) usa rpm-ostree; Fedora tradicional usa dnf.
omnia_package_manager() {
  if (( OMNIA_OSTREE == 1 )); then
    echo rpm-ostree
  elif omnia_is_bazzite || [[ "$OMNIA_DISTRO_ID" == fedora || "$OMNIA_DISTRO_ID" == nobara ]]; then
    echo dnf
  else
    echo ""
  fi
}

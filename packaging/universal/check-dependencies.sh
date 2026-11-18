#!/usr/bin/env bash
# Mismo contrato para el paquete Arch, el .run, Fedora/Bazzite y la instalación CLI.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
. "$ROOT/packaging/universal/distro.sh"
omnia_distro_detect
PROFILE="$(omnia_distro_profile)"

package_list() {
  python3 -c 'import json,sys; value=json.load(open(sys.argv[1]))[sys.argv[2]]["depends"]; print("\n".join(value.split(",") if isinstance(value,str) else value))' \
    "$ROOT/packaging/distros/profiles.json" "$1"
}

missing=""
case "$PROFILE" in
  arch)
    command -v pacman >/dev/null || { echo 'Omnia: no encuentro pacman para comprobar las dependencias.' >&2; exit 1; }
    mapfile -t packages < <(package_list arch)
    ((${#packages[@]})) || { echo 'Omnia: no se pudo leer el mapa de dependencias.' >&2; exit 1; }
    # pacman -T devuelve 127 y la lista de paquetes que faltan.
    missing="$(pacman -T "${packages[@]}" || true)"
    ;;
  fedora)
    command -v rpm >/dev/null || { echo 'Omnia: no encuentro rpm para comprobar las dependencias.' >&2; exit 1; }
    # Los nombres del perfil Fedora incluyen restricciones de versión
    # ("python3 >= 3.11"): se consulta solo el nombre del paquete.
    mapfile -t packages < <(package_list fedora | sed 's/[[:space:]].*//')
    ((${#packages[@]})) || { echo 'Omnia: no se pudo leer el mapa de dependencias.' >&2; exit 1; }
    # No se parsea el texto de rpm (varía según idioma/versión): se consulta
    # cada paquete por nombre y se recoge el que falle. Si no existe el nombre
    # exacto se acepta cualquier paquete que lo provea (p. ej. Bazzite cubre
    # "mangohud" con "terra-mangohud").
    missing_list=()
    for package in "${packages[@]}"; do
      if rpm -q "$package" >/dev/null 2>&1; then
        continue
      fi
      rpm -q --whatprovides "$package" >/dev/null 2>&1 || missing_list+=("$package")
    done
    if ((${#missing_list[@]})); then
      missing="$(printf '%s\n' "${missing_list[@]}")"
    fi
    ;;
  debian)
    command -v dpkg-query >/dev/null || { echo 'Omnia: no encuentro dpkg-query para comprobar las dependencias.' >&2; exit 1; }
    mapfile -t packages < <(package_list debian | python3 -c 'import re,sys; print("\n".join(re.findall(r"^\s*([a-zA-Z0-9+.-]+)", sys.stdin.read(), re.M)))')
    ((${#packages[@]})) || { echo 'Omnia: no se pudo leer el mapa de dependencias Debian.' >&2; exit 1; }
    missing_list=()
    for package in "${packages[@]}"; do dpkg-query -W -f='${Status}' "$package" 2>/dev/null | grep -q 'install ok installed' || missing_list+=("$package"); done
    ((${#missing_list[@]})) && missing="$(printf '%s\n' "${missing_list[@]}")" || true
    ;;
  opensuse)
    command -v rpm >/dev/null || { echo 'Omnia: no encuentro rpm para comprobar las dependencias.' >&2; exit 1; }
    mapfile -t packages < <(package_list opensuse)
    ((${#packages[@]})) || { echo 'Omnia: no se pudo leer el mapa de dependencias openSUSE.' >&2; exit 1; }
    missing_list=()
    for package in "${packages[@]}"; do rpm -q "$package" >/dev/null 2>&1 || missing_list+=("$package"); done
    ((${#missing_list[@]})) && missing="$(printf '%s\n' "${missing_list[@]}")" || true
    ;;
  *)
    echo "Omnia: no hay comprobador de dependencias para $PROFILE." >&2
    exit 1
    ;;
esac

[[ -n "$missing" ]] || exit 0
printf 'Omnia: faltan dependencias:\n%s\n' "$missing" >&2
[[ "${1:---check}" == --ensure ]] || exit 1
message="Omnia necesita instalar estos paquetes:
$missing

Se usará el gestor de paquetes con autorización de KDE. ¿Continuar?"
if command -v kdialog >/dev/null; then
  kdialog --title 'Omnia Desktop Suite' --yesno "$message" || exit 1
elif [[ -t 0 ]]; then
  printf '%s [s/N] ' "$message"
  read -r answer
  [[ "$answer" == s || "$answer" == S ]] || exit 1
else
  echo 'Instala el paquete nativo con el gestor de paquetes de tu distro para resolver también kdialog y Polkit.' >&2
  exit 1
fi
bash "$ROOT/packaging/universal/dependencies.sh"
exec bash "$0" --check

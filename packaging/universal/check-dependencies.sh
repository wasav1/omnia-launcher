#!/usr/bin/env bash
# Mismo contrato para el paquete Arch, el .run y la instalación CLI.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
. /etc/os-release
case "${ID:-}" in arch|cachyos|endeavouros|manjaro) ;; *) exit 0 ;; esac
mapfile -t packages < <(python3 -c 'import json,sys; print("\n".join(json.load(open(sys.argv[1]))["arch"]["depends"]))' "$ROOT/packaging/distros/profiles.json")
((${#packages[@]})) || { echo 'Omnia: no se pudo leer el mapa de dependencias.' >&2; exit 1; }
status=0
missing="$(pacman -T "${packages[@]}")" || status=$?
if ((status == 0)); then exit 0; fi
if ((status != 127)); then echo 'Omnia: no se pudieron comprobar las dependencias.' >&2; exit 1; fi
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
  echo 'Instala el paquete nativo con sudo pacman -U: resolverá también kdialog y Polkit.' >&2
  exit 1
fi
bash "$ROOT/packaging/universal/dependencies.sh"
exec bash "$0" --check

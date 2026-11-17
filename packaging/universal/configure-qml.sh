#!/usr/bin/env bash
# Plasma se inicia desde systemd: el script de sesión por sí solo no actualiza el gestor activo.
set -euo pipefail
QML="$HOME/.local/lib/qt6/qml"
manager_path="$(systemctl --user show-environment | sed -n 's/^QML_IMPORT_PATH=//p')"
import_path="$QML"
IFS=: read -r -a existing <<< "${manager_path:-${QML_IMPORT_PATH:-}}"
for directory in "${existing[@]}"; do
  [[ -z "$directory" || "$directory" == "$QML" ]] || import_path+=":$directory"
done
install -d "$HOME/.config/environment.d"
# environment.d admite expansión de HOME y preserva rutas aportadas por otros componentes.
cat > "$HOME/.config/environment.d/60-omnia-qml.conf" <<'ENV'
QML_IMPORT_PATH=${HOME}/.local/lib/qt6/qml${QML_IMPORT_PATH:+:${QML_IMPORT_PATH}}
ENV
systemctl --user set-environment "QML_IMPORT_PATH=$import_path"

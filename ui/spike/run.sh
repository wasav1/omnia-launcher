#!/usr/bin/env bash
# Prueba de la capa de fondo de Omnia (60 s). Uso: ./run.sh [clic|auto|ventana]
#   clic     (por defecto) empieza en «sin probar»: haz clic en «Probar API» y el texto debe cambiar
#   auto     llama a la API al arrancar
#   ventana  ventana normal en vez de capa de fondo
cd "$(dirname "$0")"
export QML_XHR_ALLOW_FILE_READ=1 QT_WAYLAND_SHELL_INTEGRATION=layer-shell
TOKEN="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/omnia/token"
case "${1:-clic}" in
  clic)    exec timeout 60 qml6 spike-layer.qml -- --token "$TOKEN" ;;
  auto)    exec timeout 60 qml6 spike-layer.qml -- --token "$TOKEN" --auto ;;
  ventana) exec timeout 60 qml6 spike-window.qml -- --token "$TOKEN" ;;
  *) echo "uso: $0 [clic|auto|ventana]" >&2; exit 2 ;;
esac

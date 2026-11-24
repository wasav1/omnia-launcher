#!/usr/bin/env bash
# Abre o cierra el panel rápido de Omnia. Una instancia mínima de Quickshell carga solo OmniaEdge (el panel) y se arranca si hace falta.
set -euo pipefail

CONFIG="${OMNIA_DUX_PANEL_CONFIG:-$HOME/.config/quickshell/ii/omnia-dms-shell.qml}"
STATE_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/omnia"
LOG="$STATE_DIR/quick-panel.log"
mkdir -p "$STATE_DIR"

panel_ipc() {
    local method="$1"
    shift
    qs -p "$CONFIG" ipc call omnia "$method" "$@" 2>/dev/null
}

if ! panel_ipc status >/dev/null; then
    nohup qs -p "$CONFIG" >>"$LOG" 2>&1 </dev/null &
    ready=0
    for _ in {1..40}; do
        if panel_ipc status >/dev/null; then
            ready=1
            break
        fi
        sleep 0.15
    done
    if [[ "$ready" -ne 1 ]]; then
        printf 'No arrancó el panel Quickshell de Omnia. Revisa %s\n' "$LOG" >&2
        exit 1
    fi
fi

if [[ "${1:-}" == "bar" ]]; then
    panel_ipc barToggle "${2:-0}"
else
    panel_ipc toggle
fi

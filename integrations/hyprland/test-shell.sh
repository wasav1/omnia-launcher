#!/usr/bin/env bash
# Prueba aislada del módulo Omnia: NO toca ~/.config/quickshell/ii ni la config de illogical-impulse.
# Copia ii y sus ajustes a un directorio temporal, instala allí el módulo y abre una segunda instancia de Quickshell
# con una barra falsa (esquina superior derecha) + el borde derecho. El fondo se «aplica» solo en la copia.
# Uso: ./test-shell.sh [--keep]     Cierra con Ctrl+C. Afecta solo a esta sesión gráfica mientras corre.
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
T="$(mktemp -d "${TMPDIR:-/tmp}/omnia-hypr-test.XXXXXX")"
trap '[ "${1:-}" = "--keep" ] || rm -rf "$T"' EXIT
mkdir -p "$T/xdg" "$T/state"
cp -r "${XDG_CONFIG_HOME:-$HOME/.config}/quickshell/ii" "$T/ii"
cp -r "${XDG_CONFIG_HOME:-$HOME/.config}/illogical-impulse" "$T/xdg/"
mkdir -p "$T/state/quickshell" && cp -r "${XDG_STATE_HOME:-$HOME/.local/state}/quickshell/user" "$T/state/quickshell/" 2>/dev/null || true
mkdir -p "$T/xdg/omnia" && EXTRA=""; [ -n "${OMNIA_TEST_PORT:-}" ] && EXTRA=",\"port\":${OMNIA_TEST_PORT},\"tokenFile\":\"${OMNIA_TEST_TOKEN}\""   # núcleo aislado (test-core.sh)
printf '{"libraryCommand":["%s","--window"]%s}\n' "$HERE/../../ui/omnia-ui" "$EXTRA" > "$T/xdg/omnia/hyprland.json"
XDG_STATE_HOME="$T/ostate" "$HERE/omnia-hyprland" install --target "$T/ii" >/dev/null
cat > "$T/ii/omnia-test-shell.qml" <<'QML'
//@ pragma UseQApplication
//@ pragma Env QT_QUICK_CONTROLS_STYLE=Basic
import qs.modules.common
import qs.services
import qs.modules.ii.bar
import qs.modules.ii.omnia
import QtQuick
import QtQuick.Layouts
import Quickshell
ShellRoot {
    Component.onCompleted: MaterialThemeLoader.reapplyTheme()      // misma paleta que la shell real
    // barra falsa a lo ancho (misma altura que la de ii) con el botón de Omnia a la derecha
    PanelWindow {
        anchors { top: true; left: true; right: true }
        implicitHeight: Appearance.sizes.barHeight
        color: "#0B0F14"
        RowLayout { anchors { right: parent.right; rightMargin: 120; verticalCenter: parent.verticalCenter } OmniaButton {} }
    }
    OmniaEdge {}
}
QML
echo "Config de prueba en $T (fondo escrito en $T/xdg/illogical-impulse/config.json)"
XDG_CONFIG_HOME="$T/xdg" XDG_STATE_HOME="$T/state" exec qs -p "$T/ii/omnia-test-shell.qml"

pragma Singleton

import qs.modules.common
import qs.modules.common.functions
import QtQuick
import Quickshell

/**
 * Colores del panel: salen de la paleta de illogical-impulse para que el panel parezca parte de la shell. En esta
 * instalación esa paleta es Omnia oscuro (fondo #0B0F14, superficies #151D27, texto #F0F3F7, acento #336599) con la
 * generación de colores desde el wallpaper desactivada, así que no cambia al cambiar de fondo.
 */
Singleton {
    readonly property color bg: Appearance.colors.colLayer0Base
    readonly property color surface: Appearance.colors.colLayer1Base
    readonly property color ink: Appearance.colors.colOnLayer0
    readonly property color inkDim: Appearance.colors.colSubtext
    readonly property color accent: Appearance.m3colors.m3primary
    readonly property color accentHi: Appearance.colors.colPrimaryHover
    readonly property color ring: Qt.lighter(Appearance.m3colors.m3primary, 1.55)
    readonly property color ok: "#6fc3a0"
    readonly property color danger: Appearance.m3colors.m3error
    readonly property color line: Qt.rgba(1, 1, 1, 0.08)

    // Casi opaco: con desenfoque queda un leve velo translúcido; sin él, aún más sólido.
    function panel(blur) { return ColorUtils.transparentize(Appearance.colors.colLayer0Base, blur ? 0.05 : 0.01) }
    function card(blur) { return ColorUtils.transparentize(Appearance.colors.colLayer1Base, blur ? 0.10 : 0.02) }
    function rowSelected() { return Qt.rgba(accent.r, accent.g, accent.b, 0.88) }
}

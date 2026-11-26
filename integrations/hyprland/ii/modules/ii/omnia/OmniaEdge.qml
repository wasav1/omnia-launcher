pragma ComponentBehavior: Bound

import qs
import qs.services
import qs.modules.common
import QtQuick
import Quickshell
import Quickshell.Wayland

/**
 * Por monitor: la superficie del panel (OmniaPanelWindow) y, si la activación incluye el borde, una franja de 2 px
 * (zona de activación) en el borde elegido: Izquierdo, Derecho, Superior o Inferior, con posición Inicio, Centro o
 * Fin. Por defecto solo en el monitor más exterior de ese borde: la unión entre pantallas queda libre.
 */
Variants {
    id: root
    model: Quickshell.screens

    Scope {
        id: scope
        required property var modelData

        readonly property string side: OmniaSettings.edgeSide
        readonly property string pos: OmniaSettings.edgePosition
        readonly property bool horizontal: side === "top" || side === "bottom"
        readonly property var scr: Quickshell.screens
        readonly property bool outermost: {
            const m = modelData;
            switch (side) {
            case "right": return m.x + m.width >= Math.max(...scr.map(s => s.x + s.width));
            case "left": return m.x <= Math.min(...scr.map(s => s.x));
            case "top": return m.y <= Math.min(...scr.map(s => s.y));
            default: return m.y + m.height >= Math.max(...scr.map(s => s.y + s.height));
            }
        }
        readonly property bool zoneAllowed: OmniaSettings.edgeEnabled && (OmniaSettings.edgeMonitors === "all" || outermost)
        // longitud de la zona (porcentaje del borde) y su desplazamiento según la posición
        readonly property real edgeLen: horizontal ? modelData.width : modelData.height
        readonly property real zoneLen: edgeLen * OmniaSettings.zoneHeightPct / 100
        readonly property real before: pos === "start" ? 0 : pos === "end" ? edgeLen - zoneLen : (edgeLen - zoneLen) / 2
        readonly property real after: edgeLen - zoneLen - before

        OmniaPanelWindow { modelData: scope.modelData }

        PanelWindow {
            id: zone
            screen: scope.modelData
            visible: scope.zoneAllowed
            color: "transparent"
            exclusionMode: ExclusionMode.Ignore
            WlrLayershell.namespace: "quickshell:omniaEdge"
            WlrLayershell.layer: WlrLayer.Top
            anchors {
                right: scope.side === "right" || scope.horizontal
                left: scope.side === "left" || scope.horizontal
                top: scope.side === "top" || !scope.horizontal
                bottom: scope.side === "bottom" || !scope.horizontal
            }
            margins {
                top: !scope.horizontal ? scope.before : 0
                bottom: !scope.horizontal ? scope.after : 0
                left: scope.horizontal ? scope.before : 0
                right: scope.horizontal ? scope.after : 0
            }
            implicitWidth: scope.horizontal ? 0 : OmniaSettings.zoneWidthPx
            implicitHeight: scope.horizontal ? OmniaSettings.zoneWidthPx : 0

            Timer {
                id: reveal
                interval: OmniaSettings.revealDelayMs
                onTriggered: OmniaPanelState.peek(scope.modelData.name)
            }
            HoverHandler {
                onHoveredChanged: {
                    OmniaPanelState.hoverZone = hovered;
                    if (hovered) {
                        if (OmniaPanelState.mode === "peek" && OmniaPanelState.screenName === scope.modelData.name) OmniaPanelState.holdOpen();
                        else if (OmniaPanelState.canPeek) reveal.restart();
                    } else {
                        reveal.stop();
                        OmniaPanelState.leave();
                    }
                }
            }
        }
    }
}

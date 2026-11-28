import QtQuick
import "Theme.js" as Theme

// Panel de cristal del rediseño D (docs/PLAN-REDISENO-D.md).
// Desenfoca lo que hay detrás (FrostedSurface), aplica un velo, un borde claro
// y un brillo en el canto superior. Sin `backdrop`, o con `glass: false`
// (Ajustes → Apariencia, o mientras hay un juego abierto), se dibuja como un
// panel casi opaco con el mismo borde: nunca queda texto sobre algo ilegible.
//
//   GlassPanel {
//       width: Theme.size.panelDetail; height: 600
//       backdrop: fondo                  // Item que hay detrás
//       backdropRect: Qt.rect(x, y, width, height)
//       Text { text: "Hola"; color: Theme.color.ink }
//   }
Item {
    id: panel

    property Item backdrop
    property rect backdropRect: Qt.rect(x, y, width, height)
    property bool glass: true
    property bool strong: false            // paneles principales: un poco más de relleno y borde
    property real radius: Theme.radius.xl
    property bool highlight: true          // brillo del canto superior
    property color fill: strong ? Theme.color.glassFillStrong : Theme.color.glassFill
    property color borderColor: strong ? Theme.color.glassBorderStrong : Theme.color.glassBorder

    readonly property bool sampling: glass && visible && backdrop !== null && width > 0 && height > 0
    default property alias content: body.data

    FrostedSurface {
        anchors.fill: parent
        visible: panel.sampling
        backdrop: panel.backdrop
        backdropRect: panel.backdropRect
        sampling: panel.sampling
        tint: Theme.color.glassTint
        radius: panel.radius
        feather: 2
    }

    Rectangle {
        id: fallback
        anchors.fill: parent
        visible: !panel.sampling
        radius: panel.radius
        color: Theme.color.glassFallback
    }

    Rectangle {
        id: veil
        anchors.fill: parent
        radius: panel.radius
        color: panel.fill
        border.width: 1
        border.color: panel.borderColor
    }

    Rectangle {
        id: shine
        visible: panel.highlight
        height: 1
        anchors { top: parent.top; topMargin: 1; left: parent.left; right: parent.right; leftMargin: panel.radius * 0.6; rightMargin: panel.radius * 0.6 }
        color: Theme.color.glassHighlight
    }

    Item {
        id: body
        anchors.fill: parent
        clip: false
    }
}

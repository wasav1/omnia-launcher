pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Window

/**
 * Fondo de BigMode: la imagen del juego (siempre la de mayor resolución) ocupa la zona superior derecha y se funde
 * con el color base por la izquierda y por abajo. Se ve nítida: sin desenfoque, sin desaturar, a resolución nativa.
 *   · la imagen toma el alto de la zona con su proporción original;
 *   · si es más ancha que la zona, se desliza muy despacio de derecha a izquierda y vuelve (movimiento continuo);
 *   · si es más estrecha, queda pegada a la derecha.
 * Al cambiar de imagen hay un fundido cruzado.
 */
Item {
    id: bd
    property url source: ""
    property color base: "#0B0F14"
    property bool animate: true
    property real regionWidth: 0.88          // fracción del ancho / alto que ocupa la imagen (arriba a la derecha)
    property real regionHeight: 0.80
    property real pan: 0.15
    property real panFrom: 0.15              // recorrido: el sujeto de la imagen (centrado) se mueve entre dos puntos visibles
    property real panTo: 0.60
    property int panMs: 18000                // duración de cada tramo (ida o vuelta)
    property Layer front: a
    property Layer back: b
    clip: true

    Rectangle { anchors.fill: parent; color: bd.base }

    // zona de la imagen
    Item {
        id: region
        anchors { top: parent.top; right: parent.right }
        width: bd.width * bd.regionWidth
        height: bd.height * bd.regionHeight
        clip: true

        Layer { id: a }
        Layer { id: b }

        // fundidos: izquierda y abajo hacia el color base
        Rectangle {
            anchors.fill: parent
            gradient: Gradient {
                orientation: Gradient.Horizontal
                GradientStop { position: 0.00; color: bd.base }
                GradientStop { position: 0.12; color: Qt.rgba(bd.base.r, bd.base.g, bd.base.b, 0.82) }
                GradientStop { position: 0.40; color: Qt.rgba(bd.base.r, bd.base.g, bd.base.b, 0.22) }
                GradientStop { position: 0.62; color: "transparent" }
            }
        }
        Rectangle {
            anchors.fill: parent
            gradient: Gradient {
                GradientStop { position: 0.00; color: Qt.rgba(bd.base.r, bd.base.g, bd.base.b, 0.30) }
                GradientStop { position: 0.14; color: "transparent" }
                GradientStop { position: 0.52; color: "transparent" }
                GradientStop { position: 0.80; color: Qt.rgba(bd.base.r, bd.base.g, bd.base.b, 0.70) }
                GradientStop { position: 1.00; color: bd.base }
            }
        }
    }

    SequentialAnimation on pan {
        running: bd.animate && bd.visible && bd.source.toString() !== ""
        loops: Animation.Infinite
        NumberAnimation { from: bd.panFrom; to: bd.panTo; duration: bd.panMs; easing.type: Easing.InOutSine }
        NumberAnimation { from: bd.panTo; to: bd.panFrom; duration: bd.panMs; easing.type: Easing.InOutSine }
    }

    function crossfade() {
        back.opacity = 1
        front.opacity = 0
        const t = front
        front = back
        back = t
    }
    onSourceChanged: {
        if (source.toString() === "") { a.source = ""; b.source = ""; a.opacity = 0; b.opacity = 0; return }
        if (source === front.source) { front.opacity = 1; return }
        back.source = source
        if (back.status === Image.Ready) crossfade()
    }

    component Layer: Item {
        id: imageLayer
        property alias source: img.source
        readonly property alias status: img.status
        anchors.fill: parent
        opacity: 0
        Behavior on opacity { NumberAnimation { duration: 600; easing.type: Easing.InOutQuad } }

        Image {
            id: img
            readonly property real aspect: implicitWidth > 0 && implicitHeight > 0 ? implicitWidth / implicitHeight : 16 / 9
            height: imageLayer.height
            width: Math.round(height * aspect)
            x: width > imageLayer.width ? -(width - imageLayer.width) * bd.pan : imageLayer.width - width
            asynchronous: true
            cache: false
            smooth: true
            mipmap: true
            fillMode: Image.Stretch
            sourceSize.height: Math.round(imageLayer.height * Screen.devicePixelRatio)
        }
    }
    Connections { target: a; function onStatusChanged() { if (a.status === Image.Ready && bd.back === a) bd.crossfade() } }
    Connections { target: b; function onStatusChanged() { if (b.status === Image.Ready && bd.back === b) bd.crossfade() } }
}

import QtQuick
import QtQuick.Effects

// Telón del juego seleccionado: fundido cruzado y desenfoque esmerilado del prototipo.
Item {
    id: bd
    property url source: ""
    property real blur: 0
    property Item front: a
    property Item back: b
    property real pan: 0
    clip: true

    SequentialAnimation on pan {
        running: bd.source.toString() !== ""
        loops: Animation.Infinite
        NumberAnimation { from:0; to:1; duration:150000; easing.type:Easing.InOutSine }
        NumberAnimation { from:1; to:0; duration:150000; easing.type:Easing.InOutSine }
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
        id: layer
        property alias source: img.source
        readonly property alias status: img.status
        property real panProgress: bd.pan
        anchors.fill: parent
        opacity: 0
        Behavior on opacity { NumberAnimation { duration: 450; easing.type: Easing.InOutQuad } }
        // Alto = 100 % de la pantalla (sin recorte vertical ni zoom); el ancho sobrante da el recorrido del paneo horizontal.
        // Si la imagen no es más ancha que la pantalla se ensancha un 10 % para que siempre haya un movimiento suave.
        Item {
            id: stage
            readonly property real aspect: img.implicitWidth > 0 && img.implicitHeight > 0 ? img.implicitWidth / img.implicitHeight : 16 / 9
            width: Math.max(parent.width * 1.10, parent.height * aspect)
            height: parent.height
            x: -(width - parent.width) * layer.panProgress
            y: 0
            Image {
                id: img
                anchors.fill: parent; visible: false
                asynchronous: true; cache: true; smooth: true
                fillMode: Image.PreserveAspectCrop
                sourceSize.height: 1080
            }
            MultiEffect {
                anchors.fill: parent
                source: img
                blurEnabled: bd.blur > 0
                blur: Math.min(1, bd.blur / 32)
                blurMax: 32
                saturation: -0.16
            }
        }
    }
    Layer { id: a }
    Layer { id: b }
    Connections { target: a; function onStatusChanged() { if (a.status === Image.Ready && bd.back === a) bd.crossfade() } }
    Connections { target: b; function onStatusChanged() { if (b.status === Image.Ready && bd.back === b) bd.crossfade() } }
}

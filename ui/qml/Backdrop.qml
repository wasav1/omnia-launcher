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
        NumberAnimation { from:0; to:1; duration:80000; easing.type:Easing.InOutSine }
        NumberAnimation { from:1; to:0; duration:80000; easing.type:Easing.InOutSine }
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
        Item {
            id: stage
            width: parent.width * 1.14
            height: parent.height * 1.14
            x: -(width - parent.width) * layer.panProgress
            y: (parent.height - height) / 2
            Image {
                id: img
                anchors.fill: parent; visible: false
                asynchronous: true; cache: true; smooth: true
                fillMode: Image.PreserveAspectCrop
                sourceSize.width: 1920
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

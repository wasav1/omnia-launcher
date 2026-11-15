import QtQuick

// Telón de fondo con fundido cruzado: al cambiar el juego seleccionado, la imagen nueva entra mientras sale la anterior.
Item {
    id: bd
    property url source: ""
    property Image front: a
    property Image back: b
    clip: true

    function crossfade() {
        back.opacity = 1
        front.opacity = 0
        const t = front
        front = back
        back = t
    }

    onSourceChanged: {
        if (source.toString() === "") { a.opacity = 0; b.opacity = 0; return }
        if (source === front.source) { front.opacity = 1; return }
        back.source = source
        if (back.status === Image.Ready) crossfade()       // ya estaba en caché
    }

    component Layer: Image {
        anchors.fill: parent
        opacity: 0
        asynchronous: true
        cache: true
        fillMode: Image.PreserveAspectCrop
        sourceSize.width: 1920
        Behavior on opacity { NumberAnimation { duration: 450; easing.type: Easing.InOutQuad } }
    }
    Layer { id: a }
    Layer { id: b }
    Connections { target: a; function onStatusChanged() { if (a.status === Image.Ready && bd.back === a) bd.crossfade() } }
    Connections { target: b; function onStatusChanged() { if (b.status === Image.Ready && bd.back === b) bd.crossfade() } }
}

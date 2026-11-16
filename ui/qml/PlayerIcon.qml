import QtQuick

// Iconos del reproductor dibujados a mano (los del prototipo): anterior, reproducir/pausar y siguiente.
// kind: "prev" | "next" | "play" | "pause".
Canvas {
    id: ic
    property string kind: "play"
    property color color: "#f3efe3"
    width: 24; height: 24
    onKindChanged: requestPaint()
    onColorChanged: requestPaint()
    Component.onCompleted: requestPaint()
    onPaint: {
        const c = getContext("2d"); c.reset()
        c.fillStyle = ic.color
        if (kind === "prev") { c.fillRect(6, 5, 2, 14); c.beginPath(); c.moveTo(20, 5); c.lineTo(20, 19); c.lineTo(9, 12); c.closePath(); c.fill() }
        else if (kind === "next") { c.fillRect(16, 5, 2, 14); c.beginPath(); c.moveTo(4, 5); c.lineTo(4, 19); c.lineTo(15, 12); c.closePath(); c.fill() }
        else if (kind === "pause") { c.fillRect(6, 4, 4, 16); c.fillRect(14, 4, 4, 16) }
        else { c.beginPath(); c.moveTo(7, 4); c.lineTo(20, 12); c.lineTo(7, 20); c.closePath(); c.fill() }
    }
}

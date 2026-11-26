import QtQuick
import Qt5Compat.GraphicalEffects

// Iconos sencillos de plataforma (dibujados, no son logos oficiales).
Canvas {
    id: c
    property string key: "n64"
    property color color: "white"
    property real size: 18
    // Si existe images/plat/<clave>.svg (una sola tinta) se tiñe con el color de la plataforma;
    // si no, se dibuja el icono propio de abajo.
    readonly property bool hasSvg: svg.status === Image.Ready
    readonly property real asp: hasSvg && svg.implicitHeight > 0 ? Math.min(2, svg.implicitWidth / svg.implicitHeight) : 1
    width: size * asp; height: size
    Image {
        id: svg
        source: ["n64", "sw1", "sw2", "pc", "steam", "hydra", "heroic", "lutris", "gfn", "ps3", "ps4", "ps5"].indexOf(c.key) >= 0 ? Qt.resolvedUrl("images/plat/" + c.key + ".svg") : ""
        sourceSize.height: Math.round(c.size * 3)
        fillMode: Image.PreserveAspectFit
        anchors.fill: parent
        visible: false
        asynchronous: false
    }
    ColorOverlay { anchors.fill: parent; source: svg; color: c.color; visible: c.hasSvg }
    onHasSvgChanged: requestPaint()
    onKeyChanged: requestPaint()
    onColorChanged: requestPaint()
    onSizeChanged: requestPaint()
    onPaint: {
        var ctx = getContext("2d")
        ctx.reset()
        if (hasSvg) return
        var k = size / 24
        ctx.scale(k, k)
        ctx.strokeStyle = color; ctx.fillStyle = color; ctx.lineWidth = 2
        function rr(x, y, w, h, r) {
            ctx.beginPath()
            ctx.moveTo(x + r, y); ctx.lineTo(x + w - r, y); ctx.quadraticCurveTo(x + w, y, x + w, y + r)
            ctx.lineTo(x + w, y + h - r); ctx.quadraticCurveTo(x + w, y + h, x + w - r, y + h)
            ctx.lineTo(x + r, y + h); ctx.quadraticCurveTo(x, y + h, x, y + h - r)
            ctx.lineTo(x, y + r); ctx.quadraticCurveTo(x, y, x + r, y)
        }
        if (key === "n64") {
            ctx.font = "bold 15px Orbitron"; ctx.textAlign = "center"; ctx.fillText("64", 12, 17)
        } else if (key === "sw1" || key === "sw2") {
            var o = key === "sw2" ? 1 : 0
            rr(3 - o, 4 + o, 7 + o, 16 - 2 * o, 3); ctx.stroke()
            rr(14, 4 + o, 7 + o, 16 - 2 * o, 3); ctx.fill()
        } else if (["nes", "snes", "gb", "gbc", "gba", "nds", "gcwii", "3ds", "switch", "ps1", "ps2", "psp"].indexOf(key) >= 0) {
            ctx.lineCap = "round"; ctx.lineJoin = "round"
            ctx.beginPath(); ctx.moveTo(7, 7); ctx.lineTo(17, 7); ctx.quadraticCurveTo(20, 7, 21, 11)
            ctx.lineTo(22, 16); ctx.quadraticCurveTo(22, 19, 19, 19); ctx.lineTo(16, 16)
            ctx.lineTo(8, 16); ctx.lineTo(5, 19); ctx.quadraticCurveTo(2, 19, 2, 16); ctx.lineTo(3, 11)
            ctx.quadraticCurveTo(4, 7, 7, 7); ctx.stroke()
            ctx.beginPath(); ctx.moveTo(6, 10); ctx.lineTo(6, 14); ctx.moveTo(4, 12); ctx.lineTo(8, 12); ctx.stroke()
            ctx.beginPath(); ctx.arc(17, 11, 1, 0, 6.2832); ctx.fill(); ctx.beginPath(); ctx.arc(19, 14, 1, 0, 6.2832); ctx.fill()
        } else if (key === "steam") {
            ctx.beginPath(); ctx.arc(12, 12, 8.5, 0, 6.2832); ctx.stroke()
            ctx.beginPath(); ctx.arc(15, 9.5, 2.6, 0, 6.2832); ctx.fill()
            ctx.beginPath(); ctx.arc(8.5, 15, 1.8, 0, 6.2832); ctx.fill()
        } else if (key === "gfn") {
            ctx.lineCap = "round"
            ctx.beginPath(); ctx.rect(4, 6, 16, 9); ctx.stroke()
            ctx.beginPath(); ctx.moveTo(9, 19); ctx.lineTo(15, 19); ctx.stroke()
        } else {
            ctx.beginPath(); ctx.moveTo(12, 3); ctx.lineTo(20, 7); ctx.lineTo(20, 13)
            ctx.quadraticCurveTo(20, 19, 12, 21); ctx.quadraticCurveTo(4, 19, 4, 13); ctx.lineTo(4, 7)
            ctx.closePath(); ctx.stroke()
        }
    }
}

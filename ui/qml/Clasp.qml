import QtQuick

// Broche separador: línea con adorno de rombos y extremos difuminados.
Canvas {
    id: c
    width: 320; height: 26
    property color color: "#91a9c2"
    onColorChanged: requestPaint()
    onPaint: {
        var ctx = getContext("2d")
        ctx.reset()
        var col = Qt.rgba(color.r, color.g, color.b, 1)
        function a(al) { return Qt.rgba(color.r, color.g, color.b, al) }
        var gl = ctx.createLinearGradient(0, 0, 126, 0)
        gl.addColorStop(0, a(0)); gl.addColorStop(0.5, a(0.4)); gl.addColorStop(1, a(0.85))
        var gr = ctx.createLinearGradient(194, 0, 320, 0)
        gr.addColorStop(0, a(0.85)); gr.addColorStop(0.5, a(0.4)); gr.addColorStop(1, a(0))
        ctx.lineWidth = 1.5
        ctx.strokeStyle = gl; ctx.beginPath(); ctx.moveTo(0, 13); ctx.lineTo(126, 13); ctx.stroke()
        ctx.strokeStyle = gr; ctx.beginPath(); ctx.moveTo(194, 13); ctx.lineTo(320, 13); ctx.stroke()
        ctx.strokeStyle = col; ctx.fillStyle = col
        ctx.beginPath(); ctx.moveTo(140, 13); ctx.lineTo(148, 13); ctx.stroke()
        ctx.beginPath(); ctx.moveTo(172, 13); ctx.lineTo(180, 13); ctx.stroke()
        ctx.beginPath(); ctx.moveTo(160, 2); ctx.lineTo(172, 13); ctx.lineTo(160, 24); ctx.lineTo(148, 13); ctx.closePath(); ctx.stroke()
        function dia(cx, cy, r) { ctx.beginPath(); ctx.moveTo(cx, cy - r); ctx.lineTo(cx + r, cy); ctx.lineTo(cx, cy + r); ctx.lineTo(cx - r, cy); ctx.closePath(); ctx.fill() }
        dia(160, 13, 5); dia(133, 13, 3.5); dia(187, 13, 3.5)
    }
}

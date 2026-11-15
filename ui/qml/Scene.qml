import QtQuick

// Paisaje de respaldo cuando un juego aún no tiene arte: colinas y sol con la paleta del juego.
Canvas {
    id: c
    property var pal: ["#101820", "#2c4968", "#1f3652", "#0f1b2a", "#bcd6f2"]
    property bool big: true
    onPalChanged: requestPaint()
    onWidthChanged: requestPaint()
    onHeightChanged: requestPaint()
    onPaint: {
        var ctx = getContext("2d")
        ctx.reset()
        var sx = width / 1280, sy = height / 720
        ctx.scale(sx, sy)
        ctx.fillStyle = pal[0]; ctx.fillRect(0, 0, 1280, 720)
        ctx.fillStyle = pal[4]; ctx.globalAlpha = 0.9
        ctx.beginPath(); ctx.arc(big ? 1010 : 820, big ? 350 : 210, big ? 62 : 90, 0, 6.2832); ctx.fill()
        ctx.globalAlpha = 1
        function poly(col, pts) {
            ctx.fillStyle = col; ctx.beginPath(); ctx.moveTo(pts[0], pts[1])
            for (var i = 2; i < pts.length; i += 2) ctx.lineTo(pts[i], pts[i + 1])
            ctx.closePath(); ctx.fill()
        }
        poly(pal[1], [0,470, 180,360, 330,440, 520,320, 700,430, 880,340, 1080,450, 1280,380, 1280,720, 0,720])
        poly(pal[2], [0,560, 220,470, 420,540, 640,440, 860,540, 1060,480, 1280,560, 1280,720, 0,720])
        poly(pal[3], [0,640, 260,590, 520,640, 800,580, 1040,640, 1280,600, 1280,720, 0,720])
    }
}

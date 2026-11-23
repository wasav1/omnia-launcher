import QtQuick

/** Fondo de BigMode: puntos que flotan y se enlazan con líneas finas, con un brillo suave arriba a la derecha.
 *  Se tiñe con `tint` (los colores se funden en ~1,2 s al cambiar de juego). Solo avanza cuando `running` es verdadero:
 *  con un juego abierto, con el modo juego activo o con la ventana oculta no consume nada.
 *  Se dibuja a media resolución (el efecto es suave) y a 30 cuadros por segundo. */
Item {
    id: bg
    property color tint: "#336599"
    property real intensity: 1.0
    property bool running: true
    property int pointCount: 64
    property color c0: Qt.hsla(tint.hslHue < 0 ? 0.6 : tint.hslHue, 0.5, 0.42, 1)
    property color c1: Qt.hsla(((tint.hslHue < 0 ? 0.6 : tint.hslHue) + 0.04) % 1, 0.62, 0.62, 1)
    property color c2: Qt.hsla(((tint.hslHue < 0 ? 0.6 : tint.hslHue) + 0.94) % 1, 0.5, 0.66, 1)
    Behavior on c0 { ColorAnimation { duration: 1200 } }
    Behavior on c1 { ColorAnimation { duration: 1200 } }
    Behavior on c2 { ColorAnimation { duration: 1200 } }

    property var points: []
    property double lastTime: 0

    function seed() {
        const list = []
        for (let i = 0; i < pointCount; i++)
            list.push({ x: Math.random(), y: Math.random(), vx: (Math.random() - 0.5) * 0.00018, vy: (Math.random() - 0.5) * 0.00018,
                        r: Math.random() * 1.3 + 0.6, p: Math.random() * 6.283 })
        points = list
    }
    function rgba(c, a) { return "rgba(" + Math.round(c.r * 255) + "," + Math.round(c.g * 255) + "," + Math.round(c.b * 255) + "," + Math.max(0, Math.min(1, a)) + ")" }
    Component.onCompleted: seed()

    Timer {
        interval: 33; repeat: true; running: bg.running && bg.visible && bg.width > 0
        onTriggered: canvas.requestPaint()
    }

    Canvas {
        id: canvas
        width: Math.max(2, Math.round(bg.width / 2)); height: Math.max(2, Math.round(bg.height / 2))
        scale: 2; transformOrigin: Item.TopLeft; smooth: true          // media resolución, estirada al tamaño del fondo
        renderStrategy: Canvas.Cooperative
        onPaint: {
            const ctx = getContext("2d")
            const w = width, h = height
            ctx.reset()
            const now = Date.now()
            const dt = bg.lastTime ? Math.min(100, now - bg.lastTime) : 33
            bg.lastTime = now
            const k = bg.intensity, pts = bg.points
            const reach = Math.min(w, h) * 0.55 * 0.5
            for (let i = 0; i < pts.length; i++) {
                const q = pts[i]
                q.x += q.vx * dt * 0.5; q.y += q.vy * dt * 0.5
                if (q.x < 0) q.x = 1; if (q.x > 1) q.x = 0
                if (q.y < 0) q.y = 1; if (q.y > 1) q.y = 0
            }
            ctx.lineWidth = 1
            for (let i = 0; i < pts.length; i++) {
                for (let j = i + 1; j < pts.length; j++) {
                    const dx = (pts[i].x - pts[j].x) * w, dy = (pts[i].y - pts[j].y) * h
                    const d = Math.sqrt(dx * dx + dy * dy)
                    if (d < reach) {
                        ctx.strokeStyle = bg.rgba(bg.c1, (1 - d / reach) * 0.35 * k)
                        ctx.beginPath(); ctx.moveTo(pts[i].x * w, pts[i].y * h); ctx.lineTo(pts[j].x * w, pts[j].y * h); ctx.stroke()
                    }
                }
            }
            const cols = [bg.c0, bg.c1, bg.c2]
            for (let i = 0; i < pts.length; i++) {
                const q = pts[i], tw = 0.55 + 0.45 * Math.sin(now * 0.002 + q.p)
                ctx.fillStyle = bg.rgba(cols[i % 3], (0.55 * tw + 0.2) * Math.min(1, k))
                ctx.beginPath(); ctx.arc(q.x * w, q.y * h, q.r * Math.max(1, w / 640), 0, 6.283); ctx.fill()
            }
            const gr = ctx.createRadialGradient(w * 0.8, h * 0.2, 0, w * 0.8, h * 0.2, w * 0.6)
            gr.addColorStop(0, bg.rgba(bg.c0, 0.22 * k)); gr.addColorStop(1, bg.rgba(bg.c0, 0))
            ctx.fillStyle = gr; ctx.fillRect(0, 0, w, h)
        }
    }
}

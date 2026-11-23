import QtQuick

/** Fondo de ondas de BigMode para la Biblioteca: cinco capas de olas suaves que suben desde abajo y un velo de color arriba.
 *  Se tiñe con `tint` (los colores se funden en ~1,2 s). Solo avanza cuando `running` es verdadero. Se dibuja a media
 *  resolución y a 30 cuadros por segundo. */
Item {
    id: bg
    property color tint: "#336599"
    property real intensity: 1.0
    property bool running: true
    property color c0: Qt.hsla(tint.hslHue < 0 ? 0.6 : tint.hslHue, 0.5, 0.42, 1)
    property color c1: Qt.hsla(((tint.hslHue < 0 ? 0.6 : tint.hslHue) + 0.04) % 1, 0.62, 0.62, 1)
    property color c2: Qt.hsla(((tint.hslHue < 0 ? 0.6 : tint.hslHue) + 0.94) % 1, 0.5, 0.66, 1)
    Behavior on c0 { ColorAnimation { duration: 1200 } }
    Behavior on c1 { ColorAnimation { duration: 1200 } }
    Behavior on c2 { ColorAnimation { duration: 1200 } }

    function rgba(c, a) { return "rgba(" + Math.round(c.r * 255) + "," + Math.round(c.g * 255) + "," + Math.round(c.b * 255) + "," + Math.max(0, Math.min(1, a)) + ")" }

    Timer {
        interval: 33; repeat: true; running: bg.running && bg.visible && bg.width > 0
        onTriggered: canvas.requestPaint()
    }

    // Cada ola es independiente: su propia altura, amplitud, tres componentes con frecuencias que no son múltiplos entre sí,
    // velocidades y sentidos distintos, y una respiración lenta de la amplitud. Así nunca se sincronizan ni se repiten.
    property var waves: []
    Component.onCompleted: {
        const list = []
        for (let i = 0; i < 6; i++) {
            const dir = i % 2 === 0 ? 1 : -1
            list.push({
                base: 0.60 + i * 0.065,                         // 0 arriba, 1 abajo: la primera queda al fondo (más arriba)
                amp: 0.022 + (i * 0.37 % 1) * 0.026,
                f: [0.0042 + i * 0.00091, 0.0097 + i * 0.0013, 0.0215 + i * 0.0021],
                v: [dir * (0.00018 + i * 0.00004), -dir * (0.00031 + i * 0.00007), dir * (0.00052 + i * 0.00005)],
                ph: [i * 1.91, i * 2.73 + 0.8, i * 0.57 + 2.1],
                w: [1, 0.55 + (i % 3) * 0.12, 0.28],
                bob: 0.00011 + i * 0.000023, bobPh: i * 1.37,
                breathe: 0.00009 + i * 0.000017
            })
        }
        waves = list
    }

    Canvas {
        id: canvas
        width: Math.max(2, Math.round(bg.width / 2)); height: Math.max(2, Math.round(bg.height / 2))
        scale: 2; transformOrigin: Item.TopLeft; smooth: true
        renderStrategy: Canvas.Cooperative
        onPaint: {
            const ctx = getContext("2d")
            const w = width, h = height, t = Date.now(), k = bg.intensity
            ctx.reset()
            const cols = [bg.c0, bg.c1, bg.c2]
            const list = bg.waves
            for (let n = 0; n < list.length; n++) {
                const o = list[n]
                const front = n / Math.max(1, list.length - 1)                // 0 al fondo, 1 delante
                const breathe = 0.72 + 0.28 * Math.sin(t * o.breathe + o.bobPh)
                const baseY = h * (o.base + Math.sin(t * o.bob + o.bobPh) * 0.012)
                ctx.beginPath()
                ctx.moveTo(0, h)
                for (let x = 0; x <= w; x += 4) {
                    let y = 0
                    for (let c = 0; c < 3; c++) y += Math.sin(x * o.f[c] * 2 + t * o.v[c] + o.ph[c]) * o.w[c]
                    ctx.lineTo(x, baseY + y * h * o.amp * breathe / 1.8)
                }
                ctx.lineTo(w, h); ctx.closePath()
                ctx.fillStyle = bg.rgba(cols[n % 3], (0.05 + front * 0.075) * k)
                ctx.fill()
                ctx.strokeStyle = bg.rgba(cols[(n + 1) % 3], (0.10 + front * 0.16) * k)
                ctx.lineWidth = 1
                ctx.stroke()
            }
            const gr = ctx.createLinearGradient(0, 0, 0, h * 0.6)
            gr.addColorStop(0, bg.rgba(bg.c0, 0.08 * k)); gr.addColorStop(1, bg.rgba(bg.c0, 0))
            ctx.fillStyle = gr; ctx.fillRect(0, 0, w, h * 0.6)
        }
    }
}

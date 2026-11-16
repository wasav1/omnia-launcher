import QtQuick
import QtQuick.Shapes

// Ondas del escritorio: 2 capas + línea, dibujadas por la GPU (Shape) y animadas a la frecuencia de la pantalla.
// - Siempre activas: sin sonido se quedan en la parte baja de la pantalla con un oleaje suave (reposo, a 30 FPS).
// - Con sonido siguen el ESPECTRO real: 32 bandas (graves a la izquierda, agudos a la derecha), con ataque muy rápido.
// - Se ocultan con visibleOnScreen = false (ventana maximizada, Big Menú, juego en ejecución).
Item {
    id: w
    width: 1920; height: 360
    property bool active: true           // siempre encendidas (la visibilidad la decide visibleOnScreen)
    property bool playing: false         // hay música o sonido
    property bool real: false            // hay espectro real del ayudante
    property var levels: [0, 0, 0, 0]
    property var bands: []               // espectro del ayudante (nb bandas, 0..1)
    readonly property int nb: 32
    property var eb: new Array(32).fill(0)
    property var frontSpec: new Array(32).fill(0)
    property color color: "#e6d9a0"
    property bool visibleOnScreen: true

    property real amp: 0.8
    property real phase: 0
    property real t: 0
    property real acc: 0
    property int frameN: 0
    property var ptsBack: []
    property var ptsFront: []
    property var lineFront: []
    readonly property bool run: visibleOnScreen && active
    visible: run

    function mixc(a) { return Qt.rgba(color.r, color.g, color.b, a) }
    // amplitud interpolada (cúbica) a lo largo del ancho: graves a la izquierda, agudos a la derecha
    function specAt(x, arr) {
        var n = arr.length, p = Math.max(0, Math.min(1, x / width)) * (n - 1)
        var i = Math.min(n - 2, Math.floor(p)), f = p - i
        var p0 = arr[Math.max(0, i - 1)], p1 = arr[i], p2 = arr[i + 1], p3 = arr[Math.min(n - 1, i + 2)]
        return Math.max(0, p1 + 0.5 * f * (p2 - p0 + f * (2 * p0 - 5 * p1 + 4 * p2 - p3 + f * (3 * (p1 - p2) + p3 - p0))))
    }

    FrameAnimation {
        running: w.run
        onTriggered: {
            w.frameN++
            w.acc += frameTime
            if (!w.playing && (w.frameN & 1)) return            // en reposo: 30 FPS bastan
            var dt = Math.min(0.06, w.acc); w.acc = 0
            var N = w.nb
            w.t += dt
            w.phase += dt * (w.playing ? 0.8 : 0.4)
            w.amp += ((w.playing ? 1 : 0.8) - w.amp) * Math.min(1, dt * 4)

            var useS = w.playing && w.real && w.bands && w.bands.length === N
            var kick = Math.exp(-((w.t * 1.6) % 1) * 4.5)
            var ebs = w.eb.slice(), sm = [], fr = []
            for (var b = 0; b < N; b++) {
                // oleaje de reposo: ondulación lenta, distinta en cada banda
                var idle = 0.21 + 0.09 * Math.sin(w.phase * 1.3 + b * 0.42) + 0.05 * Math.sin(w.phase * 0.7 - b * 0.9)
                var tb
                if (useS) tb = Math.max(w.bands[b], idle * 0.6)                 // espectro real (con un mínimo para que nunca quede plano)
                else if (w.playing) tb = idle + 0.30 * kick * (1 - b / N)       // suena algo pero sin espectro: pulso simulado
                else tb = idle
                ebs[b] += (tb - ebs[b]) * Math.min(1, dt * (tb > ebs[b] ? 24 : 5.5))   // ataque y caída suaves: se mueve con la música sin ponerse nerviosa
            }
            w.eb = ebs
            for (b = 0; b < N; b++) {
                sm.push((ebs[Math.max(0, b - 2)] + 2 * ebs[Math.max(0, b - 1)] + 3 * ebs[b] + 2 * ebs[Math.min(N - 1, b + 1)] + ebs[Math.min(N - 1, b + 2)]) / 9)
                fr.push((ebs[Math.max(0, b - 1)] + 2 * ebs[b] + ebs[Math.min(N - 1, b + 1)]) / 4)
            }
            w.frontSpec = fr

            var W = w.width, H = w.height, back = [Qt.point(0, H)], front = [Qt.point(0, H)], line = []
            for (var x = 0; ; x += 20) {
                if (x > W) x = W                                  // el último punto cae justo en el borde derecho
                var wf = 0.64 + 0.36 * Math.sin(x * 0.0030 + w.phase * 1.6) + 0.10 * Math.sin(x * 0.0071 - w.phase * 1.1)
                var wb = 0.64 + 0.36 * Math.sin(x * 0.0022 - w.phase * 1.1 + 1.7)
                var yf = H - 14 - 175 * w.specAt(x, w.frontSpec) * w.amp * (0.78 + 0.22 * wf)
                var yb = H - 14 - 120 * w.specAt(x, sm) * w.amp * (0.78 + 0.22 * wb) - 14
                front.push(Qt.point(x, yf)); back.push(Qt.point(x, yb)); line.push(Qt.point(x, yf))
                if (x >= W) break
            }
            back.push(Qt.point(W, H)); front.push(Qt.point(W, H))
            w.ptsBack = back; w.ptsFront = front; w.lineFront = line
        }
    }

    Shape {
        anchors.fill: parent
        preferredRendererType: Shape.CurveRenderer
        ShapePath {
            strokeColor: "transparent"
            fillGradient: LinearGradient {
                x1: 0; y1: 0; x2: 0; y2: w.height
                GradientStop { position: 0.0; color: w.mixc(0.0) }
                GradientStop { position: 0.45; color: w.mixc(0.12 * Math.min(1, w.amp + 0.3)) }
                GradientStop { position: 1.0; color: w.mixc(0.22 * Math.min(1, w.amp + 0.3)) }
            }
            PathPolyline { path: w.ptsBack }
        }
        ShapePath {
            strokeColor: "transparent"
            fillGradient: LinearGradient {
                x1: 0; y1: 0; x2: 0; y2: w.height
                GradientStop { position: 0.0; color: w.mixc(0.0) }
                GradientStop { position: 0.5; color: w.mixc(0.20 * Math.min(1, w.amp + 0.3)) }
                GradientStop { position: 1.0; color: w.mixc(0.36 * Math.min(1, w.amp + 0.3)) }
            }
            PathPolyline { path: w.ptsFront }
        }
        ShapePath {
            fillColor: "transparent"
            strokeColor: w.mixc(0.55 * Math.min(1, w.amp + 0.2)); strokeWidth: 2; capStyle: ShapePath.RoundCap; joinStyle: ShapePath.RoundJoin
            PathPolyline { path: w.lineFront }
        }
    }
}

import QtQuick
import QtQuick.Shapes

// Ondas suaves con solo 2 capas, dibujadas por la GPU (Shape) y animadas a la frecuencia de la pantalla (FrameAnimation, ~60 FPS).
// Los niveles de audio llegan a ~12 Hz y aquí se interpolan en cada fotograma.
Item {
    id: w
    width: 1920; height: 360
    property bool active: false          // hay música o sonido
    property bool playing: false
    property bool real: false
    property var levels: [0, 0, 0, 0]
    property var bands: []               // espectro (16 bandas) para marcar picos
    property var eb: new Array(16).fill(0)
    property var frontSpec: new Array(16).fill(0)
    property color color: "#e6d9a0"
    property bool visibleOnScreen: true

    property real amp: 0
    property real phase: 0
    property real t: 0
    property var env: [0, 0, 0, 0]
    property var ptsBack: []
    property var ptsFront: []
    property var lineFront: []
    readonly property bool run: visibleOnScreen && (active || amp > 0.01)
    visible: run

    function mixc(a) { return Qt.rgba(color.r, color.g, color.b, a) }
    // amplitud interpolada a lo largo del ancho (graves a la izquierda, agudos a la derecha)
    function specAt(x, arr) {
        var n = arr.length, p = Math.max(0, Math.min(1, x / width)) * (n - 1)
        var i = Math.min(n - 2, Math.floor(p)), f = p - i
        var p0 = arr[Math.max(0, i - 1)], p1 = arr[i], p2 = arr[i + 1], p3 = arr[Math.min(n - 1, i + 2)]
        return Math.max(0, p1 + 0.5 * f * (p2 - p0 + f * (2 * p0 - 5 * p1 + 4 * p2 - p3 + f * (3 * (p1 - p2) + p3 - p0))))
    }
    function ampAt(x, rev) {
        var p = Math.max(0, Math.min(1, x / width)) * 3
        if (rev) p = 3 - p
        var i = Math.min(2, Math.floor(p)), f = p - i
        return env[i] * (1 - f) + env[i + 1] * f
    }

    FrameAnimation {
        running: w.run
        onTriggered: {
            var dt = Math.min(0.05, frameTime)
            w.amp += ((w.active ? (w.playing ? 1 : 0.14) : 0) - w.amp) * Math.min(1, dt * 2)
            var tg
            if (w.playing && w.real) tg = [0.2 + 0.8 * w.levels[0], 0.2 + 0.8 * w.levels[1], 0.2 + 0.8 * w.levels[2], 0.2 + 0.8 * w.levels[3]]
            else if (w.playing) {
                w.t += dt
                var bt = w.t * 1.6, kick = Math.exp(-(bt % 1) * 4.5), sw = 0.5 + 0.5 * Math.sin(bt * 0.7)
                tg = [0.3 + 0.7 * kick, 0.35 + 0.4 * sw, 0.35 + 0.3 * sw, 0.4]
            } else tg = [0.12, 0.12, 0.12, 0.12]
            var e = w.env.slice(), k = Math.min(1, dt * (w.playing ? 12 : 3))      // suavizado por fotograma
            for (var i = 0; i < 4; i++) e[i] += (tg[i] - e[i]) * k
            w.env = e
            // espectro por banda: ataque rápido y caída suave para que los picos "salten" con la música
            var ebs = w.eb.slice(), useS = w.playing && w.real && w.bands && w.bands.length === 16, sm = []
            for (var b = 0; b < 16; b++) {
                var tb = useS ? w.bands[b] : (0.25 + 0.5 * e[Math.min(3, Math.floor(b / 4))])
                ebs[b] += (tb - ebs[b]) * Math.min(1, dt * (tb > ebs[b] ? 22 : 7))
            }
            w.eb = ebs
            for (b = 0; b < 16; b++) sm.push((ebs[Math.max(0, b - 2)] + 2 * ebs[Math.max(0, b - 1)] + 3 * ebs[b] + 2 * ebs[Math.min(15, b + 1)] + ebs[Math.min(15, b + 2)]) / 9)
            var fr = []
            for (b = 0; b < 16; b++) fr.push((ebs[Math.max(0, b - 1)] + 2 * ebs[b] + ebs[Math.min(15, b + 1)]) / 4)
            w.frontSpec = fr
            w.phase += dt * (w.playing ? 0.9 : 0.2)
            var W = w.width, H = w.height, back = [Qt.point(0, H)], front = [Qt.point(0, H)], line = []
            for (var x = 0; x <= W; x += 24) {
                var wf = 0.64 + 0.36 * Math.sin(x * 0.0030 + w.phase * 1.6) + 0.10 * Math.sin(x * 0.0071 - w.phase * 1.1)
                var wb = 0.64 + 0.36 * Math.sin(x * 0.0022 - w.phase * 1.1 + 1.7)
                var yf = H - 14 - 140 * w.specAt(x, w.frontSpec) * w.amp * (0.78 + 0.22 * wf)
                var yb = H - 14 - 95 * w.specAt(x, sm) * w.amp * (0.78 + 0.22 * wb) - 14
                front.push(Qt.point(x, yf)); back.push(Qt.point(x, yb)); line.push(Qt.point(x, yf))
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

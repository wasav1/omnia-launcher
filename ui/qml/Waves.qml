import QtQuick
import QtQuick.Shapes

// Cuatro capas suaves basadas en el espectro completo de salida (16 bandas).
// El core resume el monitor del PC; aquí solo se interpolan niveles, nunca audio.
Item {
    id: w
    width: 1920
    height: 360
    property bool active: false
    property bool real: false
    property var bands: []
    property color color: "#e6d9a0"
    property bool visibleOnScreen: true

    property real amp: 0
    property real phase: 0
    property var smoothBands: new Array(16).fill(0)
    property var layerLevels: [0, 0, 0, 0]
    property var paths: [[], [], [], []]
    property var frontLine: []
    readonly property bool run: visibleOnScreen && (active || amp > 0.01)
    visible: run

    function mixc(alpha) { return Qt.rgba(color.r, color.g, color.b, alpha) }
    function spectrumAt(x, values) {
        const p = Math.max(0, Math.min(1, x / width)) * (values.length - 1)
        const i = Math.min(values.length - 2, Math.floor(p)), f = p - i
        const p0 = values[Math.max(0, i - 1)], p1 = values[i], p2 = values[i + 1], p3 = values[Math.min(values.length - 1, i + 2)]
        const cubic = p1 + .5 * f * (p2 - p0 + f * (2*p0 - 5*p1 + 4*p2 - p3 + f * (3*(p1-p2) + p3-p0)))
        return Math.max(0, Math.min(1, cubic))
    }

    FrameAnimation {
        running: w.run
        onTriggered: {
            const dt = Math.min(.05, frameTime)
            const targetAmp = w.active ? 1 : 0
            w.amp += (targetAmp - w.amp) * Math.min(1, dt * (targetAmp > w.amp ? 12 : 4.5))

            const nextBands = w.smoothBands.slice()
            const source = w.real && w.bands && w.bands.length === 16 ? w.bands : new Array(16).fill(0)
            for (let b = 0; b < 16; b++) {
                const target = Math.max(0, Math.min(1, Number(source[b]) || 0))
                nextBands[b] += (target - nextBands[b]) * Math.min(1, dt * (target > nextBands[b] ? 34 : 8))
            }
            w.smoothBands = nextBands

            // Las cuatro capas siguen graves, medios-graves, medios-agudos y agudos.
            const levels = w.layerLevels.slice()
            for (let layer = 0; layer < 4; layer++) {
                let power = 0
                for (let b = layer * 4; b < layer * 4 + 4; b++) power += nextBands[b] * nextBands[b]
                const rms = Math.sqrt(power / 2)
                const target = Math.min(1, Math.pow(rms, .72) * 1.28)
                levels[layer] += (target - levels[layer]) * Math.min(1, dt * (target > levels[layer] ? 30 : 7))
            }
            w.layerLevels = levels
            w.phase += dt * (w.active ? 1.0 : .18)

            const W = w.width, H = w.height
            const maxAmp = H * .46
            const layerAmp = [1.00, .78, .60, .44]
            const phaseRate = [1.0, -.82, .62, -1.18]
            const all = [[], [], [], []]
            const front = []
            for (let x = 0; x <= W; x += 24) {
                const spectral = w.spectrumAt(x, nextBands)
                for (let j = 0; j < 4; j++) {
                    const base = H * .84 - j * 17
                    const energy = levels[j]
                    const a = maxAmp * layerAmp[j] * energy * w.amp
                    const wobble = .36 + .64 * spectral
                    const wave = .55 + .45 * Math.sin(x * (.0042 + j * .0011) + w.phase * phaseRate[j] * 2 + j)
                    const harmonic = .28 * Math.sin(x * (.0097 + j * .0012) - w.phase * 1.4 + j * 2)
                    const y = base - a * (wave + harmonic) * wobble
                    all[j].push(Qt.point(x, y))
                }
            }
            for (let j = 0; j < 4; j++) {
                all[j].unshift(Qt.point(0, H))
                all[j].push(Qt.point(W, H))
            }
            front.push.apply(front, all[0].slice(1, all[0].length - 1))
            w.paths = all
            w.frontLine = front
        }
    }

    Shape {
        anchors.fill: parent
        preferredRendererType: Shape.CurveRenderer
        ShapePath {
            strokeColor: "transparent"
            fillColor: w.mixc(.12 * Math.min(1, w.amp + .2))
            PathPolyline { path: w.paths[3] }
        }
        ShapePath {
            strokeColor: "transparent"
            fillColor: w.mixc(.16 * Math.min(1, w.amp + .2))
            PathPolyline { path: w.paths[2] }
        }
        ShapePath {
            strokeColor: "transparent"
            fillColor: w.mixc(.21 * Math.min(1, w.amp + .2))
            PathPolyline { path: w.paths[1] }
        }
        ShapePath {
            strokeColor: "transparent"
            fillColor: w.mixc(.31 * Math.min(1, w.amp + .2))
            PathPolyline { path: w.paths[0] }
        }
        ShapePath {
            fillColor: "transparent"
            strokeColor: w.mixc(.50 * Math.min(1, w.amp + .2))
            strokeWidth: 2
            capStyle: ShapePath.RoundCap
            joinStyle: ShapePath.RoundJoin
            PathPolyline { path: w.frontLine }
        }
    }
}

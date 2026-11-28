pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Shapes
import QtMultimedia
import Qt5Compat.GraphicalEffects as GE

/**
 * Bienvenida de Big Mode «Trazo que abre la barra» (propuesta G, elegida por el dueño, ~8,7 s):
 * sobre el fondo azul profundo de Omnia, el aro del logo se dibuja con su degradado, cae el punto con una onda,
 * aparecen «Omnia» y el saludo con datos reales; al final el logo viaja a su sitio en la barra superior, la barra
 * se despliega desde él hacia la derecha y la escena se funde dejando ver la barra real y el Inicio.
 * Va con su sonido (sounds/omnia/welcome.wav, volumen de los sonidos de la interfaz).
 * Se salta con cualquier tecla, botón del mando o clic. Todo se calcula a partir del tiempo `tt`, así que es determinista.
 */
Item {
    id: intro
    required property var host
    readonly property var api: intro.host.api
    property bool active: false
    property bool closing: false
    property real tt: 0
    readonly property real total: 8.7
    readonly property real u: Math.max(0.4, Math.min(width, height) / 1080)
    readonly property real cx: width / 2
    readonly property real cy: height * 0.40
    readonly property real logoSize: 300 * u
    // Longitud del trazo del logo (path del SVG, unidades del viewBox) dividida por su grosor (8): el patrón de guiones
    // de Qt se mide en grosores de línea.
    readonly property real strokeUnits: 37.56

    // ---- destino del logo: el logo de la barra superior de Big Mode (y la barra entera, para desplegarla)
    property rect targetLogo: Qt.rect(48 * u, 22 * u + 5 * u, 44 * u, 44 * u)
    property rect targetBar: Qt.rect(30 * u, 12 * u, width - 58 * u, 74 * u)
    function measureTargets() {
        const head = intro.host.headerBar
        if (!head || head.width <= 0) return
        const s = intro.host.s
        const logo = head.mapToItem(intro, 0, (head.height - 44 * s) / 2)
        intro.targetLogo = Qt.rect(logo.x, logo.y, 44 * s, 44 * s)
        const bar = head.mapToItem(intro, -18 * s, -10 * s)
        intro.targetBar = Qt.rect(bar.x, bar.y, head.width + 30 * s, head.height + 20 * s)
    }

    visible: active
    opacity: 1
    z: 200

    function ease(p) { p = Math.max(0, Math.min(1, p)); return 1 - Math.pow(1 - p, 3) }
    function easeInOut(p) { p = Math.max(0, Math.min(1, p)); return p < 0.5 ? 4 * p * p * p : 1 - Math.pow(-2 * p + 2, 3) / 2 }
    function clamp01(p) { return Math.max(0, Math.min(1, p)) }
    function lerp(a, b, p) { return a + (b - a) * p }
    function start() {
        if (intro.active) return
        intro.measureTargets()
        intro.tt = 0
        intro.closing = false
        intro.opacity = 1
        intro.active = true
        welcome.volume = intro.api.uiSoundVolume / 100
        clock.restart()
        if (intro.api.uiSounds && intro.api.uiSoundVolume > 0) welcome.play()
        intro.forceActiveFocus()
    }
    function skip() { if (intro.active && !intro.closing) intro.beginExit() }
    function beginExit() { intro.closing = true; fadeOut.restart(); fadeAudio.restart() }
    function finish() { intro.active = false; clock.stop(); welcome.stop(); intro.closing = false; intro.opacity = 1; intro.host.lastFocus() }
    onTtChanged: {
        if (intro.tt > 5.6 && intro.tt < 5.7) intro.measureTargets()      // por si la ventana cambió de tamaño
        if (intro.tt >= intro.total && !intro.closing) intro.finish()
    }

    NumberAnimation { id: clock; target: intro; property: "tt"; from: 0; to: intro.total + 0.1; duration: (intro.total + 0.1) * 1000 }
    NumberAnimation { id: fadeOut; target: intro; property: "opacity"; to: 0; duration: 450; easing.type: Easing.InOutQuad
        onFinished: intro.finish() }
    NumberAnimation { id: fadeAudio; target: welcome; property: "volume"; to: 0; duration: 400 }
    // SoundEffect y no MediaPlayer: el reproductor de vídeo (FFmpeg) abre un dispositivo Vulkan y con la capa global de MangoHud tumbaba Big Mode.
    SoundEffect { id: welcome; source: Qt.resolvedUrl("sounds/omnia/welcome.wav") }

    Keys.onPressed: function(e) { intro.skip(); e.accepted = true }
    MouseArea { anchors.fill: parent; onClicked: intro.skip() }

    // ---- escena: fondo, barra desplegándose y textos. Se funde al final para dejar ver la barra real y el Inicio.
    Item {
        id: scene
        anchors.fill: parent
        opacity: 1 - intro.ease((intro.tt - 7.7) / 0.9)

        Rectangle { anchors.fill: parent; color: "#070B12" }
        GE.RadialGradient {        // luz azul abajo a la izquierda
            x: -120 * intro.u * 2; y: intro.height * 0.48
            width: 1040 * intro.u; height: width
            gradient: Gradient { GradientStop { position: 0.0; color: "#731C4E8A" } GradientStop { position: 0.5; color: "#00070B12" } }
        }
        GE.RadialGradient {        // luz violeta arriba a la derecha
            x: intro.width - 840 * intro.u; y: -360 * intro.u
            width: 1120 * intro.u; height: width
            gradient: Gradient { GradientStop { position: 0.0; color: "#596779DA" } GradientStop { position: 0.5; color: "#00070B12" } }
        }

        // la barra superior se despliega desde el logo hacia la derecha
        Rectangle {        // el panel crece (no se recorta) para que su borde derecho siga redondeado
            readonly property real p: intro.easeInOut((intro.tt - 6.75) / 1.0)
            x: intro.targetBar.x; y: intro.targetBar.y
            height: intro.targetBar.height
            width: intro.lerp(intro.targetLogo.x + intro.targetLogo.width + 14 * intro.u - intro.targetBar.x, intro.targetBar.width, p)
            visible: intro.tt > 6.6
            opacity: intro.ease((intro.tt - 6.6) / 0.3)
            radius: 26 * intro.host.s
            color: "#14FFFFFF"; border.width: 1; border.color: "#29FFFFFF"
        }

        // onda que sale cuando cae el punto
        Rectangle {
            readonly property real p: intro.clamp01((intro.tt - 2.9) / 1.6)
            width: intro.logoSize * (0.75 + 1.9 * p); height: width; radius: width / 2
            x: intro.cx - width / 2; y: intro.cy - height / 2
            color: "transparent"; border.width: Math.max(1.5, 2.5 * intro.u); border.color: "#78DFEF"
            opacity: intro.tt > 2.9 ? 0.8 * (1 - p) : 0
        }
        // brillo detrás del logo
        GE.RadialGradient {
            readonly property real p: intro.clamp01((intro.tt - 2.8) / 0.9)
            width: intro.logoSize * 1.35; height: width
            x: intro.cx - width / 2; y: intro.cy - height / 2
            opacity: (intro.tt < 2.8 ? 0 : p < 0.6 ? p / 0.6 * 0.55 : 0.55 - (p - 0.6) * 0.75) * (1 - intro.ease((intro.tt - 5.6) / 0.5))
            gradient: Gradient {
                GradientStop { position: 0.0; color: "#8C78DFEF" }
                GradientStop { position: 0.3; color: "#406779DA" }
                GradientStop { position: 0.5; color: "#00070B12" }
            }
        }

        // «Omnia» y el saludo con datos reales
        Text {
            id: word
            x: 0; width: intro.width; horizontalAlignment: Text.AlignHCenter
            y: intro.cy + intro.logoSize / 2 + 34 * intro.u
            readonly property real pin: intro.ease((intro.tt - 3.6) / 0.9)
            readonly property real pout: intro.ease((intro.tt - 5.6) / 0.5)
            text: "Omnia"
            color: intro.host.ink; font.family: intro.host.uiFont; font.pixelSize: 84 * intro.u; font.weight: Font.Bold
            font.letterSpacing: (0.32 - 0.28 * pin) * font.pixelSize
            opacity: pin * (1 - pout)
            transform: Translate { y: (1 - word.pin) * 20 * intro.u - word.pout * 12 * intro.u }
        }
        Column {
            id: hello
            x: 0; width: intro.width
            y: intro.cy + intro.logoSize / 2 + 150 * intro.u
            spacing: 8 * intro.u
            readonly property real pin: intro.ease((intro.tt - 4.3) / 0.6)
            readonly property real pout: intro.ease((intro.tt - 5.6) / 0.45)
            opacity: pin * (1 - pout)
            transform: Translate { y: (1 - hello.pin) * 12 * intro.u }
            Text {
                width: parent.width; horizontalAlignment: Text.AlignHCenter
                text: intro.api.userName ? qsTr("Bienvenido de nuevo, %1").arg(intro.api.userName) : qsTr("Bienvenido de nuevo")
                color: "#C9D6E4"; font.family: intro.host.uiFont; font.pixelSize: 32 * intro.u; font.weight: Font.DemiBold
            }
            Text {
                width: parent.width; horizontalAlignment: Text.AlignHCenter
                readonly property var games: (intro.api.games || []).filter(function(g) { return !g.hidden })
                readonly property int updates: games.filter(function(g) { return !!g.updateAvailable }).length
                readonly property var fam: ({ xbox: "Xbox", ps: "PlayStation", "switch": "Switch", deck: "Steam Deck" })
                text: [qsTr("%n juego(s)", "", games.length), updates > 0 ? qsTr("%n actualización(es)", "", updates) : "",
                       intro.api.padOn ? ((fam[intro.api.padFamily] || qsTr("Mando")) + (intro.api.padBattery && intro.api.padBattery.level !== undefined ? " " + qsTr("al %1 %").arg(intro.api.padBattery.level) : "")) : ""]
                      .filter(function(x) { return x }).join("  ·  ")
                color: "#A9BDD3"; font.family: intro.host.uiFont; font.pixelSize: 22 * intro.u
            }
        }
    }

    // ---- logo: se dibuja en el centro y viaja hasta el logo de la barra (encima de todo, llega exacto a su sitio)
    Item {
        id: logo
        readonly property real travel: intro.easeInOut((intro.tt - 5.8) / 1.1)
        readonly property real size: intro.lerp(intro.logoSize, intro.targetLogo.width, travel)
        width: size; height: size
        x: intro.lerp(intro.cx - intro.logoSize / 2, intro.targetLogo.x, travel)
        y: intro.lerp(intro.cy - intro.logoSize / 2, intro.targetLogo.y, travel)
        opacity: 1 - intro.ease((intro.tt - 8.2) / 0.4)
        // El dibujo va en coordenadas del SVG original (viewBox 25 20 104 104) y se escala al tamaño actual.
        Item {
            width: 104; height: 104
            transform: Scale { xScale: logo.size / 104; yScale: logo.size / 104 }
            Shape {
                x: -25; y: -20
                width: 154; height: 144
                preferredRendererType: Shape.CurveRenderer
                ShapePath {         // pista del aro
                    fillColor: "transparent"
                    strokeColor: Qt.rgba(36 / 255, 59 / 255, 81 / 255, intro.ease(intro.tt / 0.5))
                    strokeWidth: 13
                    PathAngleArc { centerX: 77; centerY: 72; radiusX: 36; radiusY: 36; startAngle: 0; sweepAngle: 360 }
                }
                ShapePath {         // aro con flecha que se dibuja
                    fillColor: "transparent"
                    strokeWidth: 8
                    capStyle: ShapePath.RoundCap
                    joinStyle: ShapePath.RoundJoin
                    strokeStyle: ShapePath.DashLine
                    dashPattern: [intro.strokeUnits + 1, intro.strokeUnits + 1]
                    dashOffset: (intro.strokeUnits + 1) * (1 - intro.easeInOut((intro.tt - 0.35) / 2.5))
                    strokeGradient: LinearGradient {
                        x1: 41; y1: 108; x2: 113; y2: 36
                        GradientStop { position: 0; color: "#6779DA" }
                        GradientStop { position: 1; color: "#78DFEF" }
                    }
                    PathSvg { path: "M44 87a36 36 0 0 1 57-42l14-8-1 26-25-9 10-4a29 29 0 1 0-12 49" }
                }
            }
            Rectangle {             // el punto cae con un pequeño rebote
                readonly property real p: intro.clamp01((intro.tt - 2.85) / 0.45)
                readonly property real k: p < 0.6 ? p / 0.6 * 1.6 : 1.6 - (p - 0.6) / 0.4 * 0.6
                width: 8; height: 8; radius: 4
                x: 102 - 25 - 4; y: 96 - 20 - 4
                color: "#80DDEA"
                scale: intro.tt < 2.85 ? 0 : k
                opacity: intro.tt < 2.85 ? 0 : 1
            }
        }
    }
}

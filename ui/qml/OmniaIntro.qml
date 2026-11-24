pragma ComponentBehavior: Bound

import QtQuick
import QtMultimedia

/**
 * Bienvenida de Big Mode («Nace de la constelación», ~5,6 s): los puntos de la constelación convergen y se posan sobre el contorno del
 * logo, las líneas lo unen, el logo se rellena, el aro late, y aparecen el saludo con datos reales y la frase de Omnia; las olas del
 * fondo suben durante toda la escena. Va con su sonido (sounds/omnia/welcome.wav, volumen de los sonidos de la interfaz).
 * Se salta con cualquier tecla, botón del mando o clic. Todo se calcula a partir del tiempo `tt`, así que es determinista.
 */
Item {
    id: intro
    required property var host
    readonly property var api: intro.host.api
    property bool active: false
    property bool closing: false
    property real tt: 0
    readonly property real u: Math.max(0.4, Math.min(width, height) / 1080)
    readonly property real cx: width / 2
    readonly property real cy: height * 0.42
    readonly property real logoSize: 330 * u
    readonly property real sc: logoSize / 320
    readonly property var ptsOut: [[151.0, 30.0], [178.4, 31.8], [205.1, 39.4], [228.6, 51.9], [249.8, 69.4], [266.4, 90.1], [279.0, 115.0], [285.9, 140.7], [287.5, 167.9], [283.3, 195.3], [273.6, 220.7], [258.9, 243.3], [239.8, 262.5], [217.0, 277.4], [192.0, 287.0], [164.7, 291.3], [137.7, 289.8], [111.2, 282.5], [87.1, 270.0], [66.1, 252.9], [49.1, 231.8], [36.8, 207.5], [30.0, 181.5], [28.3, 154.5], [32.2, 127.3], [41.7, 102.2], [56.7, 79.0], [75.4, 60.2], [98.6, 44.8], [123.7, 34.8]]
    readonly property var ptsIn: [[148.0, 94.0], [128.1, 97.7], [110.7, 107.5], [97.3, 122.2], [88.9, 140.3], [86.0, 160.2], [87.9, 179.9], [95.0, 198.7], [107.1, 214.8], [122.7, 226.5], [141.9, 233.6], [161.4, 234.9], [180.8, 229.9], [197.3, 218.5], [209.6, 203.1], [218.0, 185.0], [229.6, 169.9], [214.4, 158.1], [208.0, 139.1], [198.8, 121.2], [185.4, 106.4], [167.8, 96.8]]
    visible: active
    opacity: 1
    z: 200

    function ease(p) { p = Math.max(0, Math.min(1, p)); return 1 - Math.pow(1 - p, 3) }
    function clamp01(p) { return Math.max(0, Math.min(1, p)) }
    function start() {
        if (intro.active) return
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
    onTtChanged: if (intro.tt >= 5.6 && !intro.closing) intro.beginExit()

    NumberAnimation { id: clock; target: intro; property: "tt"; from: 0; to: 6.2; duration: 6200 }
    NumberAnimation { id: fadeOut; target: intro; property: "opacity"; to: 0; duration: 450; easing.type: Easing.InOutQuad
        onFinished: { intro.active = false; clock.stop(); welcome.stop(); intro.closing = false; intro.host.lastFocus() } }
    NumberAnimation { id: fadeAudio; target: welcome; property: "volume"; to: 0; duration: 400 }
    // SoundEffect y no MediaPlayer: el reproductor de vídeo (FFmpeg) abre un dispositivo Vulkan y con la capa global de MangoHud tumbaba Big Mode.
    SoundEffect { id: welcome; source: Qt.resolvedUrl("sounds/omnia/welcome.wav") }

    Keys.onPressed: function(e) { intro.skip(); e.accepted = true }
    MouseArea { anchors.fill: parent; onClicked: intro.skip() }

    Rectangle { anchors.fill: parent; color: intro.host.base }

    // olas del fondo
    Repeater {
        model: [ { y: 0.74, amp: 9, ph: 0, col: "#336599", a: 0.22, d: 0.1 }, { y: 0.82, amp: 11, ph: 2, col: "#5B9BE0", a: 0.13, d: 0.35 }, { y: 0.90, amp: 8, ph: 4, col: "#8aa4bd", a: 0.10, d: 0.6 } ]
        delegate: Canvas {
            id: wave
            required property var modelData
            width: intro.width; height: intro.height * 0.3
            y: intro.height * wave.modelData.y + (1 - intro.ease((intro.tt - wave.modelData.d) / 1.4)) * 90 * intro.u
            opacity: intro.ease((intro.tt - wave.modelData.d) / 1.4)
            onWidthChanged: requestPaint()
            onPaint: {
                const c = getContext("2d"); c.reset(); c.fillStyle = Qt.rgba(Qt.color(wave.modelData.col).r, Qt.color(wave.modelData.col).g, Qt.color(wave.modelData.col).b, wave.modelData.a)
                c.beginPath(); c.moveTo(0, height); c.lineTo(0, 0)
                for (let x = 0; x <= width; x += 12) c.lineTo(x, wave.modelData.amp * intro.u * Math.sin(x / (58 * intro.u) + wave.modelData.ph))
                c.lineTo(width, height); c.closePath(); c.fill()
            }
        }
    }
    // puntos sueltos del fondo
    Repeater {
        model: 14
        delegate: Rectangle {
            id: bgDot
            required property int index
            width: (index % 4 === 0 ? 5 : 3.4) * intro.u; height: width; radius: width / 2
            color: index % 3 === 0 ? "#5B9BE0" : "#8aa4bd"
            x: ((index * 89) % 1000) / 1000 * intro.width + Math.sin(intro.tt * 0.7 + index) * 8 * intro.u
            y: (0.12 + ((index * 53) % 70) / 100) * intro.height + Math.cos(intro.tt * 0.6 + index) * 8 * intro.u
            opacity: 0.45 * intro.ease((intro.tt - index * 0.06) / 0.8)
        }
    }

    // líneas que unen los puntos del contorno (se dibujan de un extremo al otro)
    Repeater {
        model: intro.ptsOut.length + intro.ptsIn.length
        delegate: Rectangle {
            id: ln
            required property int index
            readonly property bool outer: index < intro.ptsOut.length
            readonly property var ring: outer ? intro.ptsOut : intro.ptsIn
            readonly property int i: outer ? index : index - intro.ptsOut.length
            readonly property var p: ring[i]
            readonly property var q: ring[(i + 1) % ring.length]
            readonly property real x1: intro.cx + (p[0] - 160) * intro.sc
            readonly property real y1: intro.cy + (p[1] - 160) * intro.sc
            readonly property real len: Math.hypot((q[0] - p[0]) * intro.sc, (q[1] - p[1]) * intro.sc)
            x: x1; y: y1 - height / 2
            height: Math.max(1.5, 2 * intro.u); width: len * intro.clamp01((intro.tt - (1.3 + i * 0.03 + (outer ? 0 : 0.2))) / 0.35)
            transformOrigin: Item.Left
            rotation: Math.atan2((q[1] - p[1]), (q[0] - p[0])) * 180 / Math.PI
            color: "#5B9BE0"
            opacity: 0.9 - 0.45 * intro.ease((intro.tt - 4.0) / 1.0)
        }
    }
    // puntos de la constelación: llegan desde lejos y se posan sobre el contorno; después se desvanecen
    Repeater {
        model: intro.ptsOut.length + intro.ptsIn.length
        delegate: Rectangle {
            id: dot
            required property int index
            readonly property bool outer: index < intro.ptsOut.length
            readonly property var ring: outer ? intro.ptsOut : intro.ptsIn
            readonly property int i: outer ? index : index - intro.ptsOut.length
            readonly property var p: ring[i]
            readonly property real ang: ((i * 47 + (outer ? 0 : 19)) % 360) * Math.PI / 180
            readonly property real prog: intro.ease((intro.tt - (i * 0.025 + (outer ? 0 : 0.1))) / 1.3)
            readonly property bool big: i % 5 === 0
            width: (big ? 6.4 : 4.4) * intro.u; height: width; radius: width / 2
            color: big ? "#F0F3F7" : "#8aa4bd"
            x: intro.cx + (p[0] - 160) * intro.sc - width / 2 + (1 - prog) * Math.cos(ang) * 150 * intro.u
            y: intro.cy + (p[1] - 160) * intro.sc - height / 2 + (1 - prog) * Math.sin(ang) * 110 * intro.u
            opacity: Math.min(1, prog * 4) * (1 - intro.ease((intro.tt - 2.6) / 0.5))
        }
    }

    // logo
    Image {
        id: logo
        width: intro.logoSize; height: intro.logoSize
        x: intro.cx - width / 2; y: intro.cy - height / 2
        source: Qt.resolvedUrl("../../assets/branding/omnia-logo.svg")
        sourceSize: Qt.size(Math.round(intro.logoSize * 2), Math.round(intro.logoSize * 2))
        smooth: true
        opacity: intro.ease((intro.tt - 2.3) / 0.8)
        scale: 0.96 + 0.04 * opacity
    }
    // pulsos del aro
    Repeater {
        model: [2.9, 4.5]
        delegate: Rectangle {
            id: ring
            required property real modelData
            readonly property real p: intro.clamp01((intro.tt - ring.modelData) / 1.6)
            width: intro.logoSize * 0.62 * (0.5 + 1.2 * p) * 2; height: width; radius: width / 2
            x: intro.cx - width / 2; y: intro.cy - height / 2
            color: "transparent"; border.width: Math.max(1.5, 2 * intro.u); border.color: "#5B9BE0"
            opacity: intro.tt > ring.modelData ? 0.45 * (1 - p) : 0
        }
    }

    // textos
    Column {
        x: 0; width: intro.width
        y: intro.cy - intro.logoSize / 2 - 120 * intro.u
        spacing: 8 * intro.u
        Text {
            width: parent.width; horizontalAlignment: Text.AlignHCenter
            text: intro.api.userName ? qsTr("Bienvenido de nuevo, %1").arg(intro.api.userName) : qsTr("Bienvenido de nuevo")
            color: intro.host.ink; font.family: intro.host.uiFont; font.pixelSize: 38 * intro.u; font.weight: Font.DemiBold
            opacity: intro.ease((intro.tt - 3.5) / 0.6); transform: Translate { y: (1 - intro.ease((intro.tt - 3.5) / 0.6)) * 12 * intro.u }
        }
        Text {
            width: parent.width; horizontalAlignment: Text.AlignHCenter
            readonly property var games: (intro.api.games || []).filter(function(g) { return !g.hidden })
            readonly property int updates: games.filter(function(g) { return !!g.updateAvailable }).length
            readonly property var fam: ({ xbox: "Xbox", ps: "PlayStation", "switch": "Switch", deck: "Steam Deck" })
            text: [qsTr("%n juego(s)", "", games.length), updates > 0 ? qsTr("%n actualización(es)", "", updates) : "",
                   intro.api.padOn ? ((fam[intro.api.padFamily] || qsTr("Mando")) + (intro.api.padBattery && intro.api.padBattery.level !== undefined ? " " + qsTr("al %1 %").arg(intro.api.padBattery.level) : "")) : ""]
                  .filter(function(x) { return x }).join("  ·  ")
            color: intro.host.ink2; font.family: intro.host.uiFont; font.pixelSize: 22 * intro.u
            opacity: intro.ease((intro.tt - 3.9) / 0.6); transform: Translate { y: (1 - intro.ease((intro.tt - 3.9) / 0.6)) * 12 * intro.u }
        }
    }
    Text {
        x: 0; width: intro.width; horizontalAlignment: Text.AlignHCenter
        y: intro.cy + intro.logoSize / 2 + 70 * intro.u
        text: qsTr("TU BIBLIOTECA UNIFICADA")
        color: intro.host.ink2; font.family: intro.host.uiFont; font.pixelSize: 21 * intro.u; font.letterSpacing: 5 * intro.u
        opacity: intro.ease((intro.tt - 3.1) / 0.6)
    }
}

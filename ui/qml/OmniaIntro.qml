pragma ComponentBehavior: Bound

import QtQuick
import QtMultimedia

/** Bienvenida «Tu biblioteca despierta». Usa el historial local disponible al empezar. */
Item {
    id: intro
    required property var host
    readonly property var api: intro.host.api
    readonly property real s: host.s
    property bool active: false
    property bool skipping: false
    property real progress: 1600
    property var recent: []
    readonly property var lastGame: recent.length ? recent[0] : null
    visible: active
    z: 200

    function phase(start, end) {
        const t = Math.max(0, Math.min(1, (progress - start) / (end - start)))
        return 1 - Math.pow(1 - t, 3)
    }
    function playedAt(game) { return Number(game.lastPlayed || (game.played || {}).last || 0) }
    function start() {
        if (active) return
        recent = api.games.filter(game => !game.hidden && playedAt(game) > 0)
            .sort((a, b) => playedAt(b) - playedAt(a)).slice(0, 5)
        opacity = 1
        progress = 0
        skipping = false
        active = true
        if (api.uiSounds && api.uiSoundVolume > 0) {
            welcome.volume = api.uiSoundVolume / 100
            welcome.play()
        }
        clock.restart()
        forceActiveFocus()
    }
    function skip() {
        if (!active || skipping) return
        skipping = true
        clock.stop()
        skipAnimation.restart()
        audioFade.restart()
    }
    function finish() {
        active = false
        recent = []
        welcome.stop()
        host.lastFocus()
    }

    NumberAnimation {
        id: clock
        target: intro
        property: "progress"
        from: 0
        to: 1600
        duration: 1600
        onFinished: intro.finish()
    }
    NumberAnimation {
        id: skipAnimation
        target: intro
        property: "opacity"
        to: 0
        duration: 150
        onFinished: intro.finish()
    }
    NumberAnimation { id: audioFade; target: welcome; property: "volume"; to: 0; duration: 140 }
    SoundEffect { id: welcome; source: Qt.resolvedUrl("sounds/omnia/welcome.wav") }

    Keys.onPressed: function(event) { intro.skip(); event.accepted = true }
    MouseArea { anchors.fill: parent; onClicked: intro.skip(); z: 5 }

    Item {
        anchors.fill: parent
        opacity: 1 - Math.max(0, (intro.progress - 1330) / 270)
        Rectangle { anchors.fill: parent; color: intro.host.base }
        Rectangle {
            anchors.fill: parent
            opacity: intro.phase(0, 770)
            gradient: Gradient {
                GradientStop { position: 0; color: "#294561" }
                GradientStop { position: 1; color: intro.host.base }
            }
        }
        Image {
            anchors.fill: parent
            source: intro.lastGame ? intro.lastGame.fondo || "" : ""
            fillMode: Image.PreserveAspectCrop
            asynchronous: true
            sourceSize.width: Math.round(intro.width)
            opacity: intro.phase(0, 800)
            scale: 1.045 - intro.phase(0, 980) * 0.045
        }
        Rectangle {
            anchors.fill: parent
            gradient: Gradient {
                GradientStop { position: 0; color: "#9A0B0F14" }
                GradientStop { position: 0.4; color: "#320B0F14" }
                GradientStop { position: 1; color: "#F40B0F14" }
            }
        }

        OmniaBigHeader {
            anchors { left: parent.left; right: parent.right; top: parent.top
                leftMargin: intro.s * 48; rightMargin: intro.s * 40; topMargin: intro.s * 22 }
            visible: true
            enabled: false
            host: intro.host
            opacity: intro.phase(420, 920)
            transform: Translate { y: -intro.s * 12 * (1 - intro.phase(420, 920)) }
        }

        Column {
            anchors { left: parent.left; bottom: parent.bottom; margins: intro.s * 85 }
            spacing: intro.s * 15
            Text {
                color: intro.host.ink
                font.family: intro.host.uiFont
                font.pixelSize: intro.s * 35
                font.weight: Font.DemiBold
                opacity: intro.phase(585, 1060)
                text: intro.recent.length ? qsTr("Seguir jugando") : qsTr("Tu biblioteca")
            }
            Row {
                spacing: intro.s * 18
                visible: intro.recent.length > 0
                Repeater {
                    model: intro.recent
                    delegate: Rectangle {
                        id: cover
                        required property int index
                        required property var modelData
                        readonly property real reveal: intro.phase(740 + index * 65, 1140 + index * 65)
                        width: intro.s * 166
                        height: intro.s * 226
                        radius: intro.s * 14
                        color: "#263B50"
                        opacity: reveal
                        clip: true
                        transform: Translate { y: intro.s * 25 * (1 - cover.reveal) }
                        Image {
                            id: artwork
                            anchors.fill: parent
                            source: cover.modelData.portada || ""
                            fillMode: Image.PreserveAspectCrop
                            asynchronous: true
                            sourceSize.height: Math.round(cover.height)
                        }
                        Text {
                            anchors { fill: parent; margins: intro.s * 12 }
                            visible: artwork.status !== Image.Ready
                            text: cover.modelData.name
                            textFormat: Text.PlainText
                            horizontalAlignment: Text.AlignHCenter
                            verticalAlignment: Text.AlignVCenter
                            wrapMode: Text.WordWrap
                            color: intro.host.ink
                            font.pixelSize: intro.s * 20
                        }
                    }
                }
            }
        }
    }
}

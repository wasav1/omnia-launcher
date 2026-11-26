import QtQuick
import QtQuick.Layouts
import QtQuick.Window

Window {
    id: prompt
    width: 390
    height: 200
    minimumWidth: width
    minimumHeight: height
    maximumWidth: width
    maximumHeight: height
    color: "#111c28"
    flags: Qt.Dialog | Qt.FramelessWindowHint | Qt.WindowStaysOnTopHint | Qt.WindowDoesNotAcceptFocus
    title: qsTr("¿Iniciar Big Mode?")

    property int choice: 1
    property int sequence: -1
    property int revision: -1
    property string family: "xbox"
    property int exitCode: -1
    property string exitSound: ""
    readonly property bool soundsEnabled: promptApi.uiSounds && promptApi.uiSoundVolume > 0

    function select(index) {
        if (choice === index) return
        choice = index
        soundLoader.item?.playWhenReady("move")
    }

    function finish(code, sound) {
        exitCode = code
        exitSound = sound
        if (promptApi.prefsLoaded && !soundsEnabled) {
            Qt.exit(code)
            return
        }
        exitFallback.start()
        soundLoader.item?.playWhenReady(sound)
    }

    // Sigue cerrando el aviso si falta el efecto o no hay salida de audio.
    Timer {
        id: exitFallback
        interval: 900
        onTriggered: Qt.exit(prompt.exitCode)
    }

    function listen() {
        promptApi.call("GET", "/events?view=connection-prompt&since=" + sequence
                 + "&padSince=" + revision + "&wait=2", function(status, data) {
            if (status !== 200 || !data.padOn) {
                Qt.quit()
                return
            }
            prompt.sequence = data.seq
            prompt.revision = data.padRevision
            prompt.family = data.padFamily || "xbox"
            prompt.visible = true
            for (const event of data.events) {
                switch (event.key) {
                case "l": prompt.select(0); break
                case "r": prompt.select(1); break
                case "A": prompt.finish(prompt.choice === 0 ? 43 : 0, "confirm"); return
                case "B": prompt.finish(0, "back"); return
                }
            }
            Qt.callLater(prompt.listen)
        })
    }

    Api {
        id: promptApi
        autoStart: false
        controlsEnabled: false
        onPrefsLoadedChanged: {
            if (prefsLoaded && prompt.exitCode >= 0 && !prompt.soundsEnabled) Qt.exit(prompt.exitCode)
        }
    }

    Component.onCompleted: {
        Qt.application.domain = "pad-prompt.omnia.org"
        promptApi.port = Number(promptApi.arg("--port", "47831"))
        promptApi.tokenPath = promptApi.arg("--token", "")
        promptApi.loadPreferences()
        listen()
    }

    Loader {
        id: soundLoader
        active: prompt.visible && promptApi.prefsLoaded && prompt.soundsEnabled
        onLoaded: {
            if (prompt.exitCode >= 0) item.playWhenReady(prompt.exitSound)
        }
        sourceComponent: OmniaSounds {
            api: promptApi
            names: ["pad-on", "move", "confirm", "back"]
            openingSound: prompt.exitCode < 0 ? "pad-on" : ""
            onSoundFinished: function(name) {
                if (prompt.exitCode >= 0 && name === prompt.exitSound) Qt.exit(prompt.exitCode)
            }
        }
    }

    ColumnLayout {
        anchors.centerIn: parent
        spacing: 14

        LucideIcon {
            Layout.alignment: Qt.AlignHCenter
            Layout.preferredWidth: 32
            Layout.preferredHeight: 32
            name: "gamepad-2"
            color: "#9fc9f2"
        }
        Text {
            Layout.alignment: Qt.AlignHCenter
            text: prompt.title
            font.pixelSize: 24
            font.weight: Font.DemiBold
            color: "#f0f3f7"
        }

        RowLayout {
            Layout.alignment: Qt.AlignHCenter
            spacing: 12

            Repeater {
                model: [qsTr("Sí"), qsTr("No")]
                delegate: Rectangle {
                    required property int index
                    required property string modelData
                    implicitWidth: 108
                    implicitHeight: 42
                    radius: 14
                    color: prompt.choice === index ? "#336599" : "#202e3d"
                    border.width: prompt.choice === index ? 2 : 1
                    border.color: prompt.choice === index ? "#9fc9f2" : "#42566b"

                    Text {
                        anchors.centerIn: parent
                        text: parent.modelData
                        font.pixelSize: 17
                        color: "#f0f3f7"
                    }
                }
            }
        }

        RowLayout {
            Layout.alignment: Qt.AlignHCenter
            spacing: 8

            PadGlyph { size: 24; family: prompt.family; key: "DPAD" }
            Text { text: qsTr("Elegir"); color: "#bac9d8" }
            PadGlyph { size: 24; family: prompt.family; key: "A" }
            Text { text: qsTr("Confirmar"); color: "#bac9d8" }
            PadGlyph { size: 24; family: prompt.family; key: "B" }
            Text { text: qsTr("Cancelar"); color: "#bac9d8" }
        }
    }
}

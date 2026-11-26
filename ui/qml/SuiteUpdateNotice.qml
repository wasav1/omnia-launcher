pragma ComponentBehavior: Bound
import QtQuick

Item {
    id: notice
    required property var api
    required property string surface
    property bool activeSurface: true
    property bool interactionBlocked: false
    property real uiScale: 1
    property bool opened: false
    property int selected: 0
    property string seenVersion: ""
    property string failure: ""
    readonly property var status: api.suiteUpdate
    readonly property bool available: !!status.available && ["available", "error", "downloading", "ready", "applying"].includes(status.phase)
    readonly property string label: status.phase === "downloading" ? qsTr("Actualizando · %1 %").arg(status.progress)
        : status.phase === "ready" ? qsTr("Reiniciar Omnia")
        : status.phase === "applying" ? qsTr("Aplicando…") : qsTr("Actualizar")
    visible: opened && activeSurface
    z: 180
    FocusScope {
        id: keys
        anchors.fill: parent
        Keys.onPressed: function(event) {
            const key = event.key
            event.accepted = notice.pad(key === Qt.Key_Left ? "l" : key === Qt.Key_Right ? "r"
                : key === Qt.Key_Escape ? "B" : key === Qt.Key_Return || key === Qt.Key_Enter ? "A" : "")
        }
    }
    function observe() {
        if (activeSurface && !interactionBlocked && status.phase === "ready" && status.available !== seenVersion) {
            seenVersion = status.available
            show()
        }
    }
    onStatusChanged: observe()
    onActiveSurfaceChanged: { api.pollSuiteUpdate(surface, activeSurface); observe() }
    onInteractionBlockedChanged: observe()
    Timer {
        interval: notice.status.phase === "downloading" || notice.status.phase === "applying" ? 900 : 8000
        repeat: true
        running: notice.activeSurface
        triggeredOnStart: true
        onTriggered: notice.api.pollSuiteUpdate(notice.surface, true)
    }
    function show() {
        selected = 0
        failure = ""
        opened = true
        keys.forceActiveFocus()
    }
    function activate() {
        if (status.phase === "available" || status.phase === "error") action()
        else show()
    }
    function close() {
        seenVersion = status.available
        opened = false
        if (parent) parent.forceActiveFocus()
    }
    function action() {
        if (status.phase === "downloading" || status.phase === "applying") return
        failure = ""
        api.suiteUpdateAction(status.phase === "ready" ? "apply" : "start", function(code, body) {
            if (code !== 200) {
                if (!notice.opened) notice.show()
                notice.failure = body?.error || qsTr("Omnia no pudo iniciar la actualización.")
            }
        })
    }
    function pad(key) {
        if (!opened || !activeSurface) return false
        if (key === "l") selected = 0
        else if (key === "r") selected = 1
        else if (key === "B") close()
        else if (key === "A") { if (selected === 1) action(); else close() }
        return true
    }
    Rectangle {
        anchors.fill: parent
        color: "#A0000000"
        MouseArea { anchors.fill: parent }
        Rectangle {
            anchors.centerIn: parent
            width: Math.min(parent.width - 32, 540 * notice.uiScale)
            height: contents.implicitHeight + 44 * notice.uiScale
            radius: 16 * notice.uiScale
            color: "#152638"
            border.color: "#405C76"
            Column {
                id: contents
                anchors { left: parent.left; right: parent.right; top: parent.top; margins: 22 * notice.uiScale }
                spacing: 14 * notice.uiScale
                Text {
                    width: parent.width; wrapMode: Text.Wrap; color: "#F0F5FB"
                    font.pixelSize: 24 * notice.uiScale; font.weight: Font.DemiBold
                    text: notice.status.phase === "ready" ? qsTr("Reinicia Omnia para actualizar") : qsTr("Actualización de Omnia Game Suite")
                }
                Text {
                    width: parent.width; wrapMode: Text.Wrap; color: "#BDCDDC"; font.pixelSize: 16 * notice.uiScale
                    textFormat: Text.PlainText
                    text: notice.failure || notice.status.error || (notice.status.phase === "applying"
                        ? qsTr("Aplicando el cambio. Si el sistema lo solicita, autoriza la instalación.")
                        : notice.status.phase === "ready"
                          ? qsTr("La versión %1 está preparada. Omnia reiniciará el servicio y volverá a abrir sus ventanas.").arg(notice.status.available)
                          : notice.status.phase === "downloading" ? qsTr("Descargando la actualización en segundo plano.")
                          : qsTr("Puedes preparar la versión %1 mientras sigues usando Omnia.").arg(notice.status.available))
                }
                Rectangle {
                    visible: notice.status.phase === "downloading"
                    width: parent.width; height: visible ? 5 * notice.uiScale : 0; radius: height / 2; color: "#30475E"
                    Rectangle { height: parent.height; radius: height / 2; width: parent.width * notice.status.progress / 100; color: "#83BCFE" }
                }
                Row {
                    anchors.right: parent.right
                    spacing: 10 * notice.uiScale
                    Repeater {
                        model: [qsTr("Más tarde"), notice.status.phase === "ready" ? qsTr("Reiniciar ahora") : notice.label]
                        delegate: Rectangle {
                            id: choice
                            required property int index
                            required property string modelData
                            readonly property bool usable: index === 0 || !["downloading", "applying"].includes(notice.status.phase)
                            width: choiceText.implicitWidth + 28 * notice.uiScale
                            height: 40 * notice.uiScale; radius: height / 2
                            color: index === notice.selected ? "#336599" : "#223B53"
                            opacity: usable ? 1 : 0.6
                            Text { id: choiceText; anchors.centerIn: parent; text: choice.modelData; color: "#F0F5FB"; font.pixelSize: 15 * notice.uiScale }
                            MouseArea {
                                anchors.fill: parent; enabled: choice.usable; cursorShape: Qt.PointingHandCursor
                                onClicked: if (choice.index === 0) notice.close(); else notice.action()
                            }
                        }
                    }
                }
            }
        }
    }
}

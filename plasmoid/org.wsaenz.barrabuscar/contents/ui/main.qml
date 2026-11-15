import QtQuick
import QtQuick.Layouts
import QtQuick.Window
import org.kde.plasma.plasmoid
import org.kde.plasma.core as PlasmaCore
import org.kde.kirigami as Kirigami
import org.kde.taskmanager as TaskManager

// Buscador de juegos: ocupa el hueco libre del panel y centra el campo respecto a la pantalla.
PlasmoidItem {
    id: root
    preferredRepresentation: fullRepresentation
    Plasmoid.backgroundHints: PlasmaCore.Types.NoBackground
    readonly property string base: "http://127.0.0.1:47831"
    property bool appActive: false
    property bool menuOpen: false
    property string query: ""

    function api(path, cb) {
        var x = new XMLHttpRequest()
        x.open("GET", base + path)
        x.onreadystatechange = function() {
            if (x.readyState !== XMLHttpRequest.DONE) return
            var r = null
            if (x.status === 200) { try { r = JSON.parse(x.responseText) } catch (e) { r = null } }
            if (cb) cb(r)
        }
        x.send()
    }
    function scanActive() {
        var found = false
        for (var i = 0; i < tasks.count; i++)
            if (tasks.data(tasks.index(i, 0), TaskManager.AbstractTasksModel.IsActive) === true) { found = true; break }
        appActive = found
    }
    TaskManager.VirtualDesktopInfo { id: vdi }
    TaskManager.ActivityInfo { id: ai }
    TaskManager.TasksModel {
        id: tasks
        virtualDesktop: vdi.currentDesktop
        activity: ai.currentActivity
        filterByVirtualDesktop: true
        filterByActivity: true
        filterMinimized: true
        groupMode: TaskManager.TasksModel.GroupDisabled
        onDataChanged: root.scanActive()
        onCountChanged: root.scanActive()
    }
    Timer { interval: 1500; repeat: true; running: true; triggeredOnStart: true; onTriggered: root.scanActive() }
    Timer { interval: 300; repeat: true; running: true; onTriggered: root.api("/ui", function(r) { if (r) { root.menuOpen = r.menu === 1; root.query = r.q || "" } }) }

    fullRepresentation: Item {
        id: bar
        implicitHeight: Kirigami.Units.gridUnit * 2
        implicitWidth: 300
        Layout.fillWidth: true
        Layout.minimumWidth: 40
        readonly property bool desk: !root.appActive
        Rectangle {
            id: sbox
            property real gx: 0
            readonly property real sw: (Window.window && Window.window.screen) ? Window.window.screen.width : 1920
            width: Math.min(400, bar.width - 20); height: 28; radius: 14
            anchors.verticalCenter: parent.verticalCenter
            x: Math.max(6, Math.min(bar.width - width - 6, sw / 2 - gx - width / 2))
            color: (root.query !== "") ? "#4d000000" : "#33000000"
            border.width: (root.query !== "") ? 1 : 0; border.color: "#80e6d9a0"
            opacity: bar.desk && !root.menuOpen ? 1 : 0
            visible: opacity > 0.01
            Behavior on opacity { NumberAnimation { duration: 240 } }
            Behavior on color { ColorAnimation { duration: 180 } }
            Behavior on x { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }
            Timer { interval: 600; repeat: true; running: bar.desk; triggeredOnStart: true; onTriggered: sbox.gx = bar.mapToGlobal(0, 0).x }
            Kirigami.Icon { x: 10; anchors.verticalCenter: parent.verticalCenter; width: 15; height: 15; source: "search"; opacity: 0.8 }
            Text {
                x: 36; anchors.verticalCenter: parent.verticalCenter
                width: parent.width - 70; elide: Text.ElideRight
                text: root.query !== "" ? root.query : "Buscar juego del catálogo…"
                color: root.query !== "" ? Kirigami.Theme.textColor : Kirigami.Theme.disabledTextColor
                font.pixelSize: 14; font.family: "Hanken Grotesk"
            }
            Text {
                visible: root.query !== ""
                anchors.right: parent.right; anchors.rightMargin: 10; anchors.verticalCenter: parent.verticalCenter
                text: "✕"; color: Kirigami.Theme.disabledTextColor; font.pixelSize: 12
                MouseArea { anchors.fill: parent; anchors.margins: -6; onClicked: root.api("/search?q=", function() {}) }
            }
            MouseArea { anchors.fill: parent; z: -1; cursorShape: Qt.PointingHandCursor; onClicked: root.api("/search/open", function() {}) }
        }
    }
}

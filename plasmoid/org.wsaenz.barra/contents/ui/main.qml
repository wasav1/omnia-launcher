import QtQuick
import QtQuick.Layouts
import QtQuick.Window
import org.kde.plasma.plasmoid
import org.kde.plasma.core as PlasmaCore
import org.kde.kirigami as Kirigami
import org.kde.taskmanager as TaskManager

// Barra del launcher: botón del Big Menu; sin ventanas, un buscador de juegos centrado en la pantalla;
// con una aplicación activa, su icono y nombre (el menú global lo pone el applet nativo de Plasma a su lado).
PlasmoidItem {
    id: root
    preferredRepresentation: fullRepresentation
    Plasmoid.backgroundHints: PlasmaCore.Types.NoBackground
    // La tecla Windows (vía Plasma, como el lanzador estándar) activa este widget: abre/cierra el Big Menu
    Plasmoid.onActivated: root.api("/menu", function() {})
    readonly property string base: "http://127.0.0.1:47831"
    property string activeName: ""
    property var activeIcon: ""
    property bool appActive: false
    property bool menuOpen: false

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
        for (var i = 0; i < tasks.count; i++) {
            var ix = tasks.index(i, 0)
            if (tasks.data(ix, TaskManager.AbstractTasksModel.IsActive) === true) {
                activeName = String(tasks.data(ix, TaskManager.AbstractTasksModel.AppName) || tasks.data(ix, Qt.DisplayRole))
                activeIcon = tasks.data(ix, Qt.DecorationRole)
                found = true
                break
            }
        }
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
    Timer { interval: 300; repeat: true; running: true; onTriggered: root.api("/ui", function(r) { if (r) root.menuOpen = r.menu === 1 }) }

    fullRepresentation: Item {
        id: bar
        readonly property bool desk: !root.appActive
        implicitHeight: Kirigami.Units.gridUnit * 2
        implicitWidth: Kirigami.Units.gridUnit * 3
        // en el escritorio ocupa el ancho libre para poder centrar el buscador en la pantalla
        Layout.fillWidth: false
        Layout.minimumWidth: root.appActive && !root.menuOpen ? appRow.implicitWidth + 66 : 52
        Layout.preferredWidth: root.appActive && !root.menuOpen ? appRow.implicitWidth + 66 : 52

        // botón del Big Menu
        Rectangle {
            id: btn
            x: 6; anchors.verticalCenter: parent.verticalCenter
            width: 34; height: 30; radius: 9
            color: (bm.containsMouse || root.menuOpen) ? "#33ffffff" : "transparent"
            scale: bm.pressed ? 0.9 : 1
            Behavior on color { ColorAnimation { duration: 180 } }
            Behavior on scale { NumberAnimation { duration: 120; easing.type: Easing.OutCubic } }
            Kirigami.Icon { anchors.centerIn: parent; width: 22; height: 22; source: "view-app-grid-symbolic" }
            MouseArea { id: bm; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: root.api("/menu", function() {}) }
        }
        // aplicación activa
        Row {
            id: appRow
            x: 52; anchors.verticalCenter: parent.verticalCenter
            spacing: 8
            opacity: root.appActive && !root.menuOpen ? 1 : 0
            visible: opacity > 0.01
            Behavior on opacity { NumberAnimation { duration: 220 } }
            Kirigami.Icon { width: 22; height: 22; source: root.activeIcon; anchors.verticalCenter: parent.verticalCenter }
            Text { text: root.activeName; font.bold: true; font.pixelSize: 15; font.family: "Rajdhani"; font.letterSpacing: 0.8; color: Kirigami.Theme.textColor; anchors.verticalCenter: parent.verticalCenter }
        }
    }
}

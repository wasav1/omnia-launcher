import QtQuick
import QtQuick.Effects

// Tarjeta de un juego. Sin arte todavía: color propio por título (como hacía el prototipo cuando no había portada).
Item {
    id: card
    property var game
    property bool current: false
    signal activated

    readonly property real hue: {
        var h = 0, n = card.game ? card.game.name : ""
        for (var i = 0; i < n.length; i++) h = (h * 31 + n.charCodeAt(i)) % 360
        return h / 360
    }

    width: 220; height: 300
    scale: current ? 1.0 : 0.88
    opacity: current ? 1.0 : 0.6
    Behavior on scale { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }
    Behavior on opacity { NumberAnimation { duration: 160 } }

    Rectangle {
        anchors.fill: parent; radius: 18
        gradient: Gradient {
            GradientStop { position: 0.0; color: Qt.hsla(card.hue, 0.45, 0.30, 1) }
            GradientStop { position: 1.0; color: Qt.hsla(card.hue, 0.50, 0.12, 1) }
        }
    }
    // portada real (SteamGridDB) con esquinas redondeadas; si no hay, queda el degradado de arriba
    Item {
        id: cover
        anchors.fill: parent
        visible: !!(card.game && card.game.portada) && img.status === Image.Ready
        Image {
            id: img
            anchors.fill: parent; visible: false; asynchronous: true; cache: true
            source: card.game && card.game.portada ? card.game.portada : ""
            fillMode: Image.PreserveAspectCrop
            sourceSize.width: 440
        }
        Rectangle { id: mask; anchors.fill: parent; radius: 18; visible: false; layer.enabled: true }
        MultiEffect { anchors.fill: parent; source: img; maskEnabled: true; maskSource: mask }
    }
    Text {      // inicial grande de fondo (solo sin portada)
        visible: !cover.visible
        anchors.centerIn: parent; anchors.verticalCenterOffset: -20
        text: card.game ? card.game.name.charAt(0).toUpperCase() : ""
        color: Qt.rgba(1, 1, 1, 0.10); font.pixelSize: 150; font.bold: true
    }
    Rectangle {
        anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
        height: 120; radius: 18
        gradient: Gradient {      // oscurece hacia abajo para que el título se lea sobre cualquier portada
            GradientStop { position: 0.0; color: Qt.rgba(0, 0, 0, 0.0) }
            GradientStop { position: 0.55; color: Qt.rgba(0, 0, 0, 0.72) }
            GradientStop { position: 1.0; color: Qt.rgba(0, 0, 0, 0.92) }
        }
        Column {
            anchors { left: parent.left; right: parent.right; bottom: parent.bottom; margins: 14 }
            spacing: 4
            Text { width: parent.width; elide: Text.ElideRight; text: card.game ? card.game.name : ""; color: "#f4efd8"; font.pixelSize: 19; font.bold: true }
            Text { text: card.game ? card.game.src : ""; color: "#c9bf8a"; font.pixelSize: 14 }
        }
    }
    Text {
        visible: !!(card.game && card.game.fav)
        anchors { top: parent.top; right: parent.right; margins: 12 }
        text: "★"; color: "#e6d9a0"; font.pixelSize: 26
    }
    Rectangle {
        visible: !!(card.game && card.game.running)
        anchors { top: parent.top; left: parent.left; margins: 12 }
        width: runTxt.width + 18; height: 26; radius: 13; color: "#2e8b57"
        Text { id: runTxt; anchors.centerIn: parent; text: "En ejecución"; color: "white"; font.pixelSize: 13 }
    }
    Rectangle {      // borde por encima de la portada y del degradado
        anchors.fill: parent; radius: 18; color: "transparent"
        border.width: card.current ? 3 : 1
        border.color: card.current ? "#e6d9a0" : Qt.rgba(1, 1, 1, 0.15)
    }
    MouseArea { anchors.fill: parent; onClicked: card.activated() }
}

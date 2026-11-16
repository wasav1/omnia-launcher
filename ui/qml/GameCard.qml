import QtQuick
import QtQuick.Effects

// Tarjeta de biblioteca del prototipo: portada limpia, insignias finas y elevación al pasar.
Item {
    id: card
    property var game
    property bool current: false
    property string platformLabel: ""
    property color platformColor: "#6fc3c9"
    property string iconKey: "pc"
    property var api
    property Item coordinateRoot
    signal activated
    signal contextRequested(real x, real y)

    z: current ? 5 : 0
    opacity: 1
    transform: Translate { y: hoverArea.containsMouse && !card.current ? -10 : 0; Behavior on y { NumberAnimation { duration: 280; easing.type: Easing.OutCubic } } }

    // máscara de esquinas: TODO lo que pinta la tarjeta (fondo, escena, portada, degradados) queda recortado a 18 px de radio
    Item { id: cardMask; anchors.fill: parent; visible: false; layer.enabled: true; layer.smooth: true
        Rectangle { anchors.fill: parent; radius: 18 } }
    Item {
        id: artLayer
        anchors.fill: parent
        layer.enabled: true
        layer.smooth: true
        layer.effect: MultiEffect { maskEnabled: true; maskSource: cardMask; maskThresholdMin: 0.5; maskSpreadAtMin: 1.0 }
        Rectangle { anchors.fill: parent; color: "#171b18" }
        Scene {
            anchors.fill: parent
            pal: card.game && card.game.pal ? card.game.pal : ["#10150f", "#1f3328", "#18271f", "#0d1510", "#e6d9a0"]
            big: false
            visible: cover.status !== Image.Ready
        }
        Image {
            id: cover
            anchors.fill: parent
            source: card.game && card.game.portada ? card.game.portada : ""
            fillMode: Image.PreserveAspectCrop
            asynchronous: true
            smooth: true
            sourceSize.width: 600
            visible: status === Image.Ready
        }
        Rectangle {
            visible: cover.status !== Image.Ready
            anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
            height: parent.height * .44
            gradient: Gradient { GradientStop { position: 0; color: "#00000000" } GradientStop { position: 1; color: "#d9000000" } }
        }
        Column {
            visible: cover.status !== Image.Ready
            anchors { left: parent.left; right: parent.right; bottom: parent.bottom; margins: 14 }
            spacing: 3
            Text { width: parent.width; text: card.game ? card.game.name : ""; color: "#f3efe3"; font.family: card.game && card.game.font ? card.game.font : "Hanken Grotesk"; font.pixelSize: card.current ? 35 : 24; wrapMode: Text.WordWrap; maximumLineCount: 2; elide: Text.ElideRight }
            Text { width: parent.width; text: card.game ? card.game.sub || card.game.src : ""; color: "#d6d0bf"; font.family: "Hanken Grotesk"; font.pixelSize: card.current ? 20 : 17; elide: Text.ElideRight }
        }
    }
    Rectangle { anchors.fill: parent; radius: 18; color: "transparent"; border.width: 1; border.color: current ? "#d9ffffff" : "#38ffffff" }

    Rectangle {
        x: 12; y: 12; height: 26; radius: 13; color: "#8c000000"
        width: originRow.implicitWidth + 18
        Row { id: originRow; anchors.centerIn: parent; spacing: 5
            PlatIcon { key: card.iconKey; size: 17; color: card.platformColor; anchors.verticalCenter: parent.verticalCenter }
            Text { text: card.game && card.game.platform === "pc" && card.game.src ? "PC · " + card.game.src : card.platformLabel; color: card.platformColor; font.family: "Rajdhani"; font.pixelSize: 15; font.weight: Font.Bold; font.letterSpacing: .9; anchors.verticalCenter: parent.verticalCenter }
        }
    }
    Text { visible: !!(card.game && card.game.fav); anchors { right: parent.right; top: parent.top; margins: 10 } text: "★"; color: "#e6d9a0"; font.pixelSize: 22; style: Text.Outline; styleColor: "#99000000" }
    Rectangle {
        visible: !!game && !(game.lastPlayed > 0)               // sin jugar nunca: punto verde; con la tarjeta seleccionada, «NUEVO»
        anchors { right: parent.right; top: parent.top; topMargin: current ? 12 : 16; rightMargin: (game && game.fav ? 40 : 12) + (current ? 0 : 4) }
        height: current ? 26 : 14; radius: height/2; width: current ? newText.implicitWidth + 18 : 14
        color: "#6fd08c"; border.width: current ? 0 : 2; border.color: "#cc0c1a10"
        Text { id: newText; visible: card.current; anchors.centerIn: parent; text: "NUEVO"; color: "#0c1a10"; font.family: "Rajdhani"; font.pixelSize: 14; font.weight: Font.Bold; font.letterSpacing: 1.2 }
    }
    Rectangle {
        visible: !!(game && game.ports && game.ports.length > 1)
        anchors { right: parent.right; bottom: parent.bottom; margins: 12 }
        height: 26; radius: 13; color: "#8c000000"; width: portsText.implicitWidth + 18
        Text { id: portsText; anchors.centerIn: parent; text: (game && game.ports ? game.ports.length : 0) + " ports"; color: "#f3efe3"; font.family: "Rajdhani"; font.pixelSize: 15; font.weight: Font.Bold; font.letterSpacing: .9 }
    }
    MouseArea {
        id: hoverArea
        anchors.fill: parent; cursorShape: Qt.PointingHandCursor; hoverEnabled: true
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        onClicked: function(mouse) {
            if (mouse.button === Qt.RightButton) {
                const p = card.coordinateRoot ? card.mapToItem(card.coordinateRoot, mouse.x, mouse.y) : Qt.point(mouse.x, mouse.y)
                card.contextRequested(p.x, p.y)
            } else card.activated()
        }
    }
}

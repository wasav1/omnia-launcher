import QtQuick
import QtQuick.Effects

// Tarjeta de biblioteca del prototipo: portada limpia, insignias finas y elevación al pasar.
Item {
    id: card
    property var game
    property bool current: false
    property bool expanded: false
    property string platformLabel: ""
    property color platformColor: "#6fc3c9"
    property string iconKey: "pc"
    property var api
    property Item coordinateRoot
    property color accent: "#56d6c8"
    property color titleColor: "#f3efe3"
    property color secondaryColor: "#d6d0bf"
    property color mutedColor: "#8c929b"
    property string portName: ""
    property int portCount: 0
    property int portIndex: 0
    property string description: ""
    property string playedText: ""
    property string playtimeText: ""
    property string savesSummary: ""
    property bool launchFocused: false
    property real selectionProgress: current ? 1 : 0
    signal activated
    signal contextRequested(real x, real y)
    signal portStepRequested(int delta)
    signal launchRequested()

    z: current ? 5 : 0
    Behavior on selectionProgress { NumberAnimation { duration:420; easing.type:Easing.OutCubic } }
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
            pal: card.game && card.game.pal ? card.game.pal : ["#111923", "#405b78", "#273b53", "#101722", "#91a9c2"]
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
            visible: cover.status !== Image.Ready && !card.expanded
            anchors { left: parent.left; right: parent.right; bottom: parent.bottom; margins: 14 }
            spacing: 3
            Text { width: parent.width; text: card.game ? card.game.name : ""; color: "#f3efe3"; font.family: card.game && card.game.font ? card.game.font : "Hanken Grotesk"; font.pixelSize: 24 + 11 * card.selectionProgress; wrapMode: Text.WordWrap; maximumLineCount: 2; elide: Text.ElideRight }
            Text { width: parent.width; text: card.game ? card.game.sub || card.game.src : ""; color: "#d6d0bf"; font.family: "Hanken Grotesk"; font.pixelSize: 17 + 3 * card.selectionProgress; elide: Text.ElideRight }
        }
    }
    Rectangle { anchors.fill: parent; radius: 18; color: "transparent"; border.width: 1; border.color: current ? "#d9ffffff" : "#38ffffff" }

    Rectangle {
        visible: !card.expanded
        x: 12; y: 12; height: 26; radius: 13; color: "#8c000000"
        width: originRow.implicitWidth + 18
        Row { id: originRow; anchors.centerIn: parent; spacing: 5
            PlatIcon { key: card.iconKey; size: 17; color: card.platformColor; anchors.verticalCenter: parent.verticalCenter }
            Text { text: card.game && card.game.platform === "pc" && card.game.src ? "PC · " + card.game.src : card.platformLabel; color: card.platformColor; font.family: "Rajdhani"; font.pixelSize: 15; font.weight: Font.Bold; font.letterSpacing: .9; anchors.verticalCenter: parent.verticalCenter }
        }
    }
    Text { visible: !!(card.game && card.game.fav); anchors { right: parent.right; top: parent.top; margins: 10 } text: "★"; color: "#91a9c2"; font.pixelSize: 22; style: Text.Outline; styleColor: "#99000000" }
    Rectangle {
        visible: !!game && !(game.lastPlayed > 0)               // sin jugar nunca: punto verde; con la tarjeta seleccionada, «NUEVO»
        anchors { right: parent.right; top: parent.top; topMargin: current ? 12 : 16; rightMargin: (game && game.fav ? 40 : 12) + (current ? 0 : 4) }
        height: current ? 26 : 14; radius: height/2; width: current ? newText.implicitWidth + 18 : 14
        color: "#6fd08c"; border.width: current ? 0 : 2; border.color: "#cc0c1a10"
        Text { id: newText; visible: card.current; anchors.centerIn: parent; text: "NUEVO"; color: "#0c1a10"; font.family: "Rajdhani"; font.pixelSize: 14; font.weight: Font.Bold; font.letterSpacing: 1.2 }
    }
    Rectangle {
        visible: !!(game && game.ports && game.ports.length > 1) && !card.expanded
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

    // Ficha integrada: el arte conserva protagonismo y los controles descansan sobre
    // un degradado ascendente para mantener legible la información.
    Item {
        id: detailsPanel
        visible: opacity > 0.01
        opacity: card.expanded ? 1 : 0
        Behavior on opacity { NumberAnimation { duration:260; easing.type:Easing.OutCubic } }
        transform: Translate { y:card.expanded ? 0 : 20; Behavior on y { NumberAnimation { duration:300; easing.type:Easing.OutCubic } } }
        z: 4
        anchors { left: parent.left; right: parent.right; bottom: parent.bottom; leftMargin:1; rightMargin:1; bottomMargin:1 }
        height: Math.min(parent.height * 0.56, 390)
        Rectangle {
            anchors.fill: parent
            radius: 17; antialiasing: true
            gradient: Gradient {
                GradientStop { position: 0.0; color: "#00101824" }
                GradientStop { position: 0.28; color: "#bb101923" }
                GradientStop { position: 1.0; color: "#f2101721" }
            }
        }
        Column {
            anchors { left: parent.left; right: parent.right; bottom: parent.bottom; margins: 20 }
            spacing: 8
            Image {
                id: logoImage
                visible: status === Image.Ready
                source: card.game && card.game.logo ? card.game.logo : ""
                width: parent.width; height: 68
                fillMode: Image.PreserveAspectFit; horizontalAlignment: Image.AlignLeft
                asynchronous: true; smooth: true; sourceSize.width: 700
            }
            Text {
                visible: !card.game || !card.game.logo || logoImage.status !== Image.Ready
                width: parent.width
                text: card.game ? card.game.name : ""
                color: card.titleColor; font.family: card.game && card.game.font ? card.game.font : "Hanken Grotesk"
                font.pixelSize: 29; font.weight: Font.Bold; wrapMode: Text.WordWrap
                maximumLineCount: 2; elide: Text.ElideRight
            }
            Row {
                width: parent.width; spacing: 8
                Text { text: card.platformLabel; color: card.platformColor; font.family: "Rajdhani"; font.pixelSize: 17; font.weight: Font.Bold; font.letterSpacing: 1; anchors.verticalCenter: parent.verticalCenter }
                Text { text: "·"; color: card.mutedColor; font.pixelSize: 17; anchors.verticalCenter: parent.verticalCenter }
                Text { text: card.playedText; color: card.secondaryColor; font.family: "Hanken Grotesk"; font.pixelSize: 16; elide: Text.ElideRight; anchors.verticalCenter: parent.verticalCenter }
            }
            Text {
                visible: card.description !== ""
                width: parent.width; text: card.description; color: card.secondaryColor
                font.family: "Hanken Grotesk"; font.pixelSize: 15; lineHeight: 1.12
                wrapMode: Text.WordWrap; maximumLineCount: 2; elide: Text.ElideRight
            }
            Text {
                visible: card.playtimeText !== ""
                width: parent.width; text: card.playtimeText; color: card.secondaryColor
                font.family: "Hanken Grotesk"; font.pixelSize: 15
            }
            Text {
                visible: card.savesSummary !== ""
                width: parent.width; text: card.savesSummary; color: card.secondaryColor
                font.family: "Hanken Grotesk"; font.pixelSize: 14; wrapMode: Text.WordWrap
                maximumLineCount: 2; elide: Text.ElideRight
            }
            Rectangle {
                width: parent.width; height: 46; radius: 23
                color: playArea.containsMouse ? Qt.lighter(card.accent, 1.08) : card.accent
                Row {
                    anchors.centerIn: parent; spacing: 10
                    Text { text: "▶"; color: card.accent.hslLightness > 0.55 ? "#101820" : "#f3f6fa"; font.pixelSize: 16; anchors.verticalCenter: parent.verticalCenter }
                    Text { text: "Jugar"; color: card.accent.hslLightness > 0.55 ? "#101820" : "#f3f6fa"; font.family: "Hanken Grotesk"; font.pixelSize: 18; font.weight: Font.DemiBold; anchors.verticalCenter: parent.verticalCenter }
                }
                Rectangle { visible: card.launchFocused; anchors.fill: parent; anchors.margins: -4; radius: 27; color: "transparent"; border.width: 3; border.color: card.accent }
                MouseArea { id: playArea; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: card.launchRequested() }
            }
        }
    }
}

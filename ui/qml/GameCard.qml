import QtQuick
import QtQuick.Effects
import QtQuick.Controls

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
    property var originBadges: []
    property string lastSessionText: ""
    property string playtimeText: ""
    property int savesCount: 0
    property string latestSaveText: ""
    property string backupText: qsTr("Sin respaldo")
    property var saveSlots: []
    property bool savesOpen: false
    property bool launchFocused: false
    property real selectionProgress: current ? 1 : 0
    signal activated
    signal contextRequested(real x, real y)
    signal portStepRequested(int delta)
    signal launchRequested()

    function relativeSaveTime(ts) {
        if (!ts) return qsTr("sin fecha")
        const d = new Date(ts * 1000), now = new Date()
        const hm = (d.getHours() < 10 ? "0" : "") + d.getHours() + ":" + (d.getMinutes() < 10 ? "0" : "") + d.getMinutes()
        const start = new Date(now.getFullYear(), now.getMonth(), now.getDate()).getTime()
        if (d.getTime() >= start) return qsTr("Hoy, %1").arg(hm)
        if (d.getTime() >= start - 86400000) return qsTr("Ayer, %1").arg(hm)
        return d.getDate() + " " + [qsTr("ene"),qsTr("feb"),qsTr("mar"),qsTr("abr"),qsTr("may"),qsTr("jun"),qsTr("jul"),qsTr("ago"),qsTr("sep"),qsTr("oct"),qsTr("nov"),qsTr("dic")][d.getMonth()] + " · " + hm
    }
    onCurrentChanged: if (!current) savesOpen = false

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
    LucideIcon { visible: !!(card.game && card.game.fav); anchors { right: parent.right; top: parent.top; margins: 12 } name: "star"; width: 20; height: 20; color: "#b1c6dc" }
    Rectangle {
        id: newBadge
        visible: !!game && !(game.lastPlayed > 0)               // sin jugar nunca: punto verde; con la tarjeta seleccionada, «NUEVO»
        anchors { right: parent.right; top: parent.top; topMargin: current ? 12 : 16; rightMargin: (game && game.fav ? 40 : 12) + (current ? 0 : 4) }
        height: current ? 26 : 14; radius: height/2; width: current ? newText.implicitWidth + 18 : 14
        color: "#6fd08c"; border.width: current ? 0 : 2; border.color: "#cc0c1a10"
        Text { id: newText; visible: card.current; anchors.centerIn: parent; text: qsTr("NUEVO"); color: "#0c1a10"; font.family: "Rajdhani"; font.pixelSize: 14; font.weight: Font.Bold; font.letterSpacing: 1.2 }
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

    Row {
        visible: card.expanded
        anchors { left: parent.left; top: parent.top; margins: 12 }
        spacing: 5
        Repeater {
            model: card.expanded ? card.originBadges : []
            delegate: Rectangle {
                required property string modelData
                required property int index
                width: Math.min(badgeText.implicitWidth + 16 + (index === 0 ? consoleIcon.width + 4 : 0),
                                Math.max(36, (card.width - 24 - (newBadge.visible ? newBadge.width + 8 : 0)
                                              - (card.game && card.game.fav ? 28 : 0)
                                              - 5 * (card.originBadges.length - 1)) / card.originBadges.length))
                height: 26
                radius: height / 2
                color: "#c31b2532"
                Row {
                    id: badgeContent
                    anchors.centerIn: parent
                    spacing: 4
                    PlatIcon {
                        id: consoleIcon
                        visible: index === 0
                        key: card.game && card.game.platform ? card.game.platform : "pc"
                        size: 16
                        color: card.platformColor
                        anchors.verticalCenter: parent.verticalCenter
                    }
                    Text {
                        id: badgeText
                        width: Math.min(implicitWidth, Math.max(0, badgeContent.parent.width - 16
                                                              - (index === 0 ? consoleIcon.width + 4 : 0)))
                        text: modelData
                        color: index === 0 ? card.platformColor : card.secondaryColor
                        font.family: "Rajdhani"
                        font.pixelSize: 14
                        font.weight: Font.Bold
                        elide: Text.ElideRight
                        anchors.verticalCenter: parent.verticalCenter
                    }
                }
            }
        }
    }

    Item {
        id: detailsPanel
        anchors.fill: parent
        visible: opacity > 0.01
        opacity: card.expanded ? 1 : 0
        Behavior on opacity { NumberAnimation { duration: 260; easing.type: Easing.OutCubic } }
        z: 4
        clip: true

        Item {
            anchors { left: parent.left; right: parent.right; margins: 15 }
            y: Math.max(42, parent.height - 417)
            height: 64
            Image {
                id: logoImage
                anchors.fill: parent
                visible: status === Image.Ready
                source: card.expanded && card.game && card.game.logo ? card.game.logo : ""
                fillMode: Image.PreserveAspectFit
                horizontalAlignment: Image.AlignLeft
                asynchronous: true
                smooth: true
                sourceSize.width: 700
            }
            Text {
                anchors.fill: parent
                visible: logoImage.status !== Image.Ready
                text: card.game ? card.game.name : ""
                color: card.titleColor
                font.family: card.game && card.game.font ? card.game.font : "Hanken Grotesk"
                font.pixelSize: 28
                font.weight: Font.Bold
                wrapMode: Text.WordWrap
                maximumLineCount: 2
                elide: Text.ElideRight
                verticalAlignment: Text.AlignVCenter
            }
        }
        Column {
            id: detailColumn
            anchors { left: parent.left; right: parent.right; bottom: parent.bottom; margins: 15; bottomMargin: 35 }
            spacing: 6
            Row {
                id: metricsRow
                width: parent.width; height: 48; spacing: 8
                Repeater {
                    model: [{label:qsTr("TIEMPO JUGADO"),value:card.playtimeText},{label:qsTr("ÚLTIMA SESIÓN"),value:card.lastSessionText}]
                    delegate: Item {
                        id: metric
                        required property var modelData
                        width: (parent.width - 8) / 2; height: 48
                        FrostedSurface {
                            anchors.fill: parent
                            backdrop: artLayer
                            backdropRect: Qt.rect(detailColumn.x + metric.x, detailColumn.y + metricsRow.y, width, height)
                            sampling: card.expanded && visible
                            radius: 10
                            feather: 4
                        }
                        Column { anchors { left:parent.left; right:parent.right; verticalCenter:parent.verticalCenter; margins:9 } spacing:1
                            Text { text:modelData.label; color:card.mutedColor; font.family:"Rajdhani"; font.pixelSize:11; font.letterSpacing:1; elide:Text.ElideRight }
                            Text { text:modelData.value; color:card.titleColor; font.family:"Hanken Grotesk"; font.pixelSize:15; font.weight:Font.DemiBold; elide:Text.ElideRight }
                        }
                    }
                }
            }
            Item {
                id: savesBox
                width: parent.width
                height: savesColumn.implicitHeight + 16
                FrostedSurface {
                    anchors.fill: parent
                    backdrop: artLayer
                    backdropRect: Qt.rect(detailColumn.x, detailColumn.y + savesBox.y, width, height)
                    sampling: card.expanded && visible
                    radius: 10
                    feather: 4
                }
                Column { id:savesColumn; anchors { left:parent.left; right:parent.right; top:parent.top; margins:8 } spacing:3
                    Row { width:parent.width; height:20; spacing:6
                        Text { width:parent.width-backupLabel.width-6; text:qsTr("Partidas: %1").arg(card.savesCount ? card.savesCount + (card.savesCount === 1 ? " " + qsTr("ranura") : " " + qsTr("ranuras")) : qsTr("ninguna")); color:card.titleColor; font.family:"Hanken Grotesk"; font.pixelSize:14; font.weight:Font.DemiBold; anchors.verticalCenter:parent.verticalCenter; elide:Text.ElideRight }
                        Text { id:backupLabel; width:Math.min(135,parent.width*0.42); text:card.backupText; color:card.mutedColor; font.family:"Hanken Grotesk"; font.pixelSize:12; anchors.verticalCenter:parent.verticalCenter; elide:Text.ElideRight }
                    }
                    Text { width:parent.width; text:card.latestSaveText; color:card.secondaryColor; font.family:"Hanken Grotesk"; font.pixelSize:13; elide:Text.ElideRight }
                    Text {
                        visible:card.savesCount > 0
                        text:card.savesOpen ? qsTr("Ocultar ranuras") : qsTr("Ver ranuras (%1)").arg(card.savesCount)
                        color:card.accent; font.family:"Hanken Grotesk"; font.pixelSize:12; font.weight:Font.DemiBold
                        MouseArea { anchors.fill:parent; cursorShape:Qt.PointingHandCursor; onClicked:card.savesOpen=!card.savesOpen }
                    }
                    ListView {
                        visible: card.savesOpen
                        width: parent.width
                        height: Math.min(114, count * 19)
                        clip: true
                        boundsBehavior: Flickable.StopAtBounds
                        model: card.savesOpen ? card.saveSlots : []
                        ScrollBar.vertical: ScrollBar {}
                        delegate: Row {
                            required property var modelData
                            width: ListView.view.width - 8
                            height: 19
                            spacing: 6
                            Text { text:modelData.name||qsTr("Partida"); color:card.secondaryColor; font.family:"Hanken Grotesk"; font.pixelSize:12; width:parent.width-100; elide:Text.ElideRight }
                            Text { text:modelData.used?card.relativeSaveTime(modelData.mtime):qsTr("vacía"); color:card.mutedColor; font.family:"Hanken Grotesk"; font.pixelSize:12; width:94; horizontalAlignment:Text.AlignRight; elide:Text.ElideRight }
                        }
                    }
                }
            }
            Rectangle {
                width: parent.width; height: 42; radius: 21
                color: playArea.containsMouse ? Qt.lighter(card.accent, 1.08) : card.accent
                Row { anchors.centerIn: parent; spacing: 9
                    LucideIcon { name: "play"; width: 16; height: 16; color: card.accent.hslLightness > 0.55 ? "#101820" : "#f3f6fa"; anchors.verticalCenter: parent.verticalCenter }
                    Text { text: qsTr("Jugar"); color: card.accent.hslLightness > 0.55 ? "#101820" : "#f3f6fa"; font.family: "Hanken Grotesk"; font.pixelSize: 17; font.weight: Font.DemiBold; anchors.verticalCenter: parent.verticalCenter }
                }
                Rectangle { visible: card.launchFocused; anchors.fill: parent; anchors.margins: -4; radius: 25; color: "transparent"; border.width: 3; border.color: card.accent }
                MouseArea { id: playArea; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: card.launchRequested() }
            }
        }
    }
}

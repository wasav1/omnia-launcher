import QtQuick

/** Tarjeta de exploración basada en carátula, con metadatos sobre un degradado y zoom al pasar el cursor. */
Item {
    id: card
    property string title: ""
    property url artwork: ""
    property string store: ""
    property url sourceLogo: ""
    property string platform: ""
    property string info: ""
    property bool installed: false
    property real scaleFactor: 1
    readonly property bool hovered: posterMouse.containsMouse
    signal activated()
    z: hovered ? 2 : 0

    Rectangle {
        id: cover
        anchors.fill: parent
        radius: 13 * card.scaleFactor
        color: "#18232D"
        clip: true
        scale: posterMouse.containsMouse ? 1.045 : 1
        z: posterMouse.containsMouse ? 2 : 0
        Behavior on scale { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }

        FadedImage {
            anchors.fill: parent
            source: card.artwork
            retainWhileLoading: true
            cornerRadius: 13 * card.scaleFactor
        }
        Rectangle {
            anchors.fill: parent
            radius: 13 * card.scaleFactor
            gradient: Gradient {
                GradientStop { position: 0.32; color: "#00000000" }
                GradientStop { position: 0.64; color: "#66000000" }
                GradientStop { position: 1.0; color: "#ED000000" }
            }
        }
        Rectangle {
            anchors.fill: parent
            radius: 13 * card.scaleFactor
            color: posterMouse.containsMouse ? "#243DD8D0" : "transparent"
            border.width: posterMouse.containsMouse ? 2 : 0
            border.color: "#6CE2DC"
            Behavior on color { ColorAnimation { duration: 150 } }
        }
        Rectangle {
            anchors.fill: parent
            radius: cover.radius
            gradient: Gradient {
                GradientStop { position: 0; color: "#CC000000" }
                GradientStop { position: 0.53; color: "transparent" }
            }
        }
        Image {
            anchors { left: parent.left; top: parent.top; margins: 11 * card.scaleFactor }
            width: 30 * card.scaleFactor; height: width
            source: card.sourceLogo
            sourceSize: Qt.size(96, 96)
            fillMode: Image.PreserveAspectFit
        }
        Column {
            anchors { left: parent.left; right: parent.right; bottom: parent.bottom; margins: 11 * card.scaleFactor }
            spacing: 3 * card.scaleFactor
            Text {
                visible: card.store !== ""
                width: parent.width
                text: card.store
                color: "#70E0D9"
                font.family: "Hanken Grotesk"
                font.pixelSize: 10 * card.scaleFactor
                font.weight: Font.Bold
                elide: Text.ElideRight

            }
            Text {
                width: parent.width
                text: card.title
                color: "#F5F7FA"
                font.family: "Hanken Grotesk"
                font.pixelSize: 15 * card.scaleFactor
                font.weight: Font.DemiBold
                elide: Text.ElideRight
                maximumLineCount: 2
                wrapMode: Text.Wrap
            }
            Text {
                visible: card.platform !== "" || card.info !== ""
                width: parent.width
                text: [card.platform, card.info].filter(function(x) { return !!x }).join(" · ")
                color: "#CBD4DC"
                font.family: "Hanken Grotesk"
                font.pixelSize: 10 * card.scaleFactor
                elide: Text.ElideRight
            }
        }
        Rectangle {
            visible: card.installed
            anchors { right: parent.right; top: parent.top; margins: 10 * card.scaleFactor }
            width: 13 * card.scaleFactor; height: width; radius: width / 2
            color: "#13E889"
            border.width: 1 * card.scaleFactor
            border.color: "#D7FFF0"
        }
        MouseArea {
            id: posterMouse
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: card.activated()
        }
    }
}

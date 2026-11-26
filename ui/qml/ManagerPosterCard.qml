import QtQuick

/** Tarjeta de exploración basada en carátula, con metadatos sobre un degradado y zoom al pasar el cursor.
 *  Cuando pertenece a una lista desplazable, solo carga el arte cerca del área visible. */
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
    property real hoverScale: 1.045
    property Flickable viewport: null
    property real viewportTop: 0
    property bool selected: false
    property color highlightColor: "#6CE2DC"
    readonly property bool emphasized: hovered || selected
    // Keep the hit area fixed and move the enlarged artwork inward at the viewport edges.
    readonly property point viewportPosition: {
        if (!viewport || !emphasized) return Qt.point(0, 0)
        const pos = card.mapToItem(viewport.contentItem, 0, 0)
        return Qt.point(pos.x - viewport.contentX, pos.y - viewport.contentY)
    }
    readonly property bool artworkInRange: {
        if (!viewport) return true
        const pos = card.mapToItem(viewport.contentItem, 0, 0)
        const x = pos.x - viewport.contentX, y = pos.y - viewport.contentY
        const marginX = width, marginY = height
        return x + width > -marginX && x < viewport.width + marginX
            && y + height > viewportTop - marginY && y < viewport.height + marginY
    }
    readonly property real enlargement: {
        if (!emphasized) return 1
        if (!viewport) return hoverScale
        const pos = viewportPosition
        return pos.x >= -0.5 && pos.y >= viewportTop - 0.5
            && pos.x + width <= viewport.width + 0.5 && pos.y + height <= viewport.height + 0.5
            ? hoverScale : 1
    }
    function correction(start, length, min, max) {
        const spill = length * (enlargement - 1) / 2
        return enlargement <= 1 ? 0 : Math.max(min - start + spill, Math.min(0, max - start - length - spill))
    }
    signal doubleActivated()
    signal contextRequested()
    readonly property bool hovered: posterMouse.containsMouse
    signal activated()
    z: emphasized ? 2 : 0

    Rectangle {
        id: cover
        width: card.width
        height: card.height
        readonly property real paddingX: card.viewport ? card.correction(card.viewportPosition.x, width, 0, card.viewport.width) : 0
        readonly property real paddingY: card.viewport ? card.correction(card.viewportPosition.y, height, card.viewportTop, card.viewport.height) : 0
        x: paddingX * (scale - 1) / Math.max(0.001, card.hoverScale - 1)
        y: paddingY * (scale - 1) / Math.max(0.001, card.hoverScale - 1)
        radius: 13 * card.scaleFactor
        color: "#18232D"
        clip: true
        scale: card.enlargement
        Behavior on scale { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }

        FadedImage {
            anchors.fill: parent
            source: card.artworkInRange ? card.artwork : ""
            retainWhileLoading: true
            cornerRadius: cover.radius
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
        Rectangle {
            anchors.fill: parent
            radius: cover.radius
            color: card.emphasized ? "#243DD8D0" : "transparent"
            border.width: card.emphasized ? Math.max(1, 2 * card.scaleFactor) : 0
            border.color: card.highlightColor
            Behavior on color { ColorAnimation { duration: 150 } }
        }
    }
    MouseArea {
        id: posterMouse
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        onClicked: mouse => { if (mouse.button === Qt.RightButton) card.contextRequested(); else card.activated() }
        onDoubleClicked: mouse => { if (mouse.button === Qt.LeftButton) card.doubleActivated() }
    }
}

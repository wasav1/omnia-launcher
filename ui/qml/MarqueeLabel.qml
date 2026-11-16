import QtQuick

// Centra el texto corto y desplaza lentamente el texto largo en un bucle suave.
Item {
    id: root
    property string text: ""
    property color color: "white"
    property font textFont: Qt.font({ family: "Noto Sans", pixelSize: 16 })
    property real gap: 54
    property bool scrolling: true
    property real offset: 0
    readonly property bool overflow: label.implicitWidth > width
    implicitHeight: textFont.pixelSize * 1.45
    clip: true

    onTextChanged: offset = 0

    Text {
        id: label
        x: root.overflow ? root.offset : Math.max(0, (root.width - implicitWidth) / 2)
        anchors.verticalCenter: parent.verticalCenter
        text: root.text
        width: implicitWidth
        color: root.color
        font: root.textFont
        elide: Text.ElideNone
        verticalAlignment: Text.AlignVCenter
    }
    Text {
        visible: root.overflow
        x: root.offset + label.implicitWidth + root.gap
        anchors.verticalCenter: parent.verticalCenter
        text: root.text
        width: implicitWidth
        color: root.color
        font: root.textFont
        elide: Text.ElideNone
        verticalAlignment: Text.AlignVCenter
    }
    SequentialAnimation {
        running: root.scrolling && root.overflow && root.visible
        loops: Animation.Infinite
        PauseAnimation { duration: 900 }
        NumberAnimation {
            target: root
            property: "offset"
            from: 0
            to: -(label.implicitWidth + root.gap)
            duration: Math.max(4200, (label.implicitWidth + root.gap) * 34)
            easing.type: Easing.Linear
        }
    }
}

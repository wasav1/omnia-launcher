import qs.services
import QtQuick

// Interruptor compacto 46×26: pista y perilla de 20 px.
Rectangle {
    id: sw
    property bool checked: false
    signal toggled(bool value)

    implicitWidth: 46
    implicitHeight: 26
    radius: 13
    color: checked ? OmniaTheme.accent : Qt.rgba(1, 1, 1, 0.11)
    border.width: checked ? 0 : 1
    border.color: Qt.rgba(1, 1, 1, 0.24)
    Behavior on color { ColorAnimation { duration: 160 } }

    Rectangle {
        width: 20; height: 20; radius: 10
        y: 3
        x: sw.checked ? 23 : 3
        color: sw.checked ? OmniaTheme.ink : "#F0F3F7"
        Behavior on x { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }
    }
    MouseArea {
        anchors.fill: parent
        cursorShape: Qt.PointingHandCursor
        onClicked: sw.toggled(!sw.checked)
    }
}

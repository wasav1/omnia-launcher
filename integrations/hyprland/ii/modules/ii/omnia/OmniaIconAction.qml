import qs.services
import qs.modules.common
import qs.modules.common.widgets
import QtQuick

// Botón redondo solo con icono (actualizar, cerrar).
Rectangle {
    id: rb
    property string icon
    signal clicked()

    implicitWidth: 32
    implicitHeight: 32
    radius: 16
    color: ma.containsMouse ? Qt.rgba(1, 1, 1, 0.10) : "transparent"

    OmniaLucide {
        anchors.centerIn: parent
        name: rb.icon
        width: 19; height: 19
        color: OmniaTheme.ink
    }
    MouseArea {
        id: ma
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: rb.clicked()
    }
}

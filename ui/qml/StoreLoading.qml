pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls

Row {
    id: status
    property real uiScale: 1
    property color ink: "white"
    spacing: 8 * uiScale
    BusyIndicator {
        anchors.verticalCenter: parent.verticalCenter
        width: 26 * status.uiScale
        height: width
        running: status.visible
    }
    Text {
        anchors.verticalCenter: parent.verticalCenter
        text: qsTr("Cargando juegos de las tiendas…")
        font.family: "Hanken Grotesk"
        font.pixelSize: 14 * status.uiScale
        color: status.ink
    }
}

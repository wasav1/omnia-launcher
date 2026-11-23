import Qt5Compat.GraphicalEffects
import QtQuick

// Imagen con esquinas redondeadas (recorte con máscara).
Item {
    id: ri
    property real radius: 12
    property alias source: img.source
    property alias status: img.status

    Image {
        id: img
        anchors.fill: parent
        visible: false
        asynchronous: true
        fillMode: Image.PreserveAspectCrop
        sourceSize.width: Math.max(1, ri.width * 2)
        sourceSize.height: Math.max(1, ri.height * 2)
    }
    Rectangle {
        id: mask
        anchors.fill: parent
        radius: ri.radius
        visible: false
    }
    OpacityMask {
        anchors.fill: parent
        source: img
        maskSource: mask
        visible: img.status === Image.Ready
    }
}

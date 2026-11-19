import QtQuick
import Qt5Compat.GraphicalEffects

Item {
    id: icon
    property string name
    property color color: "#edf4f8"
    implicitWidth: 20
    implicitHeight: 20

    Image {
        id: glyph
        anchors.fill: parent
        visible: false
        source: icon.name ? Qt.resolvedUrl("images/lucide/" + icon.name + ".svg") : ""
        sourceSize.width: Math.ceil(icon.width * 2)
        sourceSize.height: Math.ceil(icon.height * 2)
        fillMode: Image.PreserveAspectFit
    }
    ColorOverlay {
        anchors.fill: parent
        source: glyph
        color: icon.color
        visible: glyph.status === Image.Ready
    }
}

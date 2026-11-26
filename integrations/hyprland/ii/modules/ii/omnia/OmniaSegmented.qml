import qs.services
import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import QtQuick.Layouts

// Selector segmentado: la opción elegida usa el acento de Omnia y texto de alto contraste.
Rectangle {
    id: seg
    property var options: []                 // [{ label: "5 min", value: 5 }, …]
    property var current
    signal picked(var value)

    implicitHeight: 38
    implicitWidth: row.implicitWidth + 8
    radius: 13
    color: OmniaTheme.card(OmniaSettings.blur)
    border.width: 1
    border.color: Qt.rgba(1, 1, 1, 0.08)

    RowLayout {
        id: row
        anchors { fill: parent; margins: 4 }
        spacing: 2
        Repeater {
            model: seg.options
            delegate: Rectangle {
                id: opt
                required property var modelData
                readonly property bool on: seg.current === modelData.value
                Layout.fillWidth: true
                Layout.fillHeight: true
                implicitWidth: label.implicitWidth + 22
                radius: 10
                color: on ? OmniaTheme.ink : (ma.containsMouse ? Qt.rgba(1, 1, 1, 0.08) : "transparent")
                Behavior on color { ColorAnimation { duration: 120 } }
                StyledText {
                    id: label
                    anchors.centerIn: parent
                    text: opt.modelData.label
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    font.weight: Font.DemiBold
                    color: opt.on ? OmniaTheme.bg : OmniaTheme.ink
                }
                MouseArea {
                    id: ma
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: seg.picked(opt.modelData.value)
                }
            }
        }
    }
}

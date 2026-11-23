import qs.services
import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import QtQuick.Layouts

// Botón de acción en forma de píldora: primario (acento), secundario (contenedor) o translúcido (sobre imágenes).
Rectangle {
    id: pill
    property string label
    property string icon: ""
    property bool primary: false
    property bool subtle: false
    property bool danger: false
    property bool enabled2: true
    property bool ringed: false
    readonly property color ink: OmniaTheme.ink
    readonly property color fg: danger ? OmniaTheme.danger : ink
    signal clicked()

    implicitHeight: 34
    implicitWidth: pillRow.implicitWidth + 28
    radius: height / 2
    opacity: enabled2 ? 1 : 0.45
    color: danger ? (ma.containsMouse ? Qt.rgba(1, 0.4, 0.4, 0.22) : Qt.rgba(1, 0.4, 0.4, 0.10))
         : primary ? (ma.containsMouse ? OmniaTheme.accentHi : OmniaTheme.accent)
         : subtle ? (ma.containsMouse ? Qt.rgba(1, 1, 1, 0.22) : Qt.rgba(1, 1, 1, 0.12))
         : (ma.containsMouse ? Qt.rgba(1, 1, 1, 0.18) : Qt.rgba(1, 1, 1, 0.10))
    border.width: ringed ? 2 : 0
    border.color: "#5b9be0"
    Behavior on color { ColorAnimation { duration: 120 } }

    RowLayout {
        id: pillRow
        anchors.centerIn: parent
        spacing: 6
        OmniaLucide {
            visible: pill.icon !== ""
            name: pill.icon
            width: 18; height: 18
            color: pill.fg
        }
        StyledText {
            text: pill.label
            color: pill.fg
        }
    }
    MouseArea {
        id: ma
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        enabled: pill.enabled2
        onClicked: pill.clicked()
    }
}

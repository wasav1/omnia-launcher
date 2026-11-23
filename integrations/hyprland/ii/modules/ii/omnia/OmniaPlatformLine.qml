import qs.services
import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

RowLayout {
    id: platformLine
    required property var game
    readonly property var platformNames: ({ pc: "PC", sw1: "Switch", sw2: "Switch 2", n64: "N64" })
    property color ink: OmniaTheme.inkDim
    spacing: 6
    OmniaPlatformIcon {
        key: platformLine.game?.platform || ""
        size: 14
        color: platformLine.ink
        visible: key !== ""
        Accessible.name: platformLine.platformNames[key] ?? key
        ToolTip.visible: platformHover.hovered
        ToolTip.text: Accessible.name
        HoverHandler { id: platformHover }
    }
    StyledText {
        Layout.fillWidth: true
        text: (platformLine.game?.variant || platformLine.game?.src || "")
        font.pixelSize: Appearance.font.pixelSize.smaller
        color: platformLine.ink
        elide: Text.ElideRight
    }
}

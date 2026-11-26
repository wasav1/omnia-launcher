import QtQuick
import Quickshell.Io
import qs.Modules.Plugins

PluginComponent {
    id: root

    popoutWidth: 400
    popoutHeight: 620
    popoutContent: Component {
        OmniaPanel { onCloseRequested: root.closePopout() }
    }

    IpcHandler {
        target: "omniaPanel"
        function open(): string {
            root.triggerPopout();
            return "OMNIA_PANEL_OPEN";
        }
        function toggle(): string {
            root.triggerPopout();
            return "OMNIA_PANEL_TOGGLE";
        }
    }

    component BrandIcon: Image {
        source: Qt.resolvedUrl("omnia-mark-solid.svg")
        sourceSize.width: width
        sourceSize.height: height
        width: root.iconSize
        height: root.iconSize
        fillMode: Image.PreserveAspectFit
        Accessible.name: "Omnia Game Suite"
    }

    horizontalBarPill: Component { BrandIcon {} }
    verticalBarPill: Column {
        BrandIcon { anchors.horizontalCenter: parent.horizontalCenter }
    }
}

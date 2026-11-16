import QtQuick
import QtQuick.Window
import org.kde.layershell as LayerShell

// Vista de desarrollo: estantería bajo las ventanas; el menú pertenece a Plasma.
QtObject {
    id: app

    property Window desktop: Window {
        visible: true; color: "#000000"; flags: Qt.FramelessWindowHint; title: "Omnia"
        LayerShell.Window.scope: "omnia-ui"
        LayerShell.Window.layer: LayerShell.Window.LayerBackground
        LayerShell.Window.anchors: LayerShell.Window.AnchorTop | LayerShell.Window.AnchorBottom | LayerShell.Window.AnchorLeft | LayerShell.Window.AnchorRight
        LayerShell.Window.exclusionZone: -1
        LayerShell.Window.keyboardInteractivity: LayerShell.Window.KeyboardInteractivityOnDemand
        OmniaShell { id: shell; anchors.fill: parent; bottomInset: 64 }
    }

}

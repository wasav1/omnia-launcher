import QtQuick
import QtQuick.Window
import org.kde.layershell as LayerShell

// omnia-ui como escritorio: dos ventanas de capa. La estantería va al fondo (bajo ventanas y paneles) y el Big Menu en la
// capa superior con el teclado en exclusiva mientras está abierto. El raíz es un QtObject para que ambas sean de nivel superior.
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

    property Window menu: Window {
        visible: shell.menuOpen; color: "transparent"; flags: Qt.FramelessWindowHint; title: "Omnia Menú"
        LayerShell.Window.scope: "omnia-menu"
        LayerShell.Window.layer: LayerShell.Window.LayerTop
        LayerShell.Window.anchors: LayerShell.Window.AnchorTop | LayerShell.Window.AnchorBottom | LayerShell.Window.AnchorLeft | LayerShell.Window.AnchorRight
        LayerShell.Window.exclusionZone: -1
        LayerShell.Window.keyboardInteractivity: LayerShell.Window.KeyboardInteractivityExclusive
        BigMenu {
            anchors.fill: parent
            api: shell.backend
            open: shell.menuOpen
            onCloseRequested: shell.menuOpen = false
        }
    }
}

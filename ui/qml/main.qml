import QtQuick
import QtQuick.Window
import org.kde.layershell as LayerShell

// omnia-ui como escritorio: capa de fondo a pantalla completa, bajo ventanas y paneles.
Window {
    visible: true; color: "#000000"; flags: Qt.FramelessWindowHint; title: "Omnia"
    LayerShell.Window.scope: "omnia-ui"
    LayerShell.Window.layer: LayerShell.Window.LayerBackground
    LayerShell.Window.anchors: LayerShell.Window.AnchorTop | LayerShell.Window.AnchorBottom | LayerShell.Window.AnchorLeft | LayerShell.Window.AnchorRight
    LayerShell.Window.exclusionZone: -1
    LayerShell.Window.keyboardInteractivity: LayerShell.Window.KeyboardInteractivityOnDemand
    OmniaShell { anchors.fill: parent; bottomInset: 64 }
}

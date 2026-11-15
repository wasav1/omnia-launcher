import QtQuick
import QtQuick.Window
import org.kde.layershell as LayerShell

// Prueba 2: ventana en la capa de fondo, a pantalla completa, bajo ventanas y paneles.
Window {
    visible: true; color: "#000000"; flags: Qt.FramelessWindowHint; title: "Omnia spike (fondo)"
    LayerShell.Window.scope: "omnia-spike"
    LayerShell.Window.layer: Qt.application.arguments.indexOf("--top") >= 0 ? LayerShell.Window.LayerTop : (Qt.application.arguments.indexOf("--bottom") >= 0 ? LayerShell.Window.LayerBottom : LayerShell.Window.LayerBackground)
    LayerShell.Window.anchors: LayerShell.Window.AnchorTop | LayerShell.Window.AnchorBottom | LayerShell.Window.AnchorLeft | LayerShell.Window.AnchorRight
    LayerShell.Window.exclusionZone: -1
    LayerShell.Window.keyboardInteractivity: LayerShell.Window.KeyboardInteractivityOnDemand
    SpikeContent { anchors.fill: parent }
}

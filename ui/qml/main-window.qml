import QtQuick
import QtQuick.Window

// omnia-ui en una ventana normal (desarrollo y capturas): el Big Menu va incrustado.
Window {
    visible: true; visibility: Window.FullScreen; width: Screen.width; height: Screen.height; title: "Omnia (ventana)"
    OmniaShell { anchors.fill: parent; embedMenu: true }
}

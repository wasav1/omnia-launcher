import QtQuick
import QtQuick.Window

// omnia-ui en una ventana normal (desarrollo y capturas): el Big Menu va incrustado.
Window {
    visible: true; width: 1280; height: 720; title: "Omnia (ventana)"
    OmniaShell { anchors.fill: parent; embedMenu: true }
}

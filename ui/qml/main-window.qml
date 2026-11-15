import QtQuick
import QtQuick.Window

// omnia-ui en una ventana normal (desarrollo y capturas).
Window {
    visible: true; width: 1280; height: 720; title: "Omnia (ventana)"
    OmniaShell { anchors.fill: parent }
}

import QtQuick
import QtQuick.Window

// Prueba 1, segura: ventana normal de 1000x600 (comprueba QML, API y token).
Window {
    visible: true; width: 1000; height: 600; title: "Omnia spike (ventana)"
    SpikeContent { anchors.fill: parent }
}

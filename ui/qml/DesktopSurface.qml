import QtQuick

// La superficie ocupa la ventana del escritorio, no la celda movible del widget.
// Las dimensiones son lógicas: Qt ya aplica el escalado propio del monitor.
Item {
    id: surface
    required property Item viewport
    parent: viewport
    anchors.fill: parent
    z: 1
}

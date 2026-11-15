import QtQuick

// Ventana modal dentro de la estantería: telón, panel centrado, título y pie con las teclas. El contenido va dentro.
FocusScope {
    id: modal
    property string title: ""
    property string footer: ""
    property real panelWidth: Math.min(1000, width * 0.74)
    property real panelHeight: Math.min(720, height * 0.82)
    signal closeRequested
    default property alias body: holder.data
    readonly property real bodyTop: titleText.y + titleText.height + 18

    Rectangle { anchors.fill: parent; color: Qt.rgba(0.02, 0.06, 0.05, 0.82); MouseArea { anchors.fill: parent; onClicked: modal.closeRequested() } }
    Rectangle {
        id: panel
        width: modal.panelWidth; height: modal.panelHeight; anchors.centerIn: parent
        radius: 26; color: Qt.rgba(0.06, 0.14, 0.11, 0.985)
        border.width: 1; border.color: Qt.rgba(0.9, 0.85, 0.63, 0.28)
        MouseArea { anchors.fill: parent }
        Text { id: titleText; anchors { top: parent.top; left: parent.left; right: parent.right; margins: 28 }
               text: modal.title; color: "#f4efd8"; font.pixelSize: 28; font.bold: true; elide: Text.ElideRight }
        Item { id: holder; anchors { top: titleText.bottom; topMargin: 18; left: parent.left; right: parent.right; bottom: foot.top; leftMargin: 28; rightMargin: 28; bottomMargin: 10 } }
        Text { id: foot; anchors { bottom: parent.bottom; left: parent.left; right: parent.right; margins: 20 }
               horizontalAlignment: Text.AlignHCenter; text: modal.footer; color: "#8c8560"; font.pixelSize: 15 }
    }
}

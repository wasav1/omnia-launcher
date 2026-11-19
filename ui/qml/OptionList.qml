import QtQuick

// Lista vertical de opciones que se maneja con teclado, ratón y mando. items: [{text, sub, disabled, accent}].
ListView {
    id: lv
    property var items: []
    property color accentColor: "#336599"
    signal activated(int index)
    model: items
    clip: true
    spacing: 6
    keyNavigationEnabled: false
    highlightMoveDuration: 0
    boundsBehavior: Flickable.StopAtBounds

    // La posición solo la cambia el usuario (moveSelection, clic, reset). El modelo se reinicia al refrescarse la lista y ListView
    // devuelve entonces el cursor al principio: se restaura la última posición del usuario.
    property int lastIndex: 0
    function setIndex(i) { currentIndex = i; lastIndex = i }
    function reset() { setIndex(0); moveSelection(0) }
    function moveSelection(d) {
        const n = items.length
        if (n === 0) return
        let i = currentIndex
        for (let k = 0; k < n; k++) {
            i = (i + (d === 0 ? 1 : d) + n) % n
            if (d === 0 && k === 0 && !items[currentIndex].disabled) return      // d = 0: quedarse si la actual vale
            if (!items[i].disabled) { setIndex(i); return }
        }
    }
    function activate() { if (currentIndex >= 0 && currentIndex < items.length && !items[currentIndex].disabled) activated(currentIndex) }
    onCurrentIndexChanged: if (currentIndex >= 0) positionViewAtIndex(currentIndex, ListView.Contain)   // el cursor siempre a la vista
    onItemsChanged: Qt.callLater(function () {
        currentIndex = Math.max(0, Math.min(lastIndex, items.length - 1))
        if (items[currentIndex] && items[currentIndex].disabled) moveSelection(1)
    })

    delegate: Rectangle {
        id: row
        required property var modelData
        required property int index
        width: lv.width; height: modelData.sub ? 64 : 48; radius: 14
        readonly property bool cur: ListView.isCurrentItem
        color: cur ? Qt.rgba(lv.accentColor.r, lv.accentColor.g, lv.accentColor.b, 0.28) : (hov.containsMouse && !modelData.disabled ? Qt.rgba(1, 1, 1, 0.07) : "transparent")
        border.width: cur ? 2 : 0; border.color: Qt.lighter(lv.accentColor, 1.15)
        opacity: modelData.disabled ? 0.4 : 1
        Column {
            anchors { verticalCenter: parent.verticalCenter; left: parent.left; right: parent.right; leftMargin: 18; rightMargin: 18 }
            spacing: 2
            Text { width: parent.width; elide: Text.ElideRight; text: row.modelData.text; font.pixelSize: 19
                   color: row.modelData.accent ? "#7fd69f" : "#f4efd8"; font.bold: row.modelData.accent === true }
            Text { visible: !!row.modelData.sub; width: parent.width; elide: Text.ElideRight; text: row.modelData.sub || ""; color: "#a89f74"; font.pixelSize: 14 }
        }
        MouseArea { cursorShape: Qt.PointingHandCursor; id: hov; anchors.fill: parent; hoverEnabled: true
                    onClicked: { if (row.modelData.disabled) return; lv.setIndex(row.index); lv.activated(row.index) } }
    }
}

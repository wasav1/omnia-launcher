import QtQuick

/** Menú contextual del juego seleccionado (X en el mando, clic derecho, tecla M). Se maneja con ↑/↓ + A/Enter, o con el ratón. */
Item {
    id: menu
    property var items: []              // [{ key, label, icon }]
    property int index: 0
    property string title: ""
    property string subtitle: ""
    property real uiScale: 1
    property color ink: "#F0F3F7"
    property color ink2: "#B8C3D0"
    property color accent: "#336599"
    property string uiFont: "Hanken Grotesk"
    property bool open: false
    signal activated(string key)
    signal closed()
    visible: open || scrim.opacity > 0.01
    function show() { index = 0; scroll.contentY = 0; open = true }
    function close() { if (open) { open = false; closed() } }
    function pad(k) {
        if (k === "u") index = Math.max(0, index - 1)
        else if (k === "d") index = Math.min(items.length - 1, index + 1)
        else if (k === "A") activate(index)
        else if (k === "B" || k === "X") close()
    }
    function key(e) {
        if (e.key === Qt.Key_Up) pad("u")
        else if (e.key === Qt.Key_Down) pad("d")
        else if (e.key === Qt.Key_Return || e.key === Qt.Key_Enter) pad("A")
        else if (e.key === Qt.Key_Escape || e.key === Qt.Key_M || e.key === Qt.Key_Menu) close()
        else return false
        return true
    }
    function activate(i) {
        if (i < 0 || i >= items.length) return
        const k = items[i].key
        open = false
        activated(k)
    }
    onIndexChanged: {
        const row = actionRows.itemAt(index)
        if (!row) return
        if (row.y < scroll.contentY) scroll.contentY = row.y
        else if (row.y + row.height > scroll.contentY + scroll.height)
            scroll.contentY = row.y + row.height - scroll.height
    }
    Rectangle {
        id: scrim
        anchors.fill: parent
        color: "#000000"
        opacity: menu.open ? 0.55 : 0
        Behavior on opacity { NumberAnimation { duration: 160 } }
        MouseArea { anchors.fill: parent; acceptedButtons: Qt.LeftButton | Qt.RightButton; onClicked: menu.close() }
    }
    Rectangle {
        id: panel
        anchors.centerIn: parent
        width: menu.uiScale * 400
        height: Math.min(parent.height - menu.uiScale * 36, col.implicitHeight + menu.uiScale * 36)
        radius: menu.uiScale * 22
        color: "#F2101820"
        border.color: "#2effffff"
        scale: menu.open ? 1 : 0.94
        opacity: menu.open ? 1 : 0
        Behavior on scale { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }
        Behavior on opacity { NumberAnimation { duration: 160 } }
        MouseArea { anchors.fill: parent }
        Flickable {
            id: scroll
            anchors.fill: parent
            anchors.margins: menu.uiScale * 18
            clip: true
            contentWidth: width
            contentHeight: col.implicitHeight
            boundsBehavior: Flickable.StopAtBounds
            Column {
                id: col
                width: scroll.width
            spacing: menu.uiScale * 6
            Text {
                width: parent.width; text: menu.title; elide: Text.ElideRight
                color: menu.ink2; font.family: menu.uiFont; font.pixelSize: menu.uiScale * 16
                leftPadding: menu.uiScale * 8; bottomPadding: menu.uiScale * 6
            }
            Text {
                visible: menu.subtitle !== ""
                width: parent.width; text: menu.subtitle; wrapMode: Text.Wrap; textFormat: Text.PlainText
                color: menu.ink; font.family: menu.uiFont; font.pixelSize: menu.uiScale * 16
                bottomPadding: menu.uiScale * 8
            }
            Repeater {
                id: actionRows
                model: menu.items
                delegate: Rectangle {
                    id: row
                    required property var modelData
                    required property int index
                    readonly property bool on: menu.index === index
                    width: col.width; height: menu.uiScale * 52; radius: menu.uiScale * 14
                    color: on ? menu.accent : (rowMa.containsMouse ? "#1fffffff" : "transparent")
                    Row {
                        anchors { left: parent.left; leftMargin: menu.uiScale * 16; verticalCenter: parent.verticalCenter }
                        spacing: menu.uiScale * 14
                        LucideIcon { anchors.verticalCenter: parent.verticalCenter; width: menu.uiScale * 22; height: width; name: row.modelData.icon; color: menu.ink }
                        Text { anchors.verticalCenter: parent.verticalCenter; text: row.modelData.label; color: menu.ink; font.family: menu.uiFont; font.pixelSize: menu.uiScale * 20; font.weight: row.on ? Font.DemiBold : Font.Normal }
                    }
                    MouseArea {
                        id: rowMa
                        anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                        onEntered: menu.index = row.index
                        onClicked: menu.activate(row.index)
                    }
                }
            }
        }
        }
    }
}

pragma ComponentBehavior: Bound

import QtQuick
import "Theme.js" as Theme

/** Menú contextual de Desktop (clic derecho o la acción «Más» de una tarjeta): un menú de escritorio que se abre
 *  junto al puntero, con filas compactas de cristal. Misma interfaz que el menú de Big Mode (`items`, `title`,
 *  `show()`, `activated`, `closed`, `key()`), así que el gestor no cambia sus acciones.
 *  Teclado: ↑/↓, Enter, Esc. Ratón: clic en una fila; clic fuera o clic derecho cierran. */
Item {
    id: menu
    property var items: []              // [{ key, label, icon }]
    property int index: -1
    property string title: ""
    property string subtitle: ""
    property bool open: false
    property point at: Qt.point(width / 2, height / 2)
    readonly property var dangerKeys: ["uninstall", "remove", "confirmUninstall", "confirmRemove"]
    signal activated(string key)
    signal closed()
    visible: open

    // Abre en `pos` (coordenadas de este item); sin posición, en el centro.
    function show(pos) {
        index = -1
        if (pos) at = pos
        open = true
    }
    function close() { if (open) { open = false; closed() } }
    function activate(i) {
        if (i < 0 || i >= items.length) return
        const k = items[i].key
        open = false
        activated(k)
    }
    function pad(k) {
        if (k === "u") index = index <= 0 ? items.length - 1 : index - 1
        else if (k === "d") index = index >= items.length - 1 ? 0 : index + 1
        else if (k === "A") activate(Math.max(0, index))
        else if (k === "B" || k === "X") close()
    }
    function key(e) {
        if (e.key === Qt.Key_Up) pad("u")
        else if (e.key === Qt.Key_Down) pad("d")
        else if (e.key === Qt.Key_Return || e.key === Qt.Key_Enter || e.key === Qt.Key_Space) pad("A")
        else if (e.key === Qt.Key_Escape || e.key === Qt.Key_Menu) close()
        else return false
        return true
    }

    MouseArea {         // clic fuera (izquierdo o derecho) cierra
        anchors.fill: parent
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        onClicked: menu.close()
    }

    Rectangle {
        id: panel
        readonly property real margin: 8
        width: 268
        height: Math.min(menu.height - 2 * margin, col.implicitHeight + 12)
        // Se abre hacia abajo y a la derecha del puntero; si no cabe, hacia el otro lado.
        x: Math.max(margin, menu.at.x + width + margin > menu.width ? menu.at.x - width : menu.at.x)
        y: Math.max(margin, menu.at.y + height + margin > menu.height ? menu.height - height - margin : menu.at.y)
        radius: Theme.radius.md
        color: "#F70E1622"
        border.color: Theme.color.glassBorderStrong
        opacity: menu.open ? 1 : 0
        scale: menu.open ? 1 : 0.96
        transformOrigin: Item.TopLeft
        Behavior on opacity { NumberAnimation { duration: 110 } }
        Behavior on scale { NumberAnimation { duration: 110; easing.type: Easing.OutCubic } }
        Rectangle { anchors { left: parent.left; right: parent.right; top: parent.top; leftMargin: parent.radius; rightMargin: parent.radius } height: 1; color: Theme.color.glassHighlight }
        MouseArea { anchors.fill: parent; acceptedButtons: Qt.LeftButton | Qt.RightButton }

        Flickable {
            id: scroll
            anchors.fill: parent
            anchors.margins: 6
            clip: true
            contentWidth: width
            contentHeight: col.implicitHeight
            boundsBehavior: Flickable.StopAtBounds
            Column {
                id: col
                width: scroll.width
                spacing: 1
                Text {
                    visible: menu.title !== ""
                    width: parent.width; text: menu.title; elide: Text.ElideRight
                    color: Theme.color.muted; font.family: Theme.font.family; font.pixelSize: Theme.font.size.small; font.weight: Font.DemiBold
                    leftPadding: 10; rightPadding: 10; topPadding: 6; bottomPadding: 6
                }
                Text {
                    visible: menu.subtitle !== ""
                    width: parent.width; text: menu.subtitle; wrapMode: Text.Wrap; textFormat: Text.PlainText
                    color: Theme.color.ink; font.family: Theme.font.family; font.pixelSize: Theme.font.size.small + 1
                    leftPadding: 10; rightPadding: 10; bottomPadding: 8
                }
                Rectangle { visible: menu.title !== ""; width: parent.width; height: 1; color: Theme.color.glassBorder }
                Item { visible: menu.title !== ""; width: 1; height: 4 }
                Repeater {
                    model: menu.items
                    delegate: Rectangle {
                        id: row
                        required property var modelData
                        required property int index
                        readonly property bool on: menu.index === index
                        readonly property bool danger: menu.dangerKeys.indexOf(modelData.key) >= 0
                        width: col.width; height: 34; radius: Theme.radius.sm - 2
                        color: on ? (danger ? "#33E55B5B" : Theme.color.accentSoft) : "transparent"
                        Row {
                            anchors { left: parent.left; leftMargin: 10; verticalCenter: parent.verticalCenter }
                            spacing: 10
                            LucideIcon { anchors.verticalCenter: parent.verticalCenter; width: 16; height: 16; name: row.modelData.icon || ""
                                color: row.danger ? Theme.color.danger : (row.on ? Theme.color.accentLight : Theme.color.soft) }
                            Text { anchors.verticalCenter: parent.verticalCenter; text: row.modelData.label
                                color: row.danger ? Theme.color.danger : Theme.color.ink; font.family: Theme.font.family; font.pixelSize: Theme.font.size.body }
                        }
                        MouseArea {
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

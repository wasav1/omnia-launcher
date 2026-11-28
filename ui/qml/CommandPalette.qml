import QtQuick
import QtQuick.Controls
import "Theme.js" as Theme

// Paleta de comandos de Desktop (Ctrl K). Busca juegos para jugarlos o abrir su
// ficha y ofrece acciones de navegación. No guarda estado propio: todo lo que
// hace pasa por las funciones del gestor (`manager`).
Item {
    id: cmd

    property var manager
    property var games: []
    property bool open: false
    property int current: 0
    property alias text: field.text
    readonly property string query: field.text.trim()

    function show() { field.text = ""; current = 0; open = true; field.forceActiveFocus() }
    function hide() { open = false }

    function normalize(text) {
        return String(text || "").toLowerCase().normalize("NFD").replace(/[̀-ͯ]/g, "")
    }

    readonly property var actions: [
        { kind: qsTr("Ir a"), label: qsTr("Inicio"), run: () => manager.selectPage("home") },
        { kind: qsTr("Ir a"), label: qsTr("Biblioteca"), run: () => manager.selectPage("library") },
        { kind: qsTr("Ir a"), label: qsTr("Catálogo"), run: () => manager.selectPage("catalog") },
        { kind: qsTr("Ir a"), label: qsTr("Descargas"), run: () => manager.selectPage("installs") },
        { kind: qsTr("Ir a"), label: qsTr("Estadísticas"), run: () => manager.selectPage("stats") },
        { kind: qsTr("Ir a"), label: qsTr("Ajustes"), run: () => manager.selectPage("settings") },
        { kind: qsTr("Acción"), label: qsTr("Abrir Big Mode"), run: () => manager.openBigMode() },
        { kind: qsTr("Acción"), label: qsTr("Agregar juego…"), run: () => manager.libraryAction("add") }
    ]

    readonly property var results: {
        const q = normalize(query)
        const out = []
        const matched = (games || []).filter(g => !q || normalize(g.name).includes(q)).slice(0, q ? 6 : 4)
        for (const g of matched) {
            out.push({ kind: qsTr("Jugar"), label: g.name, hint: g.source || "", run: () => manager.launch(g) })
            if (q) out.push({ kind: qsTr("Ficha"), label: g.name, hint: "", run: () => manager.openGameInLibrary(g) })
        }
        for (const a of actions)
            if (!q || normalize(a.label).includes(q) || normalize(a.kind).includes(q)) out.push(a)
        return out
    }
    onResultsChanged: current = Math.min(current, Math.max(0, results.length - 1))

    function runCurrent() {
        const item = results[current]
        if (!item) return
        hide()
        item.run()
    }

    anchors.fill: parent
    visible: open
    z: 50

    Rectangle {
        anchors.fill: parent
        color: "#99040710"
        MouseArea { anchors.fill: parent; onClicked: cmd.hide() }
    }

    GlassPanel {
        id: box
        width: 640
        height: Math.min(paletteHeader.height + list.contentHeight + 24, 520)
        anchors { horizontalCenter: parent.horizontalCenter; top: parent.top; topMargin: 110 }
        strong: true
        glass: false
        radius: Theme.radius.lg

        Item {
            id: paletteHeader
            width: parent.width; height: 58
            LucideIcon { x: 18; anchors.verticalCenter: parent.verticalCenter; width: 18; height: 18; name: "search"; color: Theme.color.muted }
            TextField {
                id: field
                anchors { left: parent.left; leftMargin: 46; right: escHint.left; rightMargin: 10; verticalCenter: parent.verticalCenter }
                placeholderText: qsTr("Jugar, abrir, ir a…")
                placeholderTextColor: Theme.color.muted
                color: Theme.color.ink
                font.family: Theme.font.family
                font.pixelSize: 16
                background: null
                Keys.onDownPressed: cmd.current = Math.min(cmd.current + 1, cmd.results.length - 1)
                Keys.onUpPressed: cmd.current = Math.max(cmd.current - 1, 0)
                Keys.onReturnPressed: cmd.runCurrent()
                Keys.onEnterPressed: cmd.runCurrent()
                Keys.onEscapePressed: cmd.hide()
            }
            Rectangle {
                id: escHint
                anchors { right: parent.right; rightMargin: 16; verticalCenter: parent.verticalCenter }
                width: 36; height: 22; radius: 6; color: "transparent"; border.color: Theme.color.glassBorderStrong
                Text { anchors.centerIn: parent; text: "Esc"; color: Theme.color.muted; font.family: Theme.font.family; font.pixelSize: 11 }
            }
            Rectangle { anchors { left: parent.left; right: parent.right; bottom: parent.bottom } height: 1; color: Theme.color.glassBorder }
        }

        ListView {
            id: list
            anchors { left: parent.left; right: parent.right; top: paletteHeader.bottom; bottom: parent.bottom; margins: 8 }
            clip: true
            model: cmd.results
            currentIndex: cmd.current
            boundsBehavior: Flickable.StopAtBounds
            delegate: Rectangle {
                id: row
                required property var modelData
                required property int index
                width: list.width; height: 42; radius: Theme.radius.sm
                color: index === cmd.current ? Theme.color.accentSoft : (rowMouse.containsMouse ? Theme.color.glassFill : "transparent")
                Text { x: 12; width: 64; anchors.verticalCenter: parent.verticalCenter; text: row.modelData.kind; color: Theme.color.accentLight; font.family: Theme.font.family; font.pixelSize: 12; font.weight: Font.DemiBold; elide: Text.ElideRight }
                Text { anchors { left: parent.left; leftMargin: 84; right: hint.left; rightMargin: 10; verticalCenter: parent.verticalCenter } text: row.modelData.label; color: Theme.color.ink; font.family: Theme.font.family; font.pixelSize: 15; elide: Text.ElideRight }
                Text { id: hint; anchors { right: parent.right; rightMargin: 12; verticalCenter: parent.verticalCenter } text: row.modelData.hint || ""; color: Theme.color.muted; font.family: Theme.font.family; font.pixelSize: 12 }
                MouseArea { id: rowMouse; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                    onEntered: cmd.current = row.index
                    onClicked: { cmd.current = row.index; cmd.runCurrent() } }
            }
        }
    }
}

pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls
import "Theme.js" as Theme

/** «Ver todos» de la Biblioteca (rediseño D, fase 2b): los juegos instalados en carátulas,
 *  agrupados por Origen, Consola o Estado. Ocupa el lugar del Catálogo y usa la misma
 *  cuadrícula (Theme.posterLayout). Respeta el buscador y la colección de Instalados. */
GlassPanel {
    id: all
    required property var manager
    property var games: []                 // juegos ya filtrados por Instalados
    property string groupBy: "origin"      // origin | console | state
    property string selectedId: ""
    signal gameChosen(var game)
    signal closeRequested()

    readonly property real pad: 18
    readonly property var layout: Theme.posterLayout(width - 2 * pad)

    function originOf(g) {
        const src = String(g.src || "")
        const sub = String(g.sub || "")
        if (src === "Steam") return "Steam"
        for (const store of ["Epic", "GOG", "Amazon"]) if (sub.indexOf(store) >= 0) return store
        if (src === "Omnia") return qsTr("Omnia · ports")
        if (src === "Heroic") return "Heroic"
        return src || qsTr("Otros")
    }
    function consoleOf(g) {
        const names = { pc: "PC", n64: "Nintendo 64", sw1: "Nintendo Switch", sw2: "Nintendo Switch 2", ps1: "PlayStation", ps2: "PlayStation 2",
                        ps3: "PlayStation 3", ps4: "PlayStation 4", ps5: "PlayStation 5", psp: "PSP", nes: "NES", snes: "Super Nintendo",
                        gb: "Game Boy", gbc: "Game Boy Color", gba: "Game Boy Advance", nds: "Nintendo DS", "3ds": "Nintendo 3DS",
                        gcwii: "GameCube / Wii", wiiu: "Wii U", genesis: "Mega Drive", dreamcast: "Dreamcast", saturn: "Saturn" }
        const key = String(g.platform || "").toLowerCase()
        return names[key] || g.platform || "PC"
    }
    // Estados en un orden fijo: lo que pide atención primero.
    readonly property var stateOrder: [qsTr("Jugando ahora"), qsTr("Con actualización"), qsTr("Favoritos"), qsTr("Jugados"), qsTr("Sin jugar"), qsTr("Ocultos")]
    function stateOf(g) {
        if (g.hidden) return stateOrder[5]
        if (g.running) return stateOrder[0]
        if (g.updateAvailable || g.portAvailable) return stateOrder[1]
        if (g.fav) return stateOrder[2]
        if (Number(g.lastPlayed || (g.played || {}).last || 0) > 0) return stateOrder[3]
        return stateOrder[4]
    }
    function keyOf(g) { return groupBy === "console" ? consoleOf(g) : groupBy === "state" ? stateOf(g) : originOf(g) }

    readonly property var groups: {
        const map = new Map()
        for (const g of games || []) {
            const k = keyOf(g)
            if (!map.has(k)) map.set(k, [])
            map.get(k).push(g)
        }
        const out = Array.from(map, ([label, list]) => ({ label: label, games: list.slice().sort((a, b) => String(a.name).localeCompare(String(b.name))) }))
        if (groupBy === "state") out.sort((a, b) => stateOrder.indexOf(a.label) - stateOrder.indexOf(b.label))
        else out.sort((a, b) => b.games.length - a.games.length || a.label.localeCompare(b.label))
        return out
    }

    // ---------------- encabezado
    Item {
        id: header
        anchors { left: parent.left; right: parent.right; top: parent.top; margins: all.pad }
        height: Theme.size.control
        Rectangle {
            id: back
            anchors { left: parent.left; verticalCenter: parent.verticalCenter }
            width: 32; height: 32; radius: Theme.radius.sm
            color: backMa.containsMouse ? Theme.color.glassFillStrong : Theme.color.inset; border.color: Theme.color.glassBorder
            LucideIcon { anchors.centerIn: parent; width: 16; height: 16; name: "arrow-left"; color: Theme.color.ink }
            ToolTip.visible: backMa.containsMouse; ToolTip.text: qsTr("Volver al Catálogo"); ToolTip.delay: 400
            MouseArea { id: backMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: all.closeRequested() }
        }
        Row {
            anchors { left: back.right; leftMargin: 12; verticalCenter: parent.verticalCenter }
            spacing: 10
            Text { anchors.verticalCenter: parent.verticalCenter; text: qsTr("Todos los instalados"); color: Theme.color.ink; font.family: Theme.font.family; font.pixelSize: Theme.font.size.title + 3; font.weight: Font.Bold }
            Text { anchors.verticalCenter: parent.verticalCenter; text: all.games.length === 1 ? qsTr("1 juego") : qsTr("%1 juegos").arg(all.games.length); color: Theme.color.muted; font.family: Theme.font.family; font.pixelSize: Theme.font.size.small }
        }
    }
    Row {
        id: grouping
        anchors { left: parent.left; top: header.bottom; leftMargin: all.pad; topMargin: 12 }
        spacing: 6
        Text { anchors.verticalCenter: parent.verticalCenter; text: qsTr("Agrupar por"); color: Theme.color.muted; font.family: Theme.font.family; font.pixelSize: Theme.font.size.small; rightPadding: 4 }
        Repeater {
            model: [{ k: "origin", l: qsTr("Origen") }, { k: "console", l: qsTr("Consola") }, { k: "state", l: qsTr("Estado") }]
            delegate: Rectangle {
                id: chip
                required property var modelData
                readonly property bool on: all.groupBy === modelData.k
                height: Theme.size.chip + 2; width: chipText.implicitWidth + 24; radius: height / 2
                color: on ? Theme.color.accentSoft : (chipMa.containsMouse ? Theme.color.glassFill : "transparent")
                border.color: on ? Theme.color.accent : Theme.color.glassBorder
                Text { id: chipText; anchors.centerIn: parent; text: chip.modelData.l; color: chip.on ? Theme.color.accentLight : Theme.color.soft; font.family: Theme.font.family; font.pixelSize: Theme.font.size.small; font.weight: Font.DemiBold }
                MouseArea { id: chipMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: { all.groupBy = chip.modelData.k; flick.contentY = 0 } }
            }
        }
    }

    // ---------------- grupos
    Flickable {
        id: flick
        anchors { left: parent.left; right: parent.right; top: grouping.bottom; bottom: parent.bottom; topMargin: 8; bottomMargin: 2 }
        clip: true
        contentWidth: width
        contentHeight: body.height + 24
        boundsBehavior: Flickable.StopAtBounds
        ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }
        Column {
            id: body
            readonly property real gridWidth: all.layout.columns * all.layout.width + (all.layout.columns - 1) * Theme.size.posterGap
            x: Math.max(all.pad, (flick.width - gridWidth) / 2)
            width: gridWidth
            spacing: 10
            Repeater {
                model: all.groups
                delegate: Column {
                    id: group
                    required property var modelData
                    width: body.width
                    spacing: 10
                    Row {
                        topPadding: 10
                        spacing: 8
                        Text { text: group.modelData.label.toUpperCase(); color: Theme.color.soft; font.family: Theme.font.family; font.pixelSize: Theme.font.size.small; font.weight: Font.DemiBold; font.letterSpacing: 0.9 }
                        Text { text: String(group.modelData.games.length); color: Theme.color.muted; font.family: Theme.font.numeric; font.pixelSize: Theme.font.size.small; font.weight: Font.DemiBold }
                    }
                    Grid {
                        columns: all.layout.columns
                        columnSpacing: Theme.size.posterGap
                        rowSpacing: Theme.size.posterGap
                        Repeater {
                            model: group.modelData.games
                            delegate: Item {
                                id: cell
                                required property var modelData
                                readonly property string originLabel: all.originOf(modelData)
                                // Solo las tiendas y Omnia tienen logo; Lutris, ROMs u otros orígenes van sin él.
                                readonly property string originLogo: ["Steam", "Epic", "GOG", "Amazon", qsTr("Omnia · ports")].indexOf(originLabel) >= 0
                                                                     ? (all.manager.sourceForGame(modelData)?.logo || "") : ""
                                width: all.layout.width; height: all.layout.height
                                z: poster.hovered ? 1 : 0
                                ManagerPosterCard {
                                    id: poster
                                    anchors.fill: parent
                                    viewport: flick
                                    title: cell.modelData.name || ""
                                    artwork: cell.modelData.portada || cell.modelData.fondo || ""
                                    store: cell.originLabel
                                    sourceLogo: cell.originLogo
                                    platform: all.consoleOf(cell.modelData)
                                    installed: true
                                    selected: cell.modelData.id === all.selectedId
                                    highlightColor: Theme.color.accent
                                    onActivated: all.gameChosen(cell.modelData)
                                    onDoubleActivated: all.manager.launch(cell.modelData)
                                    onContextRequested: all.manager.openGameMenu(cell.modelData)
                                }
                            }
                        }
                    }
                }
            }
            Text {
                visible: all.games.length === 0
                width: parent.width
                text: qsTr("Ningún juego instalado coincide con el filtro.")
                color: Theme.color.muted; font.family: Theme.font.family; font.pixelSize: Theme.font.size.body; wrapMode: Text.WordWrap
            }
        }
    }
}

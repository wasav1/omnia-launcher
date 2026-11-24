pragma ComponentBehavior: Bound

import QtQuick

/** «Ver todos»: la biblioteca completa. Carril de consolas (solo logos) a la izquierda, barra de herramientas (cuadrícula/lista,
 *  tamaño, orden, agrupar por consola), cuadrícula con cabeceras por consola donde el juego seleccionado se expande en su fila,
 *  y un panel «Resumen» a la derecha. Navegación: flechas/D-pad, Enter/A jugar, I/X detalles, Esc/B volver. */
Item {
    id: all
    property var host: null                 // OmniaLibrary (colores, norm, platformLabel…)
    property var games: []
    property string railKey: "all"
    property string viewMode: "grid"        // grid | list
    property int sizeLevel: 0               // 0 S, 1 M, 2 L
    property string sortKey: "smart"        // smart (favoritos > recurrentes > resto) | name | name-desc | platform
    property bool grouped: true
    property int sel: 0
    property string selId: ""
    signal closeRequested()
    signal playRequested(var game)
    signal detailsRequested(var game)
    signal selectionChanged2(var game)
    signal contextRequested(var game)
    signal topReached()

    readonly property real s: host ? host.s : 1
    readonly property color ink: host ? host.ink : "#F0F3F7"
    readonly property color ink2: host ? host.ink2 : "#B8C3D0"
    readonly property color surface: host ? host.surface : "#151D27"
    readonly property color base: host ? host.base : "#0B0F14"
    readonly property color accent: host ? host.accent : "#336599"
    readonly property color ring: host ? host.ring : "#5b9be0"
    readonly property string uiFont: host ? host.uiFont : "Hanken Grotesk"
    readonly property var sizeNames: ["S", "M", "L"]
    readonly property int cols: [8, 6, 5][sizeLevel]
    readonly property real gap: s * 14
    readonly property real railW: s * 84
    readonly property real sumW: s * 320
    readonly property real gridW: width - railW - s * 40

    // ---- datos
    function platKey(g) { return host.norm(g.platform) }
    readonly property var rail: {
        const out = [{ key: "all", label: qsTr("Todos") }]
        if (!host) return out
        const o = host.filterOptions
        for (let i = 1; i < o.length; i++) out.push(o[i])
        return out
    }
    function order(key) { for (let i = 0; i < rail.length; i++) if (rail[i].key === key) return i; return 99 }
    function labelOf(key) { for (let i = 0; i < rail.length; i++) if (rail[i].key === key) return rail[i].label; return key }
    property var items: []
    property var rows: []
    function rebuild() {
        if (!host) return
        const q = host.norm(host.searchText).trim(), list = []
        for (let i = 0; i < games.length; i++) {
            const g = games[i]
            if (g.hidden) continue
            if (railKey === "fav" ? !g.fav : (railKey !== "all" && platKey(g) !== railKey)) continue
            if (q && host.norm(g.name + " " + (g.sub || "")).indexOf(q) < 0) continue
            list.push(g)
        }
        const byName = function(a, b) { return host.norm(a.name).localeCompare(host.norm(b.name)) }
        const tier = function(g) { return g.fav ? 0 : (host.lastPlayedOf(g) > 0 ? 1 : 2) }
        list.sort(function(a, b) {
            if (grouped || sortKey === "platform") { const d = order(platKey(a)) - order(platKey(b)); if (d) return d }
            if (sortKey === "smart") {
                const t = tier(a) - tier(b); if (t) return t
                if (tier(a) === 1) { const l = host.lastPlayedOf(b) - host.lastPlayedOf(a); if (l) return l }
                return byName(a, b)
            }
            const n = byName(a, b)
            return sortKey === "name-desc" ? -n : n
        })
        items = list
        const at = list.findIndex(function(g) { return g.id === selId })
        sel = at >= 0 ? at : 0
        selId = list.length ? list[sel].id : ""
        const r = []
        const per = viewMode === "list" ? 1 : cols
        let i = 0
        while (i < list.length) {
            const k = platKey(list[i])
            let j = i
            if (grouped) { while (j < list.length && platKey(list[j]) === k) j++ } else j = list.length
            if (grouped) r.push({ k: "h", key: k, label: labelOf(k), count: j - i })
            for (let a = i; a < j; a += per) {
                const ids = []
                for (let b = a; b < Math.min(j, a + per); b++) ids.push(b)
                r.push({ k: "c", ids: ids })
            }
            i = j
        }
        rows = r
    }
    onGamesChanged: rebuild()
    onRailKeyChanged: { selId = ""; rebuild() }
    onViewModeChanged: rebuild()
    onSortKeyChanged: rebuild()
    onGroupedChanged: rebuild()
    onColsChanged: rebuild()
    Component.onCompleted: rebuild()
    Connections { target: all.host; function onSearchTextChanged() { all.rebuild() } }

    readonly property var cur: items.length && sel < items.length ? items[sel] : null
    function rowOf(i) {
        for (let r = 0; r < rows.length; r++) if (rows[r].k === "c" && rows[r].ids.indexOf(i) >= 0) return r
        return -1
    }
    function select(i) {
        if (!items.length) return
        sel = Math.max(0, Math.min(items.length - 1, i))
        selId = items[sel].id
        const r = rowOf(sel)
        if (r >= 0) list.positionViewAtIndex(r, ListView.Contain)
        selectionChanged2(items[sel])
    }
    function vertical(d) {
        if (viewMode === "list") { if (d < 0 && sel === 0) topReached(); else select(sel + d); return }
        let r = rowOf(sel)
        if (r < 0) return
        const col = rows[r].ids.indexOf(sel)
        r += d
        while (r >= 0 && r < rows.length && rows[r].k !== "c") r += d
        if (r < 0 || r >= rows.length) { if (d < 0) topReached(); return }
        const ids = rows[r].ids
        select(ids[Math.min(col, ids.length - 1)])
    }
    function stepRail(d) {
        let i = 0
        for (let k = 0; k < rail.length; k++) if (rail[k].key === railKey) i = k
        railKey = rail[(i + d + rail.length) % rail.length].key
    }
    function cycleSort() { sortKey = sortKey === "smart" ? "name" : sortKey === "name" ? "name-desc" : sortKey === "name-desc" ? "platform" : "smart" }
    function sortLabel() { return sortKey === "smart" ? qsTr("Favoritos y recientes") : sortKey === "name" ? qsTr("Nombre A–Z") : sortKey === "name-desc" ? qsTr("Nombre Z–A") : qsTr("Consola") }
    function setSize(d) { sizeLevel = Math.max(0, Math.min(2, sizeLevel + d)) }
    function pad(k) {
        if (k === "l") select(sel - 1)
        else if (k === "r") select(sel + 1)
        else if (k === "u") vertical(-1)
        else if (k === "d") vertical(1)
        else if (k === "A") { if (cur) playRequested(cur) }
        else if (k === "X") { if (cur) contextRequested(cur) }
        else if (k === "B") closeRequested()
        else if (k === "LB") stepRail(-1)
        else if (k === "RB") stepRail(1)
        else if (k === "LT") setSize(-1)
        else if (k === "RT") setSize(1)
        else if (k === "SELECT") cycleSort()
        else if (k === "START") grouped = !grouped
        else if (k === "Y") viewMode = viewMode === "grid" ? "list" : "grid"
    }
    function key(e) {
        if (host) host.keySound(e)
        if (e.key === Qt.Key_Left) pad("l")
        else if (e.key === Qt.Key_Right) pad("r")
        else if (e.key === Qt.Key_Up) pad("u")
        else if (e.key === Qt.Key_Down) pad("d")
        else if (e.key === Qt.Key_Return || e.key === Qt.Key_Enter) pad("A")
        else if (e.key === Qt.Key_Space || e.key === Qt.Key_I) { if (cur) detailsRequested(cur) }
        else if (e.key === Qt.Key_M || e.key === Qt.Key_Menu) pad("X")
        else if (e.key === Qt.Key_Escape) pad("B")
        else if (e.key === Qt.Key_Tab) stepRail(e.modifiers & Qt.ShiftModifier ? -1 : 1)
        else if (e.key === Qt.Key_Backtab) stepRail(-1)
        else if (e.key === Qt.Key_Plus || e.key === Qt.Key_Equal) setSize(1)
        else if (e.key === Qt.Key_Minus) setSize(-1)
        else if (e.key === Qt.Key_O) cycleSort()
        else if (e.key === Qt.Key_G) grouped = !grouped
        else if (e.key === Qt.Key_L) pad("Y")
        else if (e.key === Qt.Key_Home) select(0)
        else if (e.key === Qt.Key_End) select(items.length - 1)
        else if (e.key === Qt.Key_PageDown) select(sel + cols * 2)
        else if (e.key === Qt.Key_PageUp) select(sel - cols * 2)
        else return false
        return true
    }

    // ---- carril de consolas (solo iconos)
    Column {
        id: railCol
        x: 0; y: all.s * 8
        width: all.railW
        spacing: all.s * 10
        Repeater {
            model: all.rail
            delegate: Rectangle {
                id: rb
                required property var modelData
                readonly property bool on: all.railKey === modelData.key
                width: all.railW - all.s * 16; height: width; x: all.s * 8
                radius: all.s * 16
                color: on ? all.accent : (rbMouse.containsMouse ? "#26ffffff" : "#14ffffff")
                border.color: on ? all.ring : "#22ffffff"; border.width: on ? 2 : 1
                Accessible.role: Accessible.Button
                Accessible.name: modelData.label
                PlatIcon {
                    anchors.centerIn: parent
                    visible: rb.modelData.key !== "all" && rb.modelData.key !== "fav"
                    key: rb.modelData.key; size: all.s * 30
                    color: rb.on ? all.ink : all.ink2
                }
                LucideIcon {
                    anchors.centerIn: parent
                    visible: rb.modelData.key === "all" || rb.modelData.key === "fav"
                    width: all.s * 28; height: width
                    name: rb.modelData.key === "fav" ? "star" : "layout-grid"
                    color: rb.on ? all.ink : all.ink2
                }
                MouseArea { id: rbMouse; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: all.railKey = rb.modelData.key }
            }
        }
    }

    // ---- barra de herramientas
    component ToolBtn: Rectangle {
        id: tb
        property string label
        property bool on: false
        signal clicked()
        height: all.s * 40; width: tt.implicitWidth + all.s * 30; radius: height / 2
        color: on ? all.accent : (tm.containsMouse ? "#26ffffff" : "#14ffffff")
        border.color: on ? all.ring : "#22ffffff"
        Text { id: tt; anchors.centerIn: parent; text: tb.label; color: all.ink; font.family: all.uiFont; font.pixelSize: all.s * 17; font.weight: Font.DemiBold }
        MouseArea { id: tm; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: tb.clicked() }
    }
    Row {
        id: toolbar
        x: all.railW + all.s * 20; y: all.s * 6
        spacing: all.s * 10
        Text { anchors.verticalCenter: parent.verticalCenter; text: all.labelOf(all.railKey); color: all.ink; font.family: all.uiFont; font.pixelSize: all.s * 28; font.weight: Font.Bold; rightPadding: all.s * 10 }
        ToolBtn { label: qsTr("Cuadrícula"); on: all.viewMode === "grid"; onClicked: all.viewMode = "grid" }
        ToolBtn { label: qsTr("Lista"); on: all.viewMode === "list"; onClicked: all.viewMode = "list" }
        Item { width: all.s * 8; height: 1 }
        Repeater {
            model: 3
            delegate: ToolBtn { required property int index; label: all.sizeNames[index]; on: all.sizeLevel === index; onClicked: all.sizeLevel = index; visible: all.viewMode === "grid" }
        }
        Item { width: all.s * 8; height: 1 }
        ToolBtn { label: qsTr("Ordenar: ") + all.sortLabel(); onClicked: all.cycleSort() }
        ToolBtn { label: qsTr("Agrupar por consola"); on: all.grouped; onClicked: all.grouped = !all.grouped }
    }

    // ---- contenido
    ListView {
        id: list
        x: all.railW + all.s * 20
        y: all.s * 64
        width: all.gridW
        height: all.height - y
        clip: true
        model: all.rows
        spacing: 0
        boundsBehavior: Flickable.StopAtBounds
        cacheBuffer: all.s * 600
        delegate: Item {
            id: rowItem
            required property var modelData
            required property int index
            readonly property bool header: modelData.k === "h"
            readonly property real unit: (all.gridW - (all.cols - 1) * all.gap) / all.cols
            readonly property real cardH: all.viewMode === "list" ? all.s * 84 : Math.round(unit * 1.38)
            width: list.width
            height: header ? all.s * 60 : cardH + (all.viewMode === "list" ? all.s * 6 : all.gap)

            Row {
                visible: rowItem.header
                x: all.s * 4; y: all.s * 14
                spacing: all.s * 12
                PlatIcon { anchors.verticalCenter: parent.verticalCenter; key: rowItem.modelData.key || ""; size: all.s * 26; color: all.ink2 }
                Text { anchors.verticalCenter: parent.verticalCenter; text: rowItem.modelData.label || ""; color: all.ink; font.family: all.uiFont; font.pixelSize: all.s * 24; font.weight: Font.Bold }
                Text { anchors.verticalCenter: parent.verticalCenter; text: rowItem.modelData.count || ""; color: all.ink2; font.family: all.uiFont; font.pixelSize: all.s * 18 }
            }

            // pesos de cada tarjeta de la fila: la seleccionada pesa más (se expande en la fila)
            readonly property var ids: header ? [] : modelData.ids
            readonly property bool hasSel: ids.indexOf(all.sel) >= 0
            readonly property real selWeight: 2.3
            readonly property int m: ids.length
            readonly property real unitRow: {
                if (!hasSel || all.viewMode === "list") return unit
                const need = (m - 1 + selWeight) * unit + (m - 1) * all.gap
                return need <= width ? unit : (width - (m - 1) * all.gap) / (m - 1 + selWeight)
            }
            function wOf(id) { return (id === all.sel && all.viewMode !== "list" ? selWeight : 1) * unitRow + (id === all.sel && all.viewMode !== "list" ? 0 : 0) }
            function xOf(j) {
                let x = 0
                for (let a = 0; a < j; a++) x += wOf(ids[a]) + all.gap
                return x
            }
            Repeater {
                model: rowItem.header ? 0 : rowItem.ids.length
                delegate: Loader {
                    id: cell
                    required property int index
                    readonly property int gi: rowItem.ids[index]
                    readonly property var game: all.items[gi]
                    readonly property bool sel: gi === all.sel
                    x: all.viewMode === "list" ? 0 : rowItem.xOf(index)
                    width: all.viewMode === "list" ? rowItem.width : rowItem.wOf(gi)
                    height: rowItem.cardH
                    Behavior on x { enabled: all.viewMode !== "list"; NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }
                    Behavior on width { enabled: all.viewMode !== "list"; NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }
                    active: cell.game !== undefined
                    sourceComponent: all.viewMode === "list" ? listCell : gridCell
                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        acceptedButtons: Qt.LeftButton | Qt.RightButton
                        onClicked: function(m) {
                            if (m.button === Qt.RightButton) { all.select(cell.gi); all.contextRequested(cell.game) }
                            else if (cell.sel) all.detailsRequested(cell.game)
                            else all.select(cell.gi)
                        }
                        onDoubleClicked: { all.select(cell.gi); all.playRequested(cell.game) }
                    }
                }
            }
        }
    }

    Component {
        id: gridCell
        Item {
            readonly property var game: parent.game
            readonly property bool sel: parent.sel
            readonly property real r: all.s * 16
            readonly property real coverW: sel ? Math.min(width, height * 0.72) : width
            Rectangle {
                anchors.fill: parent; radius: parent.r
                color: sel ? all.surface : "transparent"
                border.color: sel ? all.ring : "transparent"; border.width: sel ? Math.max(2, all.s * 3) : 0
            }
            Item {
                x: 0; y: 0; width: parent.coverW; height: parent.height
                Rectangle {
                    anchors.fill: parent; radius: parent.parent.r
                    color: "#16ffffff"          // sin arte: translúcida
                    visible: !cv.ready
                    Text { anchors.centerIn: parent; width: parent.width - all.s * 16; horizontalAlignment: Text.AlignHCenter; text: game.name; color: all.ink
                        font.family: all.uiFont; font.pixelSize: all.s * 16; font.weight: Font.DemiBold; wrapMode: Text.WordWrap; visible: !cv.ready }
                }
                FadedImage { id: cv; anchors.fill: parent; source: game.portada || ""; cornerRadius: parent.parent.r }
                Rectangle { anchors.fill: parent; radius: parent.parent.r; color: "#000"; opacity: sel ? 0 : 0.12 }
            }
            Column {
                visible: sel && width > all.s * 60
                x: parent.coverW + all.s * 18; y: all.s * 18
                width: parent.width - x - all.s * 16
                spacing: all.s * 8
                Row {
                    spacing: all.s * 8
                    PlatIcon { anchors.verticalCenter: parent.verticalCenter; key: all.host.norm(game.platform); size: all.s * 20; color: all.ink2 }
                    Text { anchors.verticalCenter: parent.verticalCenter; text: all.host.platformLabel(game); color: all.ink2; font.family: all.uiFont; font.pixelSize: all.s * 16 }
                }
                Text { width: parent.width; text: game.name; color: all.ink; font.family: all.uiFont; font.pixelSize: all.s * 24; font.weight: Font.Bold; wrapMode: Text.WordWrap; maximumLineCount: 3; elide: Text.ElideRight }
                Text { width: parent.width; text: game.description || ""; color: all.ink2; font.family: all.uiFont; font.pixelSize: all.s * 15; wrapMode: Text.WordWrap; maximumLineCount: 4; elide: Text.ElideRight }
            }
            Rectangle {
                visible: sel && width > all.s * 60
                x: parent.coverW + all.s * 18; y: parent.height - height - all.s * 18
                width: Math.min(all.s * 190, parent.width - x - all.s * 16); height: all.s * 42; radius: height / 2
                color: all.accent
                Text { anchors.centerIn: parent; text: game.portAvailable ? qsTr("Instalar port") : qsTr("Jugar"); color: all.ink; font.family: all.uiFont; font.pixelSize: all.s * 18; font.weight: Font.DemiBold }
                MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: all.playRequested(game) }
            }
        }
    }

    Component {
        id: listCell
        Rectangle {
            id: lrow
            readonly property var game: parent.game
            readonly property bool sel: parent.sel
            radius: all.s * 12
            color: sel ? all.surface : "#12ffffff"
            border.color: sel ? all.ring : "transparent"; border.width: sel ? 2 : 0
            clip: true
            // hero del juego a la derecha (70 % de la casilla), fundido hacia la izquierda
            FadedImage {
                id: lhero
                anchors { right: parent.right; top: parent.top; bottom: parent.bottom }
                width: Math.round(parent.width * 0.7)
                source: lrow.game.fondo || lrow.game.portada || ""
                fadeLeft: 0.55; fadeRight: 0
                alignX: 0.5
                opacity: lrow.sel ? 1 : 0.8
            }
            Row {
                anchors { left: parent.left; leftMargin: all.s * 18; verticalCenter: parent.verticalCenter }
                spacing: all.s * 14
                PlatIcon { anchors.verticalCenter: parent.verticalCenter; key: all.host.norm(lrow.game.platform); size: all.s * 26; color: all.ink2 }
                Item {      // logo del juego; sin logo, el nombre
                    anchors.verticalCenter: parent.verticalCenter
                    width: all.s * 190; height: lrow.height - all.s * 14
                    Image {
                        id: llogo
                        anchors.fill: parent
                        source: lrow.game.logo || ""
                        fillMode: Image.PreserveAspectFit
                        horizontalAlignment: Image.AlignLeft
                        asynchronous: true
                        mipmap: true
                        sourceSize.height: Math.round(all.s * 120)
                        visible: status === Image.Ready
                    }
                    Text { anchors.verticalCenter: parent.verticalCenter; visible: llogo.status !== Image.Ready; width: parent.width; text: lrow.game.name; elide: Text.ElideRight
                        color: all.ink; font.family: all.uiFont; font.pixelSize: all.s * 17; font.weight: Font.DemiBold }
                }
                Column {
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: all.s * 3
                    Text { text: lrow.game.name; color: all.ink; font.family: all.uiFont; font.pixelSize: all.s * 21; font.weight: Font.DemiBold; visible: llogo.status === Image.Ready }
                    Text { text: all.host.platformLabel(lrow.game) + (lrow.game.fav ? "  ★" : ""); color: all.ink2; font.family: all.uiFont; font.pixelSize: all.s * 15 }
                }
            }
        }
    }
}

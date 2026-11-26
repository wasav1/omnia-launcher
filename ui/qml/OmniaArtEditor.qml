pragma ComponentBehavior: Bound

import QtQuick

/** Editor de arte de Big Mode (menú contextual → «Cambiar arte»). A la izquierda, tu biblioteca en miniatura con lo que eliges;
 *  a la derecha, las pestañas Portada / Fondo / Logo y sus opciones. Moverte por las miniaturas la aplica al instante en la vista previa;
 *  nada se guarda hasta pulsar «Guardar». Con una imagen propia se elige el encuadre (Rellenar o Ajustar) y se ve el resultado antes de guardar.
 *  Mando: ←↑↓→ miniaturas · LB/RB tipo de imagen · A guardar · B descartar · Y archivo propio · X encuadre. */
Item {
    id: ed
    required property var host
    property var game: null
    signal back()
    readonly property real s: ed.host.s
    readonly property var kinds: ["portada", "fondo", "logo"]
    readonly property var kindLabels: ({ portada: qsTr("Portada"), fondo: qsTr("Fondo"), logo: qsTr("Logo") })
    property string kind: "portada"
    property var options: ({ portada: [], fondo: [], logo: [] })
    property var meta: ({ portada: { page: 0, more: false, loading: false, linked: true, warning: "" },
                          fondo: { page: 0, more: false, loading: false, linked: true, warning: "" },
                          logo: { page: 0, more: false, loading: false, linked: true, warning: "" } })
    property var choice: ({ portada: null, fondo: null, logo: null })      // null = sin cambios · {t:"option"|"local"|"reset", …}
    property int index: 0
    property bool busy: false
    property string message: ""
    property string tmpDir: ""
    readonly property var current: choice[kind]
    property var editSearchWithPad: null
    property string searchTitle: ""
    property var sourceMatch: null
    property var matches: []
    property int matchIndex: 0
    property bool showMatches: false
    property bool searching: false
    property int searchRequest: 0
    property int sourceRequest: 0
    readonly property bool localActive: !!current && current.t === "local"
    readonly property bool changed: ed.kinds.some(function(k) { return ed.choice[k] !== null })

    readonly property var tiles: {
        const out = (options[kind] || []).map(function(o, i) { return { k: "cat", i: i, url: o.thumb || o.url, cur: !!o.cur } })
        if (meta[kind] && meta[kind].more) out.push({ k: "more" })
        out.push({ k: "local" })
        if (localActive && kind !== "logo") out.push({ k: "fit" })
        out.push({ k: "reset" })
        return out
    }
    readonly property int tileW: kind === "portada" ? s * 92 : s * 150
    readonly property int tileH: kind === "portada" ? s * 138 : (kind === "fondo" ? s * 84 : s * 52)

    // ---- vista previa: lo elegido o, si no se tocó ese tipo, lo que tiene el juego ahora
    function previewUrl(k) {
        const c = choice[k]
        if (c && c.t === "option") return c.url
        if (c && c.t === "local") return "file://" + c.path
        if (c && c.t === "reset") return ""
        return game && game[k] ? game[k] : ""
    }
    function previewFit(k) { const c = choice[k]; return c && c.t === "local" && c.fit === "fit" }

    function start(g) {
        game = g; kind = "portada"; index = 0; message = ""; busy = false
        choice = { portada: null, fondo: null, logo: null }
        searchTitle = (g.artSearchTitle || g.name || "").slice(0, 140)
        sourceMatch = null
        matches = []
        showMatches = false
        searching = false
        searchRequest++
        loadSource()
        ed.host.api.artTmp(function(st, b) { if (st === 200 && b) ed.tmpDir = b.dir })
        forceActiveFocus()
    }
    function loadSource() {
        sourceRequest++
        options = { portada: [], fondo: [], logo: [] }
        meta = { portada: { page: 0, more: false, loading: false, linked: true, warning: "" },
                 fondo: { page: 0, more: false, loading: false, linked: true, warning: "" },
                 logo: { page: 0, more: false, loading: false, linked: true, warning: "" } }
        for (const k of ed.kinds) loadKind(k, 0)
    }
    function searchArtwork() {
        const title = searchTitle.trim()
        if (!title || busy) return
        const request = ++searchRequest
        showMatches = true
        searching = true
        matches = []
        matchIndex = 0
        message = ""
        forceActiveFocus()
        ed.host.api.artMatches(game, title, function(status, body) {
            if (request !== ed.searchRequest) return
            ed.searching = false
            if (status === 200) ed.matches = body.items || []
            else ed.message = (body && body.error) || qsTr("No se pudo buscar arte.")
        })
    }
    function chooseMatch(match) {
        if (!match || busy) return
        sourceMatch = match
        showMatches = false
        message = ""
        loadSource()
        forceActiveFocus()
    }
    function searchWithController() {
        if (!editSearchWithPad) { searchField.forceActiveFocus(); return }
        editSearchWithPad(searchTitle, function(value) {
            ed.forceActiveFocus()
            if (value !== undefined) {
                ed.searchTitle = String(value).slice(0, 140)
                ed.searchArtwork()
            }
        })
    }
    function cancelMatches() {
        showMatches = false
        searching = false
        searchRequest++
        message = ""
        forceActiveFocus()
    }
    function loadKind(k, page) {
        const request = sourceRequest
        const m = Object.assign({}, ed.meta[k]); m.loading = true
        const all = Object.assign({}, ed.meta); all[k] = m; ed.meta = all
        ed.host.api.artBrowse(game, k, page, 0, function(st, body) {
            if (request !== ed.sourceRequest) return
            const next = Object.assign({}, ed.options)
            const info = Object.assign({}, ed.meta[k]); info.loading = false
            if (st === 200 && body) {
                next[k] = (page === 0 ? [] : (ed.options[k] || [])).concat(body.items || [])
                info.page = page; info.more = !!body.more; info.linked = body.linked !== false; info.warning = body.warning || ""
            } else {
                info.more = false; info.warning = (body && body.error) || qsTr("No se pudieron cargar las opciones.")
            }
            const meta2 = Object.assign({}, ed.meta); meta2[k] = info; ed.meta = meta2
            ed.options = next
            if (page === 0 && k === ed.kind) moveToCurrent()
        }, sourceMatch ? sourceMatch.id : "")
    }
    function loadMore() {
        const m = meta[kind]
        if (m && m.more && !m.loading) loadKind(kind, m.page + 1)
    }
    function moveToCurrent() {
        const at = (options[kind] || []).findIndex(function(o) { return o.cur })
        index = at >= 0 ? at : 0
    }
    function setKind(k) { kind = k; moveToCurrent(); message = "" }
    function stepKind(d) { setKind(kinds[(kinds.indexOf(kind) + d + kinds.length) % kinds.length]) }

    function setChoice(value) { const next = Object.assign({}, choice); next[kind] = value; choice = next }
    function applyCursor() {                                  // moverse por una miniatura la aplica (solo a la vista previa)
        const t = tiles[index]
        if (!t) return
        if (t.k === "cat") {
            if (options[kind][t.i].cur) setChoice(null)           // volver a la imagen actual = sin cambios
            else setChoice({ t: "option", url: options[kind][t.i].url })
        } else if (t.k === "more") loadMore()
        else if (t.k === "reset") setChoice({ t: "reset" })
    }
    function move(dx, dy) {
        const cols = Math.max(1, Math.floor(grid.width / (tileW + s * 8)))
        let next = index + dx + dy * cols
        next = Math.max(0, Math.min(tiles.length - 1, next))
        if (next === index) return
        index = next
        applyCursor()
    }
    function toggleFit() {
        if (!localActive || kind === "logo") return
        const c = Object.assign({}, current); c.fit = c.fit === "fit" ? "fill" : "fit"; setChoice(c)
    }
    function chooseLocal() { browser.active = true }
    function restore() { setChoice({ t: "reset" }); index = Math.max(0, tiles.length - 1) }

    // ---- guardar: cada tipo cambiado se envía por su camino
    property var queue: []
    function save() {
        if (busy) return
        if (!changed) { back(); return }
        busy = true; message = qsTr("Guardando…")
        queue = ed.kinds.filter(function(k) { return ed.choice[k] !== null })
        next()
    }
    function fail(text) { busy = false; message = text || qsTr("No se pudo guardar el arte.") }
    function next() {
        if (queue.length === 0) {
            busy = false
            ed.host.api.refresh()
            ed.host.api.notify(qsTr("Arte actualizado: %1").arg(game.name))
            back()
            return
        }
        const k = queue[0], c = choice[k]
        queue = queue.slice(1)
        const done = function(st, b) { if (st === 200) ed.next(); else ed.fail(b && b.error) }
        if (c.t === "option") ed.host.api.artChoose(game, k, c.url, done)
        else if (c.t === "reset") ed.host.api.artReset(game, k, done)
        else if (k === "logo") ed.host.api.artLocal(game, k, c.path, done)       // un logo conserva su forma: se envía tal cual
        else renderFramed(k, c, function(path) { if (path) ed.host.api.artLocal(game, k, path, done); else ed.fail(qsTr("No se pudo preparar la imagen.")) })
    }
    function renderFramed(k, c, done) {                      // deja la imagen ya encuadrada (Rellenar o Ajustar) en la carpeta temporal del núcleo
        const t = k === "portada" ? renderP : renderF
        t.src = "file://" + c.path; t.fit = c.fit
        waiter.tries = 0; waiter.target = t; waiter.kindName = k; waiter.cb = done; waiter.start()
    }
    Timer {
        id: waiter
        interval: 80; repeat: true
        property var target: null
        property string kindName: ""
        property var cb: null
        property int tries: 0
        onTriggered: {
            tries++
            if (target.ready) {
                stop()
                const path = ed.tmpDir + "/" + kindName + "-" + Date.now() + ".png"
                target.item.grabToImage(function(res) { cb(res.saveToFile(path) ? path : "") })
            } else if (tries > 50) { stop(); cb("") }
        }
    }
    Item {       // destinos de dibujo fuera de pantalla: mismo encuadre que la vista previa
        id: renderP
        x: -100000; width: 600; height: 900
        property string src: ""
        property string fit: "fill"
        readonly property bool ready: shot.status === Image.Ready
        readonly property Item item: frame
        Rectangle { id: frame; anchors.fill: parent; color: ed.host.surface
            Image { id: shot; anchors.fill: parent; source: renderP.src; fillMode: renderP.fit === "fit" ? Image.PreserveAspectFit : Image.PreserveAspectCrop; smooth: true } }
    }
    Item {
        id: renderF
        x: -100000; width: 1920; height: 1080
        property string src: ""
        property string fit: "fill"
        readonly property bool ready: shotF.status === Image.Ready
        readonly property Item item: frameF
        Rectangle { id: frameF; anchors.fill: parent; color: ed.host.surface
            Image { id: shotF; anchors.fill: parent; source: renderF.src; fillMode: renderF.fit === "fit" ? Image.PreserveAspectFit : Image.PreserveAspectCrop; smooth: true } }
    }

    // ---- mando y teclado
    function pad(k) {
        if (browser.active || busy) return
        if (k === "SELECT") { searchWithController(); return }
        if (showMatches) {
            if (k === "u" || k === "l") matchIndex = Math.max(0, matchIndex - 1)
            else if (k === "d" || k === "r") matchIndex = Math.max(0, Math.min(matches.length - 1, matchIndex + 1))
            else if (k === "A") chooseMatch(matches[matchIndex])
            else if (k === "B") cancelMatches()
            return
        }
        if (k === "l") move(-1, 0)
        else if (k === "r") move(1, 0)
        else if (k === "u") move(0, -1)
        else if (k === "d") move(0, 1)
        else if (k === "LB") stepKind(-1)
        else if (k === "RB") stepKind(1)
        else if (k === "A") save()
        else if (k === "Y") chooseLocal()
        else if (k === "X") toggleFit()
        else if (k === "B") back()
    }
    function key(e) {
        ed.host.keySound(e)
        if (browser.active) return false
        if (e.key === Qt.Key_Left) pad("l")
        else if (e.key === Qt.Key_Right) pad("r")
        else if (e.key === Qt.Key_Up) pad("u")
        else if (e.key === Qt.Key_Down) pad("d")
        else if (e.key === Qt.Key_Tab || e.key === Qt.Key_PageDown) pad("RB")
        else if (e.key === Qt.Key_Backtab || e.key === Qt.Key_PageUp) pad("LB")
        else if (e.key === Qt.Key_Return || e.key === Qt.Key_Enter) pad("A")
        else if (e.key === Qt.Key_O) pad("Y")
        else if (e.key === Qt.Key_F) pad("X")
        else if (e.key === Qt.Key_Slash) searchField.forceActiveFocus()
        else if (e.key === Qt.Key_Delete) restore()
        else if (e.key === Qt.Key_Escape) pad("B")
        else return false
        return true
    }
    Keys.onPressed: function(e) { e.accepted = ed.key(e) }

    // ================= interfaz =================
    Rectangle { anchors.fill: parent; color: ed.host.pageShade }
    Rectangle {
        id: backB
        x: ed.s * 48; y: ed.s * 30
        width: bRow.implicitWidth + ed.s * 44; height: ed.s * 54; radius: height / 2
        color: Qt.rgba(0.05, 0.08, 0.12, 0.70); border.width: 1; border.color: Qt.rgba(1, 1, 1, 0.26)
        Row {
            id: bRow; anchors.centerIn: parent; spacing: ed.s * 10
            LucideIcon { width: ed.s * 26; height: ed.s * 26; name: "chevron-left"; color: ed.host.ink; anchors.verticalCenter: parent.verticalCenter }
            Text { text: qsTr("Descartar"); color: ed.host.ink; font.family: ed.host.uiFont; font.pixelSize: ed.s * 24; anchors.verticalCenter: parent.verticalCenter }
        }
        MouseArea { anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: ed.back() }
    }
    Text { anchors { left: backB.right; leftMargin: ed.s * 22; verticalCenter: backB.verticalCenter } color: ed.host.ink; font.family: ed.host.uiFont; font.pixelSize: ed.s * 36; font.weight: Font.Medium
           text: qsTr("Cambiar arte") + (ed.game ? "  ·  " + ed.game.name : "") }
    Rectangle {
        id: saveB
        anchors { right: parent.right; rightMargin: ed.s * 48; verticalCenter: backB.verticalCenter }
        width: saveRow.implicitWidth + ed.s * 48; height: ed.s * 54; radius: height / 2
        color: ed.changed ? ed.host.accent : Qt.rgba(0.05, 0.08, 0.12, 0.70); border.width: 1; border.color: Qt.rgba(1, 1, 1, 0.26)
        Row { id: saveRow; anchors.centerIn: parent; spacing: ed.s * 10
            Text { text: ed.busy ? qsTr("Guardando…") : qsTr("Guardar"); color: ed.host.ink; font.family: ed.host.uiFont; font.pixelSize: ed.s * 24; font.weight: Font.DemiBold } }
        MouseArea { anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: ed.save() }
    }

    Row {
        anchors { left: parent.left; right: parent.right; top: backB.bottom; bottom: hints.top; leftMargin: ed.s * 48; rightMargin: ed.s * 48; topMargin: ed.s * 26; bottomMargin: ed.s * 14 }
        spacing: ed.s * 28
        // ---- izquierda: tu biblioteca en miniatura
        Item {
            width: parent.width * 0.56; height: parent.height
            Text { id: prevTitle; text: qsTr("Así se verá tu biblioteca"); color: ed.host.ink2; font.family: ed.host.uiFont; font.pixelSize: ed.s * 20 }
            Rectangle {
                id: screen
                anchors { left: parent.left; right: parent.right; top: prevTitle.bottom; topMargin: ed.s * 10 }
                height: width * 9 / 16; radius: ed.s * 16; clip: true; color: "#1c2736"
                Image { anchors.fill: parent; source: ed.previewUrl("fondo"); smooth: true; asynchronous: true
                        fillMode: ed.previewFit("fondo") ? Image.PreserveAspectFit : Image.PreserveAspectCrop }
                Rectangle { anchors.fill: parent; color: Qt.rgba(0.04, 0.06, 0.08, 0.32) }
                Image {
                    id: prevLogo
                    x: parent.width * 0.04; y: parent.height * 0.18; width: parent.width * 0.34; height: parent.height * 0.22
                    source: ed.previewUrl("logo"); fillMode: Image.PreserveAspectFit; horizontalAlignment: Image.AlignLeft; smooth: true; asynchronous: true
                }
                Text { x: parent.width * 0.04; y: parent.height * 0.43; color: ed.host.ink; font.family: ed.host.uiFont; font.pixelSize: ed.s * 17
                       text: ed.game ? ed.game.name : "" }
                Row {
                    x: parent.width * 0.04; anchors.bottom: parent.bottom; anchors.bottomMargin: parent.height * 0.06; spacing: parent.width * 0.015
                    Rectangle {
                        width: screen.width * 0.085; height: width * 1.5; radius: ed.s * 7; color: "#243142"; clip: true
                        Image { anchors.fill: parent; source: ed.previewUrl("portada"); smooth: true; asynchronous: true
                                fillMode: ed.previewFit("portada") ? Image.PreserveAspectFit : Image.PreserveAspectCrop }
                        Rectangle { anchors.fill: parent; color: "transparent"; radius: parent.radius; border.width: 2; border.color: ed.host.accent }
                    }
                    Repeater { model: 4; Rectangle { required property int index; width: screen.width * 0.085; height: width * 1.5; radius: ed.s * 7; color: Qt.rgba(1, 1, 1, 0.08) } }
                }
            }
            Text { anchors { left: parent.left; right: parent.right; top: screen.bottom; topMargin: ed.s * 10 } wrapMode: Text.WordWrap; color: ed.host.ink2
                   font.family: ed.host.uiFont; font.pixelSize: ed.s * 17
                   text: ed.message !== "" ? ed.message : (ed.meta[ed.kind].warning !== "" ? ed.meta[ed.kind].warning : qsTr("Opciones de SteamGridDB. La estantería, la ficha y la lista usan estas mismas imágenes; nada cambia hasta que pulses Guardar.")) }
        }
        // ---- derecha: tipo de imagen y opciones
        Item {
            width: parent.width - parent.width * 0.56 - ed.s * 28; height: parent.height
            Rectangle {
                id: searchBox
                width: parent.width
                height: ed.s * 44
                radius: ed.s * 10
                color: ed.host.surface
                border.color: searchField.activeFocus ? ed.host.accent : "transparent"

                Rectangle {
                    id: searchButton
                    anchors { right: parent.right; verticalCenter: parent.verticalCenter }
                    width: searchLabel.implicitWidth + ed.s * 22
                    height: parent.height
                    radius: parent.radius
                    color: ed.host.accent
                    Text {
                        id: searchLabel
                        anchors.centerIn: parent
                        text: qsTr("Buscar arte")
                        color: ed.host.ink
                        font.pixelSize: ed.s * 16
                    }
                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: ed.searchArtwork()
                    }
                }
                TextInput {
                    id: searchField
                    anchors { left: parent.left; right: searchButton.left; verticalCenter: parent.verticalCenter; margins: ed.s * 10 }
                    text: ed.searchTitle
                    maximumLength: 140
                    clip: true
                    color: ed.host.ink
                    font.pixelSize: ed.s * 18
                    Accessible.name: qsTr("Nombre del juego")
                    onTextEdited: ed.searchTitle = text
                    onAccepted: ed.searchArtwork()
                    Keys.onEscapePressed: ed.forceActiveFocus()
                }
            }
            Text {
                id: sourceLabel
                anchors { left: parent.left; right: parent.right; top: searchBox.bottom; topMargin: ed.s * 6 }
                color: ed.host.ink2
                font.pixelSize: ed.s * 15
                visible: !!ed.sourceMatch && !ed.showMatches
                height: visible ? implicitHeight : 0
                elide: Text.ElideRight
                textFormat: Text.PlainText
                text: ed.sourceMatch ? ed.sourceMatch.name + (ed.sourceMatch.year ? " · " + ed.sourceMatch.year : "") : ""
            }
            Row {
                id: kindRow
                anchors { top: sourceLabel.bottom; topMargin: ed.s * 10 }
                visible: !ed.showMatches
                spacing: ed.s * 8
                Repeater {
                    model: ed.kinds
                    delegate: Rectangle {
                        id: kc
                        required property string modelData
                        readonly property bool on: ed.kind === modelData
                        width: kt.implicitWidth + ed.s * 34; height: ed.s * 42; radius: height / 2
                        color: on ? ed.host.accent : Qt.rgba(1, 1, 1, 0.08)
                        Text { id: kt; anchors.centerIn: parent; text: ed.kindLabels[kc.modelData] + (ed.choice[kc.modelData] ? "  •" : ""); color: ed.host.ink; font.family: ed.host.uiFont; font.pixelSize: ed.s * 19 }
                        MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: ed.setKind(kc.modelData) }
                    }
                }
            }
            ListView {
                id: matchList
                anchors { left: parent.left; right: parent.right; top: searchBox.bottom; bottom: parent.bottom; topMargin: ed.s * 12 }
                visible: ed.showMatches
                clip: true
                spacing: ed.s * 5
                model: ed.matches
                currentIndex: ed.matchIndex
                delegate: Rectangle {
                    id: matchRow
                    required property var modelData
                    required property int index
                    width: matchList.width
                    height: ed.s * 54
                    radius: ed.s * 9
                    color: index === ed.matchIndex ? ed.host.accent : ed.host.surface
                    Text {
                        anchors { left: parent.left; right: parent.right; verticalCenter: parent.verticalCenter; margins: ed.s * 10 }
                        color: ed.host.ink
                        font.pixelSize: ed.s * 18
                        elide: Text.ElideRight
                        textFormat: Text.PlainText
                        text: matchRow.modelData.name + (matchRow.modelData.year ? " · " + matchRow.modelData.year : "")
                    }
                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: ed.chooseMatch(matchRow.modelData)
                    }
                }
                Text {
                    anchors { left: parent.left; right: parent.right; top: parent.top }
                    visible: !ed.matches.length
                    wrapMode: Text.WordWrap
                    color: ed.host.ink2
                    font.pixelSize: ed.s * 18
                    text: ed.searching ? qsTr("Buscando coincidencias…") : ed.message || qsTr("No se encontraron coincidencias. Prueba otro nombre.")
                }
            }
            GridView {
                id: grid
                visible: !ed.showMatches
                anchors { left: parent.left; right: parent.right; top: kindRow.bottom; bottom: parent.bottom; topMargin: ed.s * 16 }
                cellWidth: ed.tileW + ed.s * 8; cellHeight: ed.tileH + ed.s * 8
                clip: true; interactive: true
                model: ed.tiles
                currentIndex: ed.index
                delegate: Item {
                    id: cell
                    required property var modelData
                    required property int index
                    width: grid.cellWidth; height: grid.cellHeight
                    readonly property bool sel: index === ed.index
                    Rectangle {
                        width: ed.tileW; height: ed.tileH; radius: ed.s * 10; clip: true
                        color: Qt.rgba(1, 1, 1, 0.07)
                        Image { visible: cell.modelData.k === "cat"; anchors.fill: parent; source: cell.modelData.k === "cat" ? cell.modelData.url : ""; asynchronous: true; smooth: true; fillMode: Image.PreserveAspectCrop }
                        Rectangle { visible: cell.modelData.k === "cat" && cell.modelData.cur; anchors { left: parent.left; bottom: parent.bottom; margins: ed.s * 5 }
                                    width: curT.implicitWidth + ed.s * 12; height: ed.s * 20; radius: height / 2; color: "#CC0b1016"
                                    Text { id: curT; anchors.centerIn: parent; text: qsTr("Actual"); color: ed.host.ink; font.family: ed.host.uiFont; font.pixelSize: ed.s * 12 } }
                        Image { visible: cell.modelData.k === "local" && ed.localActive; anchors.fill: parent; asynchronous: true; smooth: true
                                source: ed.localActive ? "file://" + ed.current.path : ""; fillMode: Image.PreserveAspectCrop }
                        Column {
                            visible: cell.modelData.k !== "cat" && !(cell.modelData.k === "local" && ed.localActive)
                            anchors.centerIn: parent; spacing: ed.s * 4
                            LucideIcon { anchors.horizontalCenter: parent.horizontalCenter; width: ed.s * 26; height: width; color: ed.host.ink2
                                         name: cell.modelData.k === "local" ? "folder-open" : (cell.modelData.k === "fit" ? "layout-grid" : (cell.modelData.k === "more" ? "chevron-right" : "eye-off")) }
                            Text { anchors.horizontalCenter: parent.horizontalCenter; color: ed.host.ink2; font.family: ed.host.uiFont; font.pixelSize: ed.s * 15
                                   text: cell.modelData.k === "local" ? qsTr("Mi archivo…") : (cell.modelData.k === "fit" ? (ed.current && ed.current.fit === "fit" ? qsTr("Ajustar") : qsTr("Rellenar")) : (cell.modelData.k === "more" ? (ed.meta[ed.kind].loading ? qsTr("Cargando…") : qsTr("Ver más")) : qsTr("Original"))) }
                        }
                        Rectangle { anchors.fill: parent; radius: parent.radius; color: "transparent"
                                    border.width: cell.sel ? 3 : 1; border.color: cell.sel ? ed.host.accent : Qt.rgba(1, 1, 1, 0.12) }
                        MouseArea {
                            anchors.fill: parent; cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                ed.index = cell.index
                                if (cell.modelData.k === "local") ed.chooseLocal()
                                else if (cell.modelData.k === "more") ed.loadMore()
                                else if (cell.modelData.k === "fit") ed.toggleFit()
                                else ed.applyCursor()
                            }
                        }
                    }
                }
                Text { visible: ed.options[ed.kind].length <= 1 && !ed.meta[ed.kind].more; anchors.centerIn: parent; width: parent.width * 0.8; horizontalAlignment: Text.AlignHCenter; wrapMode: Text.WordWrap
                       color: ed.host.ink2; font.family: ed.host.uiFont; font.pixelSize: ed.s * 18
                       text: ed.meta[ed.kind].loading ? qsTr("Cargando opciones…") : (!ed.meta[ed.kind].linked ? qsTr("Busca el juego por nombre o usa un archivo propio.") : qsTr("No hay otras imágenes de este tipo. Puedes usar un archivo tuyo.")) }
            }
        }
    }
    Row {
        id: hints
        anchors { left: parent.left; right: parent.right; bottom: parent.bottom; leftMargin: ed.s * 48; bottomMargin: ed.s * 28 }
        spacing: ed.s * 30
        Text { color: ed.host.ink2; font.family: ed.host.uiFont; font.pixelSize: ed.s * 20; text: qsTr("←↑↓→  Elegir") }
        Text { color: ed.host.ink2; font.family: ed.host.uiFont; font.pixelSize: ed.s * 20; text: qsTr("LB RB  Tipo") }
        Text { color: ed.host.ink2; font.family: ed.host.uiFont; font.pixelSize: ed.s * 20; text: qsTr("Y  Mi archivo") }
        Text { visible: ed.localActive && ed.kind !== "logo"; color: ed.host.ink2; font.family: ed.host.uiFont; font.pixelSize: ed.s * 20; text: qsTr("X  Encuadre") }
        Text { color: ed.host.ink2; font.family: ed.host.uiFont; font.pixelSize: ed.s * 20; text: ed.editSearchWithPad ? qsTr("SELECT  Buscar") : qsTr("/  Buscar") }
        Text { color: ed.host.ink2; font.family: ed.host.uiFont; font.pixelSize: ed.s * 20; text: ed.showMatches ? qsTr("A  Elegir juego") : qsTr("A  Guardar") }
        Text { color: ed.host.ink2; font.family: ed.host.uiFont; font.pixelSize: ed.s * 20; text: qsTr("B  Descartar") }
    }

    // explorador de archivos (mando y teclado) para elegir una imagen propia
    Loader {
        id: browser
        anchors.fill: parent
        active: false
        z: 5
        sourceComponent: Browser {
            api: ed.host.api
            mode: "file"
            exts: [".png", ".jpg", ".jpeg", ".webp"]
            heading: qsTr("Elige una imagen (%1)").arg(ed.kindLabels[ed.kind])
            onChosen: function(path) {
                browser.active = false
                ed.setChoice({ t: "local", path: path, fit: "fill" })
                ed.index = (ed.options[ed.kind] || []).length
                ed.forceActiveFocus()
            }
            onCancelled: { browser.active = false; ed.forceActiveFocus() }
        }
    }
}

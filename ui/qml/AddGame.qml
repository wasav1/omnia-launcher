import QtQuick
import QtQuick.Dialogs

/** Añadir juegos en Big Mode (entrega 4), pensado para el mando. Mismo flujo que Desktop:
 *  origen (una carpeta o un archivo) → Omnia revisa todo lo que hay dentro con `/add/scan` (ports, PC, ROMs y volcados, con su
 *  tipo ya decidido) → lista con casillas y búsqueda → «Añadir N» → resultado, con el port de lo añadido si está en otra carpeta.
 *  Mando: A marca · X marca o quita todos · LB/RB filtra por tipo · Y añade · SELECT busca · B vuelve.
 *  Teclado: escribir filtra, Retroceso borra, Enter marca, Ctrl+Enter añade, Esc vuelve. */
FocusScope {
    id: ag
    property var api
    signal finished
    signal added(string id)
    signal importRequested(string path)
    signal nameEditRequested(string initial)        // pide el teclado en pantalla (aquí, para el texto de búsqueda)

    property string stage: "source"         // source | scan | pick | done
    property string legacyPath: ""
    property string directPath: ""          // abrir directamente con un archivo
    property bool directStart: false        // abrir directamente el selector de archivo
    property bool libraryFinish: false
    property bool nameKeyboard: false
    property bool editingName: false
    property string root: ""
    property string onlyKey: ""
    property var items: []
    property var checked: ({})
    property string query: ""
    property string filter: "all"
    property bool busy: false
    property bool limited: false
    property string note: ""
    property var result: null
    readonly property var filters: ["all", "port", "game", "rom"].filter(t => t === "all" || items.some(it => it.type === t))

    readonly property var visibleItems: {
        const q = query.trim().toLowerCase()
        return items.filter(it => (filter === "all" || it.type === filter)
            && (!q || [it.name, it.systemName || "", it.recognized || "", it.fileName || it.path.split("/").pop()].join(" ").toLowerCase().indexOf(q) >= 0))
    }
    readonly property var chosen: items.filter(it => ag.checked[it.key] && !it.existingId)
    readonly property var fresh: result ? result.added.filter(a => !a.existing) : []
    function typeLabel(t) { return t === "port" ? qsTr("Port") : t === "rom" ? qsTr("ROM") : t === "game" ? qsTr("PC") : qsTr("Todo") }

    readonly property var rows: {
        if (stage === "source") {
            const out = [{ key: "folder", text: qsTr("Elegir una carpeta"), sub: qsTr("Omnia revisa ports, juegos de PC, ROMs y volcados; luego eliges cuáles añadir"), accent: true },
                         { key: "file", text: qsTr("Un solo archivo"), sub: qsTr("Un ejecutable, AppImage, .exe o ROM concreto") }]
            if (legacyPath !== "") out.push({ key: "import", text: qsTr("Importar mi biblioteca anterior…"), sub: qsTr("Vista previa e importación de ports y emuladores") })
            return out.concat([{ key: "cancel", text: qsTr("Cancelar") }])
        }
        if (stage === "scan") return [{ text: qsTr("Buscando juegos, ports y ROMs…"), disabled: true }]
        if (stage === "pick") {
            const head = [{ key: "add", text: busy ? qsTr("Añadiendo…") : qsTr("Añadir %1 seleccionados").arg(chosen.length), accent: true, disabled: busy || !chosen.length },
                          { key: "search", text: query ? qsTr("Buscar: %1").arg(query) : qsTr("Buscar por nombre, consola o archivo"),
                            sub: qsTr("Mostrando: %1 · LB/RB cambia").arg(typeLabel(filter)) }]
            return head.concat(visibleItems.map(it => ({
                key: "item", item: it, check: !!ag.checked[it.key], disabled: !!it.existingId,
                text: it.name,
                sub: [it.type === "rom" ? it.systemName : (it.recognized || ""), it.existingId ? qsTr("Ya en tu biblioteca")
                      : it.portKey ? qsTr("Su port está en la carpeta") : "", it.fileName || it.path.split("/").pop()].filter(Boolean).join("  ·  "),
                tag: typeLabel(it.type) })))
        }
        const out = (result ? result.portsFound : []).map(p => ({ key: "port", port: p, text: qsTr("Añadir también el port: %1").arg(p.recognized), sub: p.path, accent: true }))
        if (fresh.length === 1) out.push({ key: "view", text: qsTr("Ver en la biblioteca"), accent: !out.length })
        return out.concat([{ key: "close", text: qsTr("Cerrar") }])
    }

    function localPath(url) { return decodeURIComponent(url.toString().replace(/^file:\/\//, "")) }
    function parentOf(p) { return p.substring(0, p.lastIndexOf("/")) || "/" }

    function scan(path, only) {
        root = path; onlyKey = only || ""; stage = "scan"; busy = true; note = ""; items = []; checked = {}; query = ""; filter = "all"
        list.reset()
        api.addScan(path, function(st, body) {
            if (st === 403) {
                api.setLibraryRoot("add", path, function(st2, b2) {
                    if (st2 !== 200) { ag.failed((b2 && b2.error) || qsTr("No se pudo usar esa carpeta.")); return }
                    api.addScan(path, ag.scanned)
                })
                return
            }
            ag.scanned(st, body)
        })
    }
    function scanned(st, body) {
        if (stage !== "scan") return
        busy = false
        if (st !== 200) { failed((body && body.error) || qsTr("No se pudo revisar esa carpeta.")); return }
        let list2 = body.items || []
        if (onlyKey) list2 = list2.filter(it => it.key === onlyKey)
        if (!list2.length) { failed(onlyKey ? qsTr("Omnia no reconoce ese archivo como juego, port o ROM.") : qsTr("No se encontraron juegos, ports ni ROMs en esa carpeta.")); return }
        items = list2
        limited = !!body.limited
        const on = {}
        list2.forEach(it => { if (!it.existingId) on[it.key] = true })
        checked = on
        note = limited ? qsTr("La carpeta es muy grande: se muestra una parte.") : ""
        stage = "pick"
        list.reset()
    }
    function failed(msg) { busy = false; note = msg; stage = "source"; list.reset() }

    function toggle(it) {
        if (!it || it.existingId) return
        const next = Object.assign({}, checked); next[it.key] = !next[it.key]; checked = next
    }
    function toggleAll() {
        const free = visibleItems.filter(it => !it.existingId)
        const on = !free.every(it => ag.checked[it.key])
        const next = Object.assign({}, checked)
        free.forEach(it => next[it.key] = on)
        checked = next
    }
    function cycleFilter(d) {
        const i = filters.indexOf(filter)
        filter = filters[(i + d + filters.length) % filters.length]
        list.reset()
    }
    function addChosen() {
        if (!chosen.length || busy) return
        busy = true
        api.addBatch(chosen, root, function(st, body) {
            ag.busy = false
            if (st !== 200) { ag.note = (body && body.error) || qsTr("No se pudo añadir."); return }
            ag.result = body
            const n = body.added.filter(a => !a.existing).length
            ag.note = (n === 1 ? qsTr("Se añadió 1 juego a la biblioteca.") : qsTr("Se añadieron %1 juegos a la biblioteca.").arg(n))
                + (body.failed.length ? " " + qsTr("%1 no se pudieron añadir.").arg(body.failed.length) : "")
                + (body.added.some(a => a.type === "rom") && !body.portsFound.length ? " " + qsTr("Si hay un port publicado, la biblioteca mostrará «Instalar port».") : "")
            ag.stage = "done"
            list.reset()
        })
    }
    function addPort(port) {
        busy = true
        api.addBatch([port], root, function(st, body) {
            ag.busy = false
            if (st === 200 && body.added.length) {
                const r = Object.assign({}, ag.result)
                r.added = r.added.concat(body.added)
                r.portsFound = r.portsFound.filter(p => p.path !== port.path)
                ag.result = r
                ag.note = qsTr("Port añadido: %1").arg(port.recognized)
            } else ag.note = (body && body.failed && body.failed[0] && body.failed[0].error) || qsTr("No se pudo añadir el port.")
            list.reset()
        })
    }
    function askSearch() {
        if (nameKeyboard) { editingName = true; nameEditRequested(query) }
    }
    function finishNameEdit(value) {        // vuelve del teclado en pantalla
        if (value !== undefined) { query = value; list.reset() }
        Qt.callLater(function() { ag.editingName = false; ag.forceActiveFocus() })
    }

    function run(i) {
        const row = rows[i]
        if (!row) return
        if (stage === "source") {
            if (row.key === "folder") folderBrowser.active = true
            else if (row.key === "file") fileBrowser.active = true
            else if (row.key === "import") ag.importRequested(legacyPath)
            else ag.finished()
        } else if (stage === "pick") {
            if (row.key === "add") addChosen()
            else if (row.key === "search") askSearch()
            else if (row.key === "item") toggle(row.item)
        } else if (stage === "done") {
            if (row.key === "port") addPort(row.port)
            else if (row.key === "view") ag.added(fresh[0].id)
            else close()
        }
    }
    function close() {
        if (fresh.length === 1 && libraryFinish) ag.added(fresh[0].id)
        else ag.finished()
    }
    function back() {
        if (stage === "pick" && query) { query = ""; list.reset(); return }
        if (stage === "pick" || stage === "scan") { stage = "source"; items = []; note = ""; list.reset(); return }
        if (stage === "done") { close(); return }
        ag.finished()
    }

    Component.onCompleted: {
        api.importFind(function (st, b) { if (st === 200 && b.candidates.length > 0) legacyPath = b.candidates[0].path })
        forceActiveFocus()
        if (directPath !== "") scan(parentOf(directPath), directPath)
        else if (directStart) Qt.callLater(function() { directDialog.open() })
    }
    focus: true
    readonly property bool browsing: folderBrowser.active || fileBrowser.active
    Keys.onPressed: function (e) {
        if (browsing || editingName) return
        const ctrl = e.modifiers & Qt.ControlModifier
        if (e.key === Qt.Key_Down) { list.moveSelection(1); e.accepted = true }
        else if (e.key === Qt.Key_Up) { list.moveSelection(-1); e.accepted = true }
        else if ((e.key === Qt.Key_Return || e.key === Qt.Key_Enter) && ctrl && stage === "pick") { addChosen(); e.accepted = true }
        else if (e.key === Qt.Key_Return || e.key === Qt.Key_Enter || e.key === Qt.Key_Space && stage === "pick") { list.activate(); e.accepted = true }
        else if (e.key === Qt.Key_Escape) { back(); e.accepted = true }
        else if (stage === "pick" && ctrl && e.key === Qt.Key_A) { toggleAll(); e.accepted = true }
        else if (stage === "pick" && e.key === Qt.Key_Tab) { cycleFilter(1); e.accepted = true }
        else if (stage === "pick" && e.key === Qt.Key_Backtab) { cycleFilter(-1); e.accepted = true }
        else if (stage === "pick" && e.key === Qt.Key_Backspace) { query = query.slice(0, -1); list.reset(); e.accepted = true }
        else if (stage === "pick" && !ctrl && e.text && e.text.length === 1 && e.text >= " ") { query += e.text; list.reset(); e.accepted = true }
    }
    Connections {
        target: ag.api
        function onPadKey(key) {
            if (ag.browsing || ag.editingName) return
            if (key === "d") list.moveSelection(1); else if (key === "u") list.moveSelection(-1)
            else if (key === "A") list.activate(); else if (key === "B") ag.back()
            else if (ag.stage !== "pick") return
            else if (key === "X") ag.toggleAll()
            else if (key === "Y") ag.addChosen()
            else if (key === "RB") ag.cycleFilter(1); else if (key === "LB") ag.cycleFilter(-1)
            else if (key === "SELECT" || key === "BACK") ag.askSearch()
        }
    }

    Modal {
        anchors.fill: parent
        title: ag.stage === "done" ? qsTr("Listo") : ag.stage === "pick" ? qsTr("Elige qué añadir") : qsTr("Añadir juegos")
        footer: ag.stage === "pick" ? qsTr("A marcar  ·  X todos  ·  LB/RB tipo  ·  Y añadir  ·  SELECT buscar  ·  B volver")
                                    : qsTr("↑↓ elegir  ·  Enter/A aceptar  ·  Esc/B volver")
        onCloseRequested: ag.finished()
        Column {
            anchors.fill: parent
            spacing: 12
            Text {
                width: parent.width; wrapMode: Text.WordWrap; font.pixelSize: 16
                color: ag.stage === "done" ? "#7fd69f" : ag.note && ag.stage === "source" ? "#E9C46A" : "#C9D6E4"
                text: ag.note || (ag.stage === "source" ? qsTr("Steam, Epic, GOG, Heroic y Lutris se detectan solos. Para lo demás, elige una carpeta: Omnia reconoce cada juego, port o ROM.")
                                : ag.stage === "pick" ? qsTr("%1 de %2 marcados · %3").arg(ag.chosen.length).arg(ag.items.filter(it => !it.existingId).length).arg(ag.root)
                                : "")
                visible: text !== ""
            }
            OptionList {
                id: list
                width: parent.width; height: parent.height - y
                items: ag.rows
                onActivated: function (i) { ag.run(i) }
            }
        }
    }
    Loader {
        id: folderBrowser
        anchors.fill: parent
        active: false
        sourceComponent: Browser {
            api: ag.api
            mode: "dir"
            heading: qsTr("Elige la carpeta de juegos")
            onChosen: function (path) { folderBrowser.active = false; ag.forceActiveFocus(); ag.scan(path) }
            onCancelled: { folderBrowser.active = false; ag.forceActiveFocus() }
        }
    }
    Loader {
        id: fileBrowser
        anchors.fill: parent
        active: false
        sourceComponent: Browser {
            api: ag.api
            mode: "file"
            heading: qsTr("Elige el archivo del juego")
            onChosen: function (path) { fileBrowser.active = false; ag.forceActiveFocus(); ag.scan(ag.parentOf(path), path) }
            onCancelled: { fileBrowser.active = false; ag.forceActiveFocus() }
        }
    }
    FileDialog {
        id: directDialog
        title: qsTr("Selecciona el archivo del juego")
        fileMode: FileDialog.OpenFile
        nameFilters: [qsTr("Todos los archivos (*)")]
        onAccepted: { const p = ag.localPath(selectedFile); ag.scan(ag.parentOf(p), p) }
        onRejected: if (ag.directStart) ag.finished()
    }
}

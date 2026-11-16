import QtQuick
import QtQuick.Controls

// Estantería a escala lógica 1920x1080, fiel al lienzo del prototipo.
Rectangle {
    id: shell
    color: "#0b0d0c"
    focus: true

    property int bottomInset: 0
    property bool menuOpen: false
    property bool embedMenu: false
    property alias backend: api
    property string overlay: ""
    property var overlayGame: null
    property string overlayPort: ""
    property string importPath: ""
    property string pendingSavesId: ""
    property string selectedId: ""
    property string filterKey: "all"
    property string searchText: ""
    property bool searchOpen: false
    property string focusZone: "shelf"       // head | shelf | hero | player
    property int focusIndex: 0
    property var portSelection: ({})
    property var saveInfo: null
    property string saveFor: ""
    property bool contextOpen: false
    property point contextPoint: Qt.point(-1, -1)
    property int contextIndex: 0
    property bool artOpen: false
    property string artKind: "portada"
    property int artSgid: 0
    property int artPage: 0
    property int artIndex: 0
    property int artRequestSerial: 0
    property real shelfWheelRemainder: 0
    property bool artBusy: false
    property bool artMore: false
    property string artError: ""
    property var artGames: []
    property var artItems: []
    readonly property var artKinds: ["portada", "fondo", "logo"]
    readonly property int artColumns: artKind === "portada" ? 6 : (artKind === "fondo" ? 3 : 4)
    property real nowSecs: Date.now() / 1000
    property string clockText: Qt.formatTime(new Date(), "h:mm AP")
    property bool powerRequested: false
    property bool runIgnored: false       // el usuario pidió reactivar la estantería con el juego aún abierto
    readonly property var runningGame: {  // juego lanzado desde Omnia que sigue abierto (GeForce NOW no cuenta: su app queda abierta)
        for (let i = 0; i < api.games.length; i++) if (api.games[i].running) return api.games[i]
        return null
    }
    onRunningGameChanged: runIgnored = false
    property var tempHist: []             // últimas 60 lecturas de la temperatura de la CPU (1 por segundo)

    readonly property real scaleFactor: Math.min(width / 1920, height / 1080)
    readonly property var filterOptions: {
        const out = [{ key: "all", label: "Todos" }]
        let fav = false, hidden = false
        for (let i = 0; i < api.games.length; i++) {
            const g = api.games[i]
            if (g.fav) fav = true
            if (g.hidden) hidden = true
        }
        if (fav) out.push({ key: "fav", label: "Favoritos" })
        const seen = {}
        const platforms = []
        for (let i = 0; i < api.games.length; i++) {
            const key = norm(api.games[i].platform || "")
            if (!key || seen[key]) continue
            seen[key] = true
            platforms.push({ key: key, label: platformLabel(api.games[i]) })
        }
        const order = { sw2: 0, pc: 1, sw1: 2, n64: 3 }
        platforms.sort(function(a, b) { return (order[a.key] === undefined ? 9 : order[a.key]) - (order[b.key] === undefined ? 9 : order[b.key]) })
        out.push.apply(out, platforms)
        if (hidden) out.push({ key: "hidden", label: "Ocultos" })
        return out
    }
    readonly property var visibleGames: filteredAndSorted()
    readonly property var current: (visibleGames.length && list.currentIndex >= 0 && list.currentIndex < visibleGames.length) ? visibleGames[list.currentIndex] : null
    readonly property var selectedPort: {
        if (!current || !current.ports || !current.ports.length) return null
        const i = portSelection[current.id] === undefined ? 0 : Math.min(portSelection[current.id], current.ports.length - 1)
        return current.ports[i]
    }
    readonly property int selectedPortIndex: current && portSelection[current.id] !== undefined ? Math.min(portSelection[current.id], current.ports.length - 1) : 0
    readonly property var contextItems: current ? [
        { label: "Jugar", icon: "▶" },
        { label: "Respaldar partidas", icon: "▣" },
        { label: "Abrir carpeta", icon: "▱" },
        { label: "Cambiar arte", icon: "↻" },
        { label: "Elegir arte (SteamGridDB)…", icon: "▧" },
        { label: current.fav ? "Quitar de favoritos" : "Añadir a favoritos", icon: current.fav ? "★" : "☆" },
        { label: current.hidden ? "Mostrar juego" : "Ocultar juego", icon: "◉" }
    ].concat(searchText !== "" ? [{ label: "Borrar filtro de búsqueda", icon: "⌕" }] : []) : []

    function norm(s) { return (s || "").toString().toLocaleLowerCase() }
    function platformLabel(g) {
        const p = norm(g.platform || "")
        if (p === "n64") return "N64"
        if (p === "sw1") return "Switch"
        if (p === "sw2") return "Switch 2"
        if (p === "pc") return "PC"
        return g.platform || g.src || "Juegos"
    }
    function platformColor(key) {
        const k = norm(key)
        if (k === "n64") return "#d9a441"
        if (k === "sw1") return "#e8604f"
        if (k === "sw2") return "#58a6f0"
        if (k === "pc") return "#6fc3c9"
        if (k === "fav") return "#e6d9a0"
        if (k === "hidden") return "#a59f8f"
        return current ? current.acc : "#e6d9a0"
    }
    function platformIcon(g) {
        if (!g) return "pc"
        if (g.platform !== "pc" || !g.src) return g.platform
        const src = norm(g.src)
        if (src === "steam") return "steam"
        if (src === "heroic") return "heroic"
        if (src === "lutris") return "lutris"
        if (src.indexOf("geforce") >= 0) return "gfn"
        if (src === "hydra") return "hydra"
        return "pc"
    }
    function filteredAndSorted() {
        const out = [], q = norm(searchText).trim()
        for (let i = 0; i < api.games.length; i++) {
            const g = api.games[i]
            if (filterKey === "fav") { if (!g.fav || g.hidden) continue }
            else if (filterKey === "hidden") { if (!g.hidden) continue }
            else { if (g.hidden || (filterKey !== "all" && norm(g.platform) !== filterKey)) continue }
            if (q) {
                let hay = norm(g.name + " " + (g.sub || "") + " " + (g.description || ""))
                for (let p = 0; p < (g.ports || []).length; p++) hay += " " + norm(g.ports[p].name)
                if (hay.indexOf(q) < 0) continue
            }
            out.push(g)
        }
        if (filterKey === "all" || filterKey === "fav") {
            const fav = [], fresh = [], rest = []
            for (let i = 0; i < out.length; i++) {
                const g = out[i]
                if (g.fav && filterKey === "all") fav.push(g)
                else if (g.added > Date.now() / 1000 - 14 * 86400 && !g.lastPlayed) fresh.push(g)
                else rest.push(g)
            }
            fresh.sort(function(a,b) { return b.added - a.added })
            out.length = 0
            if (filterKey === "all") {
                const recent = rest.filter(function(g) { return g.lastPlayed > 0 }).sort(function(a,b) { return b.lastPlayed-a.lastPlayed })
                const old = rest.filter(function(g) { return !g.lastPlayed }).sort(function(a,b) { return a.name.localeCompare(b.name) })
                out.push.apply(out, recent.slice(0,1)); out.push.apply(out, fav); out.push.apply(out, fresh)
                for (let i=0;i<recent.length;i++) if (i>0) out.push(recent[i])
                out.push.apply(out, old)
            } else out.push.apply(out, fav.concat(fresh, rest))
        }
        return out
    }
    function chooseFilter(key) {
        const keep = current ? current.id : selectedId
        filterKey = key
        Qt.callLater(function() { restoreSelection(keep) })
    }
    function restoreSelection(id) {
        let idx = -1
        for (let i = 0; i < visibleGames.length; i++) if (visibleGames[i].id === id) idx = i
        list.currentIndex = idx >= 0 ? idx : (visibleGames.length ? 0 : -1)
    }
    function selectPort(i) {
        if (!current || current.ports.length < 2) return
        const m = Object.assign({}, portSelection)
        m[current.id] = (i + current.ports.length) % current.ports.length
        portSelection = m
        saveFor = ""; saveInfo = null; loadSaves()
    }
    function stepPort(delta) { if (current && current.ports.length > 1) selectPort(selectedPortIndex + delta) }
    function loadSaves() {
        if (!current || !selectedPort || saveFor === current.id + ":" + selectedPort.id) return
        const gid = current.id, pid = selectedPort.id
        saveFor = gid + ":" + pid; saveInfo = null
        Qt.callLater(function() {
            // Deja que ListView y la selección de port terminen de actualizar sus bindings
            // antes de capturar el juego para la petición asíncrona.
            if (!shell.current || shell.current.id !== gid || !shell.selectedPort || shell.selectedPort.id !== pid) return
            const game = shell.current
            api.savesInfo(game, function(st, body) {
                if (!shell.current || shell.current.id !== gid || !shell.selectedPort || shell.selectedPort.id !== pid) return
                shell.saveInfo = st === 200 ? body : { slots: [], error: body.error || "No se pudieron consultar las partidas (" + st + ")" }
            }, pid)
        })
    }
    function launchCurrent() { if (current && selectedPort) api.launch(current, selectedPort.id) }
    function backupCurrent() {
        if (!current || !selectedPort) return
        api.savesBackup(current, function(st,b) {
            api.toast = st === 200 ? "Respaldo creado" : (b.error || "No se pudo respaldar")
            saveFor = ""; loadSaves(); api.refresh()
        }, selectedPort.id)
    }
    function openSaveFolder() { if (current && selectedPort) api.savesOpen(current, function(st,b) { if (st !== 200) api.toast = b.error || "No se pudo abrir la carpeta" }, selectedPort.id) }
    function openArt() {
        if (!current) return
        artOpen = true; artKind = "portada"; artSgid = 0; artPage = 0; artIndex = 0
        artGames = []; artItems = []; artError = ""
        loadArt(0)
    }
    function closeArt() { artOpen = false; artBusy = false; artRequestSerial++; shell.forceActiveFocus() }
    function loadArt(page) {
        if (!current) return
        const gid = current.id, kind = artKind, edition = artSgid
        const request = ++artRequestSerial
        artBusy = true; artError = ""
        api.artBrowse(current, kind, page, edition, function(st, body) {
            if (request !== shell.artRequestSerial) return
            shell.artBusy = false
            if (!shell.current || shell.current.id !== gid || !shell.artOpen || shell.artKind !== kind) return
            if (st !== 200) { shell.artError = body.error || "No se pudo consultar SteamGridDB"; if (page === 0) shell.artItems = []; return }
            shell.artGames = body.games || []; shell.artSgid = body.sgid || 0; shell.artMore = body.more === true; shell.artPage = page
            shell.artItems = page === 0 ? (body.items || []) : shell.artItems.concat(body.items || [])
            if (page === 0) shell.artIndex = 0
        })
    }
    function setArtKind(kind) {
        if (artKinds.indexOf(kind) < 0 || kind === artKind) return
        artKind = kind; artItems = []; artIndex = 0; loadArt(0)
    }
    function stepArtEdition(delta) {
        if (artBusy || artGames.length < 2) return
        let i = artGames.findIndex(function(x) { return x.id === artSgid })
        i = (Math.max(0, i) + delta + artGames.length) % artGames.length
        artSgid = artGames[i].id; artItems = []; artIndex = 0; loadArt(0)
    }
    function pickArt(index) {
        if (!current || artBusy || index < 0 || index >= artItems.length) return
        const game = current, kind = artKind, page = artPage, sgid = artSgid
        artBusy = true
        api.artPick(game, kind, page, sgid, index, function(st, body) {
            shell.artBusy = false
            if (st !== 200) { api.toast = body.error || "No se pudo guardar el arte"; return }
            shell.artOpen = false; api.toast = "Arte aplicado: " + kind; api.refresh(); shell.forceActiveFocus()
        })
    }
    function cycleArt() {
        if (!current) return
        const game = current
        let changed = false
        api.artCycle(game, "portada", 1, function(st) {
            changed = st === 200
            api.artCycle(game, "fondo", 1, function(bg) {
                if (bg === 200) changed = true
                api.toast = changed ? "Arte cambiado" : "No hay otras opciones de arte descargadas"
                if (changed) api.refresh()
            })
        })
    }
    function toggleFavorite() { if (current) api.toggleFav(current) }
    function toggleHidden() { if (current) api.call("POST", "/game/hide?id=" + encodeURIComponent(current.id), function(st) { if (st === 200) api.refresh() }) }
    function setSearchOpen(on) { searchOpen = on; if (on) Qt.callLater(function() { searchField.forceActiveFocus() }); else shell.forceActiveFocus() }
    function showContext(x, y) { if (!current || api.gameMode) return; contextPoint = Qt.point(x, y); contextIndex = 0; contextOpen = true }
    function activateContext(i) {
        contextOpen = false
        if (i === 0) launchCurrent()
        else if (i === 1) backupCurrent()
        else if (i === 2) openSaveFolder()
        else if (i === 3) cycleArt()
        else if (i === 4) openArt()
        else if (i === 5) toggleFavorite()
        else if (i === 6) toggleHidden()
        else if (i === 7) { searchText = ""; setSearchOpen(false) }
    }
    function moveFilter(delta) {
        const n = filterOptions.length
        if (!n) return
        let i = filterOptions.findIndex(function(x) { return x.key === filterKey })
        chooseFilter(filterOptions[(Math.max(0,i) + delta + n) % n].key)
    }
    function relativeTime(ts) {
        if (!ts) return "nunca"
        const d = new Date(ts * 1000), now = new Date(nowSecs * 1000), fmt = Qt.locale("es_MX")
        const hm = (d.getHours() < 10 ? "0" : "") + d.getHours() + ":" + (d.getMinutes() < 10 ? "0" : "") + d.getMinutes()
        const start = new Date(now.getFullYear(), now.getMonth(), now.getDate()).getTime()
        if (d.getTime() >= start) return "hoy " + hm
        if (d.getTime() >= start - 86400000) return "ayer " + hm
        return d.getDate() + " " + ["ene","feb","mar","abr","may","jun","jul","ago","sep","oct","nov","dic"][d.getMonth()]
    }
    function duration(s) {
        const m = Math.floor((s || 0) / 60), h = Math.floor(m / 60)
        return h ? h + " h " + (m % 60) + " min" : Math.max(1,m) + " min"
    }
    function clockDate(d) { return d.toLocaleDateString(Qt.locale("es_MX"), "dddd d 'de' MMMM").toUpperCase() }

    Api { id: api }
    onMenuOpenChanged: api.reportMenu(menuOpen)
    onCurrentChanged: {
        if (current) {
            selectedId = current.id
            Qt.callLater(function() { if (shell.current && shell.current.id === shell.selectedId) shell.loadSaves() })
        } else { saveFor = ""; saveInfo = null }
    }
    onSelectedPortChanged: {
        if (!selectedPort) return
        saveFor = ""; saveInfo = null
        Qt.callLater(function() { shell.loadSaves() })
    }
    onVisibleGamesChanged: Qt.callLater(function() { shell.restoreSelection(shell.selectedId) })
    Timer { interval: 6000; running: !api.covered; repeat: true; onTriggered: api.refresh() }
    Timer { interval: 1000; running: !api.covered; repeat: true; onTriggered: { shell.nowSecs = Date.now()/1000; shell.clockText = Qt.formatTime(new Date(), "h:mm AP") } }
    Component.onCompleted: { forceActiveFocus(); if (visibleGames.length) list.currentIndex = 0 }

    Connections {
        target: api
        function onPadKey(key) {
            if (key === "MENU" || key === "START") { shell.menuOpen = !shell.menuOpen; return }
            if (shell.menuOpen) return
            if (runLayer.visible) return                  // con un juego abierto el mando no mueve la estantería
            if (shell.artOpen) {
                if (key === "B" || key === "SELECT") shell.closeArt()
                else if (key === "A") shell.pickArt(shell.artIndex)
                else if (key === "LB") shell.setArtKind(shell.artKinds[(shell.artKinds.indexOf(shell.artKind) + 2) % 3])
                else if (key === "RB") shell.setArtKind(shell.artKinds[(shell.artKinds.indexOf(shell.artKind) + 1) % 3])
                else if (key === "LT") shell.stepArtEdition(-1)
                else if (key === "RT") shell.stepArtEdition(1)
                else if (key === "l") shell.artIndex = Math.max(0, shell.artIndex - 1)
                else if (key === "r") shell.artIndex = Math.min(shell.artItems.length - 1, shell.artIndex + 1)
                else if (key === "u") shell.artIndex = Math.max(0, shell.artIndex - shell.artColumns)
                else if (key === "d") {
                    const next = shell.artIndex + shell.artColumns
                    if (next < shell.artItems.length) shell.artIndex = next
                    else if (shell.artMore && !shell.artBusy) shell.loadArt(shell.artPage + 1)
                }
                return
            }
            if (shell.contextOpen) {
                if (key === "u") shell.contextIndex = (shell.contextIndex - 1 + shell.contextItems.length) % shell.contextItems.length
                else if (key === "d") shell.contextIndex = (shell.contextIndex + 1) % shell.contextItems.length
                else if (key === "A") shell.activateContext(shell.contextIndex)
                else if (key === "B" || key === "SELECT") shell.contextOpen = false
                return
            }
            if (key === "SELECT" || key === "MODE") { shell.showContext(-1,-1); return }
            if (key === "X") { shell.backupCurrent(); return }
            if (key === "Y") { if (music.item) music.item.playPause(); return }
            if (key === "LB") { shell.moveFilter(-1); return }
            if (key === "RB") { shell.moveFilter(1); return }
            if (key === "LT") { shell.stepPort(-1); return }
            if (key === "RT") { shell.stepPort(1); return }
            if (shell.searchOpen) return
            if (key === "l") list.decrementCurrentIndex()
            else if (key === "r") list.incrementCurrentIndex()
            else if (key === "u") shell.focusZone = "hero"
            else if (key === "d") shell.focusZone = "shelf"
            else if (key === "A") shell.launchCurrent()
            else if (key === "B") { if (shell.overlay) shell.closeOverlay() }
        }
    }
    Keys.onPressed: function(e) {
        if (runLayer.visible) {                          // estantería deshabilitada mientras corre un juego; Esc es la salida de emergencia
            if (e.key === Qt.Key_Escape) runIgnored = true
            e.accepted = true; return
        }
        if (artOpen) {
            if (e.key === Qt.Key_Escape) closeArt()
            else if (e.key === Qt.Key_Left) artIndex = Math.max(0, artIndex - 1)
            else if (e.key === Qt.Key_Right) artIndex = Math.min(artItems.length - 1, artIndex + 1)
            else if (e.key === Qt.Key_Up) artIndex = Math.max(0, artIndex - artColumns)
            else if (e.key === Qt.Key_Down) {
                const next = artIndex + artColumns
                if (next < artItems.length) artIndex = next
                else if (artMore && !artBusy) loadArt(artPage + 1)
            }
            else if (e.key === Qt.Key_Return || e.key === Qt.Key_Enter) pickArt(artIndex)
            else if (e.key === Qt.Key_Tab) setArtKind(artKinds[(artKinds.indexOf(artKind) + 1) % artKinds.length])
            else if (e.key === Qt.Key_PageUp) stepArtEdition(-1)
            else if (e.key === Qt.Key_PageDown) stepArtEdition(1)
            else { e.accepted = false; return }
            e.accepted = true; return
        }
        if (contextOpen) {
            if (e.key === Qt.Key_Up) contextIndex = (contextIndex - 1 + contextItems.length) % contextItems.length
            else if (e.key === Qt.Key_Down) contextIndex = (contextIndex + 1) % contextItems.length
            else if (e.key === Qt.Key_Return || e.key === Qt.Key_Enter) activateContext(contextIndex)
            else if (e.key === Qt.Key_Escape || e.key === Qt.Key_Menu) contextOpen = false
            e.accepted = true; return
        }
        if (e.key === Qt.Key_Right) { list.incrementCurrentIndex(); e.accepted = true }
        else if (e.key === Qt.Key_Left) { list.decrementCurrentIndex(); e.accepted = true }
        else if (e.key === Qt.Key_Return || e.key === Qt.Key_Enter) { launchCurrent(); e.accepted = true }
        else if (e.key === Qt.Key_Menu) { showContext(-1,-1); e.accepted = true }
        else if (e.key === Qt.Key_F5) { api.call("POST", "/library/refresh", function(st) { api.refresh(); api.toast = st === 200 ? "Biblioteca actualizada" : "No se pudo actualizar" }); e.accepted = true }
        else if (e.key === Qt.Key_Slash || (e.key === Qt.Key_F && (e.modifiers & Qt.ControlModifier))) { setSearchOpen(!searchOpen); e.accepted = true }
        else if (e.key === Qt.Key_F) { toggleFavorite(); e.accepted = true }
        else if (e.key === Qt.Key_H) { toggleHidden(); e.accepted = true }
        else if (e.key === Qt.Key_Tab) { moveFilter(e.modifiers & Qt.ControlModifier ? -1 : 1); e.accepted = true }
        else if (e.key === Qt.Key_Escape && (searchOpen || searchText)) { searchText = ""; setSearchOpen(false); e.accepted = true }
        else if (e.key === Qt.Key_PageUp) { stepPort(-1); e.accepted = true }
        else if (e.key === Qt.Key_PageDown) { stepPort(1); e.accepted = true }
        else if (e.key === Qt.Key_Space) { if (music.item) music.item.playPause(); e.accepted = true }
        else if (e.key === Qt.Key_N) { openAdd(); e.accepted = true }
    }

    function openSaves(g) { if (g) { overlayGame = g; overlayPort = selectedPort ? selectedPort.id : ""; overlay = "saves" } }
    function openAdd() { overlay = "add" }
    function closeOverlay() { Qt.callLater(function() { overlay = ""; overlayGame = null; shell.forceActiveFocus() }) }
    Component { id: savesComp; SavesPanel { api: shell.backend; game: shell.overlayGame; portId: shell.overlayPort; onFinished: shell.closeOverlay() } }
    Component { id: addComp; AddGame {
        api: shell.backend
        onFinished: shell.closeOverlay()
        onAdded: function(id) { shell.pendingSavesId=id; shell.closeOverlay() }
        onImportRequested: function(path) { shell.importPath=path; shell.overlay="import" }
    } }
    Component { id: importComp; ImportPanel { api: shell.backend; path: shell.importPath; onFinished: shell.closeOverlay(); onImported: shell.closeOverlay() } }
    Loader { anchors.fill: parent; z: 90; active: shell.overlay !== ""; sourceComponent: shell.overlay === "saves" ? savesComp : (shell.overlay === "import" ? importComp : addComp) }
    Connections { target: api; function onGamesChanged() {
        if (shell.pendingSavesId === "") return
        for (let i=0;i<api.games.length;i++) if (api.games[i].id === shell.pendingSavesId) { shell.pendingSavesId=""; shell.openSaves(api.games[i]); return }
    } }
    Loader { id: music; source: "MusicSource.qml"; active: true }
    Loader { id: sensors; source: "SensorsSource.qml"; active: true }
    Timer { interval: 1000; repeat: true; running: !api.covered && !api.gameMode && sensors.item !== null
        onTriggered: { const h = shell.tempHist.slice(); h.push(sensors.item ? sensors.item.cpuTemp : 0); if (h.length > 60) h.shift(); shell.tempHist = h } }

    // Telón de arte desenfocado y película del juego seleccionado.
    Backdrop { anchors.fill: parent; source: shell.current && shell.current.fondo ? shell.current.fondo : ""; blur: 18 }
    Rectangle {
        anchors.fill: parent
        color: shell.current && shell.current.pal && shell.current.pal.length ? shell.current.pal[0] : "#10150f"
        opacity: 0.44
        Behavior on color { ColorAnimation { duration: 900 } }
    }
    Rectangle { anchors.fill: parent; color: "#59000000" }
    Rectangle { anchors { left: parent.left; top: parent.top; bottom: parent.bottom } width: parent.width * 0.78
        gradient: Gradient { orientation: Gradient.Horizontal; GradientStop { position: 0; color: "#aa000000" } GradientStop { position: 1; color: "#00000000" } }
    }
    Rectangle { anchors { left: parent.left; right: parent.right; bottom: parent.bottom } height: parent.height * 0.52
        gradient: Gradient { GradientStop { position: 0; color: "#00000000" } GradientStop { position: 1; color: "#b3000000" } }
    }

    Item {
        id: canvas
        readonly property real s: shell.scaleFactor
        width: 1920; height: shell.height / s; scale: s; transformOrigin: Item.TopLeft; clip: true
        property color acc: shell.current && shell.current.acc ? shell.current.acc : "#e6d9a0"
        property color ink: "#f3efe3"
        property color ink2: "#d6d0bf"
        property color ink3: "#a59f8f"
        property string hud: "Rajdhani"
        property string body: "Hanken Grotesk"

        // Filtros en píldoras, a las coordenadas de referencia del prototipo.
        Row {
            id: header; x: 84; y: 54; spacing: 10
            Repeater { model: shell.filterOptions
                delegate: Rectangle {
                    required property var modelData
                    required property int index
                    property bool active: shell.filterKey === modelData.key
                    height: 34; radius: 17; width: label.implicitWidth + (modelData.key === "all" ? 26 : 32)
                    color: active ? "#ebffffff" : "#59000000"; border.width: active ? 0 : 1; border.color: "#47f3efe3"
                    Row { id: label; anchors.centerIn: parent; spacing: 7
                        PlatIcon { visible: modelData.key !== "all" && modelData.key !== "fav" && modelData.key !== "hidden"; key: modelData.key; size: 17; color: shell.platformColor(modelData.key); anchors.verticalCenter: parent.verticalCenter }
                        Text { visible: modelData.key === "fav" || modelData.key === "hidden"; text: modelData.key === "fav" ? "★" : "◉"; color: shell.platformColor(modelData.key); font.family: canvas.hud; font.pixelSize: 17; font.bold: true; anchors.verticalCenter: parent.verticalCenter }
                        Text { text: modelData.label; color: active ? "#10150f" : shell.platformColor(modelData.key); font.family: canvas.hud; font.pixelSize: 17; font.weight: Font.DemiBold; font.letterSpacing: 1; anchors.verticalCenter: parent.verticalCenter }
                    }
                    Rectangle { visible: shell.focusZone === "head" && shell.focusIndex === index; anchors.fill: parent; anchors.margins: -4; radius: 22; color: "transparent"; border.width: 3; border.color: canvas.acc }
                    MouseArea { anchors.fill: parent; onClicked: shell.chooseFilter(modelData.key) }
                }
            }
            Rectangle {
                width: 34; height: 34; radius: 17; color: searchOpen ? "#ebffffff" : "#59000000"; border.width: searchOpen ? 0 : 1; border.color: "#47f3efe3"
                Text { anchors.centerIn: parent; text: "⌕"; color: searchOpen ? "#10150f" : canvas.ink; font.pixelSize: 21 }
                MouseArea { anchors.fill: parent; onClicked: shell.setSearchOpen(!searchOpen) }
            }
            Rectangle { width: 34; height: 34; radius: 17; color: "#59000000"; border.width: 1; border.color: "#47f3efe3"
                Text { anchors.centerIn: parent; text: "⏻"; color: canvas.ink; font.pixelSize: 18 }
                MouseArea { anchors.fill: parent; onClicked: { shell.menuOpen = true; api.loadApps() } }
            }
            Rectangle { width: 34; height: 34; radius: 17; color: "#59000000"; border.width: 1; border.color: "#47f3efe3"
                Text { anchors.centerIn: parent; text: "↻"; color: canvas.ink; font.pixelSize: 18 }
                MouseArea { anchors.fill: parent; onClicked: api.call("POST", "/library/refresh", function(st) { api.refresh(); api.toast = st===200 ? "Biblioteca actualizada" : "No se pudo actualizar" }) }
            }
            Rectangle { visible: api.padOn; width: 34; height: 34; radius: 17; color: "#59000000"; border.width: 1; border.color: "#47f3efe3"
                Text { anchors.centerIn: parent; text: "◖"; color: canvas.ink; font.pixelSize: 18 }
                MouseArea { anchors.fill: parent; onClicked: api.toast = "Salida de audio" }
            }
        }
        Rectangle {
            id: searchBox; x: 84; y: 54; width: 610; height: 34; radius: 17; z: 5; clip: true
            opacity: shell.searchOpen ? 1 : 0; visible: opacity > 0.01
            Behavior on opacity { NumberAnimation { duration: 180 } }
            color: "#99000000"; border.width: 1; border.color: shell.searchOpen ? "#e6d9a0" : "#47f3efe3"
            TextInput { id: searchField; x: 17; width: parent.width - 150; height: parent.height; text: shell.searchText; color: canvas.ink; font.family: canvas.hud; font.pixelSize: 18; verticalAlignment: TextInput.AlignVCenter; selectByMouse: true
                onTextChanged: shell.searchText = text
                Keys.onEscapePressed: { shell.searchText = ""; shell.setSearchOpen(false) }
                Keys.onReturnPressed: shell.forceActiveFocus()
                Keys.onEnterPressed: shell.forceActiveFocus()
            }
            Text { visible: !searchField.text; x: 17; anchors.verticalCenter: parent.verticalCenter; text: "Buscar juego…"; color: "#80f3efe3"; font.family: canvas.hud; font.pixelSize: 17 }
            Text { anchors.right: parent.right; anchors.rightMargin: 45; anchors.verticalCenter: parent.verticalCenter; text: shell.searchText ? shell.visibleGames.length + " juegos" : ""; color: "#c9f3efe3"; font.family: canvas.hud; font.pixelSize: 14 }
            Text { anchors.right: parent.right; anchors.rightMargin: 15; anchors.verticalCenter: parent.verticalCenter; text: "✕"; color: canvas.ink; visible: shell.searchText !== ""
                MouseArea { anchors.fill: parent; anchors.margins: -8; onClicked: shell.searchText = "" }
            }
        }

        // Ficha del juego: icono/origen, estado, logo o título, descripción, chips, ports y Jugar.
        Column {
            id: hero; x: 84; y: 116; width: 650; spacing: 8
            opacity: api.gameMode ? 0.12 : 1; Behavior on opacity { NumberAnimation { duration: 300 } }
            Row { spacing: 10
                PlatIcon { key: shell.platformIcon(current); color: shell.platformColor(current ? current.platform : "pc"); size: 20; anchors.verticalCenter: parent.verticalCenter }
                Text { text: current ? (platformLabel(current) + (current.platform === "pc" && current.src ? " · " + current.src : "")) : "OMNIA"; color: shell.platformColor(current ? current.platform : "pc"); font.family: canvas.hud; font.pixelSize: 20; font.weight: Font.DemiBold; font.letterSpacing: 2; anchors.verticalCenter: parent.verticalCenter }
            }
            Text { visible: !!current; text: current ? (current.plays > 0 ? platformLabel(current).toUpperCase() + " · " + shell.relativeTime(current.lastPlayed).toUpperCase() : platformLabel(current).toUpperCase() + " · SIN JUGAR") : ""; color: "#8de5c9"; font.family: canvas.hud; font.pixelSize: 16; font.letterSpacing: 3 }
            Item {
                width: 520; height: 154
                Image { anchors.fill: parent; source: current && current.logo ? current.logo : ""; fillMode: Image.PreserveAspectFit; horizontalAlignment: Image.AlignLeft; verticalAlignment: Image.AlignTop; asynchronous: true; sourceSize.width: 1000; visible: status === Image.Ready }
                Text { visible: !current || !current.logo; anchors.fill: parent; verticalAlignment: Text.AlignTop; text: current ? current.name : "Tu biblioteca"; color: canvas.ink; font.family: current && current.font ? current.font : "Hanken Grotesk"; font.pixelSize: 58; font.weight: Font.Bold; wrapMode: Text.WordWrap; maximumLineCount: 2; elide: Text.ElideNone }
            }
            Text { visible: !!current; text: current ? (selectedPort && selectedPort.description ? selectedPort.description : (current.description || current.sub || "")) : ""; color: canvas.ink2; font.family: canvas.body; font.pixelSize: 20; elide: Text.ElideRight }
            Row { visible: !!current; spacing: 18
                Repeater { model: current ? (selectedPort ? selectedPort.chips.concat(current.chips || []) : (current.chips || [])) : []
                    delegate: Row { required property string modelData; spacing: 8
                        Rectangle { width: 8; height: 8; radius: 4; color: canvas.acc; anchors.verticalCenter: parent.verticalCenter }
                        Text { text: modelData; color: canvas.ink; font.family: canvas.body; font.pixelSize: 18 }
                    }
                }
            }
            Row { visible: current && current.ports.length > 1; spacing: 10; height: 36
                Text { text: "PORT"; color: canvas.ink3; font.family: canvas.hud; font.pixelSize: 15; font.letterSpacing: 3; anchors.verticalCenter: parent.verticalCenter }
                Repeater { model: current ? current.ports : []
                    delegate: Rectangle { required property var modelData; required property int index
                        height: 34; width: portName.implicitWidth + 28; radius: 17
                        color: index === selectedPortIndex ? canvas.acc : "#59000000"; border.width: index === selectedPortIndex ? 0 : 1; border.color: "#47f3efe3"
                        Row { id: portName; anchors.centerIn: parent; spacing: 6
                            Rectangle { visible: modelData.running; width: 8; height: 8; radius: 4; color: "#6fd66f"; anchors.verticalCenter: parent.verticalCenter }
                            Text { text: modelData.name; color: index === selectedPortIndex ? "#10150f" : canvas.ink; font.family: canvas.hud; font.pixelSize: 18; font.weight: Font.DemiBold; anchors.verticalCenter: parent.verticalCenter }
                        }
                        MouseArea { anchors.fill: parent; onClicked: shell.selectPort(index) }
                    }
                }
            }
            Rectangle {
                id: playButton; height: 48; radius: 24; width: playText.implicitWidth + 52; color: "#a5efc2"
                Row { id: playText; anchors.centerIn: parent; spacing: 10
                    Text { text: "▶"; color: "#10150f"; font.pixelSize: 18; anchors.verticalCenter: parent.verticalCenter }
                    Text { text: current && current.running ? "En ejecución" : (selectedPort && current.ports.length > 1 ? "Jugar con " + selectedPort.name : "Jugar"); color: "#10150f"; font.family: canvas.body; font.pixelSize: 21; font.weight: Font.DemiBold; anchors.verticalCenter: parent.verticalCenter }
                }
                Rectangle { visible: shell.focusZone === "hero" && shell.focusIndex === (current && current.ports ? current.ports.length : 0); anchors.fill: parent; anchors.margins: -5; radius: 29; color: "transparent"; border.width: 3; border.color: canvas.acc }
                MouseArea { anchors.fill: parent; onClicked: shell.launchCurrent() }
            }
            PadGuide { visible: api.padOn; width: 650; padName: api.padName; iconSize: 24; fontPx: 14; spacing: 8; textColor: canvas.ink2; fontFamily: canvas.hud
                hints: [{k:"A",t:"Jugar"},{k:"X",t:"Respaldar"},{k:"LB+RB",t:"Filtro"},{k:"LT+RT",t:"Port"},{k:"SELECT",t:"Opciones"},{k:"START",t:"Big Menú"}]
            }
        }

        // Reloj, mando, ranuras reales y ficha.
        Item { x: 760; y: 80; width: 700; height: 140; opacity: api.gameMode ? 0.12 : 1
            Row { id: clockDigits; spacing: 0
                Text { text: { const d=new Date(shell.nowSecs*1000); return (d.getHours()%12)||12 } color: canvas.ink; font.family: canvas.hud; font.pixelSize: 104; font.weight: Font.DemiBold }
                Text { text: ":"; color: canvas.ink; font.family: canvas.hud; font.pixelSize: 104; font.weight: Font.DemiBold; opacity: new Date(shell.nowSecs*1000).getSeconds()%2 ? .2 : .85 }
                Text { text: { const d=new Date(shell.nowSecs*1000); return (d.getMinutes()<10?"0":"")+d.getMinutes() } color: canvas.ink; font.family: canvas.hud; font.pixelSize: 104; font.weight: Font.DemiBold }
            }
            Text { x: clockDigits.width + 12; y: 60; text: new Date(shell.nowSecs*1000).getHours()<12 ? "AM" : "PM"; color: canvas.acc; font.family: canvas.hud; font.pixelSize: 32; font.weight: Font.DemiBold; font.letterSpacing: 4 }
            Text { y: 112; text: clockDate(new Date(shell.nowSecs*1000)); color: canvas.ink2; font.family: canvas.hud; font.pixelSize: 22; font.letterSpacing: 3 }
        }
        Rectangle { x: 1130; y: 118; height: 36; width: padLabel.implicitWidth + 48; radius: 18; color: "#59000000"; border.width: 1; border.color: api.padOn ? "#80e6d9a0" : "#33f3efe3"
            Row { id: padLabel; anchors.centerIn: parent; spacing: 8
                Text { text: "⌘"; color: api.padOn ? canvas.acc : "#80f3efe3"; font.pixelSize: 17; anchors.verticalCenter: parent.verticalCenter }
                Text { text: api.padOn ? (api.padName || "Mando conectado") : "Sin mando"; color: api.padOn ? canvas.ink : "#80f3efe3"; font.family: canvas.hud; font.pixelSize: 16; font.weight: Font.DemiBold; font.letterSpacing: 1; anchors.verticalCenter: parent.verticalCenter }
            }
        }
        Item { id: mid; x:760; y:236; width:640; height:260; property var g: shell.selectedPort; opacity: api.gameMode ? .12:1
            Column { width: parent.width; spacing: 0
                Row { width: parent.width; spacing: 14; height: 22
                    Text { id: saveHead; text: "PARTIDAS · " + (saveInfo && saveInfo.slots.length ? saveInfo.slots.length + " RANURAS" : "NINGUNA"); color: canvas.acc; font.family: canvas.hud; font.pixelSize: 16; font.weight: Font.DemiBold; font.letterSpacing: 3.2 }
                    Rectangle { width: parent.width-saveHead.implicitWidth-14; height:1; color:"#47f3efe3"; anchors.verticalCenter:parent.verticalCenter }
                }
                Item { width:1; height:8 }
                Item { width:parent.width; height:70
                    Row { visible: saveInfo && saveInfo.slots.length; width:parent.width
                        Repeater { model: saveInfo ? saveInfo.slots.slice(0,6) : []
                            delegate: Item { required property var modelData; required property int index; width: parent.width/Math.max(1,saveInfo.slots.length); height:70
                                Rectangle { visible:index>0; width:1; height:56; color:"#47f3efe3" }
                                Column { x:index>0?14:0; spacing:2
                                    Rectangle { width:13; height:13; radius:7; color:modelData.used ? canvas.acc : "transparent"; border.width:2; border.color:modelData.used?canvas.ink:canvas.ink3 }
                                    Item { width:1;height:4 }
                                    Text { text:modelData.name; color:modelData.used?canvas.ink:canvas.ink3; font.family:canvas.hud; font.pixelSize:17; font.weight:Font.DemiBold }
                                    Text { text:modelData.used ? shell.relativeTime(modelData.mtime) : "vacía"; color:canvas.ink2; font.family:canvas.body; font.pixelSize:14 }
                                }
                            }
                        }
                    }
                    Text { visible: !saveInfo || !saveInfo.slots.length; width:560; wrapMode:Text.WordWrap; text:saveInfo ? (saveInfo.error || "Aún no hay partidas. Aparecerán aquí cuando juegues.") : "Consultando partidas…"; color:canvas.ink2; font.family:canvas.body; font.pixelSize:19 }
                }
                Row { spacing:10; height:30
                    Text { text:"☷"; color:canvas.ink3; font.pixelSize:18; anchors.verticalCenter:parent.verticalCenter }
                    Text { text:"Más opciones: clic derecho · botón Select del mando"; color:canvas.ink3; font.family:canvas.body; font.pixelSize:16; anchors.verticalCenter:parent.verticalCenter }
                }
                Item { width:1;height:14 }
                Row { width:parent.width; spacing:14; height:22
                    Text { id: infoHead; text:"FICHA"; color:canvas.acc; font.family:canvas.hud; font.pixelSize:16; font.weight:Font.DemiBold; font.letterSpacing:3.2 }
                    Rectangle { width:parent.width-infoHead.implicitWidth-14;height:1;color:"#47f3efe3";anchors.verticalCenter:parent.verticalCenter }
                }
                Item { width:1;height:10 }
                Row { width:parent.width
                    Repeater { model: current ? [
                        {v: current.plays ? shell.relativeTime(current.lastPlayed) : "nunca", l:"ÚLTIMA SESIÓN", w:150},
                        {v:"—", l:"EN DISCO", w:120},
                        {v:"por defecto", l:"AJUSTES", w:220},
                        {v: shell.relativeTime(current.lastBackup), l:"ÚLTIMO RESPALDO", w:150}
                    ] : []
                        delegate: Column { required property var modelData; width:modelData.w; spacing:3
                            Text { width:parent.width-10;text:modelData.v;color:canvas.ink;font.family:canvas.hud;font.pixelSize:22;font.weight:Font.DemiBold;elide:Text.ElideRight }
                            Text { text:modelData.l;color:canvas.ink3;font.family:canvas.hud;font.pixelSize:14;font.letterSpacing:2.5;font.weight:Font.Medium }
                        }
                    }
                }
            }
        }

        // MPRIS, broche y monitor del sistema con módulos KDE reales.
        Item { id: player; x:1530; y:38; width:320; height:170; visible: music.item && music.item.available && !api.gameMode; opacity:visible?1:0
            Column { anchors.fill:parent; spacing:2
                MarqueeLabel { width:parent.width; height:28; text:music.item?music.item.track:""; color:canvas.ink
                    textFont:Qt.font({family:canvas.hud,pixelSize:21,weight:Font.DemiBold}) }
                MarqueeLabel { width:parent.width; height:20; text:music.item?music.item.artist:""; color:canvas.ink2
                    textFont:Qt.font({family:canvas.hud,pixelSize:15}) }
                MarqueeLabel { width:parent.width; height:18; text:music.item?"REPRODUCIENDO EN · "+music.item.sourceName:""; color:canvas.ink3
                    textFont:Qt.font({family:canvas.hud,pixelSize:13,letterSpacing:1.1}) }
                Item { width:parent.width; height:46
                    Row { anchors.centerIn:parent; spacing:8
                        Repeater { model:3; delegate: Rectangle { required property int index; width:index===1?46:38;height:width;radius:width/2;color:index===1?canvas.acc:"transparent"
                            Text { anchors.centerIn:parent;anchors.horizontalCenterOffset:index===1&&music.item&&!music.item.playing?2:0;anchors.verticalCenterOffset:-1
                                text:index===0?"|◀":index===2?"▶|":(music.item&&music.item.playing?"Ⅱ":"▶")
                                color:index===1?"#10150f":canvas.ink;font.family:canvas.hud;font.pixelSize:index===1?18:16 }
                            MouseArea { anchors.fill:parent;onClicked:{if(music.item){if(index===0)music.item.previous();else if(index===1)music.item.playPause();else music.item.next()}} }
                        } }
                    }
                }
                Row { width:parent.width; spacing:8; height:20
                    Text { width:48; text:music.item?canvas.formatTrackTime(music.item.position):"0:00";color:canvas.ink3;font.family:canvas.hud;font.pixelSize:13;verticalAlignment:Text.AlignVCenter }
                    Rectangle { width:parent.width-112;height:4;radius:2;color:"#2effffff";anchors.verticalCenter:parent.verticalCenter
                        Rectangle { height:parent.height;width:music.item&&music.item.length>0?parent.width*Math.max(0,Math.min(1,music.item.position/music.item.length)):0;color:canvas.acc;radius:2
                            Behavior on width { NumberAnimation { duration:180;easing.type:Easing.OutQuad } } }
                    }
                    Text { width:48; horizontalAlignment:Text.AlignRight;text:music.item&&music.item.length>0?canvas.formatTrackTime(music.item.length):"—";color:canvas.ink3;font.family:canvas.hud;font.pixelSize:13;verticalAlignment:Text.AlignVCenter }
                }
            }
        }
        function formatTrackTime(s) { s=Math.max(0,Math.floor(Number(s)||0));return Math.floor(s/60)+":"+(s%60<10?"0":"")+(s%60) }
        Clasp { x:1530; y:212; color:canvas.acc; opacity:.9 }
        Item { id:hud; x:1530;y:246;width:320;height:440; visible:sensors.item !== null && !api.gameMode
            Column { width:parent.width; spacing:0
                Row { width:parent.width;spacing:14;height:24
                    Text { id:hudTitle;text:"SISTEMA";color:canvas.acc;font.family:canvas.hud;font.pixelSize:16;font.weight:Font.DemiBold;font.letterSpacing:3.2 }
                    Rectangle { width:parent.width-hudTitle.implicitWidth-14;height:1;color:"#47f3efe3";anchors.verticalCenter:parent.verticalCenter }
                }
                HudRow { label:"CPU";sub:api.system.cpu&&api.system.cpu.model?api.system.cpu.model:"";pct:sensors.item?sensors.item.cpu:0;vtext:Math.round(sensors.item?sensors.item.cpu:0)+" %";extra:(sensors.item?Math.round(sensors.item.cpuTemp)+" °C":"—")+(api.system.cpu&&api.system.cpu.ghz?"  "+api.system.cpu.ghz.toFixed(1)+" GHz":"");extraColor:sensors.item&&sensors.item.cpuTemp>=88?"#e2604f":(sensors.item&&sensors.item.cpuTemp>=75?"#e6a850":canvas.ink2);acc:canvas.acc;ink:canvas.ink;ink2:canvas.ink2;ink3:canvas.ink3 }
                HudRow { label:"GPU";sub:sensors.item?sensors.item.gpuName:"";pct:sensors.item?sensors.item.gpu:0;vtext:Math.round(sensors.item?sensors.item.gpu:0)+" %";extra:sensors.item?Math.round(sensors.item.gpuTemp)+" °C":"—";acc:canvas.acc;ink:canvas.ink;ink2:canvas.ink2;ink3:canvas.ink3 }
                HudRow { label:"RAM";sub:sensors.item?Math.round(sensors.item.ramTotal/1073741824)+" GB":"";pct:sensors.item?sensors.item.ramUsed/Math.max(1,sensors.item.ramTotal)*100:0;vtext:sensors.item?(sensors.item.ramUsed/1073741824).toFixed(1):"—";extra:sensors.item?"/ "+(sensors.item.ramTotal/1073741824).toFixed(1)+" GB":"";acc:canvas.acc;ink:canvas.ink;ink2:canvas.ink2;ink3:canvas.ink3 }
                HudRow { label:"VRAM";sub:sensors.item?Math.round(sensors.item.vramTotal/1073741824)+" GB":"";pct:sensors.item?sensors.item.vramUsed/Math.max(1,sensors.item.vramTotal)*100:0;vtext:sensors.item?(sensors.item.vramUsed/1073741824).toFixed(1):"—";extra:sensors.item?"/ "+(sensors.item.vramTotal/1073741824).toFixed(1)+" GB":"";acc:canvas.acc;ink:canvas.ink;ink2:canvas.ink2;ink3:canvas.ink3 }
                HudRow { label:"JUEGOS";sub:api.system.disk&&api.system.disk.fs?api.system.disk.fs:"";pct:api.system.disk?api.system.disk.used/api.system.disk.total*100:0;vtext:api.system.disk?Math.round(api.system.disk.used/1073741824)+"":"—";extra:api.system.disk?"/ "+Math.round(api.system.disk.total/1073741824)+" GB":"";acc:canvas.acc;ink:canvas.ink;ink2:canvas.ink2;ink3:canvas.ink3 }
                HudRow { visible:!!api.system.bat;height:visible?42:0;label:"BATERÍA";sub:api.system.ac?"enchufado":"con batería";pct:api.system.bat?api.system.bat.pct:0;vtext:api.system.bat?api.system.bat.pct+" %":"—";extra:"";acc:canvas.acc;ink:canvas.ink;ink2:canvas.ink2;ink3:canvas.ink3 }
                Item { width:parent.width;height:62
                    Canvas { id:spark;width:parent.width;height:34;property var h:shell.tempHist;onHChanged:requestPaint()
                        onPaint:{let c=getContext("2d");c.reset();if(h.length<2)return
                            let lo=h[0],hi=h[0];for(let k=1;k<h.length;k++){lo=Math.min(lo,h[k]);hi=Math.max(hi,h[k])}
                            const mid=(lo+hi)/2,half=Math.max(6,(hi-lo)/2+2)
                            c.strokeStyle=canvas.acc;c.lineWidth=2;c.lineJoin="round";c.beginPath()
                            for(let n=0;n<h.length;n++){const x=(60-h.length+n)*width/59,y=17-(h[n]-mid)/half*14;if(n===0)c.moveTo(x,y);else c.lineTo(x,y)}
                            c.stroke() } }
                    Text { y:38;text:"TEMP. CPU · 60 S";color:canvas.ink3;font.family:canvas.hud;font.pixelSize:15;font.letterSpacing:2.5 }
                }
            }
        }

        // Carrusel del prototipo: tarjeta activa en x=230, 290x435; laterales 190x285.
        Item { id:shelfWrap; x:0; width:1920; height:640; y:canvas.height-136-height; clip:true
            WheelHandler {
                acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
                onWheel: function(event) {
                    if (shell.menuOpen || shell.artOpen || shell.contextOpen || shell.overlay !== "") return
                    const angle = event.angleDelta.y
                    const pixel = event.pixelDelta.y
                    const stepSize = angle !== 0 ? 120 : 60
                    shell.shelfWheelRemainder += angle !== 0 ? angle : pixel
                    const steps = Math.trunc(shell.shelfWheelRemainder / stepSize)
                    if (!steps) return
                    shell.shelfWheelRemainder -= steps * stepSize
                    const direction = steps > 0 ? -1 : 1
                    list.currentIndex = Math.max(0, Math.min(shell.visibleGames.length - 1,
                        list.currentIndex + direction * Math.abs(steps)))
                    event.accepted = true
                }
            }
            Item { id:track; x:230-list.currentIndex*210; height:parent.height; Behavior on x { NumberAnimation { duration:550;easing.type:Easing.OutCubic } }
                Row { id:cardsRow; spacing:20; anchors.bottom:parent.bottom
                    Repeater { model:shell.visibleGames
                        delegate: Item { id:slot; required property var modelData; required property int index
                            readonly property bool selected:index===list.currentIndex
                            width:selected?290:190;height:435;z:selected?5:0
                            Behavior on width { NumberAnimation { duration:420;easing.type:Easing.OutBack;easing.overshoot:.8 } }
                            readonly property real cx:x+track.x+width/2
                            opacity:Math.max(0,Math.min(1,cx/300,(1920-cx)/380))
                            Loader { anchors.bottom:parent.bottom;width:slot.width;height:slot.selected?435:285;active:Math.abs(slot.index-list.currentIndex)<=9
                                Behavior on height { NumberAnimation { duration:420;easing.type:Easing.OutBack;easing.overshoot:.8 } }
                                sourceComponent: Component { GameCard { anchors.fill:parent; game:slot.modelData;current:slot.selected;api:shell.backend
                                    platformLabel:shell.platformLabel(slot.modelData);platformColor:shell.platformColor(slot.modelData.platform);iconKey:shell.platformIcon(slot.modelData);coordinateRoot:canvas
                                    onActivated: { if(slot.selected) shell.launchCurrent(); else list.currentIndex=slot.index }
                                    onContextRequested: function(px,py) {
                                        if (!slot.selected) {
                                            list.currentIndex = slot.index
                                            Qt.callLater(function() { shell.showContext(px, py) })
                                        } else shell.showContext(px, py)
                                    }
                                } }
                            }
                        }
                    }
                }
            }
        }
        // Siempre encendidas (reposo = oleaje suave abajo); solo se apagan con un juego en marcha o una ventana encima.
        Waves { x:0;y:canvas.height-360;width:1920;height:360;active:true;playing:api.audioActive||(music.item?music.item.playing:false);real:api.audioAvailable;bands:api.audioBands;color:canvas.acc;visibleOnScreen:!api.covered&&!api.gameMode&&!shell.menuOpen&&shell.runningGame===null }
        ListView { id:list; visible:false; width:1;height:1;model:shell.visibleGames;currentIndex:0 }

        MouseArea { anchors.fill:parent;z:-1;acceptedButtons:Qt.RightButton;onClicked:function(m){shell.showContext(m.x/canvas.s,m.y/canvas.s)} }
        // «EN EJECUCIÓN»: bloquea ratón, teclado y mando de la estantería mientras el juego sigue abierto; se quita sola al cerrarlo.
        Item { id:runLayer; anchors.fill:parent; z:40; visible:shell.runningGame!==null&&!shell.runIgnored
            opacity:visible?1:0
            Rectangle { anchors.fill:parent; color:"#d9050806" }
            MouseArea { anchors.fill:parent; acceptedButtons:Qt.AllButtons; hoverEnabled:true }
            Column { anchors.centerIn:parent; spacing:14; width:900
                Text { anchors.horizontalCenter:parent.horizontalCenter; text:"EN EJECUCIÓN"; color:canvas.acc; font.family:canvas.hud; font.pixelSize:22; font.weight:Font.DemiBold; font.letterSpacing:5 }
                Item { anchors.horizontalCenter:parent.horizontalCenter; width:520; height:shell.runningGame&&shell.runningGame.logo?140:90
                    Image { id:runLogo; anchors.fill:parent; source:shell.runningGame&&shell.runningGame.logo?shell.runningGame.logo:""; fillMode:Image.PreserveAspectFit; asynchronous:true; visible:status===Image.Ready }
                    Text { visible:!runLogo.visible; anchors.fill:parent; horizontalAlignment:Text.AlignHCenter; verticalAlignment:Text.AlignVCenter; wrapMode:Text.WordWrap
                        text:shell.runningGame?shell.runningGame.name:""; color:canvas.ink; font.family:shell.runningGame&&shell.runningGame.font?shell.runningGame.font:"Hanken Grotesk"; font.pixelSize:48; font.weight:Font.Bold }
                }
                Text { anchors.horizontalCenter:parent.horizontalCenter; text:"La estantería vuelve sola al cerrar el juego"; color:canvas.ink2; font.family:canvas.body; font.pixelSize:20 }
                Text { anchors.horizontalCenter:parent.horizontalCenter; text:"reactivar ahora (Esc)"; color:canvas.ink3; font.family:canvas.hud; font.pixelSize:16; font.letterSpacing:2; font.underline:true
                    MouseArea { anchors.fill:parent; anchors.margins:-10; cursorShape:Qt.PointingHandCursor; onClicked:shell.runIgnored=true } }
            }
        }
        Item { anchors.fill:parent;z:35;visible:contextOpen
            MouseArea { anchors.fill:parent;acceptedButtons:Qt.LeftButton|Qt.RightButton;onClicked:shell.contextOpen=false }
            Rectangle { id:ctx; width:360;height:shell.contextItems.length*50+28;radius:20
                x:contextPoint.x<0?560:Math.max(20,Math.min(1920-width-20,contextPoint.x)); y:contextPoint.y<0?470:Math.max(100,Math.min(canvas.height-height-130,contextPoint.y))
                color:"#ff0d1510";border.width:1;border.color:"#73e6d9a0"
                MouseArea { anchors.fill:parent;acceptedButtons:Qt.AllButtons }
                Column { x:12;y:14;width:parent.width-24
                    Repeater { model:shell.contextItems;delegate:Rectangle { required property var modelData;required property int index;height:50;width:parent.width;radius:14
                        color:index===shell.contextIndex?canvas.acc:(hover.containsMouse?"#1fffffff":"transparent")
                        Text { x:17;anchors.verticalCenter:parent.verticalCenter;text:modelData.icon;color:index===shell.contextIndex?"#10150f":canvas.ink;font.pixelSize:20 }
                        Text { x:56;anchors.verticalCenter:parent.verticalCenter;text:modelData.label;color:index===shell.contextIndex?"#10150f":canvas.ink;font.family:canvas.body;font.pixelSize:18 }
                        MouseArea { id:hover;anchors.fill:parent;hoverEnabled:true;onEntered:shell.contextIndex=index;onClicked:shell.activateContext(index) }
                    } }
                }
            }
        }
        Item { id:artLayer; anchors.fill:parent; z:45; visible:shell.artOpen
            Rectangle { anchors.fill:parent; color:"#eb050806" }
            MouseArea { anchors.fill:parent; acceptedButtons:Qt.AllButtons; onClicked:shell.closeArt() }
            Rectangle { id:artPanel; x:240;y:110;width:1440;height:860;radius:26;color:"#ff0d1510";border.width:1;border.color:"#73e6d9a0" }
            MouseArea { x:artPanel.x;y:artPanel.y;width:artPanel.width;height:artPanel.height;acceptedButtons:Qt.AllButtons }
            Text { x:276;y:136;text:"ELEGIR ARTE · " + (shell.current ? shell.current.name.toUpperCase() : "");color:canvas.acc;font.family:canvas.hud;font.pixelSize:20;font.letterSpacing:3;font.weight:Font.DemiBold }
            Row { x:276;y:180;spacing:12
                Repeater { model:shell.artKinds
                    delegate:Rectangle { required property string modelData;readonly property bool active:shell.artKind===modelData
                        height:42;width:kindText.implicitWidth+40;radius:21;color:active?canvas.acc:"#14ffffff"
                        Text { id:kindText;anchors.centerIn:parent;text:parent.modelData==="portada"?"Portada":(parent.modelData==="fondo"?"Fondo":"Logo");color:parent.active?"#10150f":canvas.ink;font.family:canvas.body;font.pixelSize:19;font.weight:Font.DemiBold }
                        MouseArea { anchors.fill:parent;onClicked:shell.setArtKind(modelData) }
                    }
                }
            }
            Row { anchors.right:artPanel.right;anchors.rightMargin:36;y:180;spacing:10;height:42
                Rectangle { visible:shell.artGames.length>1;width:42;height:42;radius:21;color:"#14ffffff"
                    Text { anchors.centerIn:parent;text:"‹";color:canvas.ink;font.pixelSize:26 }
                    MouseArea { anchors.fill:parent;onClicked:shell.stepArtEdition(-1) }
                }
                Text { width:480;anchors.verticalCenter:parent.verticalCenter;horizontalAlignment:Text.AlignRight;elide:Text.ElideMiddle;color:canvas.ink2;font.family:canvas.body;font.pixelSize:18
                    text:{for(let i=0;i<shell.artGames.length;i++)if(shell.artGames[i].id===shell.artSgid)return shell.artGames[i].name+(shell.artGames[i].year?" ("+shell.artGames[i].year+")":"")+" · "+(i+1)+"/"+shell.artGames.length;return ""}
                }
                Rectangle { visible:shell.artGames.length>1;width:42;height:42;radius:21;color:"#14ffffff"
                    Text { anchors.centerIn:parent;text:"›";color:canvas.ink;font.pixelSize:26 }
                    MouseArea { anchors.fill:parent;onClicked:shell.stepArtEdition(1) }
                }
            }
            GridView { id:artGrid;x:264;y:240;width:1392;height:650;clip:true;boundsBehavior:Flickable.StopAtBounds
                cellWidth:Math.floor(width/shell.artColumns)
                cellHeight:shell.artKind==="portada"?cellWidth*1.43:(shell.artKind==="fondo"?cellWidth*.44:cellWidth*.64)
                model:shell.artItems;currentIndex:shell.artIndex
                onAtYEndChanged:if(atYEnd&&shell.artMore&&!shell.artBusy)shell.loadArt(shell.artPage+1)
                Connections { target:shell; function onArtIndexChanged() { if (shell.artItems.length) artGrid.positionViewAtIndex(shell.artIndex, GridView.Contain) } }
                delegate:Item { id:artTile;required property var modelData;required property int index;width:artGrid.cellWidth;height:artGrid.cellHeight
                    readonly property bool focused:shell.artIndex===index
                    Rectangle { anchors.fill:parent;anchors.margins:3;radius:18;color:"transparent";border.width:focused?3:0;border.color:"#59e6d9a0" }
                    Rectangle { anchors.fill:parent;anchors.margins:8;radius:14;color:"#1a211c";clip:true
                        Image { anchors.fill:parent;anchors.margins:shell.artKind==="logo"?18:0;source:artTile.modelData.thumb;asynchronous:true;smooth:true
                            fillMode:shell.artKind==="logo"?Image.PreserveAspectFit:Image.PreserveAspectCrop;opacity:status===Image.Ready?1:0
                            Behavior on opacity { NumberAnimation { duration:150 } }
                        }
                        Rectangle { anchors.fill:parent;radius:14;color:"transparent";border.width:artTile.focused?5:(artTile.modelData.cur?3:1);border.color:artTile.focused?canvas.acc:(artTile.modelData.cur?"#7fd99a":"#33f3efe3") }
                        Rectangle { visible:artTile.modelData.cur===true;anchors.left:parent.left;anchors.top:parent.top;anchors.margins:12;height:28;radius:14;color:"#7fd99a";width:usedText.implicitWidth+22
                            Text { id:usedText;anchors.centerIn:parent;text:"✓ EN USO";color:"#0c1a10";font.family:canvas.hud;font.pixelSize:14;font.weight:Font.Bold;font.letterSpacing:1.2 }
                        }
                        Rectangle { anchors.left:parent.left;anchors.bottom:parent.bottom;anchors.margins:8;height:24;radius:12;color:"#b3000000";width:sizeText.implicitWidth+16
                            Text { id:sizeText;anchors.centerIn:parent;text:artTile.modelData.w+"×"+artTile.modelData.h+(artTile.modelData.by?" · "+artTile.modelData.by:"");color:canvas.ink;font.family:canvas.hud;font.pixelSize:12 }
                        }
                        MouseArea { anchors.fill:parent;hoverEnabled:true;onEntered:shell.artIndex=artTile.index;onClicked:shell.pickArt(artTile.index) }
                    }
                }
            }
            Text { anchors.centerIn:artPanel;visible:shell.artItems.length===0;text:shell.artBusy?"Buscando en SteamGridDB…":(shell.artError||"Sin resultados para este juego");color:canvas.ink2;font.family:canvas.body;font.pixelSize:24 }
            Text { x:276;y:930;text:api.padOn?"A aplicar · LB/RB tipo de arte · LT/RT edición · B cerrar":"Intro: aplicar · Tab: tipo de arte · Re Pág/Av Pág: edición · Esc: cerrar";color:canvas.ink3;font.family:canvas.body;font.pixelSize:17 }
            Rectangle { x:1626;y:126;width:38;height:38;radius:19;color:"#14ffffff"
                Text { anchors.centerIn:parent;text:"×";color:canvas.ink;font.pixelSize:24 }
                MouseArea { anchors.fill:parent;onClicked:shell.closeArt() }
            }
        }
    }
    Loader { active:embedMenu; anchors.fill:parent;z:100;sourceComponent:BigMenu { api:shell.backend;open:shell.menuOpen;visible:shell.menuOpen||fading;onCloseRequested:{shell.menuOpen=false;shell.forceActiveFocus()} } }
    Text { anchors { right:parent.right;bottom:parent.bottom;rightMargin:18;bottomMargin:bottomInset+8 } text:api.toast;color:canvas.acc;font.family:"Rajdhani";font.pixelSize:15 }
}

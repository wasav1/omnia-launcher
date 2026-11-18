import QtQuick
import QtQuick.Controls
import org.kde.kirigami as Kirigami

// Estantería a escala lógica 1920x1080, fiel al lienzo del prototipo.
Rectangle {
    id: shell
    color: externalWallpaper ? "transparent" : "#0b0d0c"
    focus: true
    clip: true

    property int bottomInset: 0
    property bool menuOpen: false
    property bool embedMenu: false
    property bool externalWallpaper: false
    property string sectionMode: "full"
    readonly property bool controllerOwner: sectionMode === "carousel" || sectionMode === "full"
    readonly property var sectionViewport: {
        if (sectionMode === "header") return ({ x: 60, y: 30, width: 960, height: 75 })
        if (sectionMode === "hero") return ({ x: 60, y: 110, width: 660, height: 380 })
        if (sectionMode === "activity") return ({ x: 740, y: 75, width: 700, height: 410 })
        if (sectionMode === "system") return ({ x: 1490, y: 20, width: 400, height: 685 })
        if (sectionMode === "carousel") return ({ x: 0, y: 500, width: 1480, height: 500 })
        return ({ x: 0, y: 0, width: 1920, height: 1080 })
    }
    property alias backend: api
    property string tokenSource: ""
    property string overlay: ""
    property var overlayGame: null
    property string overlayPort: ""
    property string importPath: ""
    property string pendingSavesId: ""
    property string selectedId: ""
    property int selectionRevision: -1
    property bool applyingRemoteView: false
    property bool selectionRequestActive: false
    property string filterKey: "all"
    property string searchText: ""
    property int localViewRevision: 0
    property bool viewSyncPending: false
    property bool filterTransition: false
    property int localSelectionRevision: 0
    property bool localSelectionPending: false
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
    property bool artApplying: false
    property bool artMore: false
    property string artError: ""
    property var artGames: []
    property var artItems: []
    property var artPending: ({})
    readonly property var artKinds: ["portada", "fondo", "logo"]
    readonly property int artColumns: artKind === "portada" ? 6 : (artKind === "fondo" ? 3 : 4)
    property real nowSecs: Date.now() / 1000
    property string clockText: Qt.formatTime(new Date(), "h:mm AP")
    property bool powerRequested: false
    property bool refreshBusy: false
    property string menuStartMode: "apps" // "power": el botón de apagado abre el Big Menú directamente en Energía y sesión
    // salida de audio
    property bool audOpen: false
    property int audIdx: 0
    property var audItems: []
    // teclado virtual del mando (para el buscador)
    property bool searchPad: false        // el buscador se abrió con el mando: aparece el teclado virtual
    property int oskR: 1
    property int oskC: 0
    property bool oskShift: false
    property bool runIgnored: false       // el usuario pidió reactivar la estantería con el juego aún abierto
    readonly property var runningGame: {  // juego lanzado desde Omnia que sigue abierto (GeForce NOW no cuenta: su app queda abierta)
        for (let i = 0; i < api.games.length; i++) if (api.games[i].running) return api.games[i]
        return null
    }
    onRunningGameChanged: runIgnored = false
    property var tempHist: []             // últimas 60 lecturas de la temperatura de la CPU (1 por segundo)

    readonly property real scaleFactor: sectionMode === "full" ? Math.min(width / 1920, height / 1080)
                                                              : Math.min(width / sectionViewport.width, height / sectionViewport.height)
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
        const order = { pc: 0, ps5: 1, sw2: 2, ps4: 3, sw1: 4, ps3: 5, n64: 6 }
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
    FontLoader { source: Qt.resolvedUrl("fonts/HankenGrotesk.ttf") }
    FontLoader { source: Qt.resolvedUrl("fonts/Rajdhani-Regular.ttf") }
    FontLoader { source: Qt.resolvedUrl("fonts/Rajdhani-Medium.ttf") }
    FontLoader { source: Qt.resolvedUrl("fonts/Rajdhani-SemiBold.ttf") }
    FontLoader { source: Qt.resolvedUrl("fonts/Rajdhani-Bold.ttf") }
    readonly property var contextItems: {
        if (!current) return []
        const items = [
            { label: "Jugar", icon: "media-playback-start" },
            { label: "Respaldar partidas", icon: "document-save" },
            { label: "Abrir carpeta", icon: "folder-open" },
            { label: "Elegir arte (SteamGridDB)…", icon: "images-flickr" },
            { label: current.fav ? "Quitar de favoritos" : "Añadir a favoritos", icon: "starred-symbolic" },
            { label: current.hidden ? "Mostrar juego" : "Ocultar juego", icon: current.hidden ? "view-visible" : "view-hidden" }
        ]
        items.push({ label: "Desvincular de Omnia…", icon: "edit-delete" })
        if (searchText !== "") items.push({ label: "Borrar filtro de búsqueda", icon: "edit-clear" })
        return items
    }

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
        if (k === "fav") return canvas.brand
        if (k === "hidden") return "#a59f8f"
        return current ? current.acc : canvas.brand
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
    function resetToFirstVisible() {
        const first = visibleGames.length ? visibleGames[0] : null
        list.currentIndex = first ? 0 : -1
        selectedId = first ? first.id : ""
        return first
    }
    function completeFilterTransition(revision, key) {
        if (revision !== localSelectionRevision || !filterTransition) return
        const first = resetToFirstVisible()
        filterTransition = false
        if (first && externalWallpaper && controllerOwner) {
            backend.selectGame(first.id, function(status) {
                if (revision !== shell.localSelectionRevision || status !== 200) return
                shell.localSelectionPending = false
            }, key)
        } else {
            localSelectionPending = false
        }
        if (current) loadSaves()
    }
    function chooseFilter(key) {
        if (key === filterKey) return
        filterTransition = true
        const selectionRevision = ++localSelectionRevision
        localSelectionPending = true
        selectedId = ""
        filterKey = key
        if (externalWallpaper) viewSync.restart()
        const owner = shell
        // visibleGames aún puede ser la lista anterior hasta que su binding se
        // recalcule. onVisibleGamesChanged completa primero; este doble ciclo es
        // respaldo para vistas cuyo contenido no produzca señal de cambio.
        Qt.callLater(function() { Qt.callLater(function() {
            owner.completeFilterTransition(selectionRevision, key)
        }) })
    }
    function followSelection() {
        if (!shell.externalWallpaper || shell.selectionRequestActive) return
        if (!api.ok) { selectionRetry.start(); return }
        selectionRetry.stop()
        shell.selectionRequestActive = true
        const viewRevisionAtRequest = shell.localViewRevision
        const viewPendingAtRequest = shell.viewSyncPending
        const selectionRevisionAtRequest = shell.localSelectionRevision
        const selectionPendingAtRequest = shell.localSelectionPending
        const since = shell.selectionRevision >= 0 ? "?since=" + shell.selectionRevision + "&wait=25" : ""
        api.call("GET", "/selection" + since, function(status, body) {
            shell.selectionRequestActive = false
            // Un 200 sin id ni revisión no es una selección. La versión anterior (Estantería)
            // respondía {"error": "ruta desconocida"} con 200 y este bucle devolvía el carrusel
            // al índice 0 sin parar. Reintentar con espera evita ese bloqueo.
            if (status !== 200 || !body || typeof body !== "object"
                    || (body.revision === undefined && body.id === undefined)) {
                selectionRetry.start()
                return
            }
            shell.selectionRevision = body.revision === undefined ? shell.selectionRevision : body.revision
            const localViewChanged = viewRevisionAtRequest !== shell.localViewRevision || viewPendingAtRequest || shell.viewSyncPending
            const localSelectionChanged = selectionRevisionAtRequest !== shell.localSelectionRevision || selectionPendingAtRequest || shell.localSelectionPending
            const incomingFilterKey = body.filterKey || "all"
            const remotePlatformChanged = !localViewChanged && incomingFilterKey !== shell.filterKey
            shell.applyingRemoteView = true
            if (!localViewChanged) {
                shell.viewSyncPending = false
                if (remotePlatformChanged) shell.filterTransition = true
                shell.filterKey = incomingFilterKey
                shell.searchText = body.searchText || ""
                if (remotePlatformChanged) shell.selectedId = ""
                else if (!localSelectionChanged) shell.selectedId = body.id || ""
            }
            Qt.callLater(function() {
                if (remotePlatformChanged) {
                    Qt.callLater(function() {
                        const first = shell.resetToFirstVisible()
                        shell.filterTransition = false
                        if (first && shell.controllerOwner) shell.api.selectGame(first.id, null, shell.filterKey)
                    })
                } else if (!shell.filterTransition && !localSelectionChanged) {
                    shell.restoreSelection(shell.selectedId)
                }
                Qt.callLater(function() {
                    shell.applyingRemoteView = false
                    if (localViewChanged) shell.syncView()
                })
            })
            Qt.callLater(followSelection)
        })
    }
    Timer { id: selectionRetry; interval: 1000; repeat: false; onTriggered: shell.followSelection() }
    function syncView() {
        const revision = localViewRevision
        api.setView(filterKey, searchText, function(status) {
            if (status === 200 && revision === shell.localViewRevision) shell.viewSyncPending = false
        })
    }
    Timer { id: viewSync; interval: 180; repeat: false; onTriggered: if (!shell.applyingRemoteView) shell.syncView() }
    onFilterKeyChanged: if (externalWallpaper && !applyingRemoteView) { localViewRevision++; viewSyncPending = true; viewSync.restart() }
    onSearchTextChanged: if (externalWallpaper && !applyingRemoteView) { localViewRevision++; viewSyncPending = true; viewSync.restart() }
    function restoreSelection(id) {
        if (filterTransition) return
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
            api.notify(st === 200 ? "Respaldo creado" : (b.error || "No se pudo respaldar"))
            saveFor = ""; loadSaves(); api.refresh()
        }, selectedPort.id)
    }
    function openSaveFolder() { if (current && selectedPort) api.savesOpen(current, function(st,b) { if (st !== 200) api.notify(b.error || "No se pudo abrir la carpeta") }, selectedPort.id) }
    function openArt() {
        if (!current) return
        artOpen = true; artKind = "portada"; artSgid = 0; artPage = 0; artIndex = 0; artPending = ({}); artApplying = false
        artGames = []; artItems = []; artError = ""
        loadArt(0)
    }
    function closeArt() { if (artApplying) return; artOpen = false; artBusy = false; artRequestSerial++; restoreControllerFocus() }
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
        const item = artItems[index], next = Object.assign({}, artPending)
        next[artKind] = { page: artPage, sgid: artSgid, index: index, url: item.url, thumb: item.thumb || item.url }
        artPending = next
    }
    function previewArt(kind) {
        const pending = artPending[kind]
        return pending ? pending.thumb : (current && current[kind] ? current[kind] : "")
    }
    function applyArtKinds(kinds, at, game) {
        if (at >= kinds.length) {
            artApplying = false; artOpen = false; api.refresh(); api.notify("Arte actualizado"); restoreControllerFocus(); return
        }
        const kind = kinds[at], chosen = artPending[kind]
        api.artPick(game, kind, chosen.page, chosen.sgid, chosen.index, function(status, body) {
            if (status !== 200) {
                artApplying = false; api.refresh()
                api.notify("No se pudo terminar; el arte aplicado hasta ahora se conservó. " + (body.error || "Inténtalo de nuevo."))
                return
            }
            applyArtKinds(kinds, at + 1, game)
        })
    }
    function acceptArt() {
        if (artApplying) return
        const kinds = artKinds.filter(function(kind) { return !!artPending[kind] })
        if (!kinds.length || !current) return
        artApplying = true
        applyArtKinds(kinds, 0, current)
    }
    function toggleFavorite() { if (current) api.toggleFav(current) }
    function toggleHidden() { if (current) api.call("POST", "/game/hide?id=" + encodeURIComponent(current.id), function(st) { if (st === 200) api.refresh() }) }
    function setSearchOpen(on) {
        searchOpen = on
        if (!on) { searchPad = false; restoreControllerFocus() }
        else if (!searchPad) Qt.callLater(function() { searchField.forceActiveFocus() })       // con el mando no se enfoca el campo: manda el teclado virtual
    }
    function showContext(x, y) { if (!current || api.gameRunning) return; contextPoint = Qt.point(x, y); contextIndex = 0; contextOpen = true }
    function activateContext(i) {
        contextOpen = false
        if (i === 0) launchCurrent()
        else if (i === 1) backupCurrent()
        else if (i === 2) openSaveFolder()
        else if (i === 3) openArt()
        else if (i === 4) toggleFavorite()
        else if (i === 5) toggleHidden()
        else if (current && i === 6) {
            unlinkDialog.game = current
            unlinkDialog.open()
        }
        else if (searchText !== "" && i === contextItems.length - 1) { searchText = ""; setSearchOpen(false) }
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
    function restoreControllerFocus() { if (controllerOwner) shell.forceActiveFocus() }

    Api { id: api; controlsEnabled: shell.controllerOwner; systemEnabled: shell.sectionMode === "system" || shell.sectionMode === "full" }
    Binding { target: api; property: "providedToken"; value: shell.tokenSource }
    Connections {
        target: api
        function onOkChanged() {
            if (!api.ok || !shell.externalWallpaper) return
            if (shell.controllerOwner && shell.current) api.selectGame(shell.current.id, null, shell.filterKey)
            shell.followSelection()
        }
    }
    onMenuOpenChanged: { if (controllerOwner) api.reportMenu(menuOpen); if (!menuOpen) menuStartMode = "apps" }
    onCurrentChanged: {
        if (filterTransition) return
        if (current) {
            selectedId = current.id
            if (externalWallpaper && controllerOwner) api.selectGame(selectedId, null, filterKey)
            const owner = shell
            Qt.callLater(function() { if (owner.current && owner.current.id === owner.selectedId) owner.loadSaves() })
        } else { saveFor = ""; saveInfo = null }
    }
    onSelectedPortChanged: {
        if (!selectedPort) return
        saveFor = ""; saveInfo = null
        const owner = shell
        Qt.callLater(function() { owner.loadSaves() })
    }
    onVisibleGamesChanged: {
        if (filterTransition) {
            completeFilterTransition(localSelectionRevision, filterKey)
            return
        }
        const owner = shell
        const revision = localSelectionRevision
        Qt.callLater(function() {
            if (revision === owner.localSelectionRevision) owner.restoreSelection(owner.selectedId)
        })
    }
    Timer { interval: 6000; running: !api.covered; repeat: true; onTriggered: api.refresh() }
    Timer { interval: 1000; running: !api.covered; repeat: true; onTriggered: { shell.nowSecs = Date.now()/1000; shell.clockText = Qt.formatTime(new Date(), "h:mm AP") } }
    Component.onCompleted: {
        if (controllerOwner) forceActiveFocus()
        if (visibleGames.length) list.currentIndex = 0
        if (externalWallpaper && !controllerOwner) followSelection()
    }

    Connections {
        target: api
        function onPadKey(key) {
            if (!shell.controllerOwner) return
            if ((key === "MENU" || key === "START") && !shell.artOpen) {
                if (shell.audOpen) { shell.audOpen = false; return }
                if (shell.searchOpen && shell.searchPad) { shell.closeSearch(false); return }     // Start = BUSCAR
                shell.openSearchPad(); return
            }
            if (key === "MENU_POWER") return
            if (shell.menuOpen) return
            if (runLayer.visible) return                  // con un juego abierto el mando no mueve la estantería
            if (shell.artOpen) {
                if (key === "B" || key === "SELECT") shell.closeArt()
                else if (key === "A") shell.pickArt(shell.artIndex)
                else if (key === "START") shell.acceptArt()
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
            if (shell.audOpen) { shell.audKey(key); return }
            if (shell.contextOpen) {
                if (key === "u") shell.contextIndex = (shell.contextIndex - 1 + shell.contextItems.length) % shell.contextItems.length
                else if (key === "d") shell.contextIndex = (shell.contextIndex + 1) % shell.contextItems.length
                else if (key === "A") shell.activateContext(shell.contextIndex)
                else if (key === "B" || key === "SELECT") shell.contextOpen = false
                return
            }
            if (shell.searchOpen && shell.searchPad) { shell.oskKey(key); return }
            if (key === "SELECT" || key === "MODE") { shell.showContext(-1,-1); return }
            if (key === "X") { shell.backupCurrent(); return }
            if (key === "Y") { if (music.item) music.item.playPause(); return }
            if (key === "LB") { shell.moveFilter(-1); return }
            if (key === "RB") { shell.moveFilter(1); return }
            if (key === "LT") { shell.stepPort(-1); return }
            if (key === "RT") { shell.stepPort(1); return }
            if (shell.searchOpen) return
            if (key === "l" || key === "r" || key === "u" || key === "d") shell.nav(key)
            else if (key === "A") shell.enter()
            else if (key === "B") { if (shell.overlay) shell.closeOverlay(); else shell.back() }
        }
    }
    Keys.onPressed: function(e) {
        // Only the library applet owns global keyboard navigation. Other applets stay mouse-operable.
        if (!controllerOwner) { e.accepted = false; return }
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
            else if ((e.key === Qt.Key_Return || e.key === Qt.Key_Enter) && (e.modifiers & Qt.ControlModifier)) acceptArt()
            else if (e.key === Qt.Key_Return || e.key === Qt.Key_Enter) pickArt(artIndex)
            else if (e.key === Qt.Key_Tab) setArtKind(artKinds[(artKinds.indexOf(artKind) + 1) % artKinds.length])
            else if (e.key === Qt.Key_PageUp) stepArtEdition(-1)
            else if (e.key === Qt.Key_PageDown) stepArtEdition(1)
            else { e.accepted = false; return }
            e.accepted = true; return
        }
        if (audOpen) {
            if (e.key === Qt.Key_Up) audKey("u")
            else if (e.key === Qt.Key_Down) audKey("d")
            else if (e.key === Qt.Key_Return || e.key === Qt.Key_Enter) audKey("A")
            else audOpen = false
            e.accepted = true; return
        }
        if (contextOpen) {
            if (e.key === Qt.Key_Up) contextIndex = (contextIndex - 1 + contextItems.length) % contextItems.length
            else if (e.key === Qt.Key_Down) contextIndex = (contextIndex + 1) % contextItems.length
            else if (e.key === Qt.Key_Return || e.key === Qt.Key_Enter) activateContext(contextIndex)
            else if (e.key === Qt.Key_Escape || e.key === Qt.Key_Menu) contextOpen = false
            e.accepted = true; return
        }
        if (e.key === Qt.Key_Right) { nav("r"); e.accepted = true }
        else if (e.key === Qt.Key_Left) { nav("l"); e.accepted = true }
        else if (e.key === Qt.Key_Up) { nav("u"); e.accepted = true }
        else if (e.key === Qt.Key_Down) { nav("d"); e.accepted = true }
        else if (e.key === Qt.Key_Return || e.key === Qt.Key_Enter) { enter(); e.accepted = true }
        else if (e.key === Qt.Key_Menu) { showContext(-1,-1); e.accepted = true }
        else if (e.key === Qt.Key_F5) { refreshLibrary(); e.accepted = true }
        else if (e.key === Qt.Key_Slash || (e.key === Qt.Key_F && (e.modifiers & Qt.ControlModifier))) { setSearchOpen(!searchOpen); e.accepted = true }
        else if (e.key === Qt.Key_F) { toggleFavorite(); e.accepted = true }
        else if (e.key === Qt.Key_H) { toggleHidden(); e.accepted = true }
        else if (e.key === Qt.Key_Tab) { moveFilter(e.modifiers & Qt.ControlModifier ? -1 : 1); e.accepted = true }
        else if (e.key === Qt.Key_Escape) { if (searchOpen || searchText) { searchText = ""; setSearchOpen(false) } else back(); e.accepted = true }
        else if (e.key === Qt.Key_PageUp) { stepPort(-1); e.accepted = true }
        else if (e.key === Qt.Key_PageDown) { stepPort(1); e.accepted = true }
        else if (e.key === Qt.Key_Space) { if (music.item) music.item.playPause(); e.accepted = true }
    }

    // ---- navegación por zonas con teclado y mando: shelf (carrusel) · hero (ports y Jugar) · player (reproductor) · head (filtros y botones)
    readonly property int portCount: current && current.ports && current.ports.length > 1 ? current.ports.length : 0
    readonly property bool hasMusic: music.item ? music.item.available === true : false
    readonly property int headCount: filterOptions.length + 3 + (api.padOn ? 1 : 0)
    function currentFilterIndex() { return Math.max(0, filterOptions.findIndex(function(x) { return x.key === filterKey })) }
    function goZone(z, i) { focusZone = z; focusIndex = i }
    function nav(d) {
        if (focusZone === "shelf") {
            if (d === "l") list.decrementCurrentIndex()
            else if (d === "r") list.incrementCurrentIndex()
            else if (d === "u") goZone("hero", portCount)
        } else if (focusZone === "hero") {
            if (d === "l") focusIndex = Math.max(0, focusIndex - 1)
            else if (d === "r") focusIndex = Math.min(portCount, focusIndex + 1)
            else if (d === "d") goZone("shelf", 0)
            else if (d === "u") { if (hasMusic) goZone("player", 1); else goZone("head", currentFilterIndex()) }
        } else if (focusZone === "player") {
            if (d === "l") focusIndex = Math.max(0, focusIndex - 1)
            else if (d === "r") focusIndex = Math.min(2, focusIndex + 1)
            else if (d === "d") goZone("hero", portCount)
            else if (d === "u") goZone("head", currentFilterIndex())
        } else {                                              // cabecera
            if (d === "l") focusIndex = Math.max(0, focusIndex - 1)
            else if (d === "r") focusIndex = Math.min(headCount - 1, focusIndex + 1)
            else if (d === "d") { if (hasMusic) goZone("player", 1); else goZone("hero", portCount) }
        }
    }
    function enter() {
        if (focusZone === "shelf") launchCurrent()
        else if (focusZone === "hero") { if (focusIndex < portCount) selectPort(focusIndex); else launchCurrent() }
        else if (focusZone === "player") { if (music.item) { if (focusIndex === 0) music.item.previous(); else if (focusIndex === 1) music.item.playPause(); else music.item.next() } }
        else activateHead(focusIndex)
    }
    function back() { if (focusZone !== "shelf") goZone("shelf", 0) }
    // ---- salida de audio: lista de dispositivos; A elige, B cierra
    function audShow() {
        api.loadAudioOutputs(function(items, err) {
            if (!items.length) { api.notify(err || "No se pudieron leer los dispositivos de audio"); return }
            audItems = items
            audIdx = Math.max(0, items.findIndex(function(x) { return x.current }))
            audOpen = true
        })
    }
    function audActivate(i) {
        const it = audItems[i]
        audOpen = false
        if (!it) return
        api.setAudioOutput(it, function(ok) { api.notify(ok ? "Audio: " + it.label : "No se pudo cambiar la salida de audio") })
    }
    function audKey(k) {
        const n = audItems.length
        if (k === "u") audIdx = (audIdx - 1 + n) % n
        else if (k === "d") audIdx = (audIdx + 1) % n
        else if (k === "A") audActivate(audIdx)
        else if (k === "B" || k === "SELECT" || k === "START" || k === "MENU") audOpen = false
    }
    // ---- teclado virtual (solo cuando el buscador se abre con el mando)
    readonly property var oskRows: {
        const base = ["1234567890", "qwertyuiop", "asdfghjklñ", "zxcvbnm-'."], out = []
        for (let i = 0; i < base.length; i++) {
            const r = []
            for (let j = 0; j < base[i].length; j++) { const ch = base[i][j]; r.push({ t: oskShift ? ch.toUpperCase() : ch, k: "ch", w: 1 }) }
            out.push(r)
        }
        out.push([{ t: "⇧", k: "shift", w: 1.6 }, { t: "ESPACIO", k: "space", w: 4.4 }, { t: "⌫", k: "back", w: 1.6 }, { t: "BUSCAR", k: "done", w: 2.2 }])
        return out
    }
    function openSearchPad() { searchPad = true; searchOpen = true; oskR = 1; oskC = 0 }
    function closeSearch(clear) { searchOpen = false; searchPad = false; if (clear) searchText = ""; restoreControllerFocus() }
    function oskMove(d) {
        const R = oskRows
        if (d === "u" || d === "d") {
            const x = (oskC + 0.5) / R[oskR].length
            oskR = (oskR + (d === "d" ? 1 : -1) + R.length) % R.length
            oskC = Math.min(R[oskR].length - 1, Math.floor(x * R[oskR].length))
        } else oskC = (oskC + (d === "r" ? 1 : -1) + R[oskR].length) % R[oskR].length
    }
    function oskPress() {
        const key = oskRows[oskR][oskC]
        if (key.k === "shift") oskShift = !oskShift
        else if (key.k === "space") searchText = searchText + " "
        else if (key.k === "back") searchText = searchText.slice(0, -1)
        else if (key.k === "done") closeSearch(false)                          // BUSCAR: cierra el teclado y conserva el filtro
        else { searchText = searchText + key.t; if (oskShift) oskShift = false }
    }
    function oskKey(k) {
        if (k === "l" || k === "r" || k === "u" || k === "d") oskMove(k)
        else if (k === "A") oskPress()
        else if (k === "B") { if (searchText.length) searchText = searchText.slice(0, -1); else closeSearch(true) }   // B borra; con el campo vacío cierra
        else if (k === "X") oskShift = !oskShift
        else if (k === "Y") searchText = searchText + " "
    }
    function refreshLibrary() {
        if (refreshBusy) return
        refreshBusy = true
        api.call("POST", "/library/refresh", function(st) { shell.refreshBusy = false; api.refresh(); api.notify(st === 200 ? "Biblioteca actualizada" : "No se pudo actualizar") })
    }
    function openSettings() {
        api.call("POST", "/settings/open", function(status, body) {
            if (status !== 200) api.notify(body.error || "No se pudieron abrir los ajustes de Omnia")
        })
    }
    function activateHead(i) {
        const n = filterOptions.length
        if (i < n) chooseFilter(filterOptions[i].key)
        else if (i === n) { if (searchOpen) closeSearch(true); else openSearchPad() }       // la lupa con mando abre el teclado virtual
        else if (i === n + 1) refreshLibrary()
        else if (i === n + 2) openSettings()
        else audShow()
    }
    onFocusZoneChanged: if (focusZone === "shelf") focusIndex = 0

    function openSaves(g) { if (g) { overlayGame = g; overlayPort = selectedPort ? selectedPort.id : ""; overlay = "saves" } }
    function openAdd() { overlay = "add" }
    function openQuickAdd() { overlay = "quickadd" }
    function closeOverlay() { Qt.callLater(function() { overlay = ""; overlayGame = null; shell.restoreControllerFocus() }) }
    function toastX(width) { return api.notificationPosition.endsWith("left") ? 18 : shell.width - width - 18 }
    function toastY(height) { return api.notificationPosition.startsWith("top") ? 18 : shell.height - height - bottomInset - 8 }
    Component { id: savesComp; SavesPanel { api: shell.backend; game: shell.overlayGame; portId: shell.overlayPort; onFinished: shell.closeOverlay() } }
    Component { id: addComp; AddGame {
        api: shell.backend
        onFinished: shell.closeOverlay()
        onAdded: function(id) { shell.pendingSavesId=id; shell.closeOverlay() }
        onImportRequested: function(path) { shell.importPath=path; shell.overlay="import" }
    } }
    Component { id: quickAddComp; AddGame {
        api: shell.backend
        directStart: true
        onFinished: shell.closeOverlay()
        onAdded: function(id) { shell.pendingSavesId=id; shell.closeOverlay() }
    } }
    Component { id: importComp; ImportPanel { api: shell.backend; path: shell.importPath; onFinished: shell.closeOverlay(); onImported: shell.closeOverlay() } }
    Loader { anchors.fill: parent; z: 90; active: shell.overlay !== ""; sourceComponent: shell.overlay === "saves" ? savesComp : (shell.overlay === "import" ? importComp : (shell.overlay === "quickadd" ? quickAddComp : addComp)) }
    Connections { target: api; function onGamesChanged() {
        if (shell.pendingSavesId === "") return
        for (let i=0;i<api.games.length;i++) if (api.games[i].id === shell.pendingSavesId) { shell.pendingSavesId=""; shell.openSaves(api.games[i]); return }
    } }
    Loader { id: music; source: "MusicSource.qml"; active: shell.sectionMode === "system" || shell.sectionMode === "full" }
    Loader { id: sensors; source: "SensorsSource.qml"; active: shell.sectionMode === "system" || shell.sectionMode === "full" }
    Timer { interval: 1000; repeat: true; running: (shell.sectionMode === "system" || shell.sectionMode === "full") && !api.covered && !api.gameRunning && sensors.item !== null
        onTriggered: { const h = shell.tempHist.slice(); h.push(sensors.item ? sensors.item.cpuTemp : 0); if (h.length > 60) h.shift(); shell.tempHist = h } }

    // Telón de arte desenfocado y película del juego seleccionado.
    Backdrop { anchors.fill: parent; visible: !shell.externalWallpaper; covered: api.covered || api.gameRunning; source: shell.current && shell.current.fondo ? shell.current.fondo : ""; blur: 18 }
    Rectangle {
        anchors.fill: parent
        visible: !shell.externalWallpaper
        color: shell.current && shell.current.pal && shell.current.pal.length ? shell.current.pal[0] : "#10150f"
        opacity: 0.44
        Behavior on color { ColorAnimation { duration: 900 } }
    }
    // Velo gris azulado para conservar contraste sin apagar la paleta del juego.
    Rectangle { anchors.fill: parent; visible: !shell.externalWallpaper; color: "#4835465E" }
    Rectangle { anchors { left: parent.left; top: parent.top; bottom: parent.bottom } width: parent.width * 0.78
        visible: !shell.externalWallpaper
        gradient: Gradient { orientation: Gradient.Horizontal; GradientStop { position: 0; color: "#aa000000" } GradientStop { position: 1; color: "#00000000" } }
    }
    Rectangle { anchors { left: parent.left; right: parent.right; bottom: parent.bottom } height: parent.height * 0.52
        visible: !shell.externalWallpaper
        gradient: Gradient { GradientStop { position: 0; color: "#00000000" } GradientStop { position: 1; color: "#b3000000" } }
    }

    Item {
        id: canvas
        readonly property real s: shell.scaleFactor
        width: 1920; height: shell.sectionMode === "full" ? shell.height / s : 1080
        x: shell.sectionMode === "full" ? Math.max(0, (shell.width - width * s) / 2) : -shell.sectionViewport.x * s
        y: shell.sectionMode === "full" ? Math.max(0, (shell.height - height * s) / 2) : -shell.sectionViewport.y * s
        scale: s; transformOrigin: Item.TopLeft; clip: true
        property color brand: "#91a9c2"
        property color acc: shell.current && shell.current.acc ? shell.current.acc : brand
        property color ink: "#f3efe3"
        property color ink2: "#d6d0bf"
        property color ink3: "#9aa9bc"
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
                    opacity: shell.searchOpen ? 0 : 1; Behavior on opacity { NumberAnimation { duration: 180 } }
                    color: active ? "#ebffffff" : "#59000000"; border.width: active ? 0 : 1; border.color: "#47f3efe3"
                    // Icono y texto centrados en vertical: el icono por su caja y el texto por la ALTURA DE MAYÚSCULA medida
                    // (la caja de línea de Rajdhani no está centrada ópticamente y el texto se veía más abajo que el icono).
                    TextMetrics { id: capMetrics; font: pillText.font; text: "H" }
                    Row { id: label; anchors.horizontalCenter: parent.horizontalCenter; height: parent.height; spacing: 7
                        PlatIcon { visible: modelData.key !== "all" && modelData.key !== "fav" && modelData.key !== "hidden"; key: modelData.key; size: 17; color: active ? "#10150f" : shell.platformColor(modelData.key); anchors.verticalCenter: parent.verticalCenter }
                        Text { id: starText; visible: modelData.key === "fav" || modelData.key === "hidden"; text: modelData.key === "fav" ? "★" : "◉"; color: active ? "#10150f" : shell.platformColor(modelData.key); font.family: canvas.hud; font.pixelSize: 17; font.bold: true
                            y: Math.round(parent.height / 2 - (baselineOffset + capMetrics.tightBoundingRect.y + capMetrics.tightBoundingRect.height / 2)) }
                        Text { id: pillText; text: modelData.label; color: active ? "#10150f" : shell.platformColor(modelData.key); font.family: canvas.hud; font.pixelSize: 17; font.weight: Font.DemiBold; font.letterSpacing: 1
                            y: Math.round(parent.height / 2 - (baselineOffset + capMetrics.tightBoundingRect.y + capMetrics.tightBoundingRect.height / 2)) }
                    }
                    Rectangle { visible: shell.focusZone === "head" && shell.focusIndex === index; anchors.fill: parent; anchors.margins: -4; radius: 22; color: "transparent"; border.width: 3; border.color: canvas.acc }
                    MouseArea { cursorShape: Qt.PointingHandCursor; anchors.fill: parent; onClicked: shell.chooseFilter(modelData.key) }
                }
            }
            Rectangle {
                id: searchBtn
                width: 34; height: 34; radius: 17; color: searchOpen ? canvas.acc : (sbm.containsMouse ? "#33ffffff" : "#59000000"); border.width: searchOpen ? 0 : 1; border.color: "#47f3efe3"
                Kirigami.Icon { anchors.centerIn: parent; width: 18; height: 18; source: "search"; isMask: true; color: searchOpen ? "#10150f" : "#f3efe3" }
                Rectangle { visible: shell.focusZone === "head" && shell.focusIndex === shell.filterOptions.length; anchors.fill: parent; anchors.margins: -4; radius: height / 2; color: "transparent"; border.width: 3; border.color: canvas.acc }
                MouseArea { id: sbm; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: shell.setSearchOpen(!searchOpen) }
            }
            Rectangle { id: refreshBtn; width: 34; height: 34; radius: 17; color: shell.refreshBusy ? canvas.acc : rfm.containsMouse ? "#33ffffff" : "#59000000"; border.width: shell.refreshBusy ? 0 : 1; border.color: "#47f3efe3"
                Kirigami.Icon { anchors.centerIn: parent; width: 18; height: 18; source: "view-refresh"; isMask: true; color: shell.refreshBusy ? "#10150f" : "#f3efe3" }
                Rectangle { visible: shell.focusZone === "head" && shell.focusIndex === shell.filterOptions.length + 1; anchors.fill: parent; anchors.margins: -4; radius: height / 2; color: "transparent"; border.width: 3; border.color: canvas.acc }
                MouseArea { id: rfm; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: shell.refreshLibrary() }
            }
            Rectangle { width: 34; height: 34; radius: 17; color: settingsMouse.containsMouse ? "#33ffffff" : "#59000000"; border.width: 1; border.color: "#47f3efe3"
                Kirigami.Icon { anchors.centerIn: parent; width: 18; height: 18; source: "configure"; isMask: true; color: "#f3efe3" }
                Rectangle { visible: shell.focusZone === "head" && shell.focusIndex === shell.filterOptions.length + 2; anchors.fill: parent; anchors.margins: -4; radius: height / 2; color: "transparent"; border.width: 3; border.color: canvas.acc }
                MouseArea { id: settingsMouse; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: shell.openSettings() }
                ToolTip.visible: settingsMouse.containsMouse
                ToolTip.text: "Ajustes generales de Omnia"
            }
            Rectangle { id: audBtn; visible: api.padOn; width: 34; height: 34; radius: 17; color: shell.audOpen ? canvas.acc : aum.containsMouse ? "#33ffffff" : "#59000000"; border.width: shell.audOpen ? 0 : 1; border.color: "#47f3efe3"
                Kirigami.Icon { anchors.centerIn: parent; width: 18; height: 18; source: "audio-speakers-symbolic"; isMask: true; color: shell.audOpen ? "#10150f" : "#f3efe3" }
                Rectangle { visible: shell.focusZone === "head" && shell.focusIndex === shell.filterOptions.length + 3; anchors.fill: parent; anchors.margins: -4; radius: height / 2; color: "transparent"; border.width: 3; border.color: canvas.acc }
                MouseArea { id: aum; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: shell.audShow() }
            }
        }
        Rectangle {
            id: searchBox; x: 84; y: 54; width: searchBtn.x - 10; height: 34; radius: 17; z: 5; clip: true
            opacity: shell.searchOpen ? 1 : 0; visible: opacity > 0.01
            Behavior on opacity { NumberAnimation { duration: 180 } }
            color: "#f2080b09"; border.width: 1; border.color: shell.searchOpen ? canvas.brand : "#47f3efe3"
            TextInput { id: searchField; x: 17; width: parent.width - 150; height: parent.height; text: shell.searchText; color: canvas.ink; font.family: canvas.hud; font.pixelSize: 18; verticalAlignment: TextInput.AlignVCenter; selectByMouse: true
                onTextChanged: shell.searchText = text
                Keys.onEscapePressed: { shell.searchText = ""; shell.setSearchOpen(false) }
                Keys.onReturnPressed: shell.restoreControllerFocus()
                Keys.onEnterPressed: shell.restoreControllerFocus()
            }
            Text { visible: !searchField.text; x: 17; anchors.verticalCenter: parent.verticalCenter; text: "Buscar juego…"; color: "#80f3efe3"; font.family: canvas.hud; font.pixelSize: 17 }
            Text { anchors.right: parent.right; anchors.rightMargin: 45; anchors.verticalCenter: parent.verticalCenter; text: shell.searchText ? shell.visibleGames.length + (shell.visibleGames.length === 1 ? " juego" : " juegos") : ""; color: "#c9f3efe3"; font.family: canvas.hud; font.pixelSize: 14 }
            Text { anchors.right: parent.right; anchors.rightMargin: 15; anchors.verticalCenter: parent.verticalCenter; text: "✕"; color: canvas.ink; visible: shell.searchText !== ""
                MouseArea { cursorShape: Qt.PointingHandCursor; anchors.fill: parent; anchors.margins: -8; onClicked: shell.searchText = "" }
            }
        }

        // Ficha del juego: icono/origen, estado, logo o título, descripción, chips, ports y Jugar.
        Column {
            id: hero; x: 84; y: 116; width: 650; spacing: 8
            opacity: api.gameRunning ? 0.12 : 1
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
                        Rectangle { visible: shell.focusZone === "hero" && shell.focusIndex === index; anchors.fill: parent; anchors.margins: -4; radius: height / 2; color: "transparent"; border.width: 3; border.color: canvas.acc }
                        MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: shell.selectPort(index) }
                    }
                }
            }
            Rectangle {
                id: playButton; height: 48; radius: 24; width: playText.implicitWidth + 52; color: "#a5efc2"
                Row { id: playText; anchors.centerIn: parent; spacing: 10
                    Text { text: "▶"; color: "#10150f"; font.pixelSize: 18; anchors.verticalCenter: parent.verticalCenter }
                    Text { text: current && current.running ? "En ejecución" : (selectedPort && current.ports.length > 1 ? "Jugar con " + selectedPort.name : "Jugar"); color: "#10150f"; font.family: canvas.body; font.pixelSize: 21; font.weight: Font.DemiBold; anchors.verticalCenter: parent.verticalCenter }
                }
                Rectangle { visible: shell.focusZone === "hero" && shell.focusIndex === shell.portCount; anchors.fill: parent; anchors.margins: -5; radius: 29; color: "transparent"; border.width: 3; border.color: canvas.acc }
                MouseArea { cursorShape: Qt.PointingHandCursor; anchors.fill: parent; onClicked: shell.launchCurrent() }
            }
            PadGuide { visible: api.padOn; width: 650; padName: api.padName; iconSize: 24; fontPx: 14; spacing: 8; textColor: canvas.ink2; fontFamily: canvas.hud
                hints: [{k:"A",t:"Jugar"},{k:"X",t:"Respaldar"},{k:"LB+RB",t:"Filtro"},{k:"LT+RT",t:"Port"},{k:"SELECT",t:"Opciones"},{k:"START",t:"Big Menú"}]
            }
        }

        // Reloj, mando, ranuras reales y ficha.
        Item { x: 760; y: 80; width: 700; height: 140; opacity: api.gameRunning ? 0.12 : 1
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
                Kirigami.Icon { width: 20; height: 20; source: "input-gamepad-symbolic"; isMask: true; color: api.padOn ? canvas.acc : "#80f3efe3"; anchors.verticalCenter: parent.verticalCenter }
                Text { text: api.padOn ? (api.padName || "Mando conectado") : "Sin mando"; color: api.padOn ? canvas.ink : "#80f3efe3"; font.family: canvas.hud; font.pixelSize: 16; font.weight: Font.DemiBold; font.letterSpacing: 1; anchors.verticalCenter: parent.verticalCenter }
            }
        }
        Item { id: mid; x:760; y:236; width:640; height:260; property var g: shell.selectedPort; opacity: api.gameRunning ? .12:1
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
                    Kirigami.Icon { source:"application-menu"; isMask:true; color:canvas.ink3; width:18; height:18; opacity:0.7; anchors.verticalCenter:parent.verticalCenter }
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
        // Reproductor MPRIS. Al terminar la canción o cambiar la reproducción NO desaparece de golpe: conserva lo último que
        // mostraba 2 s y se desvanece en otros 2 s. Mientras hay música todo se lee en vivo de MusicSource.
        Item { id: player; x:1530; y:58; width:320; height:170
            readonly property bool live: shell.hasMusic
            property string track: ""
            property string artist: ""
            property string source: ""
            property bool playing: false
            property real position: 0
            property real length: 0
            property real level: 0
            visible: level > 0.01 && !api.gameRunning
            opacity: level
            Binding { target: player; property: "track"; value: music.item ? music.item.track : ""; when: player.live }
            Binding { target: player; property: "artist"; value: music.item ? music.item.artist : ""; when: player.live }
            Binding { target: player; property: "source"; value: music.item ? music.item.sourceName : ""; when: player.live }
            Binding { target: player; property: "playing"; value: music.item ? music.item.playing : false; when: player.live }
            Binding { target: player; property: "position"; value: music.item ? music.item.position : 0; when: player.live }
            Binding { target: player; property: "length"; value: music.item ? music.item.length : 0; when: player.live }
            onLiveChanged: {
                holdTimer.stop(); fadeOut.stop()
                if (live) level = 1; else holdTimer.restart()
            }
            Timer { id: holdTimer; interval: 2000; onTriggered: fadeOut.start() }
            NumberAnimation { id: fadeOut; target: player; property: "level"; to: 0; duration: 2000; easing.type: Easing.InOutQuad }
            // difuminado radial de dentro hacia fuera, sin bordes, para que el reproductor se lea sobre cualquier fondo
            Canvas {
                x: -60; y: -44; width: parent.width + 120; height: parent.height + 88
                onPaint: {
                    const c = getContext("2d"); c.reset()
                    c.translate(width / 2, height / 2); c.scale(width / 2, height / 2)
                    const g = c.createRadialGradient(0, 0, 0, 0, 0, 1)
                    g.addColorStop(0, "rgba(0,0,0,0.58)"); g.addColorStop(0.4, "rgba(0,0,0,0.36)")
                    g.addColorStop(0.62, "rgba(0,0,0,0.12)"); g.addColorStop(0.78, "rgba(0,0,0,0)")
                    c.fillStyle = g; c.fillRect(-1, -1, 2, 2)
                }
            }
            Column { anchors.fill:parent; spacing:2
                MarqueeLabel { width:parent.width; height:28; text:player.track; color:canvas.ink
                    textFont:Qt.font({family:canvas.hud,pixelSize:21,weight:Font.DemiBold}) }
                MarqueeLabel { width:parent.width; height:20; text:player.artist; color:canvas.ink2
                    textFont:Qt.font({family:canvas.hud,pixelSize:15}) }
                MarqueeLabel { width:parent.width; height:18; text:player.source?"REPRODUCIENDO EN · "+player.source:""; color:canvas.ink3
                    textFont:Qt.font({family:canvas.hud,pixelSize:13,letterSpacing:1.1}) }
                Item { width:parent.width; height:46
                    Row { anchors.centerIn:parent; spacing:8
                        Repeater { model:3; delegate: Item { required property int index; width:index===1?46:38;height:width
                            anchors.verticalCenter:parent.verticalCenter                 // los tres botones comparten el mismo eje vertical
                            Rectangle { anchors.fill:parent;radius:width/2;color:index===1?canvas.acc:(pbm.containsMouse?"#29ffffff":"transparent") }
                            Rectangle { visible:shell.focusZone==="player"&&shell.focusIndex===index; anchors.fill:parent; anchors.margins:-5; radius:width/2; color:"transparent"; border.width:3; border.color:canvas.acc }
                            PlayerIcon { anchors.centerIn:parent;kind:index===0?"prev":index===2?"next":(player.playing?"pause":"play");color:index===1?"#10150f":canvas.ink }
                            MouseArea { id:pbm;anchors.fill:parent;hoverEnabled:true;cursorShape:Qt.PointingHandCursor;onClicked:{if(music.item&&player.live){if(index===0)music.item.previous();else if(index===1)music.item.playPause();else music.item.next()}} }
                        } }
                    }
                }
                Row { width:parent.width; spacing:8; height:20
                    TextMetrics { id:timeCap; font.family:canvas.hud; font.pixelSize:13; text:"0" }          // los números se centran por su altura real
                    Text { id:tLeft; width:48; text:canvas.formatTrackTime(player.position);color:canvas.ink3;font.family:canvas.hud;font.pixelSize:13
                        y:Math.round(parent.height/2-(baselineOffset+timeCap.tightBoundingRect.y+timeCap.tightBoundingRect.height/2)) }
                    Rectangle { width:parent.width-112;height:4;radius:2;color:"#2effffff";anchors.verticalCenter:parent.verticalCenter
                        Rectangle { height:parent.height;width:player.length>0?parent.width*Math.max(0,Math.min(1,player.position/player.length)):0;color:canvas.acc;radius:2 }
                    }
                    Text { width:48; horizontalAlignment:Text.AlignRight;text:player.length>0?canvas.formatTrackTime(player.length):"—";color:canvas.ink3;font.family:canvas.hud;font.pixelSize:13
                        y:Math.round(parent.height/2-(baselineOffset+timeCap.tightBoundingRect.y+timeCap.tightBoundingRect.height/2)) }
                }
            }
        }
        function formatTrackTime(s) { s=Math.max(0,Math.floor(Number(s)||0));return Math.floor(s/60)+":"+(s%60<10?"0":"")+(s%60) }
        Clasp { x:1530; y:232; color:canvas.acc; opacity:.9 }
        Item { id:hud; x:1530;y:266;width:320;height:440; visible:sensors.item !== null && !api.gameRunning
            Column { width:parent.width; spacing:0
                Row { width:parent.width;spacing:14;height:24
                    Text { id:hudTitle;text:"SISTEMA";color:canvas.brand;font.family:canvas.hud;font.pixelSize:16;font.weight:Font.DemiBold;font.letterSpacing:3.2 }
                    Rectangle { width:parent.width-hudTitle.implicitWidth-14;height:1;color:"#47f3efe3";anchors.verticalCenter:parent.verticalCenter }
                }
                HudRow { label:"CPU";sub:api.system.cpu&&api.system.cpu.model?api.system.cpu.model:"";pct:sensors.item?sensors.item.cpu:0;vtext:Math.round(sensors.item?sensors.item.cpu:0)+" %";extra:(sensors.item?Math.round(sensors.item.cpuTemp)+" °C":"—")+(api.system.cpu&&api.system.cpu.ghz?"  "+api.system.cpu.ghz.toFixed(1)+" GHz":"");extraColor:sensors.item&&sensors.item.cpuTemp>=88?"#e2604f":(sensors.item&&sensors.item.cpuTemp>=75?"#e6a850":canvas.ink2);acc:canvas.acc;ink:canvas.ink;ink2:canvas.ink2;ink3:canvas.ink3 }
                HudRow { label:"GPU";sub:sensors.item?sensors.item.gpuName:"";pct:sensors.item?Math.max(sensors.item.gpu,sensors.item.vramUsed/Math.max(1,sensors.item.vramTotal)*100):0;vtext:sensors.item?Math.round(sensors.item.gpu)+" %":"—";extra:sensors.item?Math.round(sensors.item.gpuTemp)+" °C · "+(sensors.item.vramUsed/1073741824).toFixed(1)+"/"+(sensors.item.vramTotal/1073741824).toFixed(1)+" GB":"";extraColor:sensors.item&&sensors.item.gpuTemp>=85?"#e2604f":(sensors.item&&sensors.item.gpuTemp>=75?"#e6a850":canvas.ink2);acc:canvas.acc;ink:canvas.ink;ink2:canvas.ink2;ink3:canvas.ink3 }
                HudRow { label:"RAM";sub:sensors.item?Math.round(sensors.item.ramTotal/1073741824)+" GB":"";pct:sensors.item?sensors.item.ramUsed/Math.max(1,sensors.item.ramTotal)*100:0;vtext:sensors.item?(sensors.item.ramUsed/1073741824).toFixed(1):"—";extra:sensors.item?"/ "+(sensors.item.ramTotal/1073741824).toFixed(1)+" GB":"";acc:canvas.acc;ink:canvas.ink;ink2:canvas.ink2;ink3:canvas.ink3 }
                Repeater { model:api.system.disks&&api.system.disks.length?api.system.disks:(api.system.disk?[api.system.disk]:[])
                    HudRow { required property var modelData;label:modelData.label||"DISCO";sub:modelData.fs||(!modelData.available?"no conectado":"");pct:modelData.total?modelData.used/modelData.total*100:0;vtext:modelData.total?Math.round(modelData.used/1073741824)+"":"—";extra:modelData.total?"/ "+Math.round(modelData.total/1073741824)+" GB":"";acc:canvas.acc;ink:canvas.ink;ink2:canvas.ink2;ink3:canvas.ink3 }
                }
                HudRow { visible:!!api.system.bat;height:visible?42:0;charge:true;label:"BATERÍA";sub:api.system.ac?"enchufado":"con batería";pct:api.system.bat?api.system.bat.pct:0;vtext:api.system.bat?api.system.bat.pct+" %":"—";extra:"";acc:canvas.acc;ink:canvas.ink;ink2:canvas.ink2;ink3:canvas.ink3 }
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
        Waves { x:0;y:canvas.height-360;width:1920;height:360;active:true;playing:api.audioActive||(music.item?music.item.playing:false);real:api.audioAvailable;bands:api.audioBands;color:canvas.acc;visibleOnScreen:!api.covered&&!api.gameRunning&&!shell.menuOpen&&shell.runningGame===null }
        // Selección de la estantería. Antes era un ListView invisible SIN delegate: su contador era 0 y
        // incrementCurrentIndex()/decrementCurrentIndex() no hacían nada (ni teclado ni mando movían la selección).
        QtObject { id:list; property int currentIndex:0
            function incrementCurrentIndex() { currentIndex = Math.max(0, Math.min(shell.visibleGames.length - 1, currentIndex + 1)) }
            function decrementCurrentIndex() { currentIndex = Math.max(0, currentIndex - 1) } }

        // Los clics izquierdos en el fondo devuelven el teclado a la estantería.
        // El clic derecho queda libre para el menú contextual nativo del applet Plasma.
        MouseArea { anchors.fill:parent;z:-1;acceptedButtons:Qt.LeftButton
            onPressed:function(m){if(shell.controllerOwner)shell.forceActiveFocus();m.accepted=false} }
        // salida de audio: lista de dispositivos; A elige, B cierra
        Item { anchors.fill:parent; z:31; visible:opacity>0.01; opacity:shell.audOpen?1:0
            Behavior on opacity { NumberAnimation { duration:140 } }
            MouseArea { anchors.fill:parent; acceptedButtons:Qt.AllButtons; onClicked:shell.audOpen=false }
            Rectangle { x:Math.min(1920-width-20, header.x+audBtn.x+audBtn.width+10-width/2+40); y:100
                width:520; height:shell.audItems.length*54+70; radius:20; color:"#ff141a23"; border.width:1; border.color:"#637d99"
                scale:shell.audOpen?1:0.94; transformOrigin:Item.TopRight
                Behavior on scale { NumberAnimation { duration:160; easing.type:Easing.OutCubic } }
                MouseArea { anchors.fill:parent; acceptedButtons:Qt.AllButtons }
                Text { x:24; y:16; text:"SALIDA DE AUDIO"; color:canvas.acc; font.family:canvas.hud; font.pixelSize:15; font.letterSpacing:3; font.weight:Font.DemiBold }
                Column { x:12; y:50; width:parent.width-24
                    Repeater { model:shell.audItems
                        delegate: Rectangle { id:ait; required property var modelData; required property int index
                            readonly property bool foc:shell.audIdx===index
                            readonly property bool isCurrent:!!modelData.current
                            width:parent.width; height:54; radius:14
                            color:foc?canvas.acc:(isCurrent?Qt.rgba(canvas.acc.r,canvas.acc.g,canvas.acc.b,0.16):(am.containsMouse?"#1fffffff":"transparent"))
                            border.width:isCurrent&&!foc?1:0; border.color:canvas.acc
                            Kirigami.Icon { x:16; anchors.verticalCenter:parent.verticalCenter; width:24; height:24; isMask:true
                                source:ait.modelData.kind==="hdmi"?"video-display-symbolic":(ait.modelData.kind==="usb"?"audio-headphones-symbolic":(ait.modelData.kind==="bt"?"bluetooth-symbolic":"audio-speakers-symbolic"))
                                color:ait.foc?"#10150f":"#f3efe3" }
                            Text { x:58; width:parent.width-120; elide:Text.ElideRight; anchors.verticalCenter:parent.verticalCenter; text:ait.modelData.label
                                color:ait.foc?"#10150f":"#f3efe3"; font.family:canvas.body; font.pixelSize:19; font.weight:Font.Medium }
                            Text { visible:ait.isCurrent; anchors.right:parent.right; anchors.rightMargin:18; anchors.verticalCenter:parent.verticalCenter; text:"✓"
                                color:ait.foc?"#10150f":canvas.acc; font.family:canvas.hud; font.pixelSize:24; font.weight:Font.Bold }
                            MouseArea { id:am; anchors.fill:parent; hoverEnabled:true; cursorShape:Qt.PointingHandCursor; onEntered:shell.audIdx=ait.index; onClicked:shell.audActivate(ait.index) }
                        } }
                }
            }
        }
        // teclado virtual: SOLO cuando el buscador se abre con el mando
        Rectangle { id:padKb; visible:opacity>0.01; opacity:shell.searchOpen&&shell.searchPad?1:0
            Behavior on opacity { NumberAnimation { duration:180 } }
            x:(1920-width)/2; y:104; z:8; width:1040; height:kbCol.implicitHeight+40; radius:28; color:"#fa141a23"; border.width:1; border.color:"#637d99"
            MouseArea { anchors.fill:parent; acceptedButtons:Qt.AllButtons }
            Column { id:kbCol; anchors { top:parent.top; topMargin:20; horizontalCenter:parent.horizontalCenter } width:parent.width-48; spacing:8
                Repeater { model:shell.oskRows
                    delegate: Row { id:kbRow; required property var modelData; required property int index
                        anchors.horizontalCenter:parent.horizontalCenter; spacing:8
                        readonly property real tot:{let t=0;for(let q=0;q<modelData.length;q++)t+=modelData[q].w;return t}
                        readonly property real unit:(kbCol.width-spacing*(modelData.length-1))/tot
                        Repeater { model:kbRow.modelData
                            delegate: Rectangle { id:kk; required property var modelData; required property int index
                                readonly property bool foc:shell.oskR===kbRow.index&&shell.oskC===index
                                width:kbRow.unit*modelData.w; height:58; radius:14
                                color:foc?canvas.acc:(modelData.k==="shift"&&shell.oskShift?"#5991a9c2":"#1affffff")
                                border.width:foc?0:1; border.color:"#3391a9c2"; scale:foc?1.06:1
                                Behavior on scale { NumberAnimation { duration:100 } }
                                Text { anchors.centerIn:parent; text:kk.modelData.t; color:kk.foc?"#14211a":"#f3efe3"; font.family:canvas.hud; font.weight:Font.DemiBold; font.pixelSize:kk.modelData.k==="ch"?24:17 }
                                MouseArea { anchors.fill:parent; cursorShape:Qt.PointingHandCursor; onClicked:{shell.oskR=kbRow.index;shell.oskC=kk.index;shell.oskPress()} }
                            } }
                    } }
                Row { anchors.horizontalCenter:parent.horizontalCenter; spacing:28
                    Repeater { model:[["A","Escribir"],["B","Borrar"],["X","Mayús"],["Y","Espacio"]]
                        delegate: Row { required property var modelData; spacing:8
                            Rectangle { width:32; height:32; radius:16; color:"transparent"; border.width:1; border.color:"#8091a9c2"
                                Text { anchors.centerIn:parent; text:parent.parent.modelData[0]; color:canvas.brand; font.family:canvas.hud; font.bold:true; font.pixelSize:14 } }
                            Text { anchors.verticalCenter:parent.verticalCenter; text:modelData[1].toUpperCase(); color:"#b3f3efe3"; font.family:canvas.hud; font.weight:Font.DemiBold; font.pixelSize:15; font.letterSpacing:2 }
                        } }
                }
            }
        }
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
                color:"#ff141a23";border.width:1;border.color:"#637d99"
                MouseArea { anchors.fill:parent;acceptedButtons:Qt.AllButtons }
                Column { x:12;y:14;width:parent.width-24
                    Repeater { model:shell.contextItems;delegate:Rectangle { required property var modelData;required property int index;height:50;width:parent.width;radius:14
                        color:index===shell.contextIndex?canvas.acc:(hover.containsMouse?"#1fffffff":"transparent")
                        Kirigami.Icon { x:16;anchors.verticalCenter:parent.verticalCenter;width:22;height:22;source:modelData.icon;isMask:true;color:index===shell.contextIndex?"#10150f":canvas.ink }
                        Text { x:56;anchors.verticalCenter:parent.verticalCenter;text:modelData.label;color:index===shell.contextIndex?"#10150f":canvas.ink;font.family:canvas.body;font.pixelSize:18 }
                        MouseArea { cursorShape: Qt.PointingHandCursor; id:hover;anchors.fill:parent;hoverEnabled:true;onEntered:shell.contextIndex=index;onClicked:shell.activateContext(index) }
                    } }
                }
            }
        }
        Dialog {
            id: unlinkDialog
            property var game: null
            anchors.centerIn: Overlay.overlay
            modal: true
            title: "Desvincular juego de Omnia"
            standardButtons: Dialog.Cancel | Dialog.Yes
            contentItem: Label {
                text: unlinkDialog.game
                    ? "Se quitará «" + unlinkDialog.game.name + "» de tu biblioteca y de los datos de Omnia asociados. Sus archivos no se borrarán. Si Omnia lo detectó desde un launcher, no volverá a aparecer mientras siga instalado."
                    : "Se quitará el juego de la biblioteca de Omnia."
                wrapMode: Text.WordWrap
                color: canvas.ink
                font.pixelSize: 16
                padding: 16
            }
            onAccepted: {
                if (!game) return
                const target = game
                shell.api.removeGame(target, function(status, body) {
                    if (status === 200) {
                        if (shell.selectedId === target.id) shell.selectedId = ""
                        shell.api.toast = "«" + target.name + "» se quitó de Omnia. Sus archivos siguen en el disco."
                    } else shell.api.toast = (body && body.error) || "No se pudo desvincular el juego."
                })
                game = null
            }
            onRejected: game = null
        }
        Item { id:artLayer; anchors.fill:parent; z:45; visible:shell.artOpen
            Rectangle { anchors.fill:parent; color:"#eb050806" }
            MouseArea { anchors.fill:parent; acceptedButtons:Qt.AllButtons; onClicked:shell.closeArt() }
            Rectangle { id:artPanel; x:360;y:120;width:1200;height:840;radius:24;color:"#ff141a23";border.width:1;border.color:"#637d99" }
            MouseArea { x:artPanel.x;y:artPanel.y;width:artPanel.width;height:artPanel.height;acceptedButtons:Qt.AllButtons }
            Text { x:392;y:142;text:"ELEGIR ARTE · " + (shell.current ? shell.current.name.toUpperCase() : "");color:canvas.brand;font.family:canvas.hud;font.pixelSize:19;font.letterSpacing:2.5;font.weight:Font.DemiBold }
            Row { x:392;y:178;spacing:10
                Repeater { model:shell.artKinds
                    delegate:Rectangle { required property string modelData;readonly property bool active:shell.artKind===modelData
                        height:36;width:kindText.implicitWidth+32;radius:18;color:active?canvas.brand:"#25303d"
                        Text { id:kindText;anchors.centerIn:parent;text:parent.modelData==="portada"?"Portada":(parent.modelData==="fondo"?"Fondo":"Logo");color:parent.active?"#111923":canvas.ink;font.family:canvas.body;font.pixelSize:16;font.weight:Font.DemiBold }
                        MouseArea { cursorShape: Qt.PointingHandCursor; anchors.fill:parent;onClicked:shell.setArtKind(modelData) }
                    }
                }
            }
            Row { anchors.right:artPanel.right;anchors.rightMargin:32;y:176;spacing:8;height:36
                Rectangle { visible:shell.artGames.length>1;width:34;height:34;radius:17;color:"#25303d"
                    Text { anchors.centerIn:parent;text:"‹";color:canvas.ink;font.pixelSize:22 }
                    MouseArea { cursorShape: Qt.PointingHandCursor; anchors.fill:parent;onClicked:shell.stepArtEdition(-1) }
                }
                Text { width:360;anchors.verticalCenter:parent.verticalCenter;horizontalAlignment:Text.AlignRight;elide:Text.ElideMiddle;color:canvas.ink2;font.family:canvas.body;font.pixelSize:15
                    text:{for(let i=0;i<shell.artGames.length;i++)if(shell.artGames[i].id===shell.artSgid)return shell.artGames[i].name+(shell.artGames[i].year?" ("+shell.artGames[i].year+")":"")+" · "+(i+1)+"/"+shell.artGames.length;return ""}
                }
                Rectangle { visible:shell.artGames.length>1;width:34;height:34;radius:17;color:"#25303d"
                    Text { anchors.centerIn:parent;text:"›";color:canvas.ink;font.pixelSize:22 }
                    MouseArea { cursorShape: Qt.PointingHandCursor; anchors.fill:parent;onClicked:shell.stepArtEdition(1) }
                }
            }
            GridView { id:artGrid;x:384;y:220;width:1152;height:400;clip:true;boundsBehavior:Flickable.StopAtBounds
                cellWidth:Math.floor(width/shell.artColumns)
                cellHeight:shell.artKind==="portada"?cellWidth*1.20:(shell.artKind==="fondo"?cellWidth*.40:cellWidth*.56)
                model:shell.artItems;currentIndex:shell.artIndex
                onAtYEndChanged:if(atYEnd&&shell.artMore&&!shell.artBusy)shell.loadArt(shell.artPage+1)
                Connections { target:shell; function onArtIndexChanged() { if (shell.artItems.length) artGrid.positionViewAtIndex(shell.artIndex, GridView.Contain) } }
                delegate:Item { id:artTile;required property var modelData;required property int index;width:artGrid.cellWidth;height:artGrid.cellHeight
                    readonly property bool focused:shell.artIndex===index
                    Rectangle { anchors.fill:parent;anchors.margins:2;radius:13;color:"transparent";border.width:focused?2:0;border.color:canvas.brand }
                    Rectangle { anchors.fill:parent;anchors.margins:6;radius:11;color:"#202833";clip:true
                        Image { anchors.fill:parent;anchors.margins:shell.artKind==="logo"?18:0;source:artTile.modelData.thumb;asynchronous:true;smooth:true
                            fillMode:shell.artKind==="logo"?Image.PreserveAspectFit:Image.PreserveAspectCrop;opacity:status===Image.Ready?1:0
                            Behavior on opacity { NumberAnimation { duration:150 } }
                        }
                        Rectangle { anchors.fill:parent;radius:11;color:"transparent";border.width:artTile.focused?3:(artTile.modelData.cur||shell.artPending[shell.artKind]&&shell.artPending[shell.artKind].url===artTile.modelData.url?2:1);border.color:artTile.focused?canvas.brand:(shell.artPending[shell.artKind]&&shell.artPending[shell.artKind].url===artTile.modelData.url?canvas.brand:(artTile.modelData.cur?"#7fd99a":"#394656")) }
                        Rectangle { visible:artTile.modelData.cur===true;anchors.left:parent.left;anchors.top:parent.top;anchors.margins:8;height:22;radius:11;color:"#7fd99a";width:usedText.implicitWidth+16
                            Text { id:usedText;anchors.centerIn:parent;text:"✓ EN USO";color:"#0c1a10";font.family:canvas.hud;font.pixelSize:11;font.weight:Font.Bold;font.letterSpacing:.5 }
                        }
                        Rectangle { visible:shell.artPending[shell.artKind]&&shell.artPending[shell.artKind].url===artTile.modelData.url;anchors.right:parent.right;anchors.top:parent.top;anchors.margins:8;height:22;radius:11;color:canvas.brand;width:selText.implicitWidth+16
                            Text { id:selText;anchors.centerIn:parent;text:"SELECCIONADO";color:"#111923";font.family:canvas.hud;font.pixelSize:10;font.weight:Font.Bold }
                        }
                        Rectangle { anchors.left:parent.left;anchors.bottom:parent.bottom;anchors.margins:7;height:20;radius:10;color:"#d0000000";width:sizeText.implicitWidth+12
                            Text { id:sizeText;anchors.centerIn:parent;text:artTile.modelData.w+"×"+artTile.modelData.h+(artTile.modelData.by?" · "+artTile.modelData.by:"");color:canvas.ink;font.family:canvas.hud;font.pixelSize:10 }
                        }
                        MouseArea { cursorShape: Qt.PointingHandCursor; anchors.fill:parent;hoverEnabled:true;onEntered:shell.artIndex=artTile.index;onClicked:shell.pickArt(artTile.index) }
                    }
                }
            }
            Text { x:artGrid.x;y:artGrid.y+artGrid.height/2-14;width:artGrid.width;horizontalAlignment:Text.AlignHCenter;visible:shell.artItems.length===0;text:shell.artBusy?"Buscando en SteamGridDB…":(shell.artError||"Sin resultados para este juego");color:canvas.ink2;font.family:canvas.body;font.pixelSize:18 }
            Rectangle { x:384;y:640;width:1152;height:108;radius:16;color:"#202833";border.width:1;border.color:"#394656"
                Text { x:18;y:8;text:"PREVISUALIZACIÓN ACTUAL / SELECCIONADA";color:canvas.brand;font.family:canvas.hud;font.pixelSize:12;font.letterSpacing:1.4;font.weight:Font.DemiBold }
                Row { x:18;y:29;spacing:14
                    Repeater { model:["portada","fondo","logo"]
                        delegate:Item { required property string modelData;width:365;height:72
                            Rectangle { anchors.fill:parent;radius:9;color:"#141a22";border.width:1;border.color:shell.artPending[modelData]?canvas.brand:"#303b49"
                                Image { anchors.left:parent.left;anchors.top:parent.top;anchors.bottom:parent.bottom;width:modelData==="portada"?50:102;anchors.margins:4;source:shell.previewArt(modelData);fillMode:modelData==="logo"?Image.PreserveAspectFit:Image.PreserveAspectCrop;asynchronous:true;smooth:true }
                                Text { anchors.left:parent.left;anchors.leftMargin:modelData==="portada"?64:116;anchors.verticalCenter:parent.verticalCenter;text:(modelData==="portada"?"PORTADA":modelData.toUpperCase())+" · "+(shell.artPending[modelData]?"NUEVA":"ACTUAL");color:shell.artPending[modelData]?canvas.brand:canvas.ink3;font.family:canvas.hud;font.pixelSize:12;font.weight:Font.DemiBold;elide:Text.ElideRight }
                            }
                        }
                    }
                }
            }
            Text { x:384;y:770;text:api.padOn?"A elige · LB/RB tipo · LT/RT edición · Start aceptar · B cancelar":"Clic: seleccionar · Tab: tipo · Re Pág/Av Pág: edición · Ctrl+Intro: aceptar";color:canvas.ink3;font.family:canvas.body;font.pixelSize:12;verticalAlignment:Text.AlignVCenter }
            Rectangle { x:artPanel.x+artPanel.width-300;y:766;width:130;height:42;radius:21;color:"#283342";opacity:shell.artApplying?0.55:1
                Text { anchors.centerIn:parent;text:"Cancelar";color:canvas.ink;font.family:canvas.body;font.pixelSize:15 }
                MouseArea { anchors.fill:parent;enabled:!shell.artApplying;cursorShape:Qt.PointingHandCursor;onClicked:shell.closeArt() }
            }
            Rectangle { x:artPanel.x+artPanel.width-160;y:766;width:160;height:42;radius:21;color:shell.artPending.portada||shell.artPending.fondo||shell.artPending.logo?canvas.brand:"#303846";opacity:shell.artApplying?0.55:1
                Text { anchors.centerIn:parent;text:shell.artApplying?"Aplicando…":"Aceptar cambios";color:shell.artPending.portada||shell.artPending.fondo||shell.artPending.logo?"#111923":canvas.ink3;font.family:canvas.body;font.pixelSize:15;font.weight:Font.DemiBold }
                MouseArea { anchors.fill:parent;enabled:!shell.artApplying&&!!(shell.artPending.portada||shell.artPending.fondo||shell.artPending.logo);cursorShape:Qt.PointingHandCursor;onClicked:shell.acceptArt() }
            }
            Rectangle { x:1520;y:138;width:32;height:32;radius:16;color:"#25303d"
                Text { anchors.centerIn:parent;text:"×";color:canvas.ink;font.pixelSize:20 }
                MouseArea { cursorShape: Qt.PointingHandCursor; anchors.fill:parent;enabled:!shell.artApplying;onClicked:shell.closeArt() }
            }
        }
    }

    // aviso temporal: se muestra al actuar (p. ej. «Biblioteca actualizada») y se desvanece solo (ver Api.notify)
    Rectangle { visible:api.toast!==""; opacity:api.toastLevel; x:shell.toastX(width); y:shell.toastY(height)
        width:toastText.implicitWidth+28; height:toastText.implicitHeight+14; radius:height/2; color:"#b3000000"
        Text { id:toastText; anchors.centerIn:parent; text:api.toast; color:canvas.brand; font.family:"Rajdhani"; font.pixelSize:16; font.weight:Font.DemiBold } }
}

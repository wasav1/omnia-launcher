import QtQuick
import QtQuick.Controls

// Estantería a escala lógica 1920x1080, fiel al lienzo del prototipo.
Rectangle {
    id: shell
    color: externalWallpaper ? "transparent" : "#0b0d0c"
    focus: true
    clip: true

    property int bottomInset: 0
    property bool menuOpen: false
    property bool portPickerOpen: false
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

    readonly property real scaleFactor: sectionMode === "full" ? Math.min(width / 1920, height / 1080)
                                                              : Math.min(width / sectionViewport.width, height / sectionViewport.height)
    readonly property var filterOptions: {
        const out = [{ key: "all", label: qsTr("Todos") }]
        let fav = false, hidden = false
        for (let i = 0; i < api.games.length; i++) {
            const g = api.games[i]
            if (g.fav) fav = true
            if (g.hidden) hidden = true
        }
        if (fav) out.push({ key: "fav", label: qsTr("Favoritos") })
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
        if (hidden) out.push({ key: "hidden", label: qsTr("Ocultos") })
        return out
    }
    readonly property var visibleGames: filteredAndSorted()
    readonly property var current: (visibleGames.length && list.currentIndex >= 0 && list.currentIndex < visibleGames.length) ? visibleGames[list.currentIndex] : null
    // El modelo conserva el orden real de la biblioteca. Así las tarjetas mantienen su arte
    // asociado al juego mientras la pista se desplaza para alinear la selección a la izquierda.
    readonly property var carouselGames: visibleGames
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
            { label: qsTr("Jugar"), icon: "play" },
            { label: qsTr("Respaldar partidas"), icon: "download" },
            { label: qsTr("Abrir carpeta"), icon: "folder-open" },
            { label: qsTr("Elegir arte del catálogo Omnia…"), icon: "image-plus" },
            { label: current.fav ? qsTr("Quitar de favoritos") : qsTr("Añadir a favoritos"), icon: "star" },
            { label: current.hidden ? qsTr("Mostrar juego") : qsTr("Ocultar juego"), icon: current.hidden ? "eye" : "eye-off" }
        ]
        items.push({ label: qsTr("Desvincular de Omnia…"), icon: "trash-2" })
        if (searchText !== "") items.push({ label: qsTr("Borrar filtro de búsqueda"), icon: "x" })
        return items
    }

    function norm(s) { return (s || "").toString().toLocaleLowerCase() }
    function platformLabel(g) {
        const p = norm(g.platform || "")
        const names = {n64: qsTr("Nintendo 64"), nes: qsTr("Nintendo Entertainment System"), snes: qsTr("Super Nintendo"),
            gb: qsTr("Game Boy"), gbc: qsTr("Game Boy Color"), gba: qsTr("Game Boy Advance"), nds: qsTr("Nintendo DS"),
            gcwii: qsTr("GameCube / Wii"), "3ds": qsTr("Nintendo 3DS"), switch: qsTr("Nintendo Switch"),
            ps1: qsTr("PlayStation"), ps2: qsTr("PlayStation 2"), psp: qsTr("PlayStation Portable"),
            sw1: qsTr("Nintendo Switch"), sw2: qsTr("Nintendo Switch 2")}
        if (names[p]) return names[p]
        if (p === "pc") return "PC"
        return g.platform || g.src || qsTr("Juegos")
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
    function requestPlay() {
        if (!current || !current.ports || !current.ports.length) return
        if (current.ports.length > 1 && sectionMode === "full") {
            portPickerOpen = true
        } else launchCurrent()
    }
    function choosePlayPort(index) {
        if (!current || !current.ports || index < 0 || index >= current.ports.length) return
        selectPort(index)
        portPickerOpen = false
        Qt.callLater(function() { shell.launchCurrent() })
    }
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
                shell.saveInfo = st === 200 ? body : { slots: [], error: body.error || qsTr("No se pudieron consultar las partidas (%1)").arg(st) }
            }, pid)
        })
    }
    function launchCurrent() { if (current && selectedPort) api.launch(current, selectedPort.id) }
    function backupCurrent() {
        if (!current || !selectedPort) return
        api.savesBackup(current, function(st,b) {
            api.notify(st === 200 ? qsTr("Respaldo creado") : (b.error || qsTr("No se pudo respaldar")))
            saveFor = ""; loadSaves(); api.refresh()
        }, selectedPort.id)
    }
    function openSaveFolder() { if (current && selectedPort) api.savesOpen(current, function(st,b) { if (st !== 200) api.notify(b.error || qsTr("No se pudo abrir la carpeta")) }, selectedPort.id) }
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
            if (st !== 200) { shell.artError = body.error || qsTr("No se pudo consultar el catálogo de Omnia"); if (page === 0) shell.artItems = []; return }
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
                api.notify(qsTr("No se pudo terminar; el arte aplicado hasta ahora se conservó. %1").arg(body.error || qsTr("Inténtalo de nuevo.")))
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
    function showContext(x, y) { if (!current || api.gameRunning) return; contextPoint = Qt.point(x, y); contextIndex = 0; contextOpen = true; restoreControllerFocus() }
    function activateContext(i) {
        contextOpen = false
        if (i === 0) requestPlay()
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
        if (!ts) return qsTr("Nunca")
        const d = new Date(ts * 1000), now = new Date(nowSecs * 1000), fmt = Qt.locale(api.language === "en" ? "en_US" : "es_CO")
        const hm = (d.getHours() < 10 ? "0" : "") + d.getHours() + ":" + (d.getMinutes() < 10 ? "0" : "") + d.getMinutes()
        const start = new Date(now.getFullYear(), now.getMonth(), now.getDate()).getTime()
        if (d.getTime() >= start) return qsTr("Hoy") + ", " + hm
        if (d.getTime() >= start - 86400000) return qsTr("Ayer") + ", " + hm
        return d.toLocaleDateString(fmt, "d MMM")
    }
    function duration(s) {
        const m = Math.floor((s || 0) / 60), h = Math.floor(m / 60)
        return h ? qsTr("%1 hr %2 min").arg(h).arg(m % 60) : qsTr("%1 min").arg(Math.max(1,m))
    }
    function thermalColor(celsius) {
        if (celsius >= 85) return "#e7837d"
        if (celsius >= 70) return "#e6b866"
        return canvas.ink2
    }
    function clockDate(d) { return d.toLocaleDateString(Qt.locale(api.language === "en" ? "en_US" : "es_CO"), api.language === "en" ? "dddd, MMMM d" : "dddd d 'de' MMMM").toUpperCase() }
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
        if (portPickerOpen && !current) portPickerOpen = false
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
    // El reloj siempre sigue la hora de pared del sistema, incluso cuando el escritorio cubre Omnia.
    Timer { interval: 250; running: true; repeat: true; onTriggered: shell.nowSecs = Date.now()/1000 }
    Component.onCompleted: {
        if (controllerOwner) forceActiveFocus()
        if (visibleGames.length) list.currentIndex = 0
        if (externalWallpaper && !controllerOwner) followSelection()
    }

    Connections {
        target: api
        function onPadKey(key) {
            if (!shell.controllerOwner) return
            if (unlinkDialog.opened) {
                const cancel = unlinkDialog.standardButton(Dialog.Cancel)
                const confirm = unlinkDialog.standardButton(Dialog.Yes)
                if (key === "B" || key === "SELECT") unlinkDialog.reject()
                else if (key === "l" || key === "r" || key === "u" || key === "d")
                    (confirm.activeFocus ? cancel : confirm).forceActiveFocus()
                else if (key === "A") {
                    if (confirm.activeFocus) unlinkDialog.accept()
                    else unlinkDialog.reject()
                }
                return
            }
            if (shell.portPickerOpen) {
                if (key === "B" || key === "SELECT") shell.portPickerOpen = false
                return
            }
            if ((key === "MENU" || key === "START") && !shell.artOpen) {
                if (shell.audOpen) { shell.audOpen = false; return }
                if (shell.searchOpen && shell.searchPad) { shell.closeSearch(false); return }     // Start = BUSCAR
                shell.openSearchPad(); return
            }
            if (key === "MENU_POWER") return
            if (shell.menuOpen) return
            if (runLayer.visible || (shell.sectionMode === "full" && api.gameRunning)) return // el juego deja visible solo su portada
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
        if (portPickerOpen) {
            if (e.key === Qt.Key_Escape) portPickerOpen = false
            e.accepted = true; return
        }
        if (runLayer.visible || (sectionMode === "full" && api.gameRunning)) { // el juego deja visible solo su portada
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
            else if (d === "u") goZone("hero", 0)
        } else if (focusZone === "hero") {
            if (d === "l" || d === "r") focusIndex = 0
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
            else if (d === "d") { if (hasMusic) goZone("player", 1); else goZone("hero", 0) }
        }
    }
    function enter() {
        if (focusZone === "shelf") goZone("hero", 0)
        else if (focusZone === "hero") requestPlay()
        else if (focusZone === "player") { if (music.item) { if (focusIndex === 0) music.item.previous(); else if (focusIndex === 1) music.item.playPause(); else music.item.next() } }
        else activateHead(focusIndex)
    }
    function back() { if (focusZone !== "shelf") goZone("shelf", 0) }
    // ---- salida de audio: lista de dispositivos; A elige, B cierra
    function audShow() {
        api.loadAudioOutputs(function(items, err) {
            if (!items.length) { api.notify(err || qsTr("No se pudieron leer los dispositivos de audio")); return }
            audItems = items
            audIdx = Math.max(0, items.findIndex(function(x) { return x.current }))
            audOpen = true
        })
    }
    function audActivate(i) {
        const it = audItems[i]
        audOpen = false
        if (!it) return
        api.setAudioOutput(it, function(ok) { api.notify(ok ? qsTr("Audio: %1").arg(it.label) : qsTr("No se pudo cambiar la salida de audio")) })
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

    // Telón de arte desenfocado y película del juego seleccionado.
    Backdrop { anchors.fill: parent; visible: !shell.externalWallpaper; covered: api.covered; source: shell.current && shell.current.fondo ? shell.current.fondo : ""; blur: 18 }
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
        opacity: shell.portPickerOpen || api.gameRunning ? 0 : 1
        Behavior on opacity { NumberAnimation { duration:360; easing.type:Easing.OutCubic } }
        property color brand: api.themeAccent
        property color brandLight: Qt.lighter(brand, 1.35)
        property color brandHover: Qt.lighter(brand, 1.5)
        property color brandInk: brand.hslLightness > 0.55 ? "#10150f" : "#f3f6fa"
        property color acc: brand
        property color ink: "#f3efe3"
        property color ink2: "#d6d0bf"
        property color ink3: "#9aa9bc"
        property string hud: "Rajdhani"
        property string body: "Hanken Grotesk"

        Item {
            id: contextScene
            anchors.fill: parent

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
                    color: active ? canvas.brand : "#59000000"; border.width: active ? 0 : 1; border.color: "#47f3efe3"
                    // Icono y texto centrados en vertical: el icono por su caja y el texto por la ALTURA DE MAYÚSCULA medida
                    // (la caja de línea de Rajdhani no está centrada ópticamente y el texto se veía más abajo que el icono).
                    TextMetrics { id: capMetrics; font: pillText.font; text: "H" }
                    Row { id: label; anchors.horizontalCenter: parent.horizontalCenter; height: parent.height; spacing: 7
                        PlatIcon { visible: modelData.key !== "all" && modelData.key !== "fav" && modelData.key !== "hidden"; key: modelData.key; size: 17; color: active ? canvas.brandInk : shell.platformColor(modelData.key); anchors.verticalCenter: parent.verticalCenter }
                        LucideIcon { visible: modelData.key === "fav" || modelData.key === "hidden"; name: modelData.key === "fav" ? "star" : "eye-off"; width: 17; height: 17; color: active ? canvas.brandInk : shell.platformColor(modelData.key); anchors.verticalCenter: parent.verticalCenter }
                        Text { id: pillText; text: modelData.label; color: active ? canvas.brandInk : shell.platformColor(modelData.key); font.family: canvas.hud; font.pixelSize: 17; font.weight: Font.DemiBold; font.letterSpacing: 1
                            y: Math.round(parent.height / 2 - (baselineOffset + capMetrics.tightBoundingRect.y + capMetrics.tightBoundingRect.height / 2)) }
                    }
                    Rectangle { visible: shell.focusZone === "head" && shell.focusIndex === index; anchors.fill: parent; anchors.margins: -4; radius: 22; color: "transparent"; border.width: 3; border.color: canvas.acc }
                    MouseArea { cursorShape: Qt.PointingHandCursor; anchors.fill: parent; onClicked: shell.chooseFilter(modelData.key) }
                }
            }
            Rectangle {
                id: searchBtn
                width: 34; height: 34; radius: 17; color: searchOpen ? canvas.acc : (sbm.containsMouse ? "#33ffffff" : "#59000000"); border.width: searchOpen ? 0 : 1; border.color: "#47f3efe3"
                LucideIcon { anchors.centerIn: parent; width: 18; height: 18; name: "search"; color: searchOpen ? canvas.brandInk : "#f3efe3" }
                Rectangle { visible: shell.focusZone === "head" && shell.focusIndex === shell.filterOptions.length; anchors.fill: parent; anchors.margins: -4; radius: height / 2; color: "transparent"; border.width: 3; border.color: canvas.acc }
                MouseArea { id: sbm; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: shell.setSearchOpen(!searchOpen) }
            }
            Rectangle { id: refreshBtn; width: 34; height: 34; radius: 17; color: shell.refreshBusy ? canvas.acc : rfm.containsMouse ? "#33ffffff" : "#59000000"; border.width: shell.refreshBusy ? 0 : 1; border.color: "#47f3efe3"
                LucideIcon { anchors.centerIn: parent; width: 18; height: 18; name: "refresh-cw"; color: shell.refreshBusy ? canvas.brandInk : "#f3efe3" }
                Rectangle { visible: shell.focusZone === "head" && shell.focusIndex === shell.filterOptions.length + 1; anchors.fill: parent; anchors.margins: -4; radius: height / 2; color: "transparent"; border.width: 3; border.color: canvas.acc }
                MouseArea { id: rfm; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: shell.refreshLibrary() }
            }
            Rectangle { width: 34; height: 34; radius: 17; color: settingsMouse.containsMouse ? "#33ffffff" : "#59000000"; border.width: 1; border.color: "#47f3efe3"
                LucideIcon { anchors.centerIn: parent; width: 18; height: 18; name: "settings"; color: "#f3efe3" }
                Rectangle { visible: shell.focusZone === "head" && shell.focusIndex === shell.filterOptions.length + 2; anchors.fill: parent; anchors.margins: -4; radius: height / 2; color: "transparent"; border.width: 3; border.color: canvas.acc }
                MouseArea { id: settingsMouse; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: shell.openSettings() }
                ToolTip.visible: settingsMouse.containsMouse
                ToolTip.text: qsTr("Ajustes generales de Omnia")
            }
            Rectangle { id: audBtn; visible: api.padOn; width: 34; height: 34; radius: 17; color: shell.audOpen ? canvas.acc : aum.containsMouse ? "#33ffffff" : "#59000000"; border.width: shell.audOpen ? 0 : 1; border.color: "#47f3efe3"
                LucideIcon { anchors.centerIn: parent; width: 18; height: 18; name: "speaker"; color: shell.audOpen ? canvas.brandInk : "#f3efe3" }
                Rectangle { visible: shell.focusZone === "head" && shell.focusIndex === shell.filterOptions.length + 3; anchors.fill: parent; anchors.margins: -4; radius: height / 2; color: "transparent"; border.width: 3; border.color: canvas.acc }
                MouseArea { id: aum; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: shell.audShow() }
            }
        }
        // Mando y guía sobre la tarjeta activa.
        PadGuide {
            x: 84; y: 160; width: 430; height: 52
            visible: api.padOn && shell.sectionMode === "full"
            padName: api.padName; iconSize: 17; fontPx: 12; spacing: 7
            textColor: canvas.ink2; fontFamily: canvas.hud
            hints: [{k:"↑",t:qsTr("Jugar")},{k:"A",t:qsTr("Seleccionar")},{k:"B",t:qsTr("Volver")}]
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
            Text { visible: !searchField.text; x: 17; anchors.verticalCenter: parent.verticalCenter; text: qsTr("Buscar juego…"); color: "#80f3efe3"; font.family: canvas.hud; font.pixelSize: 17 }
            Text { anchors.right: parent.right; anchors.rightMargin: 45; anchors.verticalCenter: parent.verticalCenter; text: shell.searchText ? shell.visibleGames.length + (shell.visibleGames.length === 1 ? " juego" : " juegos") : ""; color: "#c9f3efe3"; font.family: canvas.hud; font.pixelSize: 14 }
            LucideIcon { anchors.right: parent.right; anchors.rightMargin: 15; anchors.verticalCenter: parent.verticalCenter; name: "x"; color: canvas.ink; visible: shell.searchText !== ""
                MouseArea { cursorShape: Qt.PointingHandCursor; anchors.fill: parent; anchors.margins: -8; onClicked: shell.searchText = "" }
            }
        }

        // Ficha del juego: icono/origen, estado, logo o título, descripción, chips, ports y Jugar.
        Column {
            id: hero; x: 84; y: 116; width: 650; spacing: 8
            // En la vista completa, la ficha principal vive dentro de la tarjeta activa.
            visible: shell.sectionMode !== "full" || !current
            opacity: api.gameRunning ? 0.12 : 1
            Row { spacing: 10
                PlatIcon { key: shell.platformIcon(current); color: shell.platformColor(current ? current.platform : "pc"); size: 20; anchors.verticalCenter: parent.verticalCenter }
                Text { text: current ? (platformLabel(current) + (current.platform === "pc" && current.src ? " · " + current.src : "")) : "OMNIA"; color: shell.platformColor(current ? current.platform : "pc"); font.family: canvas.hud; font.pixelSize: 20; font.weight: Font.DemiBold; font.letterSpacing: 2; anchors.verticalCenter: parent.verticalCenter }
            }
            Text { visible: !!current; text: current ? (current.plays > 0 ? platformLabel(current).toUpperCase() + " · " + shell.relativeTime(current.lastPlayed).toUpperCase() : platformLabel(current).toUpperCase() + " · SIN JUGAR") : ""; color: canvas.brandLight; font.family: canvas.hud; font.pixelSize: 16; font.letterSpacing: 3 }
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
            Row { visible: false; spacing: 10; height: 36
                Text { text: "PORT"; color: canvas.ink3; font.family: canvas.hud; font.pixelSize: 15; font.letterSpacing: 3; anchors.verticalCenter: parent.verticalCenter }
                Repeater { model: current ? current.ports : []
                    delegate: Rectangle { required property var modelData; required property int index
                        height: 34; width: portName.implicitWidth + 28; radius: 17
                        color: index === selectedPortIndex ? canvas.acc : "#59000000"; border.width: index === selectedPortIndex ? 0 : 1; border.color: "#47f3efe3"
                        Row { id: portName; anchors.centerIn: parent; spacing: 6
                            Rectangle { visible: modelData.running; width: 8; height: 8; radius: 4; color: "#6fd66f"; anchors.verticalCenter: parent.verticalCenter }
                            Text { text: modelData.name; color: index === selectedPortIndex ? canvas.brandInk : canvas.ink; font.family: canvas.hud; font.pixelSize: 18; font.weight: Font.DemiBold; anchors.verticalCenter: parent.verticalCenter }
                        }
                        Rectangle { visible: shell.focusZone === "hero" && shell.focusIndex === index; anchors.fill: parent; anchors.margins: -4; radius: height / 2; color: "transparent"; border.width: 3; border.color: canvas.acc }
                        MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: shell.selectPort(index) }
                    }
                }
            }
            Rectangle {
                id: playButton; height: 48; radius: 24; width: playText.implicitWidth + 52; color: playMouse.containsMouse ? canvas.brandHover : canvas.brandLight
                Row { id: playText; anchors.centerIn: parent; spacing: 10
                    LucideIcon { name: "play"; width: 18; height: 18; color: playButton.color.hslLightness > 0.55 ? "#10150f" : "#f3f6fa"; anchors.verticalCenter: parent.verticalCenter }
                Text { text: qsTr("Jugar"); color: playButton.color.hslLightness > 0.55 ? "#10150f" : "#f3f6fa"; font.family: canvas.body; font.pixelSize: 21; font.weight: Font.DemiBold; anchors.verticalCenter: parent.verticalCenter }
                }
                Rectangle { visible: shell.focusZone === "hero"; anchors.fill: parent; anchors.margins: -5; radius: 29; color: "transparent"; border.width: 3; border.color: canvas.acc }
                MouseArea { id: playMouse; cursorShape: Qt.PointingHandCursor; anchors.fill: parent; hoverEnabled: true; onClicked: shell.requestPlay() }
            }
        }

        // Reloj principal centrado y ampliado.
        Item { id:clock; x:0; y:110; width:1920; height:200; opacity: api.gameRunning ? 0.12 : 1
            Column { anchors.centerIn:parent; spacing:0
                Row { anchors.horizontalCenter:parent.horizontalCenter; spacing:5
                    Text { text: { const d=new Date(shell.nowSecs*1000); return (d.getHours()%12)||12 } color: canvas.ink; font.family: canvas.hud; font.pixelSize: 158; font.weight: Font.DemiBold }
                    Text { text: ":"; color: canvas.ink; font.family: canvas.hud; font.pixelSize: 158; font.weight: Font.DemiBold; opacity: new Date(shell.nowSecs*1000).getSeconds()%2 ? .2 : .85 }
                    Text { text: { const d=new Date(shell.nowSecs*1000); return (d.getMinutes()<10?"0":"")+d.getMinutes() } color: canvas.ink; font.family: canvas.hud; font.pixelSize: 158; font.weight: Font.DemiBold }
                    Text { text: new Date(shell.nowSecs*1000).getHours()<12 ? "AM" : "PM"; color: canvas.acc; font.family: canvas.hud; font.pixelSize: 34; font.weight: Font.DemiBold; font.letterSpacing: 4; anchors.bottom:parent.bottom; anchors.bottomMargin:20 }
                }
                Text { anchors.horizontalCenter:parent.horizontalCenter; text: clockDate(new Date(shell.nowSecs*1000)); color: canvas.ink2; font.family: canvas.hud; font.pixelSize: 21; font.letterSpacing: 3 }
            }
        }
        Rectangle { x: 84; y: 112; height: 36; width: padLabel.implicitWidth + 48; radius: 18; color: "#59000000"; border.width: 1; border.color: api.padOn ? "#80e6d9a0" : "#33f3efe3"
            Row { id: padLabel; anchors.centerIn: parent; spacing: 8
                LucideIcon { width: 20; height: 20; name: "gamepad-2"; color: api.padOn ? canvas.acc : "#80f3efe3"; anchors.verticalCenter: parent.verticalCenter }
                Text { text: api.padOn ? (api.padName || qsTr("Mando conectado")) : qsTr("Sin mando"); color: api.padOn ? canvas.ink : "#80f3efe3"; font.family: canvas.hud; font.pixelSize: 16; font.weight: Font.DemiBold; font.letterSpacing: 1; anchors.verticalCenter: parent.verticalCenter }
            }
        }
        Item { id: mid; x:760; y:236; width:640; height:260; property var g: shell.selectedPort; visible:shell.sectionMode !== "full"; opacity: api.gameRunning ? .12:1
            Column { width: parent.width; spacing: 0
                Row { width: parent.width; spacing: 14; height: 22
                    Text { id: saveHead; text: qsTr("PARTIDAS") + " · " + (saveInfo && saveInfo.slots.length ? qsTr("%1 RANURAS").arg(saveInfo.slots.length) : qsTr("NINGUNA")); color: canvas.acc; font.family: canvas.hud; font.pixelSize: 16; font.weight: Font.DemiBold; font.letterSpacing: 3.2 }
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
                                    Text { text:modelData.used ? shell.relativeTime(modelData.mtime) : qsTr("vacía"); color:canvas.ink2; font.family:canvas.body; font.pixelSize:14 }
                                }
                            }
                        }
                    }
                    Text { visible: !saveInfo || !saveInfo.slots.length; width:560; wrapMode:Text.WordWrap; text:saveInfo ? (saveInfo.error || qsTr("Aún no hay partidas. Aparecerán aquí cuando juegues.")) : qsTr("Consultando partidas…"); color:canvas.ink2; font.family:canvas.body; font.pixelSize:19 }
                }
                Row { spacing:10; height:30
                    LucideIcon { name:"menu"; color:canvas.ink3; width:18; height:18; opacity:0.7; anchors.verticalCenter:parent.verticalCenter }
                    Text { text:qsTr("Más opciones: clic derecho · botón Select del mando"); color:canvas.ink3; font.family:canvas.body; font.pixelSize:16; anchors.verticalCenter:parent.verticalCenter }
                }
                Item { width:1;height:14 }
                Row { width:parent.width; spacing:14; height:22
                    Text { id: infoHead; text:qsTr("FICHA"); color:canvas.acc; font.family:canvas.hud; font.pixelSize:16; font.weight:Font.DemiBold; font.letterSpacing:3.2 }
                    Rectangle { width:parent.width-infoHead.implicitWidth-14;height:1;color:"#47f3efe3";anchors.verticalCenter:parent.verticalCenter }
                }
                Item { width:1;height:10 }
                Row { width:parent.width
                    Repeater { model: current ? [
                        {v: current.plays ? shell.relativeTime(current.lastPlayed) : qsTr("Nunca"), l:qsTr("ÚLTIMA SESIÓN"), w:150},
                        {v:"—", l:qsTr("EN DISCO"), w:120},
                        {v:qsTr("por defecto"), l:qsTr("AJUSTES"), w:220},
                        {v: shell.relativeTime(current.lastBackup), l:qsTr("ÚLTIMO RESPALDO"), w:150}
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
        Item { id: player; x:800; y:360; width:320; height:170
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
        Clasp { x:800; y:328; color:canvas.acc; opacity:.9 }
        Item {
            id: hud
            x: 1530; y: 58; width: 340
            height: hudContent.implicitHeight + 40
            visible: sensors.item !== null && !api.gameRunning && !shell.portPickerOpen

            FrostedSurface {
                anchors.fill: parent
                tint: "#48101722"
                feather: 24
                radius: 24
            }
            Column {
                id: hudContent
                x: 16; y: 20; width: parent.width - 32; spacing: 0
                Row { width:parent.width;spacing:14;height:24
                    Text { id:hudTitle;text:qsTr("SISTEMA");color:canvas.brand;font.family:canvas.hud;font.pixelSize:16;font.weight:Font.DemiBold;font.letterSpacing:3.2 }
                    Rectangle { width:parent.width-hudTitle.implicitWidth-14;height:1;color:"#47f3efe3";anchors.verticalCenter:parent.verticalCenter }
                }
                HudRow { width:parent.width; label:"CPU";sub:api.system.cpu&&api.system.cpu.model?api.system.cpu.model:"";pct:sensors.item?sensors.item.cpu:0;vtext:Math.round(sensors.item?sensors.item.cpu:0)+" %";extra:(sensors.item?Math.round(sensors.item.cpuTemp)+" °C":"—")+(api.system.cpu&&api.system.cpu.ghz?"  "+api.system.cpu.ghz.toFixed(1)+" GHz":"");extraColor:sensors.item?shell.thermalColor(sensors.item.cpuTemp):canvas.ink2;acc:canvas.acc;ink:canvas.ink;ink2:canvas.ink2;ink3:canvas.ink3 }
                HudRow { width:parent.width; label:"GPU";sub:sensors.item?sensors.item.gpuName:"";pct:sensors.item?Math.max(sensors.item.gpu,sensors.item.vramUsed/Math.max(1,sensors.item.vramTotal)*100):0;vtext:sensors.item?Math.round(sensors.item.gpu)+" %":"—";extra:sensors.item?Math.round(sensors.item.gpuTemp)+" °C · "+(sensors.item.vramUsed/1073741824).toFixed(1)+"/"+(sensors.item.vramTotal/1073741824).toFixed(1)+" GB":"";extraColor:sensors.item?shell.thermalColor(sensors.item.gpuTemp):canvas.ink2;acc:canvas.acc;ink:canvas.ink;ink2:canvas.ink2;ink3:canvas.ink3 }
                HudRow { width:parent.width; label:"RAM";sub:sensors.item?Math.round(sensors.item.ramTotal/1073741824)+" GB":"";pct:sensors.item?sensors.item.ramUsed/Math.max(1,sensors.item.ramTotal)*100:0;vtext:sensors.item?(sensors.item.ramUsed/1073741824).toFixed(1):"—";extra:sensors.item?"/ "+(sensors.item.ramTotal/1073741824).toFixed(1)+" GB":"";acc:canvas.acc;ink:canvas.ink;ink2:canvas.ink2;ink3:canvas.ink3 }
                Repeater { model:api.system.disks&&api.system.disks.length?api.system.disks:(api.system.disk?[api.system.disk]:[])
                    HudRow { width:parent.width; required property var modelData;label:modelData.label||"DISCO";sub:modelData.fs||(!modelData.available?"no conectado":"");pct:modelData.total?modelData.used/modelData.total*100:0;vtext:modelData.total?Math.round(modelData.used/1073741824)+"":"—";extra:modelData.total?"/ "+Math.round(modelData.total/1073741824)+" GB":"";acc:canvas.acc;ink:canvas.ink;ink2:canvas.ink2;ink3:canvas.ink3 }
                }
                HudRow { width:parent.width; visible:!!api.system.bat;height:visible?42:0;charge:true;label:qsTr("BATERÍA");sub:api.system.ac?qsTr("enchufado"):qsTr("con batería");pct:api.system.bat?api.system.bat.pct:0;vtext:api.system.bat?api.system.bat.pct+" %":"—";extra:"";acc:canvas.acc;ink:canvas.ink;ink2:canvas.ink2;ink3:canvas.ink3 }
                Item { width:parent.width; height:34
                    Row { anchors.verticalCenter:parent.verticalCenter; spacing:6
                        Text { text:qsTr("PERFIL"); color:canvas.ink3; font.family:canvas.hud; font.pixelSize:12; font.letterSpacing:1 }
                        Text { text:api.system.profile||"No disponible"; color:canvas.ink2; font.family:canvas.hud; font.pixelSize:14; elide:Text.ElideRight; width:92 }
                        Rectangle { width:1; height:18; color:"#477d8da2"; anchors.verticalCenter:parent.verticalCenter }
                        Text { text:"RPM"; color:canvas.ink3; font.family:canvas.hud; font.pixelSize:12; font.letterSpacing:1 }
                        Text { text:api.system.fans&&api.system.fans.length?api.system.fans.map(function(f){return f.rpm+" RPM"}).join(" · "):"RPM no disponible"; color:canvas.ink2; font.family:canvas.hud; font.pixelSize:13; elide:Text.ElideRight; width:104 }
                    }
                }
            }
        }

        // Carrusel anclado abajo, sin mover la fila al cambiar de juego.
        Item { id:shelfWrap; x:0; width:1920; height:shell.sectionMode === "full" ? 720 : 640; y:canvas.height-136-height; clip:true
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
            Item { id:track; x:(shell.sectionMode === "full" ? 84 : 230) - list.currentIndex * 271; height:parent.height
                Behavior on x { NumberAnimation { duration:550; easing.type:Easing.OutCubic } }
                Row { id:cardsRow; spacing:20; anchors.bottom:parent.bottom
                    Repeater { model:shell.visibleGames.length
                        delegate: Item { id:slot; required property int index
                            readonly property var entry:shell.carouselGames[index]
                            readonly property int gameIndex:index
                            readonly property bool selected:index===list.currentIndex
                            readonly property bool expanded: selected && shell.sectionMode === "full"
                            // Todos los slots comparten altura y línea de base; las portadas pequeñas
                            // se dibujan abajo para no quedar alineadas con el borde superior de la ficha.
                            readonly property int slotHeight: shell.sectionMode === "full" ? 720 : 574
                            readonly property int visualHeight: selected ? slotHeight : 377
                            width:selected?(expanded?420:383):251;height:slotHeight;z:selected?5:0
                            Behavior on width { NumberAnimation { duration:420; easing.type:Easing.OutBack; easing.overshoot:0.8 } }
                            readonly property real cx:x+track.x+width/2
                            // Simetricamente desvanece por el espacio visible a cada extremo;
                            // la fórmula anterior ocultaba por completo la siguiente tarjeta al borde derecho.
                            opacity:Math.max(0,Math.min(1,(cx+210)/420,(1920+210-cx)/420))
                            Behavior on opacity { NumberAnimation { duration:420;easing.type:Easing.OutCubic } }
                            // Precarga más tarjetas hacia adelante para que sus portadas estén listas al navegar.
                            Loader { anchors.left:parent.left;anchors.right:parent.right;anchors.bottom:parent.bottom;height:slot.visualHeight;active:slot.index>=list.currentIndex-12&&slot.index<=list.currentIndex+14
                                Behavior on height { NumberAnimation { duration:420; easing.type:Easing.OutBack; easing.overshoot:0.8 } }
                                sourceComponent: Component { GameCard { anchors.fill:parent; game:slot.entry;current:slot.selected;expanded:slot.expanded;api:shell.backend
                                    platformLabel:shell.platformLabel(slot.entry);platformColor:shell.platformColor(slot.entry.platform);iconKey:shell.platformIcon(slot.entry);coordinateRoot:canvas
                                    accent:canvas.acc;titleColor:canvas.ink;secondaryColor:canvas.ink2;mutedColor:canvas.ink3
                                    portName:slot.selected && shell.selectedPort ? shell.selectedPort.name : "";portCount:slot.selected && slot.entry.ports ? slot.entry.ports.length : 0
                                    portIndex:slot.selected ? shell.selectedPortIndex : 0;description:slot.selected && shell.selectedPort && shell.selectedPort.description ? shell.selectedPort.description : (slot.entry.description || slot.entry.sub || "")
                                    originBadges: {
                                        const badges = [shell.platformLabel(slot.entry)]
                                        const chips = slot.selected && shell.selectedPort ? (shell.selectedPort.chips || []) : (slot.entry.chips || [])
                                        for (let i=0;i<chips.length;i++) if (chips[i] && badges.indexOf(chips[i])<0) badges.push(chips[i])
                                        if (slot.selected && slot.entry.ports && slot.entry.ports.length>1 && shell.selectedPort && badges.indexOf(shell.selectedPort.name)<0) badges.push(shell.selectedPort.name)
                                        return badges
                                    }
                                    lastSessionText: {
                                        if (!slot.entry.plays) return qsTr("Sin sesiones")
                                        const value=shell.relativeTime(slot.entry.lastPlayed)
                                        return value.charAt(0).toUpperCase()+value.slice(1)
                                    }
                                    playtimeText:slot.entry.totalSecs > 0 ? shell.duration(slot.entry.totalSecs) : qsTr("Sin tiempo")
                                    savesCount:slot.selected && shell.saveInfo && shell.saveInfo.slots ? shell.saveInfo.slots.length : 0
                                    saveSlots: {
                                        if (!slot.selected || !shell.saveInfo || !shell.saveInfo.slots) return []
                                        const slots = shell.saveInfo.slots.slice()
                                        slots.sort(function(a,b){return (b.mtime||0)-(a.mtime||0)})
                                        return slots
                                    }
                                    latestSaveText: {
                                        if (!slot.selected) return ""
                                        if (!shell.saveInfo) return qsTr("Buscando la ranura reciente…")
                                        if (!shell.saveInfo.slots || !shell.saveInfo.slots.length) return shell.saveInfo.configured ? qsTr("Aún no hay partidas guardadas") : qsTr("Partidas sin configurar")
                                        const slots=shell.saveInfo.slots.slice().sort(function(a,b){return (b.mtime||0)-(a.mtime||0)})
                                        const when=slots[0].used?shell.relativeTime(slots[0].mtime):qsTr("vacía")
                                        return (slots[0].name||qsTr("Partida")) + " · " + when.charAt(0).toUpperCase()+when.slice(1)
                                    }
                                    backupText: {
                                        if (!slot.selected || !shell.saveInfo) return qsTr("Sin respaldo")
                                        const backup=shell.saveInfo.lastBackup||slot.entry.lastBackup||(shell.saveInfo.backups&&shell.saveInfo.backups.length?shell.saveInfo.backups[0].mtime:0)||0
                                        return backup>0 ? qsTr("Respaldo · %1").arg(shell.relativeTime(backup)) : qsTr("Sin respaldo")
                                    }
                                    launchFocused:slot.selected && shell.focusZone === "hero"
                                    onPortStepRequested: function(delta) { if(slot.selected) shell.stepPort(delta) }
                                    onLaunchRequested: if(slot.selected) shell.requestPlay()
                                    onActivated: { if(!slot.selected) list.currentIndex=slot.gameIndex; else shell.goZone("hero",0) }
                                    onContextRequested: function(px,py) {
                                        if (!slot.selected) {
                                            list.currentIndex = slot.gameIndex
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
                Text { x:24; y:16; text:qsTr("SALIDA DE AUDIO"); color:canvas.acc; font.family:canvas.hud; font.pixelSize:15; font.letterSpacing:3; font.weight:Font.DemiBold }
                Column { x:12; y:50; width:parent.width-24
                    Repeater { model:shell.audItems
                        delegate: Rectangle { id:ait; required property var modelData; required property int index
                            readonly property bool foc:shell.audIdx===index
                            readonly property bool isCurrent:!!modelData.current
                            width:parent.width; height:54; radius:14
                            color:foc?canvas.acc:(isCurrent?Qt.rgba(canvas.acc.r,canvas.acc.g,canvas.acc.b,0.16):(am.containsMouse?"#1fffffff":"transparent"))
                            border.width:isCurrent&&!foc?1:0; border.color:canvas.acc
                            LucideIcon { x:16; anchors.verticalCenter:parent.verticalCenter; width:24; height:24
                                name: ait.modelData.kind === "hdmi" ? "monitor" : ait.modelData.kind === "usb" ? "headphones" : ait.modelData.kind === "bt" ? "bluetooth" : "speaker"
                                color:ait.foc?canvas.brandInk:"#f3efe3" }
                            Text { x:58; width:parent.width-120; elide:Text.ElideRight; anchors.verticalCenter:parent.verticalCenter; text:ait.modelData.label
                                color:ait.foc?canvas.brandInk:"#f3efe3"; font.family:canvas.body; font.pixelSize:19; font.weight:Font.Medium }
                            LucideIcon { visible: ait.isCurrent; anchors.right: parent.right; anchors.rightMargin: 18; anchors.verticalCenter: parent.verticalCenter; name: "check"; color: ait.foc ? canvas.brandInk : canvas.acc }
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
                                LucideIcon { anchors.centerIn: parent; visible: name !== ""; name: kk.modelData.k === "shift" ? "arrow-up" : kk.modelData.k === "back" ? "delete" : ""; color: kk.foc ? "#14211a" : "#f3efe3" }
                                Text { anchors.centerIn:parent; visible: kk.modelData.k !== "shift" && kk.modelData.k !== "back"; text:kk.modelData.t; color:kk.foc?"#14211a":"#f3efe3"; font.family:canvas.hud; font.weight:Font.DemiBold; font.pixelSize:kk.modelData.k==="ch"?24:17 }
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
        }
        // «EN EJECUCIÓN»: bloquea ratón, teclado y mando de la estantería mientras el juego sigue abierto; se quita sola al cerrarlo.
        Item { id:runLayer; anchors.fill:parent; z:40; visible:shell.sectionMode !== "full" && shell.runningGame!==null&&!shell.runIgnored
            opacity:visible?1:0
            Rectangle { anchors.fill:parent; color:"#d9050806" }
            MouseArea { anchors.fill:parent; acceptedButtons:Qt.AllButtons; hoverEnabled:true }
            Column { anchors.centerIn:parent; spacing:14; width:900
                Text { anchors.horizontalCenter:parent.horizontalCenter; text:qsTr("EN EJECUCIÓN"); color:canvas.acc; font.family:canvas.hud; font.pixelSize:22; font.weight:Font.DemiBold; font.letterSpacing:5 }
                Item { anchors.horizontalCenter:parent.horizontalCenter; width:520; height:shell.runningGame&&shell.runningGame.logo?140:90
                    Image { id:runLogo; anchors.fill:parent; source:shell.runningGame&&shell.runningGame.logo?shell.runningGame.logo:""; fillMode:Image.PreserveAspectFit; asynchronous:true; visible:status===Image.Ready }
                    Text { visible:!runLogo.visible; anchors.fill:parent; horizontalAlignment:Text.AlignHCenter; verticalAlignment:Text.AlignVCenter; wrapMode:Text.WordWrap
                        text:shell.runningGame?shell.runningGame.name:""; color:canvas.ink; font.family:shell.runningGame&&shell.runningGame.font?shell.runningGame.font:"Hanken Grotesk"; font.pixelSize:48; font.weight:Font.Bold }
                }
                Text { anchors.horizontalCenter:parent.horizontalCenter; text:qsTr("La estantería vuelve sola al cerrar el juego"); color:canvas.ink2; font.family:canvas.body; font.pixelSize:20 }
                Text { anchors.horizontalCenter:parent.horizontalCenter; text:qsTr("reactivar ahora (Esc)"); color:canvas.ink3; font.family:canvas.hud; font.pixelSize:16; font.letterSpacing:2; font.underline:true
                    MouseArea { anchors.fill:parent; anchors.margins:-10; cursorShape:Qt.PointingHandCursor; onClicked:shell.runIgnored=true } }
            }
        }
        Item {
            anchors.fill: parent
            z: 35
            visible: shell.contextOpen && shell.contextItems.length > 0
            MouseArea {
                anchors.fill: parent
                acceptedButtons: Qt.LeftButton | Qt.RightButton
                onClicked: shell.contextOpen = false
            }
            Item {
                id: contextPanel
                width: 432
                height: contextRows.implicitHeight + 40
                x: Math.max(16, Math.min(parent.width - width - 16,
                    shell.contextPoint.x < 0 ? 560 : shell.contextPoint.x))
                y: Math.max(16, Math.min(parent.height - height - 24,
                    shell.contextPoint.y < 0 ? 470 : shell.contextPoint.y))

                FrostedSurface {
                    anchors.fill: parent
                    backdrop: contextScene
                    backdropRect: Qt.rect(contextPanel.x, contextPanel.y, width, height)
                    tint: "#ed111a24"
                    radius: 23
                    feather: 1
                }
                Rectangle {
                    anchors.fill: parent
                    radius: 23
                    color: "transparent"
                    border.color: "#62778b"
                    border.width: 1
                }
                MouseArea { anchors.fill: parent; acceptedButtons: Qt.AllButtons }
                Column {
                    id: contextRows
                    x: 17; y: 20; width: parent.width - 34
                    spacing: 3
                    Repeater {
                        model: shell.contextItems
                        delegate: Column {
                            id: entry
                            required property var modelData
                            required property int index
                            readonly property bool destructive: index === 6
                            width: contextRows.width
                            spacing: 5

                            Rectangle {
                                visible: entry.index === 1 || entry.index === 4 || entry.destructive || entry.index === 7
                                width: parent.width; height: 1
                                color: "#3e5368"
                            }
                            Text {
                                visible: entry.destructive
                                leftPadding: 63; topPadding: 7
                                text: qsTr("Acción destructiva")
                                color: "#e3867e"
                                font.family: canvas.body
                                font.pixelSize: 17
                            }
                            Rectangle {
                                width: parent.width; height: entry.index === 0 ? 46 : 43
                                radius: entry.index === 0 ? height / 2 : 12
                                color: entry.index === 0 ? (shell.contextIndex === 0 ? canvas.acc : Qt.darker(canvas.acc, 1.22))
                                    : shell.contextIndex === entry.index ? (entry.destructive ? "#463039" : "#2b4156") : "transparent"

                                LucideIcon {
                                    x: 20; width: 22; height: 22
                                    anchors.verticalCenter: parent.verticalCenter
                                    name: entry.modelData.icon
                                    color: entry.destructive ? "#ee9289" : canvas.ink
                                }
                                Text {
                                    x: 63; width: parent.width - x - 10
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: entry.modelData.label
                                    elide: Text.ElideRight
                                    color: entry.destructive ? "#ee9289" : canvas.ink
                                    font.family: canvas.body
                                    font.pixelSize: 21
                                    font.weight: entry.index === 0 || entry.destructive ? Font.DemiBold : Font.Normal
                                }
                                MouseArea {
                                    anchors.fill: parent
                                    cursorShape: Qt.PointingHandCursor
                                    hoverEnabled: true
                                    onEntered: shell.contextIndex = entry.index
                                    onClicked: shell.activateContext(entry.index)
                                }
                            }
                        }
                    }
                }
            }
        }
        Dialog {
            id: unlinkDialog
            property var game: null
            anchors.centerIn: Overlay.overlay
            modal: true
            title: qsTr("Desvincular juego de Omnia")
            standardButtons: Dialog.Cancel | Dialog.Yes
            onOpened: {
                const cancel = standardButton(Dialog.Cancel)
                const confirm = standardButton(Dialog.Yes)
                cancel.icon.source = Qt.resolvedUrl("images/lucide/x.svg")
                confirm.icon.source = Qt.resolvedUrl("images/lucide/trash-2.svg")
                confirm.text = qsTr("Desvincular")
                cancel.forceActiveFocus()
            }
            onClosed: shell.restoreControllerFocus()
            contentItem: Label {
                text: unlinkDialog.game
                    ? qsTr("Se quitará «%1» de tu biblioteca y de los datos de Omnia asociados. Sus archivos no se borrarán. Si Omnia lo detectó desde un launcher, no volverá a aparecer mientras siga instalado.").arg(unlinkDialog.game.name)
                    : qsTr("Se quitará el juego de la biblioteca de Omnia.")
                wrapMode: Text.WordWrap
                color: canvas.ink
                font.pixelSize: 16
                padding: 16
            }
            onAccepted: {
                if (!game) return
                const target = game
                api.removeGame(target, function(status, body) {
                    if (status === 200) {
                        if (shell.selectedId === target.id) shell.selectedId = ""
                        api.toast = qsTr("«%1» se quitó de Omnia. Sus archivos siguen en el disco.").arg(target.name)
                    } else api.toast = (body && body.error) || qsTr("No se pudo desvincular el juego.")
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
            Text { x:392;y:142;text:qsTr("ELEGIR ARTE · %1").arg(shell.current ? shell.current.name.toUpperCase() : "");color:canvas.brand;font.family:canvas.hud;font.pixelSize:19;font.letterSpacing:2.5;font.weight:Font.DemiBold }
            Row { x:392;y:178;spacing:10
                Repeater { model:shell.artKinds
                    delegate:Rectangle { required property string modelData;readonly property bool active:shell.artKind===modelData
                        height:36;width:kindText.implicitWidth+32;radius:18;color:active?canvas.brand:"#25303d"
                        Text { id:kindText;anchors.centerIn:parent;text:parent.modelData==="portada"?"Portada":(parent.modelData==="fondo"?"Fondo":"Logo");color:parent.active?canvas.brandInk:canvas.ink;font.family:canvas.body;font.pixelSize:16;font.weight:Font.DemiBold }
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
                            Text { id:usedText;anchors.centerIn:parent;text:qsTr("EN USO");color:"#0c1a10";font.family:canvas.hud;font.pixelSize:11;font.weight:Font.Bold;font.letterSpacing:.5 }
                        }
                        Rectangle { visible:shell.artPending[shell.artKind]&&shell.artPending[shell.artKind].url===artTile.modelData.url;anchors.right:parent.right;anchors.top:parent.top;anchors.margins:8;height:22;radius:11;color:canvas.brand;width:selText.implicitWidth+16
                            Text { id:selText;anchors.centerIn:parent;text:qsTr("SELECCIONADO");color:canvas.brandInk;font.family:canvas.hud;font.pixelSize:10;font.weight:Font.Bold }
                        }
                        Rectangle { anchors.left:parent.left;anchors.bottom:parent.bottom;anchors.margins:7;height:20;radius:10;color:"#d0000000";width:sizeText.implicitWidth+12
                            Text { id:sizeText;anchors.centerIn:parent;text:artTile.modelData.w+"×"+artTile.modelData.h+(artTile.modelData.by?" · "+artTile.modelData.by:"");color:canvas.ink;font.family:canvas.hud;font.pixelSize:10 }
                        }
                        MouseArea { cursorShape: Qt.PointingHandCursor; anchors.fill:parent;hoverEnabled:true;onEntered:shell.artIndex=artTile.index;onClicked:shell.pickArt(artTile.index) }
                    }
                }
            }
            Text { x:artGrid.x;y:artGrid.y+artGrid.height/2-14;width:artGrid.width;horizontalAlignment:Text.AlignHCenter;visible:shell.artItems.length===0;text:shell.artBusy?"Consultando el catálogo de Omnia…":(shell.artError||"Sin arte publicado para este juego");color:canvas.ink2;font.family:canvas.body;font.pixelSize:18 }
            Rectangle { x:384;y:640;width:1152;height:108;radius:16;color:"#202833";border.width:1;border.color:"#394656"
                    Text { x:18;y:8;text:qsTr("PREVISUALIZACIÓN ACTUAL / SELECCIONADA");color:canvas.brand;font.family:canvas.hud;font.pixelSize:12;font.letterSpacing:1.4;font.weight:Font.DemiBold }
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
                Text { anchors.centerIn:parent;text:qsTr("Cancelar");color:canvas.ink;font.family:canvas.body;font.pixelSize:15 }
                MouseArea { anchors.fill:parent;enabled:!shell.artApplying;cursorShape:Qt.PointingHandCursor;onClicked:shell.closeArt() }
            }
            Rectangle { x:artPanel.x+artPanel.width-160;y:766;width:160;height:42;radius:21;color:shell.artPending.portada||shell.artPending.fondo||shell.artPending.logo?canvas.brand:"#303846";opacity:shell.artApplying?0.55:1
                Text { anchors.centerIn:parent;text:shell.artApplying?"Aplicando…":"Aceptar cambios";color:shell.artPending.portada||shell.artPending.fondo||shell.artPending.logo?canvas.brandInk:canvas.ink3;font.family:canvas.body;font.pixelSize:15;font.weight:Font.DemiBold }
                MouseArea { anchors.fill:parent;enabled:!shell.artApplying&&!!(shell.artPending.portada||shell.artPending.fondo||shell.artPending.logo);cursorShape:Qt.PointingHandCursor;onClicked:shell.acceptArt() }
            }
            Rectangle { x:1520;y:138;width:32;height:32;radius:16;color:"#25303d"
                LucideIcon { anchors.centerIn: parent; name: "x"; color: canvas.ink }
                MouseArea { cursorShape: Qt.PointingHandCursor; anchors.fill:parent;enabled:!shell.artApplying;onClicked:shell.closeArt() }
            }
        }
    }

    // Al elegir port o mientras corre un juego, Omnia deja solo la portada animada.
    // El selector aparece encima de esa imagen y devuelve el foco al juego al elegir.
    Item {
        id: playScene
        anchors.fill: parent
        z: 100
        clip: true
        visible: shell.sectionMode === "full"
        opacity: shell.portPickerOpen || api.gameRunning ? 1 : 0
        enabled: opacity > 0.01
        Behavior on opacity { NumberAnimation { duration:360; easing.type:Easing.OutCubic } }
        // El fondo permanece transparente: solo se ve el wallpaper animado existente.
        MouseArea {
            anchors.fill:parent; acceptedButtons:Qt.AllButtons
            onClicked:function(mouse) {
                if (shell.portPickerOpen && (mouse.x < portOptions.x || mouse.x > portOptions.x + portOptions.width || mouse.y < portOptions.y || mouse.y > portOptions.y + portOptions.height))
                    shell.portPickerOpen = false
            }
        }
        Column {
            id:playingStatus
            visible:api.gameRunning && !shell.portPickerOpen
            anchors.centerIn:parent
            width:560
            spacing:14
            Item {
                width:parent.width;height:150
                Image {
                    id:playingLogo
                    anchors.centerIn:parent
                    width:500;height:150
                    source:shell.runningGame && shell.runningGame.logo ? shell.runningGame.logo : (shell.current ? shell.current.logo : "")
                    fillMode:Image.PreserveAspectFit;asynchronous:true;smooth:true;sourceSize.width:1000
                    visible:status===Image.Ready
                }
                Text {
                    anchors.centerIn:parent
                    visible:!playingLogo.visible
                    text:shell.runningGame ? shell.runningGame.name : (shell.current ? shell.current.name : "")
                    color:canvas.ink;font.family:canvas.hud;font.pixelSize:36;font.weight:Font.Bold
                    horizontalAlignment:Text.AlignHCenter;wrapMode:Text.WordWrap;width:parent.width
                }
            }
            Text {
                width:parent.width;horizontalAlignment:Text.AlignHCenter
                text:qsTr("JUGANDO AHORA")
                color:canvas.acc;font.family:canvas.hud;font.pixelSize:19;font.weight:Font.DemiBold;font.letterSpacing:4
            }
            Text {
                width:parent.width;horizontalAlignment:Text.AlignHCenter
                text:shell.runningGame ? shell.runningGame.name : (shell.current ? shell.current.name : "El juego seleccionado")
                color:canvas.ink;font.family:canvas.body;font.pixelSize:23;font.weight:Font.DemiBold;wrapMode:Text.WordWrap
            }
            Text {
                width:parent.width;horizontalAlignment:Text.AlignHCenter
                text:qsTr("La biblioteca volverá al cerrar el juego")
                color:canvas.ink2;font.family:canvas.body;font.pixelSize:16
            }
        }
        Column {
            id:portOptions
            visible: opacity > 0.01
            opacity: shell.portPickerOpen ? 1 : 0
            Behavior on opacity { NumberAnimation { duration:240; easing.type:Easing.OutCubic } }
            width: 580
            anchors.centerIn: parent
            spacing: 13
            Item {
                width: parent.width; height: 92
                Image {
                    id: pickerLogo
                    anchors.centerIn: parent
                    width: 380; height: 92
                    source: shell.current && shell.current.logo ? shell.current.logo : ""
                    fillMode: Image.PreserveAspectFit; asynchronous: true; smooth: true
                    sourceSize.width: 760
                    visible: status === Image.Ready
                }
                Text {
                    anchors.centerIn: parent
                    visible: !shell.current || !shell.current.logo || pickerLogo.status !== Image.Ready
                    text: shell.current ? shell.current.name : ""
                    color: canvas.ink; font.family: canvas.hud; font.pixelSize: 30
                    font.weight: Font.Bold; elide: Text.ElideRight; width: parent.width
                    horizontalAlignment: Text.AlignHCenter
                }
            }
            Text {
                width: parent.width; horizontalAlignment: Text.AlignHCenter
                text: shell.current ? shell.current.name : "Selecciona una versión"
                color: canvas.ink; font.family: canvas.hud; font.pixelSize: 22; font.weight: Font.DemiBold
                elide: Text.ElideRight
            }
            Text {
                width: parent.width; horizontalAlignment: Text.AlignHCenter
                text: qsTr("ELIGE CÓMO JUGAR"); color: canvas.acc; font.family: canvas.hud
                font.pixelSize: 14; font.weight: Font.DemiBold; font.letterSpacing: 3
            }
            Repeater {
                model: shell.current ? shell.current.ports : []
                delegate: Rectangle {
                    required property var modelData
                    required property int index
                    property bool hovered: false
                    width: parent.width; height: 66; radius: 16
                    color: hovered ? "#dd336599" : "#a9151c26"
                    border.width: hovered ? 2 : 1
                    border.color: hovered ? canvas.brandLight : "#66ffffff"
                    Row {
                        anchors { left: parent.left; right: parent.right; verticalCenter: parent.verticalCenter; leftMargin: 20; rightMargin: 20 }
                        spacing: 12
                        PlatIcon { key: shell.platformIcon(shell.current); color: shell.platformColor(shell.current.platform); size: 22; anchors.verticalCenter: parent.verticalCenter }
                        Column {
                            width: parent.width - 40; anchors.verticalCenter: parent.verticalCenter; spacing: 2
                            Text { width: parent.width; text: modelData.name; color: canvas.ink; font.family: canvas.body; font.pixelSize: 19; font.weight: Font.DemiBold; elide: Text.ElideRight }
                            Text { width: parent.width; text: modelData.description || shell.platformLabel(shell.current); color: canvas.ink2; font.family: canvas.body; font.pixelSize: 14; elide: Text.ElideRight }
                        }
                    }
                    Text { visible: modelData.running; anchors.right: parent.right; anchors.rightMargin: 20; anchors.verticalCenter: parent.verticalCenter; text: qsTr("EN EJECUCIÓN"); color: canvas.brandLight; font.family: canvas.hud; font.pixelSize: 12; font.weight: Font.Bold; font.letterSpacing: 1 }
                    MouseArea { anchors.fill: parent; hoverEnabled:true; cursorShape: Qt.PointingHandCursor; onEntered: parent.hovered=true; onExited: parent.hovered=false; onClicked: shell.choosePlayPort(index) }
                }
            }
            Row {
                width:parent.width; spacing:14
                Rectangle {
                    width:138; height:42; radius:21
                    color:cancelMouse.containsMouse?"#303b49":"#a9151c26"
                    border.width:1; border.color:"#66ffffff"
                    Text { anchors.centerIn:parent; text:qsTr("Cancelar"); color:canvas.ink; font.family:canvas.body; font.pixelSize:16; font.weight:Font.DemiBold }
                    MouseArea { id:cancelMouse; anchors.fill:parent; hoverEnabled:true; cursorShape:Qt.PointingHandCursor; onClicked:shell.portPickerOpen=false }
                }
                Text {
                    width:parent.width-152; anchors.verticalCenter:parent.verticalCenter
                    text: api.padOn ? "Clic en una opción · B cancelar" : "Clic en una opción · Esc cancelar"
                    color: canvas.ink2; font.family: canvas.body; font.pixelSize: 14; wrapMode:Text.WordWrap
                }
            }
        }
    }

    // aviso temporal: se muestra al actuar (p. ej. «Biblioteca actualizada») y se desvanece solo (ver Api.notify)
    Rectangle { visible:api.toast!==""&&!shell.portPickerOpen&&!api.gameRunning; opacity:api.toastLevel; x:shell.toastX(width); y:shell.toastY(height)
        width:toastText.implicitWidth+28; height:toastText.implicitHeight+14; radius:height/2; color:"#b3000000"
        Text { id:toastText; anchors.centerIn:parent; text:api.toast; color:canvas.brand; font.family:"Rajdhani"; font.pixelSize:16; font.weight:Font.DemiBold } }
}

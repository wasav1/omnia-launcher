import QtQuick
import QtQuick.Window
import Qt5Compat.GraphicalEffects

/**
 * BigMode: la biblioteca completa de Omnia (pantalla completa): barra superior con filtros, búsqueda y estado del
 * sistema; ficha del juego con logo, descripción, «Jugar» y «Detalles»; estantería de portadas; guía de botones.
 * Todo se escala con el alto de la ventana (referencia 1920×1080). El fondo ocupa el 100 % del alto (OmniaBackdrop).
 *
 * Teclado: ←/→ cambiar juego · Re Pág/Av Pág cambiar de página de la estantería · Enter jugar · Espacio/I detalles · Tab filtro · / buscar · F favorito · Esc atrás.
 * Ratón: rueda = desplazar la estantería (sin cambiar la selección) · flechas laterales = saltar de página.
 * Mando: ◀ ▶ cambiar · LT/RT cambiar de página · A jugar · X detalles · LB/RB filtro · B atrás.
 */
Item {
    id: lib
    focus: true
    // Inyectable para que el gestor y Big Mode compartan el mismo cliente local.
    // En la ventana independiente se usa la instancia propia de esta vista.
    property var backend: null
    readonly property var api: backend || ownedApi
    // Cuando el gestor crea Big Mode, ambos comparten el servicio y el sondeo del gestor.
    // La ventana independiente conserva su propio sondeo.
    property bool sharedBackend: false
    property bool externalWallpaper: false     // true: ventana transparente; se ve el wallpaper del escritorio
    signal closeRequested()

    // ---- paleta Omnia oscuro
    readonly property color base: "#0B0F14"
    readonly property color surface: "#151D27"
    readonly property color ink: "#F0F3F7"
    readonly property color ink2: "#B8C3D0"
    readonly property color accent: "#336599"
    readonly property color ring: "#5b9be0"
    readonly property real libraryCoverWidth: s * 210
    readonly property real libraryCoverHeight: s * 298
    readonly property real libraryFocusedCoverHeight: s * 310
    readonly property real s: Math.max(0.4, Math.min(width / 1920, height / 1080))
    readonly property string uiFont: "Hanken Grotesk"

    // ---- estado
    readonly property alias allView: allGames
    readonly property alias shelfView: shelf        // para pruebas
    readonly property alias sfx: sfx
    readonly property alias introView: intro
    readonly property alias settingsView: settings
    property bool introShown: false
    property var kbCallback: null
    property var kbClosed: null
    function playIntro() { intro.start() }
    function lastFocus() { lib.forceActiveFocus() }
    // Teclado virtual para otros usos (apodo de un mando): el texto va a `onText` en vivo y `onDone` se llama al cerrar.
    function openKeyboardFor(initial, onText, onDone, mode) {
        kbCallback = onText; kbClosed = onDone; searchFocus = false
        vkb.show(initial || "", mode)
    }
    function chooseStoreInstallRoot(done) {
        let pending = api.installRoot
        openKeyboardFor(pending, value => pending = value, function(accepted) {
            if (!accepted || pending.trim() === api.installRoot) return
            api.setInstallRoot(pending.trim(), function(status, body) {
                done(status === 200 ? qsTr("Carpeta de instalación guardada.") : body.error || qsTr("No se pudo guardar la carpeta."))
            })
        }, "path")
    }
    function openStorePort(title, offer) { portDialog.show(offer, title) }
    function maybeIntro() {
        if (introShown || !api.prefsLoaded) return
        introShown = true
        if (api.introEnabled && api.arg("--game", "") === "" && api.arg("--downloads", "") === "") intro.start()
    }
    // Sonidos: el mando y el teclado ponen los suyos en todas las pantallas (los ajustes tienen los propios y la estantería suena al cambiar de página).
    function padSound(k) {
        if (page === "settings") return
        const m = { l: "move", r: "move", u: "move", d: "move", A: "confirm", B: "back", X: "menu", Y: "menu", LB: "move", RB: "move", START: "menu" }
        if (m[k]) sfx.play(m[k])
    }
    function keySound(e) {
        if (page === "settings") return
        const k = e.key
        if (k === Qt.Key_Left || k === Qt.Key_Right || k === Qt.Key_Up || k === Qt.Key_Down || k === Qt.Key_Tab || k === Qt.Key_Backtab) sfx.play("move")
        else if (k === Qt.Key_Return || k === Qt.Key_Enter || k === Qt.Key_Space) sfx.play("confirm")
        else if (k === Qt.Key_Escape || k === Qt.Key_Backspace) sfx.play("back")
        else if (k === Qt.Key_M || k === Qt.Key_Menu) sfx.play("menu")
    }
    property string filterKey: "all"
    property string searchText: ""
    property bool searchOpen: false
    property bool searchFocus: false          // con mando: el foco está en la lupa de la barra superior
    function lastPlayedOf(g) { return Number(g && (g.lastPlayed || (g.played || {}).last) || 0) }
    property int mainNavIndex: -1
    property string settingsFrom: "library"
    property string downloadsFrom: "library"
    readonly property bool mainNavVisible: page === "home" || page === "library" || page === "all" || page === "store"
    readonly property var mainNavTabs: [
        {key:"home", label:qsTr("Inicio")}, {key:"library", label:qsTr("Biblioteca")}, {key:"store", label:qsTr("Tienda")}
    ]
    onPageChanged: { mainNavIndex = -1; searchFocus = false; searchOpen = false }
    function focusMainNav(preferStore) {
        searchFocus = false
        mainNavIndex = preferStore === true || page === "store" ? 2 : page === "home" ? 0 : 1
        lib.forceActiveFocus()
    }
    function activateMainNav(i) {
        mainNavIndex = -1
        if (i === 0) openHome()
        else if (i === 1) openLibrary()
        else if (i === 2) openStore()
        else openSettings()
    }
    function handleMainNav(key) {
        if (mainNavIndex < 0) return false
        if (key === "l" || key === "r") mainNavIndex = (mainNavIndex + (key === "l" ? 3 : 1)) % 4
        else if (key === "A") activateMainNav(mainNavIndex)
        else if (key === "B" || key === "d" || key === "SELECT") {
            mainNavIndex = -1
            if (page === "store") bigStoreView.forceActiveFocus()
        }
        return true
    }
    property string page: "home"               // home | library | all | details | settings | downloads | art
    readonly property bool detailsOpen: page === "details"
    readonly property bool padOn: api.padOn
    property bool detailsFromAll: false
    function openDetails() { if (current) { detailsFromAll = page === "all"; page = "details"; details.forceActiveFocus() } }
    function closeDetails() { page = detailsFromAll ? "all" : "library"; detailsFromAll = false; lib.forceActiveFocus() }
    // ---- descargas e instalaciones (pastilla en la barra + pantalla propia; START las abre desde el mando)
    property var dlJobs: []
    property var dlSeen: ({})
    readonly property int dlBusy: dlJobs.filter(function(j) { return ["queued", "downloading", "verifying", "extracting", "finalizing", "paused"].indexOf(j.status) >= 0 }).length
    readonly property int dlFailed: dlJobs.filter(function(j) { return ["failed", "cancelled", "interrupted"].indexOf(j.status) >= 0 }).length
    readonly property int dlProgress: {
        const busy = dlJobs.filter(function(j) { return ["queued", "downloading", "verifying", "extracting", "finalizing", "paused"].indexOf(j.status) >= 0 })
        return busy.length ? Math.round(busy.reduce(function(a, j) { return a + Number(j.progress || 0) }, 0) / busy.length) : 0
    }
    function pollDownloads() {
        api.installationSnapshot(function(st, body) {
            if (st !== 200) return
            const jobs = body.jobs || []
            for (const job of jobs) {                     // aviso único al terminar bien
                if (job.status === "completed" && dlSeen[job.id] && dlSeen[job.id] !== "completed") {
                    api.notify(job.updateOf ? qsTr("Actualizado: %1").arg(job.name) : qsTr("Instalado: %1").arg(job.name))
                    sfx.play("done")
                } else if (job.status === "failed" && dlSeen[job.id] && dlSeen[job.id] !== "failed") sfx.play("error")
                dlSeen[job.id] = job.status
            }
            dlJobs = jobs
            if (jobs.some(function(j) { return j.status === "completed" })) api.refresh()
        })
    }
    function openArt(g) { g = g || current; if (!g) return; artEditor.start(g); page = "art"; artEditor.forceActiveFocus() }
    function closeArt() { page = "library"; lib.forceActiveFocus() }
    function openDownloads() {
        if (page !== "downloads") downloadsFrom = page
        page = "downloads"; downloads.forceActiveFocus()
    }
    function restorePage(from) {
        page = from
        if (from === "store") bigStoreView.forceActiveFocus()
        else if (from === "details") details.forceActiveFocus()
        else if (from === "downloads") downloads.forceActiveFocus()
        else if (from === "art") artEditor.forceActiveFocus()
        else if (from === "settings") settings.forceActiveFocus()
        else lib.forceActiveFocus()
    }
    function closeDownloads() { restorePage(downloadsFrom); pollDownloads() }
    Timer { interval: 2000; repeat: true; running: api.ok && lib.visible && lib.page !== "downloads"; triggeredOnStart: true; onTriggered: lib.pollDownloads() }
    function openSettings() {
        if (page !== "settings") settingsFrom = page
        page = "settings"; settings.forceActiveFocus()
    }
    function closeSettings() { restorePage(settingsFrom) }
    function openAll() { if (!api.games.length) return; page = "all"; allGames.selId = current ? current.id : ""; allGames.rebuild(); lib.forceActiveFocus() }
    // ---- menú contextual del juego (X / clic derecho / M)
    function menuItems(g) {
        if (!g) return []
        const out = []
        if (g.portAvailable) out.push({ key: "port", label: qsTr("Instalar port"), icon: "download" })
        else if (!g.running) out.push({ key: "play", label: qsTr("Jugar"), icon: "play" })
        if (g.updateAvailable && !g.running) out.push({ key: "update", label: qsTr("Actualizar"), icon: "download" })
        out.push({ key: "details", label: qsTr("Detalles"), icon: "info" })
        out.push({ key: "fav", label: g.fav ? qsTr("Quitar de favoritos") : qsTr("Añadir a favoritos"), icon: "star" })
        out.push({ key: "saves", label: qsTr("Abrir carpeta de partidas"), icon: "folder-open" })
        out.push({ key: "art", label: qsTr("Cambiar arte"), icon: "image" })
        out.push({ key: "hide", label: qsTr("Ocultar de la biblioteca"), icon: "eye-off" })
        return out
    }
    property var menuGame: null
    function openMenu(g) {
        g = g || current
        if (!g) return
        menuGame = g
        ctxMenu.items = menuItems(g)
        ctxMenu.title = g.name
        ctxMenu.show()
    }
    function menuAction(key) {
        const g = menuGame
        if (!g) return
        if (key === "port") openPortInstall(g)
        else if (key === "update") openUpdate(g)
        else if (key === "play") play(g)
        else if (key === "details") { selectById(g.id); openDetails() }
        else if (key === "fav") api.toggleFav(g)
        else if (key === "saves") api.savesOpen(g, function() { })
        else if (key === "art") openArt(g)
        else if (key === "hide") api.call("POST", "/game/hide?id=" + encodeURIComponent(g.id), function() { api.refresh() })
        menuGame = null
    }
    function openPortInstall(g) {
        g = g || current
        if (!g || !g.portAvailable) return
        portDialog.show(g.portAvailable, g.name)
    }
    function openUpdate(g) {
        g = g || current
        if (!g || !g.updateAvailable) return
        portDialog.show(g.updateAvailable, g.name, g.id)
    }
    function openKeyboard() { searchFocus = false; searchOpen = false; vkb.show(searchText) }
    function openLibrary() { page = "library"; lib.forceActiveFocus() }
    function openHome() { page = "home"; lib.forceActiveFocus() }
    function openStore() { page = "store"; bigStoreView.open(); bigStoreView.forceActiveFocus() }
    function openLocalFromHome(id, thenPlay) {
        const at = api.games.findIndex(g => g.id === id)
        if (at < 0) return
        filterKey = "all"; searchText = ""; openLibrary()
        Qt.callLater(function() {
            const next = lib.visibleGames.findIndex(g => g.id === id)
            if (next >= 0) { lib.select(next); if (thenPlay) lib.play() }
        })
    }
    property int index: 0
    property string selectedId: ""
    property double lastLocalChange: 0
    readonly property var visibleGames: filtered()
    readonly property var current: visibleGames.length && index >= 0 && index < visibleGames.length ? visibleGames[index] : null
    readonly property var live: api.system && api.system.live ? api.system.live : ({})

    property date clockTime: new Date()
    property bool showSystem: false
    readonly property real contentInset: s * 96
    readonly property string clockLabel: clockTime.toLocaleTimeString(Qt.locale(lib.api.language === "en" ? "en_US" : "es_CO"), "h:mm ap")
    property var gameActivity: null
    readonly property var runningGame: api.games.find(game => game.running) || null
    readonly property string activityGameId: current?.id || ""
    onActivityGameIdChanged: {
        gameActivity = null
        activityDelay.restart()
    }
    Timer {
        id: activityDelay
        interval: 220
        onTriggered: {
            if (!lib.current || api.gameRunning) return
            const id = lib.activityGameId
            api.call("GET", "/game/activity?id=" + encodeURIComponent(id), function(status, data) {
                if (status === 200 && lib.current?.id === id) lib.gameActivity = data
            })
        }
    }
    Connections { target: api; function onGameRunningChanged() { if (!api.gameRunning) activityDelay.restart() } }
    // Big Mode se oculta mientras hay un juego en marcha y vuelve a pantalla completa cuando el juego se cierra.
    // Con un juego abierto el núcleo no entrega los botones del mando a la interfaz, así que no hay entradas accidentales.
    property bool hiddenForGame: false
    Connections {
        target: api
        function onGameRunningChanged() {
            if (api.gameRunning) { reopenDelay.stop(); lib.hideForGame() }
            else if (lib.hiddenForGame) reopenDelay.restart()
        }
    }
    Timer {      // el cierre se confirma un instante (un lanzador puede soltar el proceso antes de que arranque el juego)
        id: reopenDelay
        interval: 1500
        onTriggered: lib.reopenAfterGame()
    }
    function hideForGame() {
        const win = lib.Window.window
        if (!win || !win.visible || hiddenForGame) return
        hiddenForGame = true
        win.hide()
    }
    function reopenAfterGame() {
        if (!hiddenForGame || api.gameRunning) return
        hiddenForGame = false
        const win = lib.Window.window
        if (!win) return
        win.showFullScreen()
        win.requestActivate()
    }
    Timer { interval: 15000; repeat: true; running: lib.visible; onTriggered: lib.clockTime = new Date() }
    FontLoader { source: Qt.resolvedUrl("fonts/HankenGrotesk.ttf") }
    Api {
        id: ownedApi
        autoStart: !lib.backend
        controlsEnabled: !lib.backend
        systemEnabled: !lib.backend && lib.showSystem
    }

    function norm(t) { return (t || "").toString().toLocaleLowerCase() }
    function platformLabel(g) {
        const p = norm(g.platform)
        const names = {n64: qsTr("Nintendo 64"), nes: qsTr("Nintendo Entertainment System"), snes: qsTr("Super Nintendo"),
            gb: qsTr("Game Boy"), gbc: qsTr("Game Boy Color"), gba: qsTr("Game Boy Advance"), nds: qsTr("Nintendo DS"),
            gcwii: qsTr("GameCube / Wii"), "3ds": qsTr("Nintendo 3DS"), switch: qsTr("Nintendo Switch"),
            ps1: qsTr("PlayStation"), ps2: qsTr("PlayStation 2"), psp: qsTr("PlayStation Portable"),
            sw1: qsTr("Nintendo Switch"), sw2: qsTr("Nintendo Switch 2"), pc: "PC"}
        return names[p] || g.platform || g.src || qsTr("Juegos")
    }
    function subtitle(g) { return g ? platformLabel(g) + (g.variant || g.src ? " · " + (g.variant || g.src) : "") : "" }
    function platformColor(key) {
        const k = norm(key)
        return k === "n64" ? "#d9a441" : k === "sw1" ? "#e8604f" : k === "sw2" ? "#58a6f0" : k === "pc" ? "#6fc3c9" : lib.ink2
    }
    readonly property var filterOptions: {
        const out = [{ key: "all", label: qsTr("Todos") }]
        let fav = false
        const seen = {}, plats = []
        for (let i = 0; i < api.games.length; i++) {
            const g = api.games[i]
            if (g.hidden) continue
            if (g.fav) fav = true
            const k = norm(g.platform)
            if (k && !seen[k]) { seen[k] = true; plats.push({ key: k, label: platformLabel(g) }) }
        }
        const order = { pc: 0, ps5: 1, sw2: 2, ps4: 3, sw1: 4, ps3: 5, n64: 6 }
        plats.sort(function(a, b) { return (order[a.key] === undefined ? 9 : order[a.key]) - (order[b.key] === undefined ? 9 : order[b.key]) })
        if (fav) out.push({ key: "fav", label: qsTr("Favoritos") })
        return out.concat(plats)
    }
    function filtered() {
        const q = norm(searchText).trim(), out = []
        for (let i = 0; i < api.games.length; i++) {
            const g = api.games[i]
            if (g.hidden) continue
            if (filterKey === "fav" ? !g.fav : (filterKey !== "all" && norm(g.platform) !== filterKey)) continue
            if (q && norm(g.name + " " + (g.sub || "") + " " + (g.description || "")).indexOf(q) < 0) continue
            out.push(g)
        }
        // favoritos primero, luego los recurrentes (última sesión más reciente) y después el resto, en su orden de siempre
        const rank = function(g) { return g.fav ? 0 : (lib.lastPlayedOf(g) > 0 ? 1 : 2) }
        const pos = new Map(); out.forEach(function(g, k) { pos.set(g, k) })
        out.sort(function(a, b) {
            const t = rank(a) - rank(b); if (t) return t
            if (rank(a) === 1) { const l = lib.lastPlayedOf(b) - lib.lastPlayedOf(a); if (l) return l }
            return pos.get(a) - pos.get(b)
        })
        return out
    }
    function select(i, local) {
        if (!visibleGames.length) return
        index = Math.max(0, Math.min(visibleGames.length - 1, i))
        const g = visibleGames[index]
        selectedId = g.id
        if (local !== false) { lastLocalChange = Date.now(); api.selectGame(g.id, null, filterKey) }
    }
    function step(d) { select(index + d) }
    function selectById(id) {
        const i = visibleGames.findIndex(function(g) { return g.id === id })
        if (i < 0) { filterKey = "all"; searchText = ""; Qt.callLater(function() { select(visibleGames.findIndex(function(g) { return g.id === id })) }); return }
        select(i)
    }
    function setFilter(key) { filterKey = key; Qt.callLater(function() { select(0) }) }
    function stepFilter(d) {
        const i = Math.max(0, filterOptions.findIndex(function(f) { return f.key === filterKey }))
        setFilter(filterOptions[(i + d + filterOptions.length) % filterOptions.length].key)
    }
    function play(g, portId) {
        g = g || current
        if (!g || g.running) return
        if (g.portAvailable) { openPortInstall(g); return }       // un volcado con port disponible: «Jugar» ofrece instalarlo
        const port = portId || (g.ports || []).filter(function(p) { return p.canLaunch && !p.running }).map(function(p) { return p.id })[0]
        if (port) api.launch(g, port)
        else sfx.play("error")
    }
    function back() {
        if (page === "art") closeArt()
        else if (page === "downloads") closeDownloads()
        else if (page === "settings") closeSettings()
        else if (page === "all") openLibrary()
        else if (detailsOpen) closeDetails()
        else if (page === "home" && home.detail) home.closeCatalogDetails()
        else if (page === "home") openLibrary()
        else if (showSystem) showSystem = false
        else if (searchOpen || searchText) { searchText = ""; searchOpen = false; lib.forceActiveFocus() }
        else lib.closeRequested()
    }
    function duration(secs) {
        const m = Math.round(secs / 60)
        return secs < 1 ? "—" : secs < 60 ? Math.round(secs) + " s" : m < 60 ? m + " min" : Math.floor(m / 60) + " h " + (m % 60) + " min"
    }

    // BigMode abierto desde el panel: --game ID [--details] selecciona ese juego y, opcionalmente, abre su ficha.
    property bool argsApplied: false
    Timer { id: tabTimer; interval: 600; onTriggered: details.tab = Math.max(0, Math.min(2, parseInt(api.arg("--tab", "0")))) }
    Connections {
        target: api
        function onGamesChanged() {
            if (lib.argsApplied || api.games.length === 0) return
            lib.argsApplied = true
            if (Qt.application.arguments.indexOf("--settings") >= 0) { Qt.callLater(lib.openSettings); return }
            const id = api.arg("--game", "")
            if (!id) return
            const at = lib.visibleGames.findIndex(function(g) { return g.id === id })
            if (at >= 0) {
                lib.select(at)
                if (Qt.application.arguments.indexOf("--details") >= 0) Qt.callLater(function() { lib.openDetails(); tabTimer.start() })
                else if (Qt.application.arguments.indexOf("--install-port") >= 0) Qt.callLater(function() { lib.openLibrary(); lib.openPortInstall() })
                else if (Qt.application.arguments.indexOf("--update-port") >= 0) Qt.callLater(function() { lib.openLibrary(); lib.openUpdate() })
            }
        }
    }
    // Si el juego seleccionado deja de existir en la vista, se vuelve a ordenar la selección.
    onVisibleGamesChanged: {
        if (!visibleGames.length) return
        const at = visibleGames.findIndex(function(g) { return g.id === selectedId })
        if (at >= 0) index = at
        else if (index >= visibleGames.length) index = visibleGames.length - 1
        if (!selectedId) select(index, false)
    }
    // Sigue la selección hecha desde el panel (misma selección del núcleo), salvo justo después de un cambio local.
    Timer {
        interval: 2500; running: api.ok; repeat: true; triggeredOnStart: true
        onTriggered: api.call("GET", "/selection", function(st, b) {
            if (st !== 200 || !b || Date.now() - lib.lastLocalChange < 3500 || !b.id || b.id === lib.selectedId) return
            let at = lib.visibleGames.findIndex(function(g) { return g.id === b.id })
            if (at < 0) { lib.filterKey = "all"; lib.searchText = ""; Qt.callLater(function() { lib.select(lib.visibleGames.findIndex(function(g) { return g.id === b.id }), false) }); return }
            lib.select(at, false)
        })
    }
    Timer { interval: 6000; running: !lib.sharedBackend; repeat: true; onTriggered: api.refresh() }
    Connections {
        target: api
        function onPadKey(k) {
            if (intro.active) { intro.skip(); return }
            lib.padSound(k)
            if (portDialog.open) { portDialog.pad(k); return }
            if (vkb.open) { vkb.pad(k); return }
            if (ctxMenu.open) { ctxMenu.pad(k); return }
            if (lib.handleMainNav(k)) return
            if (k === "SELECT" && lib.mainNavVisible && !home.detail && !bigStoreView.detail) { lib.focusMainNav(true); return }
            if (lib.page === "store") { bigStoreView.pad(k); return }
            if (lib.searchFocus) {
                if (k === "A") lib.openKeyboard()
                else if (k === "u") lib.focusMainNav()
                else if (k === "d" || k === "B") lib.searchFocus = false
                return
            }
            if (lib.page === "art") { artEditor.pad(k); return }
            if (lib.page === "downloads") { downloads.pad(k); return }
            if (k === "START" && lib.dlBusy + lib.dlFailed > 0) { lib.openDownloads(); return }
            if (lib.page === "settings") { settings.pad(k); return }
            if (lib.page === "all") { allGames.pad(k); return }
            if (lib.page === "home") {
                if (home.detail) { if (k === "B") home.closeCatalogDetails(); return }
                if (k === "l") home.nav("left")
                else if (k === "r") home.nav("right")
                else if (k === "u") home.nav("up")
                else if (k === "d") home.nav("down")
                else if (k === "A") home.accept()
                else if (k === "B") lib.back()
                return
            }
            if (lib.detailsOpen) {
                const dm = { l: "left", r: "right", u: "up", d: "down", A: "accept", B: "back", Y: "menu", LB: "tabprev", RB: "tabnext" }
                if (dm[k]) details.nav(dm[k])
                return
            }
            if (k === "Y") lib.openAll()
            else if (k === "l") lib.step(-1)
            else if (k === "r") lib.step(1)
            else if (k === "A") lib.play()
            else if (k === "X") lib.openMenu()
            else if (k === "u") lib.searchFocus = true
            else if (k === "B") lib.back()
            else if (k === "LB") lib.stepFilter(-1)
            else if (k === "RB") lib.stepFilter(1)
            else if (k === "LT") shelf.page(-1)
            else if (k === "RT") shelf.page(1)
        }
    }
    Keys.onPressed: function(e) {
        if (intro.active) { intro.skip(); e.accepted = true; return }
        lib.keySound(e)
        if (portDialog.open) { e.accepted = portDialog.key(e); return }
        if (ctxMenu.open) { e.accepted = ctxMenu.key(e); return }
        if (vkb.open) { e.accepted = vkb.key(e); return }
        if (page === "store" && mainNavIndex < 0 && !(e.modifiers & Qt.ControlModifier)) { e.accepted = bigStoreView.key(e); return }
        if (mainNavIndex >= 0) {
            const navKeys = { [Qt.Key_Left]:"l", [Qt.Key_Right]:"r", [Qt.Key_Down]:"d", [Qt.Key_Escape]:"B", [Qt.Key_Return]:"A", [Qt.Key_Enter]:"A" }
            e.accepted = !!navKeys[e.key] && handleMainNav(navKeys[e.key])
            return
        }
        if (mainNavVisible && (e.modifiers & Qt.ControlModifier)) {
            const i = [Qt.Key_1, Qt.Key_2, Qt.Key_3, Qt.Key_4].indexOf(e.key)
            if (i >= 0) { activateMainNav(i); e.accepted = true; return }
        }
        if (searchOpen) return                              // el campo de texto maneja el teclado
        if (detailsOpen || page === "settings" || page === "downloads" || page === "art") return           // la ficha, los ajustes y las descargas manejan su propio teclado
        if (page === "all") { e.accepted = allGames.key(e); return }
        if (page === "home") {
            if (e.key === Qt.Key_Left) home.nav("left")
            else if (e.key === Qt.Key_Right) home.nav("right")
            else if (e.key === Qt.Key_Up) home.nav("up")
            else if (e.key === Qt.Key_Down) home.nav("down")
            else if (e.key === Qt.Key_Return || e.key === Qt.Key_Enter) home.accept()
            else if (e.key === Qt.Key_Escape) back()
            else { e.accepted = false; return }
            e.accepted = true
            return
        }
        if (e.key === Qt.Key_Left) step(-1)
        else if (e.key === Qt.Key_Right) step(1)
        else if (e.key === Qt.Key_V && page === "library") openAll()
        else if (e.key === Qt.Key_PageUp && page === "library") shelf.page(-1)
        else if (e.key === Qt.Key_PageDown && page === "library") shelf.page(1)
        else if (e.key === Qt.Key_Home && page === "library") select(0)
        else if (e.key === Qt.Key_1 && (e.modifiers & Qt.ControlModifier)) openHome()
        else if (e.key === Qt.Key_2 && (e.modifiers & Qt.ControlModifier)) openLibrary()
        else if (e.key === Qt.Key_End) select(visibleGames.length - 1)
        else if (e.key === Qt.Key_Return || e.key === Qt.Key_Enter) play()
        else if (e.key === Qt.Key_Space || e.key === Qt.Key_I) openDetails()
        else if (e.key === Qt.Key_M || e.key === Qt.Key_Menu) openMenu()
        else if (e.key === Qt.Key_Tab) stepFilter(e.modifiers & Qt.ShiftModifier ? -1 : 1)
        else if (e.key === Qt.Key_Backtab) stepFilter(-1)
        else if (e.key === Qt.Key_Slash || (e.key === Qt.Key_F && (e.modifiers & Qt.ControlModifier))) { searchOpen = true; searchInput.forceActiveFocus() }
        else if (e.key === Qt.Key_F) { if (current) api.toggleFav(current) }
        else if (e.key === Qt.Key_F5) api.refresh()
        else if (e.key === Qt.Key_Escape) back()
        else { e.accepted = false; return }
        e.accepted = true
    }

    // ================= fondo =================
    Rectangle { anchors.fill: parent; color: lib.base; visible: !lib.externalWallpaper }
    // La imagen del juego seleccionado solo se ve fuera del Inicio (choca con el banner de novedades): se funde en 0,7 s.
    Item {
        id: gameBackdrop
        anchors.fill: parent
        opacity: (lib.page === "home" || lib.page === "store") || (lib.page === "all" && allGames.viewMode === "list") ? 0 : 1   // en la lista cada fila lleva su propio hero
        visible: opacity > 0.01
        Behavior on opacity { NumberAnimation { duration: 700; easing.type: Easing.InOutQuad } }
        OmniaBackdrop {
            anchors.fill: parent
            visible: !lib.externalWallpaper
            animate: (lib.page === "library" || lib.page === "all") && !api.gameRunning
            base: lib.base
            source: lib.current && lib.current.fondo ? lib.current.fondo : ""
        }
        Rectangle {        // sin fondo propio: degradado con la paleta del juego
            anchors.fill: parent
            visible: !lib.externalWallpaper && !(lib.current && lib.current.fondo)
            gradient: Gradient {
                GradientStop { position: 0; color: lib.current && lib.current.pal ? Qt.darker(lib.current.pal[1] || "#1b2a3b", 1.9) : "#101722" }
                GradientStop { position: 1; color: lib.base }
            }
        }
        Rectangle {        // oscurece la izquierda (zona del texto), como en el diseño
            anchors.fill: parent
            gradient: Gradient {
                orientation: Gradient.Horizontal
                GradientStop { position: 0.00; color: Qt.rgba(0.043, 0.059, 0.078, 0.96) }
                GradientStop { position: 0.22; color: Qt.rgba(0.043, 0.059, 0.078, 0.82) }
                GradientStop { position: 0.45; color: Qt.rgba(0.043, 0.059, 0.078, 0.46) }
                GradientStop { position: 0.64; color: Qt.rgba(0.043, 0.059, 0.078, 0.14) }
                GradientStop { position: 0.80; color: "transparent" }
            }
        }
        Rectangle {        // oscurece abajo (estantería y guía)
            anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
            height: parent.height * 0.62
            gradient: Gradient {
                GradientStop { position: 0.00; color: "transparent" }
                GradientStop { position: 0.38; color: Qt.rgba(0.043, 0.059, 0.078, 0.58) }
                GradientStop { position: 0.72; color: Qt.rgba(0.043, 0.059, 0.078, 0.90) }
                GradientStop { position: 1.00; color: Qt.rgba(0.043, 0.059, 0.078, 0.98) }
            }
        }
        Rectangle {        // viñeta superior para la barra
            anchors { left: parent.left; right: parent.right; top: parent.top }
            height: lib.s * 150
            gradient: Gradient {
                GradientStop { position: 0.0; color: Qt.rgba(0.043, 0.059, 0.078, 0.78) }
                GradientStop { position: 1.0; color: "transparent" }
            }
        }
    }

    // fondo de constelación: detrás de todo el contenido, teñido con el color del juego o de la novedad enfocada
    readonly property color effectTint: {
        if (page === "home") return home.effectTint
        const acc = current && current.acc ? Qt.lighter(String(current.acc), 1.0) : null
        return acc ? Qt.hsla(acc.hslHue < 0 ? 0.6 : acc.hslHue, 0.5, 0.5, 1) : "#336599"
    }
    // Dos fondos que se funden entre sí al cambiar de sección (0,7 s): constelación en Inicio y ficha, ondas en la Biblioteca.
    // Cada uno se detiene por completo mientras es invisible, así que solo trabaja el que se ve.
    readonly property bool wavesPage: page === "library" || page === "all"
    readonly property bool fxEnabled: api.animatedBackground && !lib.externalWallpaper
    Constellation {
        id: starsFx
        anchors.fill: parent
        opacity: lib.wavesPage ? 0 : 1
        visible: lib.fxEnabled && opacity > 0.01
        running: visible && !api.gameRunning && !api.covered
        tint: lib.effectTint
        Behavior on opacity { NumberAnimation { duration: 700; easing.type: Easing.InOutQuad } }
    }
    WaveField {
        id: wavesFx
        anchors.fill: parent
        opacity: lib.wavesPage ? 1 : 0
        visible: lib.fxEnabled && opacity > 0.01
        running: visible && !api.gameRunning && !api.covered
        tint: lib.effectTint
        intensity: lib.current && lib.current.fondo ? 0.35 : 0.6     // más suave si el juego tiene imagen de fondo
        Behavior on opacity { NumberAnimation { duration: 700; easing.type: Easing.InOutQuad } }
    }

    // ================= barra superior =================
    Item {
        id: top
        anchors { left: parent.left; right: parent.right; top: parent.top; leftMargin: lib.s * 48; rightMargin: lib.s * 40; topMargin: lib.s * 22 }
        height: lib.s * 54
        z: 2
        visible: lib.mainNavVisible

        Row {
            id: brand
            anchors.verticalCenter: parent.verticalCenter
            spacing: lib.s * 14
            Image {
                width: lib.s * 44; height: lib.s * 44
                anchors.verticalCenter: parent.verticalCenter
                source: Qt.resolvedUrl("../../assets/branding/omnia-logo.svg")
                fillMode: Image.PreserveAspectFit
                sourceSize.height: 128
                smooth: true
                visible: status === Image.Ready
            }
            Text { text: qsTr("Omnia"); anchors.verticalCenter: parent.verticalCenter; color: lib.ink; font.family: lib.uiFont; font.pixelSize: lib.s * 38; font.weight: Font.Medium }
        }
        Rectangle { id: sep1; anchors { left: brand.right; leftMargin: lib.s * 30; verticalCenter: parent.verticalCenter } width: 1; height: lib.s * 36; color: Qt.rgba(1, 1, 1, 0.16) }

        Row {
            id: mainNav
            anchors { left: sep1.right; leftMargin: lib.s * 22; verticalCenter: parent.verticalCenter }
            spacing: lib.s * 6
            Repeater {
                model: lib.mainNavTabs
                delegate: Rectangle {
                    required property var modelData
                    required property int index
                    readonly property bool active: lib.page === modelData.key
                    height: lib.s * 38
                    width: navLabel.implicitWidth + lib.s * 28
                    radius: height / 2
                    color: active ? lib.accent : navMouse.containsMouse ? Qt.rgba(1, 1, 1, 0.10) : "transparent"
                    border.width: lib.mainNavIndex === index ? 3 : 0; border.color: lib.ring
                    Text { id: navLabel; anchors.centerIn: parent; text: modelData.label; color: lib.ink; font.family: lib.uiFont; font.pixelSize: lib.s * 17; font.weight: active ? Font.DemiBold : Font.Medium }
                    MouseArea { id: navMouse; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: lib.activateMainNav(index) }
                }
            }
        }

        PlatformPicker {
            id: chips
            visible: lib.page === "library"
            anchors { left: mainNav.right; leftMargin: lib.s * 18; verticalCenter: parent.verticalCenter }
            width: lib.page === "library" ? implicitWidth : 0
            options: lib.filterOptions
            current: lib.filterKey
            games: lib.api.games
            padMode: lib.api.padOn
            padFamily: lib.api.padFamily || "xbox"
            uiScale: lib.s; ink: lib.ink; ink2: lib.ink2; accent: lib.accent; uiFont: lib.uiFont
            colorOf: function(key) { return lib.platformColor(key) }
            onPicked: function(key) { lib.setFilter(key) }
        }
        Rectangle { id: sep2; visible: lib.page === "library"; anchors { left: chips.right; leftMargin: lib.s * 18; verticalCenter: parent.verticalCenter } width: visible ? 1 : 0; height: lib.s * 36; color: Qt.rgba(1, 1, 1, 0.16) }

        // búsqueda (no se muestra en el Inicio)
        Rectangle {
            id: searchBox
            visible: lib.page === "library" || lib.page === "all"
            anchors { left: sep2.right; leftMargin: lib.page === "library" ? lib.s * 18 : lib.s * 12; verticalCenter: parent.verticalCenter }
            height: lib.s * 42
            width: lib.searchOpen || lib.searchText ? lib.s * 300 : lib.s * 46
            radius: height / 2
            color: Qt.rgba(0.05, 0.08, 0.12, 0.65)
            border.color: lib.searchOpen || lib.searchFocus ? lib.ring : Qt.rgba(1, 1, 1, 0.26)
            border.width: lib.searchFocus ? 3 : 1
            clip: true
            Behavior on width { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }
            LucideIcon { id: sIcon; x: lib.s * 13; anchors.verticalCenter: parent.verticalCenter; width: lib.s * 20; height: lib.s * 20; name: "search"; color: lib.ink }
            TextInput {
                id: searchInput
                anchors { left: sIcon.right; leftMargin: lib.s * 10; right: parent.right; rightMargin: lib.s * 14; verticalCenter: parent.verticalCenter }
                visible: lib.searchOpen || lib.searchText !== ""
                color: lib.ink
                selectionColor: lib.accent
                font.family: lib.uiFont
                font.pixelSize: lib.s * 18
                clip: true
                text: lib.searchText
                onTextChanged: if (text !== lib.searchText) { lib.searchText = text; Qt.callLater(function() { lib.select(0) }) }
                Keys.onEscapePressed: { lib.searchOpen = false; lib.searchText = ""; text = ""; lib.forceActiveFocus() }
                Keys.onReturnPressed: { lib.searchOpen = false; lib.forceActiveFocus() }
                Text { visible: !parent.text; text: qsTr("Buscar juego…"); color: lib.ink2; font: parent.font; anchors.verticalCenter: parent.verticalCenter }
            }
            MouseArea {
                anchors.fill: parent
                enabled: !lib.searchOpen
                cursorShape: Qt.PointingHandCursor
                onClicked: { lib.searchOpen = true; searchInput.forceActiveFocus() }
            }
        }

        // cerrar BigMode con el ratón (con mando hay «B Atrás»)
        Rectangle {
            id: closeBtn
            visible: !api.padOn
            anchors { right: parent.right; verticalCenter: parent.verticalCenter }
            width: visible ? lib.s * 42 : 0; height: lib.s * 42; radius: width / 2
            color: clMa2.containsMouse ? Qt.rgba(1, 1, 1, 0.16) : Qt.rgba(0.05, 0.08, 0.12, 0.72)
            border.width: 1; border.color: Qt.rgba(1, 1, 1, 0.20)
            LucideIcon { anchors.centerIn: parent; width: lib.s * 18; height: lib.s * 18; name: "x"; color: lib.ink }
            MouseArea { id: clMa2; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: lib.closeRequested() }
        }

        // ajustes de BigMode
        Rectangle {
            id: gearBtn
            anchors { right: closeBtn.visible ? closeBtn.left : parent.right; rightMargin: closeBtn.visible ? lib.s * 12 : 0; verticalCenter: parent.verticalCenter }
            width: lib.s * 42; height: lib.s * 42; radius: width / 2
            color: gearMa.containsMouse ? Qt.rgba(1, 1, 1, 0.16) : Qt.rgba(0.05, 0.08, 0.12, 0.72)
            border.width: lib.mainNavIndex === 3 ? 3 : 1; border.color: lib.mainNavIndex === 3 ? lib.ring : Qt.rgba(1, 1, 1, 0.20)
            LucideIcon { anchors.centerIn: parent; width: lib.s * 20; height: lib.s * 20; name: "settings"; color: lib.ink }
            MouseArea { id: gearMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: lib.openSettings() }
        }

        Rectangle {
            id: clockPill
            anchors { right: gearBtn.left; rightMargin: lib.s * 12; verticalCenter: parent.verticalCenter }
            width: timeLabel.implicitWidth + lib.s * 28
            height: lib.s * 42
            radius: height / 2
            color: "#b30b0f14"
            Text {
                id: timeLabel
                anchors.centerIn: parent
                text: lib.clockLabel
                color: lib.ink
                font.family: lib.uiFont
                font.pixelSize: lib.s * 17
            }
        }
        PadBattery {         // visible en todas las pantallas de BigMode junto con el reloj
            id: padBatteryChip
            api: lib.api; uiScale: lib.s; uiFont: lib.uiFont; ink: lib.ink; muted: lib.ink2
            compact: lib.page === "library"
            anchors { right: sysPill.left; rightMargin: lib.s * 10; verticalCenter: parent.verticalCenter }
        }
        Rectangle {          // descargas e instalaciones en curso o fallidas (START en el mando)
            id: dlPill
            visible: lib.dlBusy + lib.dlFailed > 0
            anchors { right: padBatteryChip.left; rightMargin: lib.s * 10; verticalCenter: parent.verticalCenter }
            width: dlLabel.implicitWidth + lib.s * 60; height: lib.s * 42; radius: height / 2
            color: dlMouse.containsMouse ? lib.surface : "#b30b0f14"
            border.color: lib.dlFailed > 0 ? "#80E8B86D" : "#30ffffff"
            Row {
                anchors.centerIn: parent; spacing: lib.s * 9
                LucideIcon { width: lib.s * 19; height: width; name: lib.dlBusy > 0 ? "download" : "info"; color: lib.dlFailed > 0 ? "#E8B86D" : lib.ink2 }
                Text {
                    id: dlLabel; color: lib.ink; font.family: lib.uiFont; font.pixelSize: lib.s * 17
                    text: lib.dlBusy > 0 ? qsTr("Descargas %1%").arg(lib.dlProgress) + (lib.dlFailed > 0 ? "  ⚠ " + lib.dlFailed : "") : qsTr("%1 fallida(s)").arg(lib.dlFailed)
                }
            }
            MouseArea { id: dlMouse; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: lib.openDownloads() }
        }
        Rectangle {
            id: sysPill
            anchors { right: clockPill.left; rightMargin: lib.s * 10; verticalCenter: parent.verticalCenter }
            width: systemLabel.implicitWidth + lib.s * 60
            height: lib.s * 42
            radius: height / 2
            color: lib.showSystem || sysMouse.containsMouse ? lib.surface : "#b30b0f14"
            border.color: "#30ffffff"
            Row {
                anchors.centerIn: parent
                spacing: lib.s * 9
                LucideIcon { width: lib.s * 19; height: width; name: lib.runningGame ? "gamepad-2" : "activity"; color: lib.ink2 }
                Text {
                    id: systemLabel
                    text: lib.runningGame ? qsTr("Jugando") : qsTr("Sistema")
                    color: lib.ink
                    font.family: lib.uiFont
                    font.pixelSize: lib.s * 17
                }
            }
            MouseArea {
                id: sysMouse
                anchors.fill: parent
                enabled: api.ok && !api.gameRunning
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: lib.showSystem = !lib.showSystem
            }
        }

        Rectangle {      // panel Sistema: tres anillos (CPU, GPU, RAM) con temperaturas, y energía, perfil y disco debajo
            id: sysCard
            visible: lib.showSystem && api.ok && !api.gameRunning
            anchors { right: clockPill.right; top: sysPill.bottom; topMargin: lib.s * 10 }
            width: Math.max(lib.s * 340, clockPill.x + clockPill.width - sysPill.x)       // al menos tan ancho como los botones Sistema y reloj
            height: sysCol.implicitHeight + lib.s * 36
            radius: lib.s * 20
            color: lib.surface
            border.color: "#30ffffff"
            readonly property var sys: api.system || ({})
            function tempColor(t) { return t === undefined ? lib.ink2 : (t <= 70 ? "#7fd69f" : (t <= 85 ? "#E8B86D" : "#E86D6D")) }
            function tempText(t) { return t === undefined ? "" : Math.round(t) + " °C" }
            Column {
                id: sysCol
                anchors { left: parent.left; right: parent.right; verticalCenter: parent.verticalCenter; margins: lib.s * 18 }
                spacing: lib.s * 14
                Row {
                    width: parent.width
                    readonly property real cell: width / 3
                    SystemGauge {
                        width: parent.cell; s: lib.s; ink: lib.ink; ink2: lib.ink2; uiFont: lib.uiFont
                        value: lib.live.cpu_pct === undefined ? -1 : lib.live.cpu_pct / 100
                        centerText: lib.live.cpu_pct === undefined ? "–" : Math.round(lib.live.cpu_pct) + "%"
                        label: "CPU"; detail: sysCard.tempText(lib.live.cpu_temp); detailColor: sysCard.tempColor(lib.live.cpu_temp)
                        ringColor: lib.live.cpu_pct > 90 ? "#E8B86D" : "#5B9BE0"
                    }
                    SystemGauge {
                        width: parent.cell; s: lib.s; ink: lib.ink; ink2: lib.ink2; uiFont: lib.uiFont
                        value: lib.live.gpu_pct === undefined ? -1 : lib.live.gpu_pct / 100
                        centerText: lib.live.gpu_pct === undefined ? "–" : Math.round(lib.live.gpu_pct) + "%"
                        label: "GPU"; detail: sysCard.tempText(lib.live.gpu_temp); detailColor: sysCard.tempColor(lib.live.gpu_temp)
                        ringColor: lib.live.gpu_pct > 90 ? "#E8B86D" : "#5B9BE0"
                    }
                    SystemGauge {
                        width: parent.cell; s: lib.s; ink: lib.ink; ink2: lib.ink2; uiFont: lib.uiFont
                        value: lib.live.ram_total ? lib.live.ram_used / lib.live.ram_total : -1
                        centerText: lib.live.ram_total ? Math.round(100 * lib.live.ram_used / lib.live.ram_total) + "%" : "–"
                        label: "RAM"
                        detail: lib.live.ram_total ? (lib.live.ram_used / 1073741824).toFixed(1) + " / " + (lib.live.ram_total / 1073741824).toFixed(1) + " GB" : ""
                        ringColor: lib.live.ram_total && lib.live.ram_used / lib.live.ram_total > 0.9 ? "#E8B86D" : "#5B9BE0"
                    }
                }
                Flow {
                    width: parent.width; spacing: lib.s * 8
                    layoutDirection: Qt.LeftToRight
                    Repeater {
                        model: {
                            const out = [], sys = sysCard.sys
                            if (sys.bat && sys.bat.pct !== undefined) out.push({ icon: "activity", text: sys.bat.pct + " %" + (sys.ac ? "  ·  " + qsTr("conectado") : "") })
                            if (sys.profile) out.push({ icon: "activity", text: sys.profile })
                            if (sys.disk && sys.disk.total) out.push({ icon: "folder-open", text: Math.round(sys.disk.used / 1073741824) + " / " + Math.round(sys.disk.total / 1073741824) + " GB" })
                            return out
                        }
                        delegate: Rectangle {
                            required property var modelData
                            width: chipText.implicitWidth + lib.s * 24; height: lib.s * 32; radius: height / 2
                            color: "#b30b0f14"; border.color: "#30ffffff"
                            Text { id: chipText; anchors.centerIn: parent; text: modelData.text; color: lib.ink; font.family: lib.uiFont; font.pixelSize: lib.s * 15 }
                        }
                    }
                }
                Text {
                    visible: !!sysCard.sys.cpu && !!sysCard.sys.cpu.model
                    width: parent.width; horizontalAlignment: Text.AlignHCenter; elide: Text.ElideRight
                    color: lib.ink2; font.family: lib.uiFont; font.pixelSize: lib.s * 14
                    text: sysCard.sys.cpu ? sysCard.sys.cpu.model + (sysCard.sys.cpu.ghz ? "  ·  " + sysCard.sys.cpu.ghz + " GHz" : "") : ""
                }
                Text { visible: lib.live.cpu_pct === undefined && lib.live.gpu_pct === undefined && lib.live.ram_total === undefined; text: qsTr("Sin datos de telemetría"); color: lib.ink2
                       font.family: lib.uiFont; font.pixelSize: lib.s * 18 }
            }
        }
    }

    // ================= ficha del juego =================
    Item {
        id: hero
        visible: lib.page === "library" && lib.current !== null
        property string gameId: lib.current ? lib.current.id : ""
        onGameIdChanged: heroIn.restart()
        transform: Translate { id: heroShift }
        ParallelAnimation {
            id: heroIn
            NumberAnimation { target: hero; property: "opacity"; from: 0; to: 1; duration: 320; easing.type: Easing.OutCubic }
            NumberAnimation { target: heroShift; property: "y"; from: lib.s * 16; to: 0; duration: 320; easing.type: Easing.OutCubic }
        }
        x: lib.contentInset
        y: lib.s * 104
        width: lib.s * 760
        height: lib.s * 330

        // logo del juego o, si no hay, el nombre en grande
        Item {
            id: logoBox
            width: lib.s * 540; height: lib.s * 182
            Image {
                id: logoImg
                anchors.fill: parent
                source: lib.current && lib.current.logo ? lib.current.logo : ""
                fillMode: Image.PreserveAspectFit
                horizontalAlignment: Image.AlignLeft
                verticalAlignment: Image.AlignBottom
                asynchronous: true
                smooth: true
                mipmap: true
                sourceSize.width: Math.round(lib.s * 1080)
                visible: status === Image.Ready
            }
            Text {
                visible: logoImg.status !== Image.Ready
                anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
                text: lib.current ? lib.current.name : ""
                color: lib.ink
                font.family: lib.current && lib.current.font ? lib.current.font : lib.uiFont
                font.pixelSize: lib.s * 64
                font.weight: Font.Bold
                wrapMode: Text.WordWrap
                maximumLineCount: 2
                elide: Text.ElideRight
                lineHeight: 0.95
            }
        }
        Rectangle { id: rule; anchors { top: logoBox.bottom; topMargin: lib.s * 18 } width: lib.s * 46; height: lib.s * 3; radius: 2; color: lib.ring }
        Text {
            id: blurb
            anchors { top: rule.bottom; topMargin: lib.s * 16 }
            width: lib.s * 560
            text: lib.current ? (lib.current.description || "").replace(/\s+/g, " ").trim() : ""
            visible: text.length > 0
            height: visible ? implicitHeight : 0
            color: lib.ink
            opacity: 0.92
            font.family: lib.uiFont
            font.pixelSize: lib.s * 22
            lineHeight: 1.25
            wrapMode: Text.WordWrap
            maximumLineCount: 2
            elide: Text.ElideRight
        }
        Text {
            id: sessionSummary
            anchors { top: blurb.bottom; topMargin: visible ? lib.s * 8 : 0 }
            visible: text.length > 0
            height: visible ? implicitHeight : 0
            text: {
                const data = lib.gameActivity
                const parts = lib.current ? [lib.subtitle(lib.current)] : []
                if (data?.lastPlayed > 0)
                    parts.push("Última sesión: " + Qt.formatDate(new Date(data.lastPlayed * 1000), Locale.ShortFormat))
                if (data?.totalSecs > 0)
                    parts.push("Tiempo jugado: " + lib.duration(data.totalSecs))
                return parts.join(" · ")
            }
            color: lib.ink2
            font.family: lib.uiFont
            font.pixelSize: lib.s * 16
            leftPadding: (summaryIcon.visible ? summaryIcon.width : 0) + lib.s * 10      // el logo de consola puede ser ancho (p. ej. Switch 2)
            PlatIcon {
                id: summaryIcon
                visible: lib.current !== null
                anchors { left: parent.left; verticalCenter: parent.verticalCenter }
                key: lib.current ? lib.norm(lib.current.platform) : ""
                size: lib.s * 20; color: lib.ink2
            }
        }
        Row {
            anchors { top: sessionSummary.bottom; topMargin: lib.s * 18 }
            spacing: lib.s * 14
            Rectangle {      // Jugar
                id: playBtn
                readonly property bool running: lib.current && lib.current.running
                width: lib.s * 265; height: lib.s * 50
                radius: lib.s * 10
                opacity: running ? 0.7 : 1
                gradient: Gradient {
                    GradientStop { position: 0; color: playMa.containsMouse ? Qt.lighter(lib.accent, 1.35) : Qt.lighter(lib.accent, 1.2) }
                    GradientStop { position: 1; color: playMa.containsMouse ? Qt.lighter(lib.accent, 1.1) : lib.accent }
                }
                border.width: 1
                border.color: Qt.rgba(1, 1, 1, 0.22)
                Row {
                    anchors.centerIn: parent
                    spacing: lib.s * 12
                    LucideIcon { width: lib.s * 22; height: lib.s * 22; name: lib.current && lib.current.portAvailable ? "download" : "play"; color: lib.ink; anchors.verticalCenter: parent.verticalCenter; visible: !playBtn.running }
                    Text { text: playBtn.running ? qsTr("En ejecución") : (lib.current && lib.current.portAvailable ? qsTr("Instalar port") : qsTr("Jugar")); color: lib.ink; font.family: lib.uiFont; font.pixelSize: lib.s * 22; font.weight: Font.Medium; anchors.verticalCenter: parent.verticalCenter }
                }
                MouseArea { id: playMa; anchors.fill: parent; enabled: !playBtn.running; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: lib.play() }
            }
            Rectangle {      // Detalles
                width: lib.s * 160; height: lib.s * 50
                radius: height / 2
                color: detMa.containsMouse ? Qt.rgba(1, 1, 1, 0.14) : Qt.rgba(0.05, 0.08, 0.12, 0.45)
                border.width: 1
                border.color: Qt.rgba(1, 1, 1, 0.40)
                Text { anchors.centerIn: parent; text: qsTr("Detalles"); color: lib.ink; font.family: lib.uiFont; font.pixelSize: lib.s * 20; font.weight: Font.Medium }
                MouseArea { id: detMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: lib.openDetails() }
            }
        }
    }

    // ================= estantería =================
    ListView {
        id: shelf
        visible: lib.page === "library"
        anchors { left: parent.left; right: parent.right; bottom: parent.bottom; bottomMargin: lib.s * 108 }
        anchors.leftMargin: lib.contentInset
        anchors.rightMargin: lib.contentInset
        readonly property real reflectH: lib.s * 68
        readonly property real headroom: lib.s * 30      // hueco superior para que el rebote no se recorte
        height: lib.s * 310 + reflectH + headroom
        orientation: ListView.Horizontal
        spacing: lib.s * 18
        model: lib.visibleGames
        currentIndex: lib.index
        // El desplazamiento es propio (no el de ListView) para separarlo de la selección: la rueda mueve la estantería sin cambiar
        // el juego seleccionado y los saltos de página llevan la selección a la página nueva.
        highlightFollowsCurrentItem: false
        highlightRangeMode: ListView.NoHighlightRange
        boundsBehavior: Flickable.StopAtBounds
        interactive: false          // sin arrastre: la estantería avanza con la rueda, las flechas, los gatillos o la navegación
        readonly property real cardStep: lib.libraryCoverWidth + spacing                 // ancho de una tarjeta más su separación
        readonly property real hlBegin: fadeOk ? fadeWidth + lib.s * 6 : 0     // la tarjeta seleccionada queda entre estos dos bordes
        readonly property real hlEnd: width * 0.62
        readonly property real maxX: Math.max(0, contentWidth - width)
        readonly property int perPage: Math.max(2, Math.floor((width + spacing) / cardStep))   // tarjetas completas que caben
        property bool paging: false
        function clampX(x) { return Math.max(0, Math.min(maxX, x)) }
        function scrollTo(x, animate, ms) {
            x = clampX(x)
            scrollAnim.stop()
            if (!animate) { contentX = x; return }
            scrollAnim.duration = ms || 260
            scrollAnim.to = x
            scrollAnim.restart()
        }
        function scrollBy(dx) { scrollTo((scrollAnim.running ? scrollAnim.to : contentX) + dx, true, 160) }
        // Lo mismo que hacía highlightRangeMode: ApplyRange: la tarjeta seleccionada queda dentro de [hlBegin, hlEnd].
        function revealIndex(i, animate) {
            const left = i * cardStep, right = left + lib.s * 210
            if (left < contentX + hlBegin) scrollTo(left - hlBegin, animate)
            else if (right > contentX + hlEnd) scrollTo(right - hlEnd, animate)
        }
        // Salta una página (los juegos visibles menos uno, para conservar una referencia) y lleva la selección a su primera tarjeta.
        function page(dir) {
            const n = lib.visibleGames.length
            if (n === 0) return
            const jump = Math.max(1, perPage - 1)
            const from = Math.max(0, Math.min(n - 1, Math.round(((scrollAnim.running ? scrollAnim.to : contentX) + hlBegin) / cardStep)))
            const first = Math.max(0, Math.min(n - 1, from + dir * jump))
            paging = true
            lib.select(first)
            paging = false
            scrollTo(first * cardStep - hlBegin, true)
            sfx.play("page")
        }
        NumberAnimation { id: scrollAnim; target: shelf; property: "contentX"; duration: 260; easing.type: Easing.OutCubic }
        Connections {
            target: lib
            function onIndexChanged() { if (!shelf.paging) shelf.revealIndex(lib.index, true) }
        }
        onCountChanged: Qt.callLater(function() { shelf.revealIndex(lib.index, false) })
        onWidthChanged: Qt.callLater(function() { shelf.revealIndex(lib.index, false) })
        // Rueda del mouse (o del panel táctil): desplaza la estantería una tarjeta por muesca, sin tocar la selección.
        WheelHandler {
            acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
            onWheel: function(ev) {
                const d = ev.angleDelta.y !== 0 ? ev.angleDelta.y : ev.angleDelta.x
                if (d !== 0) shelf.scrollBy(-d / 120 * shelf.cardStep)
            }
        }
        clip: true
        cacheBuffer: 1200
        // Las tarjetas que quedan cortadas en un extremo se desvanecen hacia ese extremo (solo del lado donde hay más contenido).
        // Con el renderizador por software no hay shaders y se omite.
        readonly property bool fadeOk: GraphicsInfo.api !== GraphicsInfo.Software
        readonly property real fadeWidth: Math.min(lib.s * 120, width * 0.3)
        // El desvanecido izquierdo se aplica siempre que la seleccionada no sea la primera (aunque la lista esté en su inicio): la
        // primera asoma desvanecida mientras se está sobre la segunda y vuelve a verse normal al volver a ella. Se anima.
        property real leftAmount: lib.index > 0 || !atXBeginning ? 1 : 0
        Behavior on leftAmount { NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }
        layer.enabled: fadeOk && contentWidth > width
        layer.effect: OpacityMask {
            maskSource: Rectangle {
                width: shelf.width; height: shelf.height
                gradient: Gradient {
                    orientation: Gradient.Horizontal
                    GradientStop { position: 0; color: Qt.rgba(0, 0, 0, 1 - shelf.leftAmount) }
                    GradientStop { position: Math.max(0.001, shelf.leftAmount * shelf.fadeWidth / shelf.width); color: "#FF000000" }
                    GradientStop { position: shelf.atXEnd ? 0.999 : 1 - shelf.fadeWidth / shelf.width; color: "#FF000000" }
                    GradientStop { position: 1; color: shelf.atXEnd ? "#FF000000" : "#00000000" }
                }
            }
        }
        delegate: Item {
            id: card
            required property var modelData
            required property int index
            readonly property bool sel: index === lib.index
            width: lib.libraryCoverWidth
            height: shelf.height
            Item {
                id: face
                anchors { left: parent.left; right: parent.right; bottom: parent.bottom; bottomMargin: shelf.reflectH + (card.sel ? lib.s * 8 : 0) }
                height: card.sel ? lib.libraryFocusedCoverHeight : lib.libraryCoverHeight
                scale: cardMa.containsMouse && !card.sel ? 1.02 : 1
                // rebote al cambiar de selección: la seleccionada sube con sobreimpulso y se asienta
                Behavior on height { NumberAnimation { duration: 420; easing.type: Easing.OutBack; easing.overshoot: 2.6 } }
                Behavior on anchors.bottomMargin { NumberAnimation { duration: 420; easing.type: Easing.OutBack; easing.overshoot: 3.2 } }
                Behavior on scale { NumberAnimation { duration: 140 } }

                Rectangle {      // tarjeta sin portada
                    id: tile
                    anchors.fill: parent
                    radius: lib.s * 20
                    color: "#16ffffff"          // sin arte: translúcida
                    border.color: "#1fffffff"; border.width: 1
                    visible: cover.status !== Image.Ready
                    Text {
                        anchors.centerIn: parent
                        width: parent.width - lib.s * 30
                        horizontalAlignment: Text.AlignHCenter
                        text: card.modelData.name
                        color: lib.ink
                        font.family: lib.uiFont
                        font.pixelSize: lib.s * 30
                        font.weight: Font.Bold
                        wrapMode: Text.WordWrap
                        visible: cover.status !== Image.Ready
                    }
                }
                Image {
                    id: cover
                    anchors.fill: parent
                    source: card.modelData.portada || ""
                    fillMode: Image.PreserveAspectCrop
                    asynchronous: true
                    smooth: true
                    mipmap: true
                    sourceSize.height: Math.round(lib.s * 768)
                    visible: false
                }
                Rectangle { id: coverMask; anchors.fill: parent; radius: lib.s * 20; visible: false }
                OpacityMask { anchors.fill: parent; source: cover; maskSource: coverMask; visible: cover.status === Image.Ready }
                Rectangle {      // anillo de selección
                    anchors.fill: parent
                    radius: lib.s * 22
                    color: "transparent"
                    border.width: card.sel ? Math.max(2, lib.s * 4) : 0
                    border.color: lib.ring
                    opacity: card.sel ? 1 : 0
                    Behavior on opacity { NumberAnimation { duration: 140 } }
                }
                Rectangle {      // «en ejecución»
                    visible: card.modelData.running
                    anchors { left: parent.left; top: parent.top; margins: lib.s * 12 }
                    width: runTxt.implicitWidth + lib.s * 20; height: lib.s * 26; radius: height / 2
                    color: "#6fc3a0"
                    Text { id: runTxt; anchors.centerIn: parent; text: qsTr("En juego"); color: lib.base; font.family: lib.uiFont; font.pixelSize: lib.s * 14; font.weight: Font.DemiBold }
                }
                Rectangle {      // port disponible
                    visible: !!card.modelData.portAvailable
                    anchors { left: parent.left; bottom: parent.bottom; margins: lib.s * 10 }
                    width: portTxt.implicitWidth + lib.s * 20; height: lib.s * 26; radius: height / 2
                    color: "#5b9be0"
                    Text { id: portTxt; anchors.centerIn: parent; text: qsTr("Port disponible"); color: lib.base; font.family: lib.uiFont; font.pixelSize: lib.s * 13; font.weight: Font.DemiBold }
                }
                Rectangle {      // actualización disponible
                    visible: !!card.modelData.updateAvailable && !card.modelData.portAvailable
                    anchors { left: parent.left; bottom: parent.bottom; margins: lib.s * 10 }
                    width: updTxt.implicitWidth + lib.s * 20; height: lib.s * 26; radius: height / 2
                    color: "#e0a24b"
                    Text { id: updTxt; anchors.centerIn: parent; text: qsTr("Actualización"); color: lib.base; font.family: lib.uiFont; font.pixelSize: lib.s * 13; font.weight: Font.DemiBold }
                }
                Rectangle {      // favorito
                    visible: card.modelData.fav
                    anchors { right: parent.right; top: parent.top; margins: lib.s * 12 }
                    width: lib.s * 30; height: lib.s * 30; radius: width / 2
                    color: Qt.rgba(0.04, 0.06, 0.08, 0.7)
                    LucideIcon { anchors.centerIn: parent; width: lib.s * 16; height: lib.s * 16; name: "star"; color: "#f5b83d" }
                }
            }
            // reflejo corto de espejo bajo la tarjeta (Canvas, sin shaders)
            ReflectionImage {
                anchors { left: parent.left; right: parent.right; top: face.bottom; topMargin: lib.s * 3 }
                height: shelf.reflectH - lib.s * 3
                source: card.modelData.portada || ""
                cardHeight: face.height
                radius: lib.s * 20
                strength: card.sel ? 0.32 : 0.24
                tileColor: card.modelData.pal ? Qt.darker(card.modelData.pal[1] || "#223244", 1.4) : "#223244"
            }
            MouseArea {
                id: cardMa
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                acceptedButtons: Qt.LeftButton | Qt.RightButton
                onClicked: function(m) {
                    sfx.play(m.button === Qt.RightButton ? "menu" : "move")
                    lib.select(card.index)
                    if (m.button === Qt.RightButton) lib.openMenu(card.modelData)
                }
                onDoubleClicked: function(m) { if (m.button === Qt.LeftButton) { lib.select(card.index); lib.play() } }
            }
        }
    }

    Repeater {      // flechas para el ratón: saltan una página. Con mando se sustituyen por LT / RT, que hacen lo mismo

        model: [-1, 1]
        delegate: Rectangle {
            id: shelfArrow
            required property int modelData
            readonly property bool previous: modelData < 0
            visible: lib.page === "library" && shelf.contentWidth > shelf.width
                && (previous ? !shelf.atXBeginning : !shelf.atXEnd)
            x: previous ? shelf.x - width - lib.s * 12 : shelf.x + shelf.width + lib.s * 12
            y: shelf.y + shelf.headroom + (shelf.height - shelf.headroom - shelf.reflectH - height) / 2
            width: lib.s * 42
            height: width
            radius: width / 2
            color: shelfArrowMouse.containsMouse ? lib.accent : lib.surface
            border.color: "#40ffffff"
            Accessible.role: Accessible.Button
            Accessible.name: previous ? qsTr("Página anterior") : qsTr("Página siguiente")
            LucideIcon { visible: !lib.padOn; anchors.centerIn: parent; width: lib.s * 21; height: width; name: shelfArrow.previous ? "arrow-left" : "arrow-right"; color: lib.ink }
            PadGlyph { visible: lib.padOn; anchors.centerIn: parent; size: lib.s * 34; family: lib.api.padFamily || "xbox"; key: shelfArrow.previous ? "LT" : "RT" }
            MouseArea {
                id: shelfArrowMouse
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: shelf.page(shelfArrow.modelData)
            }
        }
    }

    // ================= pie con la guía de botones =================
    Item {
        id: footer
        visible: lib.mainNavVisible
        anchors { left: parent.left; right: parent.right; bottom: parent.bottom; leftMargin: lib.s * 48; rightMargin: lib.s * 48; bottomMargin: lib.s * 34 }
        height: lib.s * 42
        Rectangle { anchors { left: parent.left; right: parent.right; top: parent.top; topMargin: -lib.s * 18 } height: 1; color: Qt.rgba(1, 1, 1, 0.12) }

        component Hint: OmniaControlHint {
            uiScale: lib.s
            uiFont: lib.uiFont
            ink: lib.ink
            muted: lib.ink2
            roundButton: lib.padOn
            padFamily: lib.api.padFamily || "xbox"
            anchors.verticalCenter: parent.verticalCenter
        }
        Row {
            anchors.verticalCenter: parent.verticalCenter
            spacing: lib.s * 29
            LucideIcon {
                anchors.verticalCenter: parent.verticalCenter
                width: lib.s * 25
                height: width
                name: lib.padOn ? "gamepad-2" : "keyboard"
                color: lib.ink2
            }
            // Con mando se dibujan los iconos reales de su familia (Xbox, PlayStation, Switch, Deck); sin mando, teclas.
            Hint { padKeys: lib.padOn ? ["A"] : []; glyph: "Enter"; label: lib.page === "store" ? qsTr("Elegir") : lib.page === "home" ? home.acceptLabel : (lib.current && lib.current.portAvailable ? qsTr("Instalar port") : qsTr("Jugar")) }
            Hint { visible: lib.page === "library" || lib.page === "all"; padKeys: lib.padOn ? ["X"] : []; glyph: "M"; label: qsTr("Menú") }
            Hint { padKeys: lib.padOn ? (lib.page === "home" || lib.page === "store" ? ["DPAD"] : ["l"]) : []; glyph: lib.page === "home" || lib.page === "store" ? "← ↑ ↓ →" : "← / →"
                label: lib.page === "store" && bigStoreView.detail ? qsTr("Desplazar ficha · Cambiar acción")
                    : lib.page === "home" || lib.page === "store" ? qsTr("Navegar") : qsTr("Cambiar juego") }
            Hint { visible: lib.page === "library" || lib.page === "all"; padKeys: lib.padOn ? ["LB", "RB"] : []; glyph: "Tab"; label: lib.page === "all" ? qsTr("Consola") : qsTr("Filtrar") }
            Hint { visible: lib.page === "library"; padKeys: lib.padOn ? ["LT", "RT"] : []; glyph: "Re Pág / Av Pág"; label: qsTr("Página") }
            Hint { visible: lib.page === "library"; padKeys: lib.padOn ? ["Y"] : []; glyph: "V"; label: qsTr("Ver todos") }
            Hint { visible: lib.page === "all"; padKeys: lib.padOn ? ["Y"] : []; glyph: "L"; label: qsTr("Cuadrícula/Lista") }
            Hint { visible: lib.page === "all"; padKeys: lib.padOn ? ["START"] : []; glyph: "G"; label: qsTr("Agrupar") }
            Hint { visible: lib.padOn && !bigStoreView.detail; padKeys: ["SELECT"]; label: lib.page === "store" ? qsTr("Barra superior") : qsTr("Ir a Tienda") }
            Hint { visible: lib.page === "store" && !bigStoreView.detail; padKeys: lib.padOn ? ["LB", "RB"] : []; glyph: "Tab"; label: qsTr("Tiendas") }
            Hint { visible: lib.page === "store" && !bigStoreView.detail; padKeys: lib.padOn ? ["X"] : []; glyph: "/"; label: qsTr("Buscar") }
            Hint { visible: lib.page === "store" && !bigStoreView.detail; padKeys: lib.padOn ? ["Y"] : []; glyph: "Y"; label: qsTr("Descargas") }
            Hint { visible: !lib.padOn && lib.page !== "store"; icon: "mouse"; label: lib.page === "library" ? qsTr("Clic para seleccionar · rueda para desplazar") : qsTr("Clic para seleccionar") }
        }
        Row {
            anchors { right: parent.right; verticalCenter: parent.verticalCenter }
            spacing: lib.s * 22
            Hint { padKeys: lib.padOn ? ["B"] : []; glyph: "Esc"; label: qsTr("Atrás") }
        }
    }

    // ================= ver todos =================
    OmniaAllGames {
        id: allGames
        visible: lib.page === "all"
        host: lib
        games: lib.api.games
        x: lib.contentInset - lib.s * 48; y: lib.s * 92
        width: lib.width - x - lib.s * 40
        height: lib.height - y - lib.s * 112
        onCloseRequested: lib.openLibrary()
        onPlayRequested: function(g) { lib.play(g) }
        onDetailsRequested: function(g) { lib.selectById(g.id); lib.openDetails() }
        onSelectionChanged2: function(g) { lib.selectById(g.id) }
        onContextRequested: function(g) { lib.openMenu(g) }
        onTopReached: lib.searchFocus = true
    }

    // ================= menú contextual y teclado virtual =================
    OmniaContextMenu {
        id: ctxMenu
        anchors.fill: parent
        z: 50
        uiScale: lib.s; ink: lib.ink; ink2: lib.ink2; accent: lib.accent; uiFont: lib.uiFont
        onActivated: function(key) { lib.menuAction(key) }
        onClosed: lib.menuGame = null
    }
    OmniaPortInstall {
        id: portDialog
        anchors.fill: parent
        z: 58
        api: lib.api
        uiScale: lib.s; ink: lib.ink; ink2: lib.ink2; accent: lib.accent; uiFont: lib.uiFont
        onStarted: function(name) {
            lib.api.notify(qsTr("Instalación iniciada: %1").arg(name))
            lib.pollDownloads()
            if (lib.page === "store") { bigStoreView.closeDetail(); lib.openDownloads() }
        }
    }
    OmniaVirtualKeyboard {
        id: vkb
        anchors.fill: parent
        z: 60
        uiScale: lib.s; ink: lib.ink; ink2: lib.ink2; accent: lib.accent; uiFont: lib.uiFont
        onTextChanged2: function(v) {
            if (lib.kbCallback) { lib.kbCallback(v); return }
            lib.searchText = v; Qt.callLater(function() { lib.select(0) })
        }
        onClosed: function(accepted) {
            const done = lib.kbClosed
            lib.kbCallback = null; lib.kbClosed = null
            if (lib.page === "settings") settings.forceActiveFocus()
            else if (lib.page === "store") bigStoreView.forceActiveFocus()
            else lib.forceActiveFocus()
            if (done) done(accepted)
        }
    }

    // ================= inicio del catálogo =================
    OmniaHome {
        id: home
        anchors.fill: parent
        visible: lib.page === "home"
        api: lib.api            // «api: api» se resolvía a la propiedad del propio Inicio (nula)
        localGames: lib.api.games
        searchText: lib.searchText
        uiScale: lib.s
        ink: lib.ink
        ink2: lib.ink2
        surface: lib.surface
        accent: lib.accent
        onOpenLocalGame: function(id) { lib.openLocalFromHome(id) }
        onPlayLocalGame: function(id) { lib.openLocalFromHome(id, true) }
        onOpenSection: function(section) {
            if (section === "settings") lib.openSettings()
            else if (section === "system") lib.showSystem = true
            else if (section === "favorites" && api.games.some(g => g.fav && !g.hidden)) { lib.openLibrary(); lib.setFilter("fav") }
            else lib.openLibrary()
        }
        onInstallRequested: function(game) { home.openCatalogDetails(game) }
    }

    // ================= estados sin datos =================
    Rectangle {
        anchors.centerIn: parent
        visible: lib.page === "library" && (!api.ok || (api.ok && api.games.length === 0) || (api.games.length > 0 && lib.visibleGames.length === 0))
        width: lib.s * 640; height: msgCol.implicitHeight + lib.s * 56
        radius: lib.s * 20
        color: Qt.rgba(0.08, 0.11, 0.15, 0.92)
        border.width: 1; border.color: Qt.rgba(1, 1, 1, 0.14)
        Column {
            id: msgCol
            anchors { left: parent.left; right: parent.right; verticalCenter: parent.verticalCenter; margins: lib.s * 28 }
            spacing: lib.s * 12
            Text {
                width: parent.width; horizontalAlignment: Text.AlignHCenter; wrapMode: Text.WordWrap
                text: !api.ok ? qsTr("No se pudo cargar la biblioteca") : api.games.length === 0 ? qsTr("Tu biblioteca está vacía") : qsTr("Ningún juego coincide")
                color: !api.ok ? "#ff8a8a" : lib.ink; font.family: lib.uiFont; font.pixelSize: lib.s * 30; font.weight: Font.Medium
            }
            Text {
                width: parent.width; horizontalAlignment: Text.AlignHCenter; wrapMode: Text.WordWrap
                text: !api.ok ? (api.error || qsTr("omnia-core no responde.")) + " " + qsTr("Revisa el servicio: systemctl --user status omnia")
                    : api.games.length === 0 ? qsTr("Aún no hay juegos detectados.") : qsTr("Prueba otro filtro o borra la búsqueda.")
                color: lib.ink2; font.family: lib.uiFont; font.pixelSize: lib.s * 18
            }
            Rectangle {
                visible: !api.ok
                anchors.horizontalCenter: parent.horizontalCenter
                width: lib.s * 170; height: lib.s * 44; radius: height / 2; color: lib.accent
                Text { anchors.centerIn: parent; text: qsTr("Reintentar"); color: lib.ink; font.family: lib.uiFont; font.pixelSize: lib.s * 18; font.weight: Font.Medium }
                MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: api.refresh() }
            }
        }
    }

    // ================= descargas e instalaciones =================
    OmniaDownloads {
        id: downloads
        anchors.fill: parent
        host: lib
        visible: lib.page === "downloads"
        onBack: lib.closeDownloads()
    }

    // ================= editor de arte (menú contextual → Cambiar arte) =================
    OmniaArtEditor {
        id: artEditor
        anchors.fill: parent
        host: lib
        visible: lib.page === "art"
        onBack: lib.closeArt()
    }

    ManagerStores {
        id: bigStoreAccounts
        visible: false
        compactHost: true
        controllerHost: true
        manager: QtObject {
            readonly property real s: lib.s
            readonly property color ink: lib.ink
            readonly property color muted: lib.ink2
            readonly property color surface: lib.surface
            readonly property color surface2: Qt.lighter(lib.surface, 1.15)
        }
        api: lib.api
        accountsOpen: settings.visible && settings.tab === 5
    }
    OmniaBigStore {
        id: bigStoreView
        anchors { left: parent.left; right: parent.right; top: top.bottom; bottom: footer.top
                  leftMargin: lib.s * 66; rightMargin: lib.s * 66; topMargin: lib.s * 18; bottomMargin: lib.s * 22 }
        host: lib
        accounts: bigStoreAccounts
        visible: lib.page === "store"
    }

    // ================= ajustes de BigMode =================
    OmniaBigSettings {
        id: settings
        anchors.fill: parent
        host: lib
        storeAccounts: bigStoreAccounts
        visible: lib.page === "settings"
        onBack: lib.closeSettings()
    }

    // ================= ficha de detalles (pantalla completa) =================
    OmniaGameDetails {
        id: details
        anchors.fill: parent
        host: lib
        game: lib.current
        visible: lib.page === "details" && lib.current !== null
        onBack: lib.closeDetails()
    }

    Rectangle {      // aviso («Lanzando …»)
        visible: api.toast !== ""
        opacity: api.toastLevel
        anchors { horizontalCenter: parent.horizontalCenter; bottom: parent.bottom; bottomMargin: lib.s * 100 }
        width: toastTxt.implicitWidth + lib.s * 44; height: lib.s * 44; radius: height / 2
        color: Qt.rgba(0.08, 0.11, 0.15, 0.95); border.width: 1; border.color: Qt.rgba(1, 1, 1, 0.16)
        Text { id: toastTxt; anchors.centerIn: parent; text: api.toast; color: lib.ink; font.family: lib.uiFont; font.pixelSize: lib.s * 18 }
    }

    Component.onCompleted: forceActiveFocus()

    // ================= sonidos y bienvenida =================
    OmniaSounds { id: sfx; api: lib.api; muted: lib.api.gameRunning || lib.api.covered }
    OmniaIntro { id: intro; anchors.fill: parent; host: lib }
    Connections { target: lib.api; function onPrefsLoadedChanged() { lib.maybeIntro() } }
    Timer { interval: 60; running: true; onTriggered: lib.maybeIntro() }
    property bool padSoundsArmed: false
    Timer { interval: 4000; running: true; onTriggered: lib.padSoundsArmed = true }
    Connections { target: lib.api; function onPadOnChanged() { if (lib.padSoundsArmed && !intro.active) sfx.play(lib.api.padOn ? "pad-on" : "pad-off") } }
}

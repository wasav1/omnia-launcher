import QtQuick
import QtQuick.Window

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

    Timer {
        id: mouseIdle
        interval: 2000
    }
    Loader {
        id: windowIntegration
        source: "BigModeWindowIntegration.qml"
    }
    Binding {
        target: windowIntegration.item
        property: "window"
        value: lib.Window.window
        when: windowIntegration.status === Loader.Ready
    }
    Binding {
        target: windowIntegration.item
        property: "pointerHidden"
        value: (lib.padOn || lib.api.padSeq < 0) && !mouseIdle.running
        when: windowIntegration.status === Loader.Ready
    }
    Connections {
        target: windowIntegration.item
        function onMouseUsed() {
            if (lib.padOn || lib.api.padSeq < 0) mouseIdle.restart()
        }
    }
    onPadOnChanged: mouseIdle.stop()
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
    readonly property color surface: "#28FFFFFF"
    readonly property color surfaceBorder: "#35FFFFFF"
    readonly property color surfaceFocus: "#403A5E85"
    readonly property color pageShade: "#730A1017"
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
    function lastFocus() {
        if (page === "settings") settings.forceActiveFocus()
        else lib.forceActiveFocus()
    }
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
    function maybeIntro(useFallback) {
        if (introShown || !api.prefsLoaded) return
        if (!api.introEnabled || api.arg("--game", "") || api.arg("--downloads", "")) {
            introShown = true
            return
        }
        if (!useFallback && api.revision < 0) {
            if (!introFallback.running) introFallback.start()
            return
        }
        introFallback.stop()
        introShown = true
        intro.start()
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
    property bool exitConfirmOpen: false
    property int exitConfirmChoice: 0
    // Índices de la barra con mando: 0–3 pestañas, luego «Añadir» (solo en Biblioteca), el aviso de
    // actualización (si hay) y el Menú rápido, que es el último.
    readonly property int powerIndex: menuIndex
    property string downloadsFrom: "library"
    property bool addOpen: false
    property string addImportPath: ""
    property string addedGameId: ""
    readonly property int addIndex: page === "library" ? 4 : -1
    readonly property int updateIndex: page === "library" ? 5 : 4
    readonly property int menuIndex: updateIndex + (suiteNotice.available ? 1 : 0)
    readonly property int gearIndex: menuIndex
    // Efecto cristal de la barra (Ajustes → Apariencia); se apaga mientras haya un juego abierto.
    readonly property Item glassBackdrop: api.glassEffect && !api.gameRunning ? gameBackdrop : null
    readonly property alias suiteUpdateNotice: suiteNotice
    SuiteUpdateNotice {
        id: suiteNotice
        anchors.fill: parent
        api: lib.api
        surface: "big-mode"
        activeSurface: lib.visible
        interactionBlocked: intro.active || lib.exitConfirmOpen || vkb.open || ctxMenu.open
        uiScale: lib.s
    }
    function openAddGame() { mainNavIndex = -1; addImportPath = ""; addOpen = true }
    function closeAddGame() { addOpen = false; addImportPath = ""; lib.forceActiveFocus() }
    function selectAddedGame() {
        if (!addedGameId || !api.games.some(game => game.id === addedGameId)) return
        selectById(addedGameId)
        addedGameId = ""
    }
    readonly property bool mainNavVisible: page === "home" || page === "library" || page === "all" || page === "store"
    readonly property var mainNavTabs: [
        {key:"home", label:qsTr("Inicio")}, {key:"library", label:qsTr("Biblioteca")}, {key:"store", label:qsTr("Catálogo")},
        {key:"downloads", label:qsTr("Descargas")}
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
        else if (i === 3) openDownloads()
        else if (i === menuIndex) quickMenu.show()
        else if (suiteNotice.available && i === updateIndex) suiteNotice.activate()
        else if (i === addIndex) openAddGame()
    }
    function handleMainNav(key) {
        if (mainNavIndex < 0) return false
        if (key === "l" || key === "r") mainNavIndex = (mainNavIndex + (key === "l" ? powerIndex : 1)) % (powerIndex + 1)
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
    function requestExit() {
        exitConfirmChoice = 0
        exitConfirmOpen = true
        sfx.play("open")
    }
    function finishExitConfirmation() {
        if (!exitConfirmOpen) return
        exitConfirmOpen = false
        if (exitConfirmChoice === 0) { sfx.play("back"); lib.forceActiveFocus(); return }
        sfx.play("confirm")
        lib.closeRequested()
    }
    function openAll() { if (!api.games.length) return; page = "all"; allGames.selId = current ? current.id : ""; allGames.rebuild(); lib.forceActiveFocus() }
    // ---- menú contextual del juego (X / clic derecho / M)
    GameActions { id: gameActions }
    function menuItems(g) { return gameActions.entries(g) }
    property var menuGame: null
    property var menuRemoval: null
    function openMenu(g) {
        g = g || current
        if (!g) return
        menuGame = g
        menuRemoval = null
        ctxMenu.items = menuItems(g)
        ctxMenu.title = g.name
        ctxMenu.subtitle = ""
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
        else if (key === "folder") api.openInstallationFolder(g.id, (status, body) => { if (status !== 200 && body.error) api.notify(body.error) })
        else if (key === "uninstall") {
            const requestedPage = page
            api.removalPreview(g.id, (status, body) => {
                if (menuGame !== g || page !== requestedPage) return
                if (status !== 200) { menuGame = null; gameActions.removalResult(api, status, body); return }
                menuRemoval = body
                ctxMenu.title = qsTr("Desinstalar %1").arg(g.name)
                ctxMenu.subtitle = gameActions.uninstallText(body)
                ctxMenu.items = [
                    {key: "backInstall", label: qsTr("Cancelar"), icon: "chevron-left"},
                    {key: "confirmUninstall", label: qsTr("Desinstalar juego"), icon: "trash-2"}
                ]
                ctxMenu.show()
            })
            return
        }
        else if (key === "remove") {
            ctxMenu.title = g.name
            ctxMenu.subtitle = qsTr("El juego dejará de aparecer en Omnia. Sus archivos no se borrarán del disco.")
            ctxMenu.items = [
                {key: "backInstall", label: qsTr("Cancelar"), icon: "chevron-left"},
                {key: "confirmRemove", label: qsTr("Quitar de la biblioteca"), icon: "eye-off"}
            ]
            ctxMenu.show()
            return
        }
        else if (key === "backInstall") { openMenu(g); return }
        else if (key === "confirmUninstall" && menuRemoval) api.removeInstallation(g.id, menuRemoval.path, (status, body) => {
            if (status === 200) { api.refresh(); pollDownloads() }
            gameActions.removalResult(api, status, body)
        })
        else if (key === "confirmRemove") api.removeGame(g, (status, body) => {
            if (status !== 200) api.notify(body.error || qsTr("No se pudo quitar el juego de Omnia."))
        })
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
            lib.selectAddedGame()
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
            if (suiteNotice.pad(k)) return
            if (quickMenu.open) { lib.padSound(k === "MODE" ? "B" : k); quickMenu.pad(k); return }
            if (k === "MODE" && !lib.exitConfirmOpen && !api.covered) { lib.padSound("X"); quickMenu.show(); return }
            if (lib.exitConfirmOpen) {
                if (k === "l" || k === "r") { lib.exitConfirmChoice = lib.exitConfirmChoice === 0 ? 1 : 0; sfx.play("move") }
                else if (k === "A") lib.finishExitConfirmation()
                else if (k === "B") { lib.exitConfirmOpen = false; sfx.play("back"); lib.forceActiveFocus() }
                return
            }
            lib.padSound(k)
            if (portDialog.open) { portDialog.pad(k); return }
            if (vkb.open) { vkb.pad(k); return }
            if (lib.addOpen) return
            if (ctxMenu.open) { ctxMenu.pad(k); return }
            if (k === "START" && transferBar.visible && lib.page !== "downloads") { lib.openDownloads(); return }
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
                const dm = { l: "left", r: "right", u: "up", d: "down", A: "accept", B: "back", X: "menu", LB: "tabprev", RB: "tabnext" }
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
        if (suiteNotice.opened) {
            e.accepted = suiteNotice.pad(e.key === Qt.Key_Left ? "l" : e.key === Qt.Key_Right ? "r"
                : e.key === Qt.Key_Escape ? "B" : e.key === Qt.Key_Return || e.key === Qt.Key_Enter ? "A" : "")
            return
        }
        if (lib.exitConfirmOpen) {
            if (e.key === Qt.Key_Left || e.key === Qt.Key_Right || e.key === Qt.Key_Tab) { lib.exitConfirmChoice = lib.exitConfirmChoice === 0 ? 1 : 0; sfx.play("move") }
            else if (e.key === Qt.Key_Return || e.key === Qt.Key_Enter || e.key === Qt.Key_Space) lib.finishExitConfirmation()
            else if (e.key === Qt.Key_Escape) { lib.exitConfirmOpen = false; sfx.play("back"); lib.forceActiveFocus() }
            e.accepted = true
            return
        }
        lib.keySound(e)
        if (e.key === Qt.Key_M && (e.modifiers & Qt.ControlModifier)) { quickMenu.toggle(); e.accepted = true; return }
        if (portDialog.open) { e.accepted = portDialog.key(e); return }
        if (ctxMenu.open) { e.accepted = ctxMenu.key(e); return }
        if (vkb.open) { e.accepted = vkb.key(e); return }
        if (lib.addOpen) return
        if (page === "store" && mainNavIndex < 0 && !(e.modifiers & Qt.ControlModifier)) { e.accepted = bigStoreView.key(e); return }
        if (mainNavIndex >= 0) {
            const navKeys = { [Qt.Key_Left]:"l", [Qt.Key_Right]:"r", [Qt.Key_Down]:"d", [Qt.Key_Escape]:"B", [Qt.Key_Return]:"A", [Qt.Key_Enter]:"A" }
            e.accepted = !!navKeys[e.key] && handleMainNav(navKeys[e.key])
            return
        }
        if (mainNavVisible && (e.modifiers & Qt.ControlModifier)) {
            const i = [Qt.Key_1, Qt.Key_2, Qt.Key_3, Qt.Key_4].indexOf(e.key)
            if (i >= 0) { activateMainNav(i); e.accepted = true; return }
            if (e.key === Qt.Key_O && page === "library") { openAddGame(); e.accepted = true; return }
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
        else if (e.key === Qt.Key_Slash || (e.key === Qt.Key_F && (e.modifiers & Qt.ControlModifier))) { searchOpen = true; header.searchField.forceActiveFocus() }
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
    OmniaBigHeader {
        id: header
        anchors { left: parent.left; right: parent.right; top: parent.top; leftMargin: lib.s * 48; rightMargin: lib.s * 40; topMargin: lib.s * 22 }
        host: lib
    }

    OmniaQuickMenu {
        id: quickMenu
        host: lib
        onOpenChanged: if (!open) lib.restorePage(lib.page)
        onSettingsRequested: lib.openSettings()
        onDesktopRequested: lib.closeRequested()
    }

    OmniaLibraryHero {
        id: hero
        host: lib
    }

    OmniaBigShelf {
        id: shelf
        host: lib
        sounds: sfx
        transferInset: transferBar.visible ? transferBar.height + lib.s * 15 : 0
    }

    TransferStrip {
        id: transferBar
        z: 15
        anchors {
            left: parent.left; right: parent.right
            bottom: lib.mainNavVisible ? footer.top : parent.bottom
            margins: lib.s * 48; bottomMargin: lib.mainNavVisible ? lib.s * 23 : lib.s * 12
        }
        visible: !!current && !intro.active && !ctxMenu.open && !vkb.open && !portDialog.open && !lib.addOpen
        jobs: lib.dlJobs
        uiScale: lib.s * 1.30
        ink: lib.ink
        accent: lib.ring
        shortcutHint: lib.padOn ? "START" : "F8"
        onClicked: if (lib.page !== "downloads") lib.openDownloads()
    }
    Shortcut {
        sequence: "F8"
        enabled: transferBar.visible && lib.page !== "downloads"
        onActivated: lib.openDownloads()
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
            Hint { visible: lib.page === "store" && !bigStoreView.detail && !bigStoreView.contextGame; padKeys: lib.padOn ? ["Y"] : []; glyph: "Y"; label: qsTr("Descargas") }
            Hint { visible: lib.page === "store" && !!bigStoreView.contextGame; padKeys: lib.padOn ? ["Y"] : []; glyph: "M"; label: qsTr("Menú") }
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
        height: lib.height - y - lib.s * 112 - (transferBar.visible ? transferBar.height + lib.s * 15 : 0)
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

    Loader {
        anchors.fill: parent
        z: 59
        active: lib.addOpen
        sourceComponent: lib.addImportPath ? importGameComponent : addGameComponent
    }
    Component {
        id: addGameComponent
        AddGame {
            api: lib.api
            libraryFinish: true
            nameKeyboard: lib.padOn
            onFinished: lib.closeAddGame()
            onAdded: function(id) { lib.addedGameId = id; lib.closeAddGame(); lib.selectAddedGame() }
            onImportRequested: function(path) { lib.addImportPath = path }
            onNameEditRequested: function(initial) {
                let pending = initial
                lib.openKeyboardFor(initial, value => pending = value,
                                    accepted => finishNameEdit(accepted ? pending : undefined))
            }
        }
    }
    Component {
        id: importGameComponent
        ImportPanel {
            api: lib.api
            path: lib.addImportPath
            onFinished: lib.closeAddGame()
            onImported: { lib.closeAddGame(); lib.api.refresh() }
        }
    }

    // ================= inicio del catálogo =================
    OmniaHome {
        id: home
        anchors.fill: parent
        visible: lib.page === "home"
        api: lib.api            // «api: api» se resolvía a la propiedad del propio Inicio (nula)
        localGames: lib.api.games
        footerSpace: transferBar.visible ? transferBar.height + lib.s * 18 : 0
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
        anchors { left: parent.left; right: parent.right; top: parent.top
            bottom: transferBar.visible ? transferBar.top : parent.bottom }
        host: lib
        visible: lib.page === "downloads"
        onBack: lib.closeDownloads()
    }

    // ================= editor de arte (menú contextual → Cambiar arte) =================
    OmniaArtEditor {
        id: artEditor
        editSearchWithPad: function(initial, done) {
            let value = initial
            lib.openKeyboardFor(initial, text => value = text, accepted => done(accepted ? value : undefined))
        }
        anchors { left: parent.left; right: parent.right; top: parent.top
            bottom: transferBar.visible ? transferBar.top : parent.bottom }
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
        anchors { left: parent.left; right: parent.right; top: header.bottom; bottom: transferBar.visible ? transferBar.top : footer.top
                  leftMargin: lib.s * 66; rightMargin: lib.s * 66; topMargin: lib.s * 18; bottomMargin: lib.s * 22 }
        host: lib
        accounts: bigStoreAccounts
        visible: lib.page === "store"
    }

    // ================= ajustes de BigMode =================
    OmniaBigSettings {
        id: settings
        anchors { left: parent.left; right: parent.right; top: parent.top
            bottom: transferBar.visible ? transferBar.top : parent.bottom }
        host: lib
        storeAccounts: bigStoreAccounts
        visible: lib.page === "settings"
        onBack: lib.closeSettings()
    }

    // ================= ficha de detalles (pantalla completa) =================
    OmniaGameDetails {
        id: details
        anchors { left: parent.left; right: parent.right; top: parent.top
            bottom: transferBar.visible ? transferBar.top : parent.bottom }
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

    Rectangle {
        anchors.fill: parent
        z: 100
        visible: lib.exitConfirmOpen
        color: "#B8000000"
        MouseArea { anchors.fill: parent }
        Rectangle {
            anchors.centerIn: parent
            width: Math.min(parent.width - lib.s * 64, lib.s * 620)
            height: exitDialogContent.implicitHeight + lib.s * 48
            radius: lib.s * 20
            color: "#192F46"
            border.width: 1
            border.color: lib.surfaceBorder
            Column {
                id: exitDialogContent
                anchors { fill: parent; margins: lib.s * 24 }
                spacing: lib.s * 16
                Text { text: qsTr("¿Cerrar Big Mode?"); color: lib.ink; font.family: lib.uiFont; font.pixelSize: lib.s * 28; font.weight: Font.DemiBold }
                Text { width: parent.width; text: qsTr("Volverás al escritorio. ¿Quieres cerrar Big Mode?"); wrapMode: Text.WordWrap; color: lib.ink2; font.family: lib.uiFont; font.pixelSize: lib.s * 19 }
                Row {
                    anchors.right: parent.right
                    spacing: lib.s * 12
                    Repeater {
                        model: [qsTr("Cancelar"), qsTr("Cerrar Big Mode")]
                        delegate: Rectangle {
                            required property string modelData
                            required property int index
                            width: exitButtonText.implicitWidth + lib.s * 38
                            height: lib.s * 46
                            radius: height / 2
                            color: lib.exitConfirmChoice === index ? lib.accent : Qt.rgba(1, 1, 1, 0.08)
                            border.width: lib.exitConfirmChoice === index ? 2 : 1
                            border.color: lib.exitConfirmChoice === index ? lib.ring : lib.surfaceBorder
                            Text { id: exitButtonText; anchors.centerIn: parent; text: modelData; color: lib.ink; font.family: lib.uiFont; font.pixelSize: lib.s * 17; font.weight: Font.DemiBold }
                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                onClicked: { lib.exitConfirmChoice = index; lib.finishExitConfirmation() }
                            }
                        }
                    }
                }
            }
        }
    }

    Component.onCompleted: forceActiveFocus()

    // ================= sonidos y bienvenida =================
    OmniaSounds { id: sfx; api: lib.api; muted: lib.api.gameRunning || lib.api.covered }
    OmniaIntro { id: intro; anchors.fill: parent; host: lib }
    Connections {
        target: lib.api
        function onPrefsLoadedChanged() { lib.maybeIntro(false) }
        function onRevisionChanged() { lib.maybeIntro(false) }
    }
    Timer { interval: 60; running: true; onTriggered: lib.maybeIntro(false) }
    Timer { id: introFallback; interval: 450; onTriggered: lib.maybeIntro(true) }
    property bool padSoundsArmed: false
    Timer { interval: 4000; running: true; onTriggered: lib.padSoundsArmed = true }
    Connections { target: lib.api; function onPadOnChanged() { if (lib.padSoundsArmed && !intro.active) sfx.play(lib.api.padOn ? "pad-on" : "pad-off") } }
}

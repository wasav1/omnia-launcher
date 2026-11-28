import QtQuick
import QtQuick.Controls
import Qt5Compat.GraphicalEffects
import "Theme.js" as Theme

/** Centro de control de escritorio de Omnia: biblioteca, catálogo y acceso a Big Mode. */
Item {
    id: manager
    property string page: "home"
    property string query: ""
    property var onlineGames: []
    property var onlineMeta: ({})
    property int onlinePage: 1
    property int onlinePageSize: 30
    property string exploreFilter: "all"
    property string exploreSort: "year-desc"
    property var detailGame: null
    property var storeDetailItem: null
    property var packageOptions: []
    property var selectedPackage: null
    property var installJobs: []
    property var installedPackages: []                   // paquetes que Omnia instaló (package-installs.json)
    property var seenJobStatus: ({})                     // id -> último estado visto, para avisar una sola vez cuando un trabajo termina bien
    property string packageMessage: ""
    property bool packagesBusy: false
    property bool acceptLicense: false
    property var libraryRoots: []
    property string rootPath: ""
    property string rootsMessage: ""
    property var romResults: []
    property string romMessage: ""
    property bool romScanning: false
    property bool romMatching: false
    property int romScanGeneration: 0
    property bool addWizardOpen: false
    property bool importPanelOpen: false
    property string importPath: ""
    property bool onlineBusy: false
    property string onlineWarning: ""
    property bool showHiddenGames: false
    property string settingsSection: "general"
    readonly property bool storeSettingsOpen: page === "settings" && settingsSection === "stores"
    onStoreSettingsOpenChanged: {
        storesView.accountsOpen = storeSettingsOpen
        if (storeSettingsOpen) storesView.refreshStores()
        else storesView.linking = ""
    }
    function openStoreSettings() {
        settingsSection = "stores"
        selectPage("settings")
    }
    property string catalogLinkTargetId: ""
    // Efecto cristal (Ajustes → Apariencia); se apaga solo mientras haya un juego abierto.
    readonly property bool gameRunning: (api.games || []).some(g => g.running)
    readonly property bool glassActive: api.glassEffect && !gameRunning
    readonly property Item glassBackdrop: glassActive ? ambient : null
    property var bigModeWindow: null
    readonly property alias desktopBackend: api
    readonly property color bg: "#0B0F14"
    readonly property color surface: "#111C27"
    readonly property color surface2: "#192837"
    readonly property color ink: "#F0F3F7"
    readonly property color muted: "#B8C3D0"
    readonly property color accent: "#167E87"
    // El tamaño de ventana reorganiza el contenido, no reduce los controles ni la tipografía.
    readonly property real s: 1
    readonly property real cs: 1
    // Tamaños fijos (Theme.js): la barra superior no escala, solo se reorganiza.
    readonly property bool commandCompact: width < Theme.breakpoint.commandField
    readonly property bool navIconsOnly: width < Theme.breakpoint.navIcons
    readonly property bool compactNav: navIconsOnly
    readonly property bool narrowContent: width < 880
    readonly property var recentGames: {
        const games = (api.games || []).filter(g => !g.hidden)
        games.sort((a,b) => Number(b.added || 0) - Number(a.added || 0))
        return games.slice(0, 5)
    }
    readonly property var exploreSources: [
        { k: "all", label: qsTr("Todas"), logo: "" },
        { k: "omnia", label: qsTr("Omnia (ports)"), logo: "images/stores/omnia.svg" },
        { k: "steam", label: "Steam", logo: "images/stores/steam.svg" },
        { k: "epic", label: "Epic", logo: "images/stores/epic.svg" },
        { k: "gog", label: "GOG", logo: "images/stores/gog.svg" },
        { k: "amazon", label: "Amazon", logo: "images/stores/amazon.svg" }
    ]
    readonly property var exploreItems: {
        const q = String(query || "").trim().toLowerCase()
        const source = []
        if (exploreFilter === "all" || exploreFilter === "omnia") onlineGames.forEach(function(g) {
            source.push({ kind: "omnia", game: g, name: g.name || "", art: manager.imageFor(g, ["grid", "hero"]), store: qsTr("Omnia · ports"), logo: "images/stores/omnia.svg", platform: (g.platforms || []).map(p => p.name || p.slug).join(" · "), info: [g.year || g.releaseYear || "", (g.genres || []).slice(0, 2).join(" · ")].filter(Boolean).join(" · "), year: Number(g.year || g.releaseYear || 0), installed: !!manager.localMatch(g) })
        })
        if (exploreFilter !== "omnia") storesView.allItems.forEach(function(i) {
            if (exploreFilter === "all" || i.store === exploreFilter) source.push({ kind: "store", item: i, name: i.name || "", art: i.art || "", store: storesView.names[i.store] || "", logo: manager.storeLogo(i.store), platform: i.local ? (i.local.platform || i.local.sub || "PC") : "PC", info: i.installed ? qsTr("En biblioteca") : qsTr("Disponible para instalar"), year: Number((i.local && (i.local.year || i.local.releaseYear)) || i.year || 0), installed: !!i.installed })
        })
        const filtered = source.filter(function(i) { return !q || (i.name + " " + i.store + " " + i.platform).toLowerCase().indexOf(q) >= 0 })
        filtered.sort(function(a, b) {
            const yearA = Number(a.year || 0), yearB = Number(b.year || 0)
            if (manager.exploreSort === "year-asc" && yearA !== yearB) return (yearA || 9999) - (yearB || 9999)
            if (manager.exploreSort === "year-desc" && yearA !== yearB) return (yearB || 0) - (yearA || 0)
            const byName = a.name.localeCompare(b.name, api.language === "en" ? "en" : "es", { sensitivity: "base" })
            return manager.exploreSort === "name-desc" ? -byName : byName
        })
        return filtered
    }
    Api { id: api; controlsEnabled: false; systemEnabled: true }
    Component.onCompleted: {
        loadOnline(1)
        if (api.arg("--open-big-mode", "0") === "1") Qt.callLater(manager.openBigMode)
    }
    SuiteUpdateNotice {
        id: suiteNotice
        anchors.fill: parent
        api: manager.desktopBackend
        surface: "desktop"
        activeSurface: manager.bigModeWindow === null
        uiScale: manager.s
    }
    Timer { interval: 6000; repeat: true; running: manager.visible; onTriggered: api.refresh() }
    // La lista abierta mantiene respuesta rápida; con transferencias en curso se actualiza cada 2.5 s;
    // en reposo basta consultar cada 15 s para no sondear el servicio continuamente.
    Timer { interval: manager.page === "installs" ? 1500 : manager.activeInstalls.length ? 2500 : 15000; repeat: true; running: manager.visible && api.ok; triggeredOnStart: true; onTriggered: manager.loadInstallations() }

    function loadOnline(page, append) {
        const requestedPage = page !== undefined ? Math.max(1, Number(page) || 1) : onlinePage
        if (requestedPage !== onlinePage || !append) onlinePage = requestedPage
        onlineBusy = true
        api.catalogGames({page: requestedPage, pageSize: onlinePageSize, sort: "updatedAt", order: "desc", q: query}, function(status, body) {
            manager.onlineBusy = false
            if (status === 200 && body) {
                const received = body.items || []
                manager.onlineGames = append ? manager.onlineGames.concat(received.filter(function(g) { return !manager.onlineGames.some(x => x.id === g.id) })) : received
                manager.onlineMeta = body.meta || {}
                manager.onlinePage = Number(manager.onlineMeta.page) || requestedPage
                const catalogNotice = body.warning ? (api.language === "en" ? api.localizeNotice(body.warning) : body.warning) : ""
                manager.onlineWarning = manager.catalogLinkTargetId
                    ? qsTr("Elige una ficha para vincularla con el juego seleccionado.") + (catalogNotice ? " · " + catalogNotice : "")
                    : catalogNotice
            } else manager.onlineWarning = (body && body.error) || qsTr("No se pudo cargar el catálogo.")
        })
    }
    function loadNextOnline() {
        const total = Number(onlineMeta.totalPages) || 1
        if (!onlineBusy && onlinePage < total) loadOnline(onlinePage + 1, true)
    }
    function goOnlinePage(n) {
        const pages = Math.max(1, Number(onlineMeta.totalPages) || 1)
        const next = Math.max(1, Math.min(pages, n))
        if (next !== onlinePage && !onlineBusy) loadOnline(next)
    }
    function changeOnlinePage(delta) {
        const pages = Math.max(1, Number(onlineMeta.totalPages) || 1)
        const next = Math.max(1, Math.min(pages, onlinePage + delta))
        if (next !== onlinePage && !onlineBusy) loadOnline(next)
    }
    function startCatalogLink(game) {
        catalogLinkTargetId = game.id
        query = ""
        page = "library"
        loadOnline(1)
        storesView.open()
        managerLibrary.showAll = false
        managerLibrary.catalog.focusSearch()
    }
    function cancelCatalogLink() {
        catalogLinkTargetId = ""
        onlineWarning = ""
        loadOnline(1)
    }
    function linkCatalogGame(remote) {
        if (!catalogLinkTargetId || !remote || !remote.slug) return
        const id = catalogLinkTargetId
        api.call("POST", "/game/catalog-link", function(status, body) {
            if (status === 200) {
                manager.catalogLinkTargetId = ""
                manager.onlineWarning = ""
                api.refresh()
                api.notify(qsTr("Ficha vinculada a la biblioteca local."))
            } else manager.onlineWarning = (body && body.error) || qsTr("No se pudo vincular la ficha.")
        }, {id: id, slug: remote.slug})
    }
    readonly property var activeInstalls: installJobs.filter(job => ["queued", "downloading", "verifying", "extracting", "finalizing", "paused"].includes(job.status))
    // Argumentos de arranque (los usa el panel rápido: instalar o actualizar abre esta app, no Big Mode):
    //   --game ID [--install-port | --update-port]   abre la ficha del juego y su diálogo      --downloads   abre Descargas
    property bool argsApplied: false
    function applyLaunchArgs() {
        argsApplied = true
        const args = Qt.application.arguments
        if (args.indexOf("--downloads") >= 0) { selectPage("installs"); return }
        const id = api.arg("--game", "")
        const game = id ? (api.games || []).find(function(g) { return g.id === id }) : null
        if (!game) return
        openGameInLibrary(game)
        if (args.indexOf("--install-port") >= 0) Qt.callLater(function() { installPortFor(game) })
        else if (args.indexOf("--update-port") >= 0) Qt.callLater(function() { updateFor(game) })
    }
    Connections {
        target: api
        function onGamesChanged() { if (!manager.argsApplied && api.games.length > 0) manager.applyLaunchArgs() }
    }
    function openGameInLibrary(game) { selectPage("library"); if (game) managerLibrary.selectGame(game.id) }
    function libraryAction(act) {
        if (act === "add") addWizardOpen = true
        else if (act === "roms") folderDialogs.openRomFolder()
        else if (act === "refresh") api.call("POST", "/library/refresh", function(status) { api.refresh(); if (status !== 200) api.notify(qsTr("No se pudo actualizar la biblioteca.")) })
        else if (act === "hidden") showHiddenGames = !showHiddenGames
    }
    GameActions { id: gameActions }
    property var contextualGame: null
    property var contextualOffer: null
    function openOfferMenu(offer) {
        if (!offer) return
        contextualGame = null
        contextualOffer = offer
        desktopMenu.items = [{key: "offer", label: qsTr("Ver opciones de instalación"), icon: "download"}]
        desktopMenu.title = offer.name
        desktopMenu.show()
        desktopMenu.forceActiveFocus()
    }
    function openGameMenu(game) {
        if (!game) return
        contextualGame = game
        contextualOffer = null
        desktopMenu.items = gameActions.entries(game)
        desktopMenu.title = game.name
        desktopMenu.show()
        desktopMenu.forceActiveFocus()
    }
    OmniaContextMenu {
        id: desktopMenu
        anchors.fill: parent; z: 50
        uiScale: manager.s; ink: manager.ink; ink2: manager.muted; accent: manager.accent
        Keys.onPressed: event => event.accepted = desktopMenu.key(event)
        onActivated: key => {
            const game = manager.contextualGame
            const offer = manager.contextualOffer
            manager.contextualGame = null
            manager.contextualOffer = null
            if (offer?.kind === "omnia") manager.openCatalogDetail(offer.game)
            else if (offer?.item) manager.openStoreDetail(offer.item)
            else manager.gameAction(key, game)
        }
        onClosed: { manager.contextualGame = null; manager.contextualOffer = null }
    }
    OmniaArtEditor {
        id: desktopArt
        anchors.fill: parent; z: 48
        visible: false
        host: QtObject {
            readonly property real s: manager.s
            readonly property var api: manager.desktopBackend
            readonly property color surface: manager.surface
            readonly property color ink: manager.ink
            readonly property color ink2: manager.muted
            readonly property color accent: manager.accent
            readonly property color pageShade: "#F00B1118"
            readonly property string uiFont: "Hanken Grotesk"
            function keySound(event) {}
        }
        onBack: visible = false
    }
    function gameAction(act, game) {
        if (!game) return
        if (act === "port") installPortFor(game)
        else if (act === "play") launch(game)
        else if (act === "update") updateFor(game)
        else if (act === "details") openGameInLibrary(game)
        else if (act === "fav") api.toggleFav(game)
        else if (act === "saves") api.savesOpen(game, (status, body) => { if (status !== 200 && body.error) api.notify(body.error) })
        else if (act === "art") { desktopArt.visible = true; desktopArt.start(game); desktopArt.forceActiveFocus() }
        else if (act === "folder") api.openInstallationFolder(game.id, (status, body) => { if (status !== 200 && body.error) api.notify(body.error) })
        else if (act === "uninstall") confirmationDialogs.askUninstallFor(game)
        else if (act === "hide") api.call("POST", "/game/hide?id=" + encodeURIComponent(game.id), function(status) { if (status === 200) api.refresh(); else api.notify(qsTr("No se pudo actualizar el juego.")) })
        else if (act === "link") startCatalogLink(game)
        else if (act === "unlink") api.call("POST", "/game/catalog-link", function(status, body) {
            if (status === 200) { api.refresh(); api.notify(qsTr("Vínculo del catálogo retirado.")) }
            else api.notify((body && body.error) || qsTr("No se pudo retirar el vínculo."))
        }, {id: game.id, slug: ""})
        else if (act === "remove") confirmationDialogs.unlinkGame(game)
    }
    function installPortFor(game) {         // «Port disponible»: abre la ficha del catálogo con su paquete, licencia y botón Instalar
        if (!game || !game.portAvailable) return
        openCatalogDetail({slug: game.portAvailable.slug, name: game.name, description: game.description})
    }
    function openStoreDetail(item) {
        if (!item) return
        if (item.local) { openGameInLibrary(item.local); return }
        storeDetailItem = item
    }
    function installStoreDetail() {
        const item = storeDetailItem
        if (!item) return
        storeDetailItem = null
        if (item.store === "steam") storesView.installSteam(item)
        else storesView.askInstall(item)
    }
    function gameById(id) { return api.games.find(g => g.id === id) || null }
    function localMatch(remote) {
        if (!remote) return null
        const slug = String(remote.slug || "").toLowerCase().replace(/[^a-z0-9]+/g, "-").replace(/^-|-$/g, "")
        return api.games.find(g => !g.portAvailable && (g.catalogSlug === remote.slug || g.id === slug || String(g.id).endsWith("-" + slug))) || null
    }
    function launch(game) {
        if (game && game.portAvailable) { installPortFor(game); return }          // sin port instalado no se puede jugar: se ofrece instalarlo
        if (!game || !game.ports || !game.ports.length) return
        const port = game.ports.find(p => p.canLaunch && !p.running) || game.ports[0]
        api.launch(game, port.id)
    }
    function openBigMode() {
        if (bigModeWindow) return
        api.padSeq = -1
        api.controlsEnabled = true
        bigModeWindow = bigModeComponent.createObject(manager)
        if (bigModeWindow) bigModeWindow.show()
        else api.controlsEnabled = false
    }
    function closeBigMode() {
        if (bigModeWindow) bigModeWindow.close()
    }
    function imageFor(game, types) {
        const art = game && game.artwork ? Array.from(game.artwork) : []
        for (let type of types) {
            const item = art.find(x => x && x.type === type && x.imageUrl)
            if (item) return item.localUrl || (item.imageUrl.startsWith("/") ? (api.catalogBaseUrl + item.imageUrl) : item.imageUrl)
        }
        return ""
    }
    function sourceForGame(game) {
        if (game && game.src === "Steam") return { label: "Steam", logo: "images/stores/steam.svg" }
        const sub = String(game && game.sub || "")
        if (sub.indexOf("Epic") >= 0) return { label: "Epic", logo: "images/stores/epic.svg" }
        if (sub.indexOf("GOG") >= 0) return { label: "GOG", logo: "images/stores/gog.svg" }
        if (sub.indexOf("Amazon") >= 0) return { label: "Amazon", logo: "images/stores/amazon.svg" }
        return { label: qsTr("Omnia · ports"), logo: "images/stores/omnia.svg" }
    }
    function storeLogo(key) {
        return ({ steam: "images/stores/steam.svg", epic: "images/stores/epic.svg", gog: "images/stores/gog.svg", amazon: "images/stores/amazon.svg" })[key] || ""
    }
    // Desde la fase 2 el Catálogo vive dentro de Biblioteca: «catalog» y «stores» llevan ahí y
    // ponen el foco en el buscador del Catálogo.
    function selectPage(key) {
        const toCatalog = key === "catalog" || key === "stores"
        if (toCatalog) key = "library"
        if (key !== page) { detailGame = null; storeDetailItem = null }   // las fichas emergentes no siguen abiertas en otra sección
        if (key === "home" && onlineGames.length === 0 && !onlineBusy) loadOnline(1)
        if (key !== "library" && catalogLinkTargetId) catalogLinkTargetId = ""
        page = key
        if (key === "library") { loadOnline(); storesView.open() }
        if (toCatalog) {
            managerLibrary.showAll = false
            if (managerLibrary.detailFloating) managerLibrary.closeDetail()
            managerLibrary.catalog.focusSearch()
        }
        if (key === "installs") loadInstallations()
        if (key === "stats") statsView.open()
        if (key === "settings") loadRoots()
    }
    function openCatalogDetail(game) {
        detailGame = game
        packageOptions = []
        selectedPackage = null
        packageMessage = ""
        acceptLicense = false
        packagesBusy = true
        api.catalogInstallPackages(game.slug || "", function(status, body) {
            manager.packagesBusy = false
            if (status === 200) {
                manager.packageOptions = body.items || []
                if (manager.packageOptions.length) manager.selectedPackage = manager.packageOptions[0]
                else manager.packageMessage = body.unsupported ? qsTr("El backend todavía no tiene habilitadas las instalaciones.") : body.offline ? qsTr("Sin conexión: los paquetes en caché no se pueden instalar.") : qsTr("Este juego aún no tiene un paquete instalable publicado.")
            } else manager.packageMessage = (body && body.error) || qsTr("No se pudieron consultar los paquetes.")
        })
    }
    function loadInstallations() {
        api.installationSnapshot(function(status, body) {
            if (status !== 200) return
            const jobs = body.jobs || []
            for (const job of jobs) {                     // aviso único al terminar bien (la tarjeta se quita sola a los pocos segundos)
                if (job.status === "completed" && seenJobStatus[job.id] && seenJobStatus[job.id] !== "completed")
                    api.notify(job.updateOf ? qsTr("Actualizado: %1").arg(job.name) : qsTr("Instalado: %1").arg(job.name))
                seenJobStatus[job.id] = job.status
            }
            manager.installJobs = jobs
            manager.installedPackages = body.installed || []
        })
    }
    function installationStatusLabel(status) {
        if (status === "interrupted") return qsTr("Interrumpida")
        return status
    }
    function installationErrorText(error) {
        if (error === "Omnia se reinició. Esta instalación no se reanudó; inicia una nueva descarga.")
            return qsTr("Omnia se reinició. La instalación no se reanudó; inicia una nueva descarga.")
        return error
    }
    function startPackageInstall() {
        if (!detailGame || !selectedPackage || !api.installRoot || !acceptLicense) return
        packageMessage = qsTr("Preparando descarga verificada…")
        api.startInstallation(detailGame.slug, selectedPackage.id, api.installRoot, function(status, body) {
            if (status === 200) {
                manager.packageMessage = qsTr("Instalación añadida a la cola.")
                manager.loadInstallations()
                manager.selectPage("installs")
                manager.detailGame = null
            } else manager.packageMessage = (body && body.error) || qsTr("No se pudo iniciar la instalación.")
        })
    }
    function loadRoots() {
        api.libraryRoots(function(status, body) {
            if (status === 200) manager.libraryRoots = body.roots || []
            else manager.rootsMessage = (body && body.error) || qsTr("No se pudieron leer las carpetas.")
        })
    }
    function changeRoot(action, path) {
        manager.rootsMessage = ""
        api.setLibraryRoot(action, path, function(status, body) {
            if (status === 200) {
                manager.libraryRoots = body.roots || []
                manager.rootPath = ""
                api.notify(action === "add" ? qsTr("Carpeta añadida a la biblioteca.") : qsTr("Carpeta retirada; los archivos siguen en el disco."))
            } else manager.rootsMessage = (body && body.error) || qsTr("No se pudo actualizar la biblioteca.")
        })
    }
    function scanRomFolder(path) {
        const generation = ++manager.romScanGeneration
        romScanning = true
        romMatching = false
        romMessage = qsTr("Buscando juegos de consola…")
        romResults = []
        romScanDialog.open()
        api.scanRoms(path, function(status, body) {
            if (generation !== manager.romScanGeneration) return
            manager.romScanning = false
            if (status !== 200) { manager.romMessage = (body && body.error) || qsTr("No se pudo analizar la carpeta."); return }
            manager.matchRomResults(body.items || [], generation)
            manager.romMessage = manager.romResults.length
                ? qsTr("%1 juegos reconocidos por formato o cabecera. Confirma cada uno antes de añadirlo.").arg(manager.romResults.length)
                : qsTr("No se encontraron ROMs compatibles en esta carpeta.")
            if (body.truncated) manager.romMessage += " " + qsTr("El análisis llegó al límite; elige una subcarpeta para continuar.")
            romScanDialog.open()
        })
    }
    function matchRomResults(items, generation) {
        manager.romResults = items.map(item => Object.assign({}, item, {catalogMatch: null}))
        const types = []
        items.forEach(item => { if (item.internalIdType && types.indexOf(item.internalIdType) < 0) types.push(item.internalIdType) })
        if (types.length === 0) return
        manager.romMatching = true
        const index = {}
        let pending = types.length
        types.forEach(type => api.catalogRomIdentifiers(type, function(status, body) {
            if (generation !== manager.romScanGeneration) return
            index[type] = status === 200 && body && Array.isArray(body.items) ? body.items : []
            pending -= 1
            if (pending === 0) {
                manager.romResults = items.map(item => {
                    const record = (index[item.internalIdType] || []).find(entry =>
                        entry.type === item.internalIdType &&
                        String(entry.identifier || "").toUpperCase() === String(item.internalId || "").toUpperCase() &&
                        entry.game && entry.game.slug)
                    return Object.assign({}, item, {catalogMatch: record ? record.game : null,
                                                   name: record ? record.game.name : item.name})
                })
                manager.romMatching = false
            }
        }))
    }
    function addScannedRom(item, name, system, emulator, catalogSlug) {
        api.addRom(item.path, name, system, emulator, catalogSlug, function(status, body) {
            if (status === 200) {
                manager.romResults = manager.romResults.filter(r => r.path !== item.path)
                manager.romMessage = qsTr("Añadida a la biblioteca: %1").arg(body.name || name)
            } else manager.romMessage = (body && body.error) || qsTr("No se pudo añadir la ROM.")
        })
    }
    function catalogMatchFor(item, selectedSystem) {
        if (!item || !item.catalogMatch || !item.internalIdType) return null
        const isDiscConsole = item.internalIdType === "gamecube" || item.internalIdType === "wii"
        return (isDiscConsole ? selectedSystem === "gcwii" : item.internalIdType === selectedSystem)
            ? item.catalogMatch : null
    }

    Rectangle { anchors.fill: parent; color: Theme.color.background }

    // ---------------- fondo ambiental: lo que desenfoca el cristal de la barra superior
    Item {
        id: ambient
        anchors.fill: parent
        RadialGradient {
            x: parent.width * 0.35; y: -parent.height * 0.75
            width: parent.width * 0.9; height: width
            opacity: 0.45
            gradient: Gradient { GradientStop { position: 0.0; color: Theme.color.accent } GradientStop { position: 0.5; color: "transparent" } }
        }
        RadialGradient {
            x: -parent.width * 0.25; y: parent.height * 0.3
            width: parent.width * 0.7; height: width
            opacity: 0.25
            gradient: Gradient { GradientStop { position: 0.0; color: "#7B3FBF" } GradientStop { position: 0.5; color: "transparent" } }
        }
    }

    // ---------------- navegación superior: logo, «Omnia» y menús
    GlassPanel {
        id: topbar
        anchors { left: parent.left; right: parent.right; top: parent.top
            leftMargin: Theme.size.pageMargin; rightMargin: Theme.size.pageMargin; topMargin: Theme.size.topBarMarginTop }
        height: Theme.size.topBarHeight
        radius: Theme.radius.lg
        strong: true
        backdrop: manager.glassBackdrop
        backdropRect: Qt.rect(x, y, width, height)

        Row {
            id: brand
            anchors { left: parent.left; leftMargin: 18; verticalCenter: parent.verticalCenter }
            spacing: 10
            Image { anchors.verticalCenter: parent.verticalCenter; width: 28; height: 28; source: Qt.resolvedUrl("images/omnia-mark.svg"); fillMode: Image.PreserveAspectFit; sourceSize.height: 96 }
            Text { anchors.verticalCenter: parent.verticalCenter; text: "Omnia"; color: Theme.color.ink; font.family: Theme.font.family; font.pixelSize: 21; font.weight: Font.Bold }
        }
        Rectangle { id: brandDivider; anchors { left: brand.right; leftMargin: 18; verticalCenter: parent.verticalCenter } width: 1; height: 24; color: Theme.color.glassBorderStrong }

        Row {
            id: navRow
            anchors { left: brandDivider.right; leftMargin: 14; verticalCenter: parent.verticalCenter }
            spacing: 4
            Repeater {
                model: [
                    {key: "home", label: qsTr("Inicio"), icon: "layout-grid"},
                    {key: "library", label: qsTr("Biblioteca"), icon: "folder-open"},
                    {key: "installs", label: qsTr("Descargas"), icon: "download"},
                    {key: "stats", label: qsTr("Estadísticas"), icon: "activity"},
                    {key: "settings", label: qsTr("Ajustes"), icon: "settings"}
                ]
                delegate: Rectangle {
                    id: navItem
                    required property var modelData
                    readonly property bool on: manager.page === modelData.key
                    width: manager.navIconsOnly ? Theme.size.control : navLabel.implicitWidth + 32
                    height: Theme.size.control
                    radius: 12
                    color: on ? "#24FFFFFF" : (navMouse.containsMouse ? Theme.color.glassFill : "transparent")
                    LucideIcon { visible: manager.navIconsOnly; anchors.centerIn: parent; width: 18; height: 18; name: navItem.modelData.icon; color: navItem.on ? Theme.color.inkStrong : Theme.color.soft }
                    Text { id: navLabel; visible: !manager.navIconsOnly; anchors.centerIn: parent; text: navItem.modelData.label
                        color: navItem.on ? Theme.color.inkStrong : Theme.color.soft
                        font.family: Theme.font.family; font.pixelSize: 14; font.weight: Font.DemiBold }
                    ToolTip.visible: manager.navIconsOnly && navMouse.containsMouse
                    ToolTip.text: navItem.modelData.label
                    ToolTip.delay: 450
                    Accessible.role: Accessible.Button
                    Accessible.name: navItem.modelData.label
                    MouseArea { id: navMouse; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: manager.selectPage(navItem.modelData.key) }
                }
            }
        }

        Row {
            id: topActions
            anchors { right: parent.right; rightMargin: 12; verticalCenter: parent.verticalCenter }
            spacing: 8
            Rectangle {
                id: commandField
                width: manager.commandCompact ? Theme.size.control : 260
                height: Theme.size.control; radius: 12
                color: Theme.color.inset
                border.color: commandMouse.containsMouse ? Theme.color.glassBorderStrong : Theme.color.glassBorder
                LucideIcon { x: manager.commandCompact ? (parent.width - width) / 2 : 12; anchors.verticalCenter: parent.verticalCenter; width: 16; height: 16; name: "search"; color: Theme.color.muted }
                Text { visible: !manager.commandCompact; x: 36; anchors.verticalCenter: parent.verticalCenter; text: qsTr("Buscar o ejecutar…"); color: Theme.color.muted; font.family: Theme.font.family; font.pixelSize: 13 }
                Rectangle { visible: !manager.commandCompact; anchors { right: parent.right; rightMargin: 8; verticalCenter: parent.verticalCenter }
                    width: 44; height: 20; radius: 6; color: "transparent"; border.color: Theme.color.glassBorderStrong
                    Text { anchors.centerIn: parent; text: "Ctrl K"; color: Theme.color.muted; font.family: Theme.font.family; font.pixelSize: 11 } }
                ToolTip.visible: manager.commandCompact && commandMouse.containsMouse
                ToolTip.text: qsTr("Buscar o ejecutar (Ctrl K)")
                ToolTip.delay: 450
                MouseArea { id: commandMouse; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: commandPalette.show() }
            }
            Rectangle {
                id: updateChip
                readonly property bool showLabel: manager.width >= 1480
                visible: suiteNotice.available
                width: showLabel ? updateRow.implicitWidth + 24 : Theme.size.control
                height: Theme.size.control; radius: 12
                color: Theme.color.accentSoft; border.color: Theme.color.accent
                Row {
                    id: updateRow
                    anchors.centerIn: parent; spacing: 6
                    LucideIcon { anchors.verticalCenter: parent.verticalCenter; width: 16; height: 16; name: "download"; color: Theme.color.ink }
                    Text { visible: updateChip.showLabel; anchors.verticalCenter: parent.verticalCenter; text: suiteNotice.label; color: Theme.color.ink; font.family: Theme.font.family; font.pixelSize: 12 }
                }
                ToolTip.visible: updateMouse.containsMouse
                ToolTip.text: suiteNotice.label
                MouseArea { id: updateMouse; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: suiteNotice.activate() }
            }
            Rectangle {
                id: bigModeButton
                width: bigModeRow.implicitWidth + 28
                height: Theme.size.control; radius: 12
                color: bigModeMouse.containsMouse ? Theme.color.accentLight : Theme.color.accent
                Row {
                    id: bigModeRow
                    anchors.centerIn: parent; spacing: 8
                    LucideIcon { anchors.verticalCenter: parent.verticalCenter; width: 16; height: 16; name: "gamepad-2"; color: Theme.color.accentInk }
                    Text { anchors.verticalCenter: parent.verticalCenter; text: qsTr("Big Mode"); color: Theme.color.accentInk; font.family: Theme.font.family; font.pixelSize: 13; font.weight: Font.Bold }
                }
                Accessible.role: Accessible.Button
                Accessible.name: qsTr("Big Mode")
                MouseArea { id: bigModeMouse; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: manager.openBigMode() }
            }
        }
    }

    // ---------------- barra inferior (añadir juego, descargas y estado)
    Rectangle {
        id: statusbar
        anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
        height: manager.cs * 26
        color: "#0A121B"
        Rectangle { anchors { left: parent.left; right: parent.right; top: parent.top } height: 1; color: "#1c2733" }
        Row {
            anchors { right: parent.right; rightMargin: manager.cs * 18; verticalCenter: parent.verticalCenter }
            spacing: manager.cs * 22
            Text { anchors.verticalCenter: parent.verticalCenter; text: api.gameRunning ? qsTr("Jugando") : qsTr("Omnia independiente · la biblioteca vive en este equipo"); color: "#8495A8"; font.family: "Hanken Grotesk"; font.pixelSize: manager.cs * 12 }
        }
    }

    TransferStrip {
        id: activeTransfer
        anchors { left: parent.left; right: parent.right; bottom: statusbar.top
            leftMargin: manager.s * 18; rightMargin: manager.s * 18 }
        jobs: manager.installJobs
        uiScale: manager.s
        onClicked: manager.selectPage("installs")
    }
    Shortcut {
        sequence: "F8"
        enabled: activeTransfer.visible
        onActivated: manager.selectPage("installs")
    }

    Item {
        id: content
        anchors { left: parent.left; right: parent.right; top: topbar.bottom; bottom: activeTransfer.top }
        property real pad: manager.narrowContent ? 18 : 28
        readonly property real top0: manager.narrowContent ? 12 : 18
        // Inicio: resumen, novedades y estanterías.
        ManagerHome {
            anchors.fill: parent
            manager: manager
            api: api
            contentPad: content.pad
            contentTop: content.top0
        }

        // Biblioteca local
        // Biblioteca + Catálogo en tres paneles (Instalados · Catálogo · ficha).
        ManagerLibrary {
            id: managerLibrary
            anchors.fill: parent
            visible: manager.page === "library"
            manager: manager
            api: api
            stores: storesView
            backdrop: manager.glassBackdrop
            onChooseInstallFolder: folderDialogs.openInstallFolder()
        }

        // Estadísticas de juego
        ManagerStats {
            id: statsView
            anchors.fill: parent
            visible: manager.page === "stats"
            manager: manager
            api: api
        }

        // Tiendas: biblioteca unificada (Steam, Epic, GOG, Amazon)
        ManagerStores {
            id: storesView
            anchors.fill: parent
            visible: manager.storeSettingsOpen
            accountsContainer: manager.storeSettingsOpen ? managerSettings.accountsContainer : null
            compactHost: true
            manager: manager
            api: api
        }

        // Descargas e instalaciones (pantalla propia)
        ManagerDownloads {
            anchors.fill: parent
            visible: manager.page === "installs"
            manager: manager
            api: api
        }

        // Ajustes: vista separada; estado y navegación permanecen en el gestor.
        ManagerSettings {
            id: managerSettings
            anchors.fill: parent
            manager: manager
            api: api
            stores: storesView
            backdrop: manager.glassBackdrop
            onChooseInstallFolder: folderDialogs.openInstallFolder()
        }
    }

    ManagerCatalogDetails {
        anchors.fill: parent
        manager: manager
        api: api
        stores: storesView
        onChooseInstallFolder: folderDialogs.openInstallFolder()
    }

    ManagerFolderDialogs {
        id: folderDialogs
        anchors.fill: parent
        manager: manager
        api: api
    }
    function updateFor(game) { confirmationDialogs.updateFor(game) }
    ManagerGameDialogs {
        id: confirmationDialogs
        anchors.fill: parent
        manager: manager
        api: api
        gameActions: gameActions
    }
    ManagerRomScanner {
        id: romScanDialog
        anchors.fill: parent
        manager: manager
    }

    ManagerAddFlows {
        anchors.fill: parent
        z: 20
        manager: manager
        api: api
    }

    // Paleta de comandos (Ctrl K): jugar, abrir fichas e ir a cualquier sección.
    CommandPalette {
        id: commandPalette
        manager: manager
        games: api.games
    }
    Shortcut {
        sequence: "Ctrl+K"
        onActivated: commandPalette.open ? commandPalette.hide() : commandPalette.show()
    }

    Component {
        id: bigModeComponent
        ManagerBigModeWindow { manager: manager }
    }
}

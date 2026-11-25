import QtQuick
import QtQuick.Controls
import QtQuick.Dialogs
import QtQuick.Window

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
    property var exploreDetailGame: null
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
    property string unlinkGameId: ""
    property string catalogLinkTargetId: ""
    property var bigModeWindow: null
    readonly property alias desktopBackend: api
    readonly property color bg: "#0B0F14"
    readonly property color surface: "#111C27"
    readonly property color surface2: "#192837"
    readonly property color ink: "#F0F3F7"
    readonly property color muted: "#B8C3D0"
    readonly property color accent: "#167E87"
    readonly property real s: Math.max(0.72, Math.min(1, width / 1440, height / 900))
    readonly property real cs: Math.min(s, 1)      // escala de los menús (barras): no crece con la ventana
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
    Component.onCompleted: loadOnline(1)
    Timer { interval: 6000; repeat: true; running: manager.visible; onTriggered: api.refresh() }
    Timer { interval: manager.page === "installs" ? 1500 : 5000; repeat: true; running: manager.visible && api.ok; triggeredOnStart: true; onTriggered: manager.loadInstallations() }

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
        page = "catalog"
        loadOnline(1)
        storesView.open()
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
    function openGameInLibrary(game) { page = "library"; if (game) managerLibrary.selId = game.id }
    function openLocalExploreDetail(game) { if (game) exploreDetailGame = game }
    function libraryAction(act) {
        if (act === "add") addWizardOpen = true
        else if (act === "roms") romScanFolderDialog.open()
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
        uiScale: manager.s * 0.82; ink: manager.ink; ink2: manager.muted; accent: manager.accent
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
            readonly property real s: manager.s * 0.82
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
        else if (act === "external") gameActions.openExternal(game)
        else if (act === "uninstall") { removeGameId = game.id; askUninstall() }
        else if (act === "hide") api.call("POST", "/game/hide?id=" + encodeURIComponent(game.id), function(status) { if (status === 200) api.refresh(); else api.notify(qsTr("No se pudo actualizar el juego.")) })
        else if (act === "link") startCatalogLink(game)
        else if (act === "unlink") api.call("POST", "/game/catalog-link", function(status, body) {
            if (status === 200) { api.refresh(); api.notify(qsTr("Vínculo del catálogo retirado.")) }
            else api.notify((body && body.error) || qsTr("No se pudo retirar el vínculo."))
        }, {id: game.id, slug: ""})
        else if (act === "remove") { unlinkGameId = game.id; unlinkGameDialog.open() }
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
        api.controlsEnabled = true
        if (!bigModeWindow) bigModeWindow = bigModeComponent.createObject(manager)
        if (bigModeWindow) bigModeWindow.show()
        else api.controlsEnabled = false
    }
    function closeBigMode() {
        const window = bigModeWindow
        bigModeWindow = null
        api.controlsEnabled = false
        if (window) { window.close(); window.destroy() }
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
    function selectPage(key) {
        if (key === "stores") key = "catalog"
        if (key === "home" && onlineGames.length === 0 && !onlineBusy) loadOnline(1)
        if (key !== "catalog" && catalogLinkTargetId) catalogLinkTargetId = ""
        page = key
        if (key === "catalog") loadOnline()
        if (key === "catalog") storesView.open()
        if (key === "installs") loadInstallations()
        if (key === "stores") storesView.open()
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

    Rectangle { anchors.fill: parent; color: manager.bg }

    // ---------------- navegación persistente
    Rectangle {
        id: topbar
        anchors { left: parent.left; top: parent.top; bottom: parent.bottom }
        width: manager.cs * 220
        color: "#0A121B"
        Rectangle { anchors { top: parent.top; bottom: parent.bottom; right: parent.right } width: 1; color: "#203140" }
        Column {
            id: brandRow
            anchors { left: parent.left; right: parent.right; top: parent.top; leftMargin: manager.cs * 22; topMargin: manager.cs * 24 }
            spacing: manager.cs * 5
            Row {
                spacing: manager.cs * 9
                Image { width: manager.cs * 30; height: manager.cs * 30; anchors.verticalCenter: parent.verticalCenter; source: Qt.resolvedUrl("../../assets/branding/omnia-logo.svg"); fillMode: Image.PreserveAspectFit; sourceSize.height: 96 }
                Column {
                    anchors.verticalCenter: parent.verticalCenter
                    Text { text: "Omnia"; color: manager.ink; font.family: "Hanken Grotesk"; font.pixelSize: manager.cs * 19; font.weight: Font.Bold }
                    Text { text: qsTr("DESKTOP SUITE"); color: "#8496A8"; font.family: "Hanken Grotesk"; font.pixelSize: manager.cs * 9; font.weight: Font.DemiBold; font.letterSpacing: 1.5 }
                }
            }
        }
        Column {
            anchors { left: parent.left; right: parent.right; top: brandRow.bottom; topMargin: manager.cs * 42; leftMargin: manager.cs * 10; rightMargin: manager.cs * 10 }
            spacing: manager.cs * 7
            Repeater {
                model: [
                    {key:"home",label:qsTr("Inicio"),icon:"layout-grid"},
                    {key:"library",label:qsTr("Biblioteca"),icon:"folder-open"},
                    {key:"catalog",label:qsTr("Explorar"),icon:"search"},
                    {key:"stats",label:qsTr("Estadísticas"),icon:"activity"},
                    {key:"installs",label:qsTr("Descargas"),icon:"download"}
                ]
                delegate: Rectangle {
                    id: menuItem
                    required property var modelData
                    readonly property bool on: manager.page === modelData.key
                    width: parent.width; height: manager.cs * 44; radius: manager.cs * 11
                    color: on ? "#153E4A" : (navMouse.containsMouse ? "#142330" : "transparent")
                    Rectangle { anchors { left: parent.left; top: parent.top; bottom: parent.bottom } width: manager.cs * 3; radius: width / 2; color: "#20C4C2"; visible: menuItem.on }
                    LucideIcon { x: manager.cs * 13; anchors.verticalCenter: parent.verticalCenter; width: manager.cs * 18; height: width; name: menuItem.modelData.icon; color: menuItem.on ? "#43D4CF" : (navMouse.containsMouse ? manager.ink : "#91A1B1") }
                    Text { id: menuLabel; anchors { left: parent.left; leftMargin: manager.cs * 43; verticalCenter: parent.verticalCenter } text: menuItem.modelData.label; color: menuItem.on || navMouse.containsMouse ? manager.ink : "#AAB6C2"
                        font.family: "Hanken Grotesk"; font.pixelSize: manager.cs * 14; font.weight: menuItem.on ? Font.DemiBold : Font.Medium }
                    MouseArea { id: navMouse; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: manager.selectPage(menuItem.modelData.key) }
                }
            }
        }
        Column {
            anchors { left: parent.left; right: parent.right; bottom: parent.bottom; leftMargin: manager.cs * 12; rightMargin: manager.cs * 12; bottomMargin: manager.cs * 28 }
            spacing: manager.cs * 9
            Rectangle {
                width: parent.width; height: manager.cs * 40; radius: height / 2; color: "#103A42"; border.color: "#247B80"
                Row { anchors.centerIn: parent; spacing: manager.cs * 8; LucideIcon { anchors.verticalCenter: parent.verticalCenter; width: manager.cs * 16; height: width; name: "gamepad-2"; color: "#4DD5D0" } Text { anchors.verticalCenter: parent.verticalCenter; text: qsTr("Big Mode"); color: manager.ink; font.family: "Hanken Grotesk"; font.pixelSize: manager.cs * 13; font.weight: Font.DemiBold } }
                MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: manager.openBigMode() }
            }
            Rectangle {
                width: parent.width; height: manager.cs * 40; radius: manager.cs * 10
                color: manager.page === "settings" ? "#153E4A" : (gearMouse.containsMouse ? "#142330" : "transparent")
                LucideIcon { x: manager.cs * 13; anchors.verticalCenter: parent.verticalCenter; width: manager.cs * 18; height: width; name: "settings"; color: manager.page === "settings" ? "#43D4CF" : manager.muted }
                Text { anchors { left: parent.left; leftMargin: manager.cs * 43; verticalCenter: parent.verticalCenter } text: qsTr("Ajustes"); color: manager.page === "settings" || gearMouse.containsMouse ? manager.ink : "#AAB6C2"; font.family: "Hanken Grotesk"; font.pixelSize: manager.cs * 14 }
                MouseArea { id: gearMouse; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: manager.selectPage("settings") }
            }
        }
    }

    // ---------------- barra inferior (añadir juego, descargas y estado)
    Rectangle {
        id: statusbar
        anchors { left: topbar.right; right: parent.right; bottom: parent.bottom }
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
        anchors { left: topbar.right; right: parent.right; bottom: statusbar.top
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
        anchors { left: topbar.right; right: parent.right; top: parent.top; bottom: activeTransfer.top }
        property real pad: manager.s * 34
        readonly property real top0: manager.s * 30
        Flickable {
            id: homePage
            anchors.fill: parent
            visible: manager.page === "home"
            clip: true
            contentWidth: width
            contentHeight: homeContent.height + 2 * content.top0
            boundsBehavior: Flickable.StopAtBounds
            Column {
                id: homeContent
                x: content.pad
                y: content.top0
                width: homePage.width - 2 * x
                spacing: manager.s * 18
                ManagerStoreNews {
                    width: parent.width
                    manager: explorePage.newsTheme
                    api: explorePage.newsApi
                    active: homePage.visible
                    onOpenGame: game => manager.openCatalogDetail(game)
                }
                Row {
                    spacing: manager.s * 12
                    Repeater {
                        model: [
                            {count: api.games.filter(g => !g.hidden).length, label: qsTr("JUEGOS")},
                            {count: manager.recentGames.length, label: qsTr("RECIENTES")},
                            {count: api.gameRunning ? 1 : 0, label: qsTr("EN JUEGO")}
                        ]
                        delegate: Rectangle {
                            required property var modelData
                            width: manager.s * 150; height: manager.s * 40; radius: manager.s * 12
                            color: manager.surface
                            Text {
                                anchors.centerIn: parent
                                text: modelData.count + "  " + modelData.label
                                color: manager.ink; font.family: "Hanken Grotesk"
                                font.pixelSize: manager.s * 13; font.weight: Font.DemiBold
                            }
                        }
                    }
                }
                HomeShelf {
                    heading: qsTr("Seguir jugando")
                    games: manager.recentGames
                }
                HomeShelf {
                    visible: games.length > 0
                    heading: qsTr("Favoritos")
                    games: api.games.filter(g => g.fav && !g.hidden).slice(0, 5)
                }
                Rectangle {
                    visible: manager.activeInstalls.length > 0
                    width: parent.width; height: manager.s * 64
                    radius: manager.s * 14
                    color: manager.surface
                    LucideIcon {
                        anchors { left: parent.left; leftMargin: manager.s * 16; verticalCenter: parent.verticalCenter }
                        width: manager.s * 24; height: width; name: "download"; color: manager.ink
                    }
                    Text {
                        x: manager.s * 55; anchors.verticalCenter: parent.verticalCenter
                        text: qsTr("Descargas en curso") + " · " + manager.activeInstalls.length
                        color: manager.ink; font.family: "Hanken Grotesk"; font.pixelSize: manager.s * 17; font.weight: Font.DemiBold
                    }
                    MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: manager.selectPage("installs") }
                }
            }
        }

        component HomeShelf: Column {
            id: homeShelf
            property string heading
            property var games: []
            width: parent ? parent.width : 0
            spacing: manager.s * 4
            Text { text: homeShelf.heading; color: manager.ink; font.family: "Hanken Grotesk"; font.pixelSize: manager.s * 21; font.weight: Font.DemiBold }
            Flickable {
                id: homeRow
                width: parent.width; height: manager.s * 197
                contentWidth: homeCards.implicitWidth + 2 * homeCards.x
                contentHeight: height
                flickableDirection: Flickable.HorizontalFlick
                boundsBehavior: Flickable.StopAtBounds
                clip: true
                Row {
                    id: homeCards
                    x: manager.s * 10; y: manager.s * 9
                    spacing: manager.s * 16
                    Repeater {
                        model: homeShelf.games
                        delegate: ManagerPosterCard {
                            required property var modelData
                            width: manager.s * 250; height: manager.s * 179
                            viewport: homeRow
                            scaleFactor: manager.s
                            artwork: modelData.fondo || modelData.portada || ""
                            title: modelData.name
                            sourceLogo: manager.sourceForGame(modelData).logo
                            info: modelData.lastPlayed
                                ? new Date(modelData.lastPlayed * 1000).toLocaleDateString(Qt.locale(api.language === "en" ? "en_US" : "es_CO"), "d MMM")
                                : qsTr("En tu biblioteca")
                            onContextRequested: manager.openGameMenu(modelData)
                            onActivated: manager.openGameInLibrary(modelData)
                            onDoubleActivated: manager.launch(modelData)
                        }
                    }
                }
                Text { visible: !homeShelf.games.length; anchors.verticalCenter: parent.verticalCenter; text: qsTr("Añade juegos para verlos aquí."); color: manager.muted; font.family: "Hanken Grotesk"; font.pixelSize: manager.s * 15 }
            }
        }

        // Biblioteca local
        ManagerLibrary {
            id: managerLibrary
            anchors.fill: parent
            visible: manager.page === "library"
            manager: manager
            api: api
        }

        // Explorar: novedades, instalaciones recientes y cuadrícula unificada sin paginación.
        Item {
            id: explorePage
            readonly property var newsTheme: manager
            readonly property var newsApi: api
            anchors.fill: parent
            visible: manager.page === "catalog"
            Column {
                id: exploreHeading
                x: content.pad; y: content.top0
                width: remoteSearch.x - x - manager.s * 12
                spacing: manager.s * 3
                Text {
                    text: qsTr("Explorar"); color: manager.ink
                    font.family: "Hanken Grotesk"; font.pixelSize: manager.s * 28; font.weight: Font.Bold
                }
                Text {
                    width: parent.width
                    text: qsTr("Ports de Omnia y juegos de tus tiendas, en un solo lugar.")
                    color: manager.muted; font.family: "Hanken Grotesk"; font.pixelSize: manager.s * 13
                    wrapMode: Text.WordWrap
                }
            }
            TextField {
                id: remoteSearch
                anchors.right: parent.right; anchors.rightMargin: content.pad
                y: content.top0 - manager.s * 1
                width: Math.min(parent.width * 0.43, manager.s * 510); height: manager.s * 36
                placeholderText: manager.catalogLinkTargetId ? qsTr("Buscar una ficha para vincular") : qsTr("Buscar juegos, tiendas o plataformas")
                color: manager.ink; font.family: "Hanken Grotesk"; font.pixelSize: manager.s * 14
                onAccepted: { manager.query = text; manager.loadOnline(1); exploreFlick.contentY = 0 }
                background: Rectangle { radius: manager.s * 11; color: manager.surface2; border.color: remoteSearch.activeFocus ? "#45CFC9" : "#24FFFFFF" }
            }
            Rectangle {
                visible: !!manager.catalogLinkTargetId
                anchors { right: parent.right; verticalCenter: remoteSearch.verticalCenter; rightMargin: content.pad }
                width: manager.s * 112; height: manager.s * 34; radius: manager.s * 11; color: manager.surface2
                Text { anchors.centerIn: parent; text: qsTr("Cancelar vínculo"); color: manager.ink; font.family: "Hanken Grotesk"; font.pixelSize: manager.s * 11 }
                MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: manager.cancelCatalogLink() }
            }
            Text {
                id: exploreWarning
                x: content.pad; y: Math.max(exploreHeading.y + exploreHeading.height, remoteSearch.y + remoteSearch.height) + manager.s * 4
                width: parent.width - content.pad * 2
                text: manager.onlineWarning; visible: !!text
                color: "#E8B86D"; font.family: "Hanken Grotesk"; font.pixelSize: manager.s * 11; elide: Text.ElideRight
            }
            Button {
                anchors { right: parent.right; rightMargin: content.pad; top: remoteSearch.bottom; topMargin: manager.s * 5 }
                z: 3
                text: qsTr("Cuentas de tiendas")
                onClicked: manager.openStoreSettings()
            }
            Flickable {
                id: exploreFlick
                anchors { left: parent.left; right: parent.right; top: exploreWarning.bottom; bottom: parent.bottom }
                anchors.topMargin: manager.s * 40
                clip: true
                contentWidth: width
                contentHeight: exploreContent.height
                boundsBehavior: Flickable.StopAtBounds
                Column {
                    id: exploreContent
                    x: content.pad
                    width: exploreFlick.width - content.pad * 2
                    spacing: manager.s * 17

                    ManagerStoreNews {
                        width: parent.width
                        manager: explorePage.newsTheme
                        api: explorePage.newsApi
                        active: explorePage.visible
                        onOpenGame: game => manager.openCatalogDetail(game)
                    }

                    Column {
                        width: parent.width
                        spacing: manager.s * 7
                        Item {
                            width: parent.width; height: manager.s * 24
                            Text { anchors.verticalCenter: parent.verticalCenter; text: qsTr("Últimos instalados"); color: manager.ink; font.family: "Hanken Grotesk"; font.pixelSize: manager.s * 17; font.weight: Font.DemiBold }
                            Rectangle {
                                anchors { right: parent.right; verticalCenter: parent.verticalCenter }
                                width: moreInstalled.implicitWidth + manager.s * 22; height: manager.s * 25; radius: height / 2
                                color: moreInstalledMouse.containsMouse ? "#16434E" : manager.surface2
                                Text { id: moreInstalled; anchors.centerIn: parent; text: qsTr("Ver más"); color: "#72E0DA"; font.family: "Hanken Grotesk"; font.pixelSize: manager.s * 10; font.weight: Font.DemiBold }
                                MouseArea { id: moreInstalledMouse; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: manager.selectPage("library") }
                            }
                        }
                        Flickable {
                            id: installedList
                            width: parent.width
                            height: cardHeight + 2 * zoomMargin
                            readonly property real cardHeight: manager.s * 178
                            readonly property int visibleCount: Math.max(1, manager.recentGames.length)
                            readonly property real cardWidth: Math.max(manager.s * 175,
                                (width - 2 * zoomMargin - installedRow.spacing * (visibleCount - 1)) / visibleCount)
                            readonly property real zoomMargin: Math.ceil(0.023 * Math.max(width / visibleCount, manager.s * 178)) + 2
                            contentWidth: installedRow.width + 2 * zoomMargin
                            contentHeight: height
                            clip: true
                            flickableDirection: Flickable.HorizontalFlick
                            boundsBehavior: Flickable.StopAtBounds
                            Row {
                                id: installedRow
                                x: installedList.zoomMargin; y: installedList.zoomMargin
                                width: installedList.cardWidth * installedList.visibleCount + spacing * (installedList.visibleCount - 1)
                                spacing: manager.s * 12
                                Repeater {
                                    // Los delegados sobreviven a cada actualización de la biblioteca.
                                    model: 5
                                    delegate: ManagerPosterCard {
                                        id: recentCard
                                        required property int index
                                        readonly property var game: manager.recentGames[index] || null
                                        visible: !!game
                                        width: installedList.cardWidth; height: installedList.cardHeight
                                        scaleFactor: manager.s
                                        viewport: installedList
                                        title: game?.name || ""
                                        artwork: game?.fondo || game?.portada || ""
                                        store: game ? manager.sourceForGame(game).label : ""
                                        sourceLogo: game ? manager.sourceForGame(game).logo : ""
                                        platform: game?.platform || game?.sub || ""
                                        info: String(game?.year || game?.releaseYear || "")
                                        installed: true
                                        onContextRequested: manager.openGameMenu(game)
                                        onActivated: manager.openLocalExploreDetail(game)
                                    }
                                }
                            }
                            Text {
                                visible: manager.recentGames.length === 0
                                x: installedList.zoomMargin
                                anchors.verticalCenter: parent.verticalCenter
                                text: qsTr("Tus juegos instalados aparecerán aquí.")
                                color: manager.muted
                                font.family: "Hanken Grotesk"
                                font.pixelSize: manager.s * 12
                            }
                        }
                    }

                    Item {
                        id: inlineExploreFilters
                        width: parent.width; height: manager.s * 46
                        Row {
                            id: inlineFilterRow
                            width: parent.width
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: manager.s * 6
                            Repeater {
                                model: manager.exploreSources
                                delegate: Rectangle {
                                    id: inlineChip
                                    required property var modelData
                                    readonly property bool selected: manager.exploreFilter === modelData.k
                                    width: (inlineFilterRow.width - inlineFilterRow.spacing * 5) / 6; height: manager.s * 36; radius: height / 2
                                    color: selected ? "#16434E" : "#101C27"
                                    border.color: selected ? "#45CFC9" : "#30414E"
                                    Row {
                                        anchors.centerIn: parent; spacing: manager.s * 6
                                        LucideIcon { visible: inlineChip.modelData.k === "all"; anchors.verticalCenter: parent.verticalCenter; width: manager.s * 19; height: width; name: "layout-grid"; color: inlineChip.selected ? "#72E0DA" : manager.muted }
                                        Image { visible: !!inlineChip.modelData.logo; anchors.verticalCenter: parent.verticalCenter; width: manager.s * 26; height: width; source: inlineChip.modelData.logo; sourceSize.width: 48; sourceSize.height: 48; fillMode: Image.PreserveAspectFit }
                                        Text { anchors.verticalCenter: parent.verticalCenter; text: inlineChip.modelData.label; color: inlineChip.selected ? "#72E0DA" : manager.muted; font.family: "Hanken Grotesk"; font.pixelSize: manager.s * 13; font.weight: Font.DemiBold; elide: Text.ElideRight }
                                    }
                                    MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: { manager.exploreFilter = inlineChip.modelData.k; exploreFlick.contentY = inlineExploreFilters.y } }
                                }
                            }
                        }
                    }

                    Column {
                        width: parent.width
                        spacing: manager.s * 9
                        Row {
                            width: parent.width; height: manager.s * 25; spacing: manager.s * 8
                            Text { id: exploreGridTitle; anchors.verticalCenter: parent.verticalCenter; text: manager.exploreFilter === "all" ? qsTr("Todos los juegos") : manager.exploreSources.find(function(s) { return s.k === manager.exploreFilter }).label; color: manager.ink; font.family: "Hanken Grotesk"; font.pixelSize: manager.s * 17; font.weight: Font.DemiBold }
                            Text { id: exploreGridCount; anchors.verticalCenter: parent.verticalCenter; text: qsTr("%1 juegos").arg(exploreGridRepeater.count); color: manager.muted; font.family: "Hanken Grotesk"; font.pixelSize: manager.s * 10 }
                            Item { width: Math.max(0, parent.width - sortControl.width - exploreGridTitle.implicitWidth - exploreGridCount.implicitWidth - parent.spacing * 3); height: 1 }
                            ComboBox {
                                id: sortControl
                                width: manager.s * 168; height: manager.s * 30
                                model: [qsTr("Año · recientes"), qsTr("Año · antiguos"), qsTr("Nombre · A–Z"), qsTr("Nombre · Z–A")]
                                currentIndex: ["year-desc", "year-asc", "name-asc", "name-desc"].indexOf(manager.exploreSort)
                                onActivated: manager.exploreSort = ["year-desc", "year-asc", "name-asc", "name-desc"][currentIndex]
                                contentItem: Text { leftPadding: manager.s * 10; rightPadding: manager.s * 24; text: sortControl.displayText; color: manager.ink; font.family: "Hanken Grotesk"; font.pixelSize: manager.s * 10; verticalAlignment: Text.AlignVCenter; elide: Text.ElideRight }
                                background: Rectangle { radius: manager.s * 9; color: manager.surface2; border.color: sortControl.activeFocus ? "#45CFC9" : "#30414E" }
                            }
                        }
                        Grid {
                            id: exploreGrid
                            x: zoomInset
                            width: parent.width - 2 * zoomInset
                            readonly property real gap: manager.s * 16
                            readonly property real zoomInset: Math.ceil(parent.width / columns * 0.023) + 2
                            readonly property real cardWidth: Math.max(manager.s * 112, Math.floor((width - gap * (columns - 1)) / columns))
                            readonly property real cardHeight: cardWidth * 1.42
                            columns: Math.max(2, Math.floor((parent.width + gap) / (manager.s * 185 + gap)))
                            columnSpacing: gap; rowSpacing: gap
                            height: exploreGridRepeater.count ? Math.ceil(exploreGridRepeater.count / columns) * (cardHeight + rowSpacing) - rowSpacing : 0
                            Repeater {
                                id: exploreGridRepeater
                                model: storesView.ready ? manager.exploreItems : []
                                delegate: Item {
                                    id: exploreCell
                                    required property var modelData
                                    width: exploreGrid.cardWidth; height: exploreGrid.cardHeight
                                    z: explorePoster.hovered ? 1 : 0
                                    ManagerPosterCard {
                                        id: explorePoster
                                        anchors.fill: parent
                                        scaleFactor: manager.s
                                        viewport: exploreFlick
                                        viewportTop: pinnedExploreFilters.visible ? pinnedExploreFilters.height : 0
                                        title: exploreCell.modelData.name
                                        artwork: exploreCell.modelData.art
                                        store: exploreCell.modelData.store
                                        sourceLogo: exploreCell.modelData.logo
                                        platform: exploreCell.modelData.platform
                                        info: exploreCell.modelData.info
                                        installed: exploreCell.modelData.installed
                                        onContextRequested: {
                                            const offer = exploreCell.modelData
                                            const local = offer.item?.local || manager.localMatch(offer.game)
                                            if (local) manager.openGameMenu(local)
                                            else manager.openOfferMenu(offer)
                                        }
                                        onActivated: {
                                            if (exploreCell.modelData.kind === "omnia") {
                                                const local = manager.localMatch(exploreCell.modelData.game)
                                                if (local && !manager.catalogLinkTargetId) manager.openLocalExploreDetail(local)
                                                else if (manager.catalogLinkTargetId) manager.linkCatalogGame(exploreCell.modelData.game)
                                                else manager.openCatalogDetail(exploreCell.modelData.game)
                                            }
                                            else if (exploreCell.modelData.item.local) manager.openLocalExploreDetail(exploreCell.modelData.item.local)
                                            else manager.openStoreDetail(exploreCell.modelData.item)
                                        }
                                    }
                                }
                            }
                        }
                        StoreLoading {
                            width: parent.width
                            visible: storesView.loadingContent
                            ink: manager.muted
                            uiScale: manager.s
                        }
                        Text { visible: exploreGridRepeater.count === 0 && !manager.onlineBusy && !storesView.loadingContent; text: qsTr("No hay juegos para este filtro."); color: manager.muted; font.family: "Hanken Grotesk"; font.pixelSize: manager.s * 12 }
                        Text { visible: manager.onlineBusy; text: qsTr("Cargando más juegos…"); color: manager.muted; font.family: "Hanken Grotesk"; font.pixelSize: manager.s * 11 }
                    }
                    Item { width: 1; height: manager.s * 22 }
                }
                onContentYChanged: {
                    if (contentY + height >= contentHeight - manager.s * 420) manager.loadNextOnline()
                }
            }
            Rectangle {
                id: pinnedExploreFilters
                visible: exploreFlick.contentY >= inlineExploreFilters.y && exploreFlick.contentHeight > exploreFlick.height
                z: 10
                anchors { left: exploreFlick.left; right: exploreFlick.right; top: exploreFlick.top; leftMargin: content.pad; rightMargin: content.pad }
                height: manager.s * 46; color: "#F20B1118"
                Row {
                    id: pinnedFilterRow
                    width: parent.width
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: manager.s * 6
                    Repeater {
                        model: manager.exploreSources
                        delegate: Rectangle {
                            id: pinnedChip
                            required property var modelData
                            readonly property bool selected: manager.exploreFilter === modelData.k
                            width: (pinnedFilterRow.width - pinnedFilterRow.spacing * 5) / 6; height: manager.s * 36; radius: height / 2
                            color: selected ? "#16434E" : "#101C27"
                            border.color: selected ? "#45CFC9" : "#30414E"
                            Row {
                                anchors.centerIn: parent; spacing: manager.s * 6
                                LucideIcon { visible: pinnedChip.modelData.k === "all"; anchors.verticalCenter: parent.verticalCenter; width: manager.s * 19; height: width; name: "layout-grid"; color: pinnedChip.selected ? "#72E0DA" : manager.muted }
                                Image { visible: !!pinnedChip.modelData.logo; anchors.verticalCenter: parent.verticalCenter; width: manager.s * 26; height: width; source: pinnedChip.modelData.logo; sourceSize.width: 48; sourceSize.height: 48; fillMode: Image.PreserveAspectFit }
                                Text { anchors.verticalCenter: parent.verticalCenter; text: pinnedChip.modelData.label; color: pinnedChip.selected ? "#72E0DA" : manager.muted; font.family: "Hanken Grotesk"; font.pixelSize: manager.s * 13; font.weight: Font.DemiBold; elide: Text.ElideRight }
                            }
                            MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: { manager.exploreFilter = pinnedChip.modelData.k; exploreFlick.contentY = inlineExploreFilters.y } }
                        }
                    }
                }
            }
            Rectangle {
                id: localExploreDetail
                visible: !!manager.exploreDetailGame
                anchors.fill: parent
                z: 30
                color: "#C9000000"
                MouseArea { anchors.fill: parent; onClicked: manager.exploreDetailGame = null }
                Rectangle {
                    id: localDetailPanel
                    anchors.centerIn: parent
                    width: Math.min(parent.width - manager.s * 64, manager.s * 760)
                    height: Math.min(parent.height - manager.s * 64, manager.s * 430)
                    radius: manager.s * 18; color: manager.surface; clip: true
                    MouseArea { anchors.fill: parent }
                    FadedImage {
                        anchors.fill: parent
                        source: manager.exploreDetailGame ? (manager.exploreDetailGame.fondo || manager.exploreDetailGame.portada || "") : ""
                        cornerRadius: manager.s * 18; fadeBottom: 0.55; opacity: 0.42
                    }
                    Rectangle { anchors.fill: parent; radius: manager.s * 18; color: "#A90B1118" }
                    Column {
                        id: localDetailHeading
                        anchors { left: parent.left; right: parent.right; top: parent.top; margins: manager.s * 28 }
                        spacing: manager.s * 10
                        Row {
                            spacing: manager.s * 9
                            Image { anchors.verticalCenter: parent.verticalCenter; width: manager.s * 32; height: width; source: manager.exploreDetailGame ? manager.sourceForGame(manager.exploreDetailGame).logo : ""; sourceSize.width: 64; sourceSize.height: 64; fillMode: Image.PreserveAspectFit }
                            Text { anchors.verticalCenter: parent.verticalCenter; text: manager.exploreDetailGame ? (manager.sourceForGame(manager.exploreDetailGame).label + "  ·  " + (manager.exploreDetailGame.platform || manager.exploreDetailGame.sub || "PC")) : ""; color: "#70E0D9"; font.family: "Hanken Grotesk"; font.pixelSize: manager.s * 12; font.weight: Font.DemiBold }
                        }
                        Text { width: parent.width; text: manager.exploreDetailGame ? manager.exploreDetailGame.name || "" : ""; color: manager.ink; font.family: "Hanken Grotesk"; font.pixelSize: manager.s * 30; font.weight: Font.Bold; wrapMode: Text.WordWrap }
                    }
                    ScrollView {
                        id: localFactsScroll
                        anchors { left: parent.left; right: parent.right; top: localDetailHeading.bottom; bottom: localDetailActions.top; margins: manager.s * 28; topMargin: manager.s * 10; bottomMargin: manager.s * 12 }
                        clip: true; contentWidth: availableWidth
                        GameFacts {
                            width: localFactsScroll.availableWidth
                            api: manager.desktopBackend; game: manager.exploreDetailGame; uiScale: manager.s
                            ink: manager.ink; muted: manager.muted
                        }
                    }
                    Row {
                        id: localDetailActions
                        anchors { left: parent.left; bottom: parent.bottom; margins: manager.s * 28 }
                        spacing: manager.s * 10
                        Rectangle {
                            width: manager.s * 140; height: manager.s * 40; radius: height / 2; color: "#15915F"
                            Text { anchors.centerIn: parent; text: qsTr("Jugar"); color: "white"; font.family: "Hanken Grotesk"; font.pixelSize: manager.s * 13; font.weight: Font.DemiBold }
                            MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: { const game = manager.exploreDetailGame; manager.exploreDetailGame = null; if (game) manager.launch(game) } }
                        }
                        Rectangle {
                            width: manager.s * 112; height: manager.s * 40; radius: height / 2; color: manager.surface2
                            Text { anchors.centerIn: parent; text: qsTr("Cerrar"); color: manager.ink; font.family: "Hanken Grotesk"; font.pixelSize: manager.s * 13 }
                            MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: manager.exploreDetailGame = null }
                        }
                    }
                }
            }

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
            visible: manager.page === "catalog" || manager.storeSettingsOpen
            accountsContainer: manager.storeSettingsOpen ? accountHost : null
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

        // Preferencias
        Item {
            anchors { left: parent.left; right: parent.right; top: parent.top; bottom: parent.bottom }
            visible: manager.page === "settings"
            Text { x: content.pad; y: content.top0; text: qsTr("Ajustes"); color: manager.ink; font.family: "Hanken Grotesk"; font.pixelSize: manager.s * 28; font.weight: Font.Bold }
            Column {
                x: content.pad; y: content.top0 + manager.s * 48; width: manager.s * 190; spacing: manager.s * 4
                Repeater {
                    model: [{ k: "general", l: qsTr("General") }, { k: "library", l: qsTr("Biblioteca") }, { k: "bigmode", l: qsTr("Big Mode") }, { k: "stores", l: qsTr("Cuentas de tiendas") }, { k: "about", l: qsTr("Acerca de") }]
                    delegate: Rectangle {
                        id: setTab
                        required property var modelData
                        readonly property bool on: manager.settingsSection === modelData.k
                        width: parent.width; height: manager.s * 42; radius: manager.s * 10
                        color: on ? "#16434E" : (setMa.containsMouse ? "#14FFFFFF" : "transparent")
                        Text { anchors { left: parent.left; leftMargin: manager.s * 14; verticalCenter: parent.verticalCenter } text: setTab.modelData.l; color: manager.ink; font.family: "Hanken Grotesk"; font.pixelSize: manager.s * 16; font.weight: setTab.on ? Font.DemiBold : Font.Normal }
                        MouseArea { id: setMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: manager.settingsSection = setTab.modelData.k }
                    }
                }
            }
            ScrollView {
                visible: manager.storeSettingsOpen
                anchors { left: parent.left; right: parent.right; top: parent.top; bottom: parent.bottom
                    leftMargin: content.pad + manager.s * 214; rightMargin: content.pad
                    topMargin: content.top0 + manager.s * 48; bottomMargin: manager.s * 12 }
                contentWidth: availableWidth
                clip: true
                Item {
                    id: accountHost
                    width: parent.width
                    implicitHeight: storesView.accountsHeight
                }
            }
            Column {
                x: content.pad + manager.s * 214; y: content.top0 + manager.s * 48; width: parent.width - content.pad * 2 - manager.s * 214; spacing: manager.s * 14
                Rectangle {
                    visible: manager.settingsSection === "about"
                    width: parent.width; height: manager.s * 150; radius: manager.s * 16; color: manager.surface
                    Row { anchors { left: parent.left; verticalCenter: parent.verticalCenter; leftMargin: manager.s * 22 } spacing: manager.s * 18
                        Image { width: manager.s * 72; height: width; anchors.verticalCenter: parent.verticalCenter; source: Qt.resolvedUrl("../../assets/branding/omnia-icon.svg"); sourceSize.height: 192; fillMode: Image.PreserveAspectFit }
                        Column { anchors.verticalCenter: parent.verticalCenter; spacing: manager.s * 5
                            Text { text: "Omnia Desktop Suite"; color: manager.ink; font.family: "Hanken Grotesk"; font.pixelSize: manager.s * 22; font.weight: Font.DemiBold }
                            Text { text: qsTr("Biblioteca de juegos y Big Mode para Linux. "); color: manager.muted; font.family: "Hanken Grotesk"; font.pixelSize: manager.s * 14 }
                            Text { text: qsTr("Los juegos y sus archivos viven en este equipo; Omnia no incluye ni descarga ROMs."); color: manager.muted; font.family: "Hanken Grotesk"; font.pixelSize: manager.s * 13 } }
                    }
                }
                Rectangle {
                    visible: manager.settingsSection === "bigmode"
                    width: parent.width; height: manager.s * 86; radius: manager.s * 16; color: manager.surface
                    Column { anchors { left: parent.left; verticalCenter: parent.verticalCenter; leftMargin: manager.s * 18 } spacing: manager.s * 4
                        Text { text: qsTr("Fondo animado"); color: manager.ink; font.family: "Hanken Grotesk"; font.pixelSize: manager.s * 16; font.weight: Font.DemiBold }
                        Text { text: qsTr("Constelación en el Inicio y ondas en la Biblioteca de Big Mode."); color: manager.muted; font.family: "Hanken Grotesk"; font.pixelSize: manager.s * 12 } }
                    Switch { anchors { right: parent.right; verticalCenter: parent.verticalCenter; rightMargin: manager.s * 18 }
                        checked: api.animatedBackground
                        onToggled: api.setAnimatedBackground(checked, function(status) { if (status !== 200) api.notify(qsTr("No se pudo guardar el ajuste.")) }) }
                }
                Rectangle {
                    visible: manager.settingsSection === "bigmode"
                    width: parent.width; height: manager.s * 86; radius: manager.s * 16; color: manager.surface
                    Text { anchors { left: parent.left; verticalCenter: parent.verticalCenter; leftMargin: manager.s * 18 } text: qsTr("Abrir Big Mode a pantalla completa"); color: manager.ink; font.family: "Hanken Grotesk"; font.pixelSize: manager.s * 16; font.weight: Font.DemiBold }
                    Rectangle { anchors { right: parent.right; verticalCenter: parent.verticalCenter; rightMargin: manager.s * 16 } width: manager.s * 148; height: manager.s * 40; radius: height / 2; color: manager.accent
                        Text { anchors.centerIn: parent; text: qsTr("Abrir"); color: manager.ink; font.family: "Hanken Grotesk"; font.pixelSize: manager.s * 14; font.weight: Font.DemiBold }
                        MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: manager.openBigMode() } }
                }
                Rectangle {
                    visible: manager.settingsSection === "general"
                    width: parent.width; height: manager.s * 86; radius: manager.s * 16; color: manager.surface
                    Text { anchors { left: parent.left; verticalCenter: parent.verticalCenter; leftMargin: manager.s * 18 } text: qsTr("Idioma de Omnia"); color: manager.ink; font.family: "Hanken Grotesk"; font.pixelSize: manager.s * 16; font.weight: Font.DemiBold }
                    ComboBox {
                        anchors { right: parent.right; verticalCenter: parent.verticalCenter; rightMargin: manager.s * 18 }
                        width: manager.s * 220
                        model: [qsTr("Español"), qsTr("English")]
                        currentIndex: api.language === "en" ? 1 : 0
                        onActivated: function(index) {
                            api.setLanguage(index === 1 ? "en" : "es", function(status, body) {
                                if (status === 200) api.notify(qsTr("Idioma actualizado."))
                                else api.notify((body && body.error) || qsTr("No se pudo guardar el idioma."))
                            })
                        }
                    }
                }
                Rectangle {
                    visible: manager.settingsSection === "general"
                    width: parent.width; height: manager.s * 88; radius: manager.s * 16; color: manager.surface
                    Column { anchors { left: parent.left; right: installRootButton.left; verticalCenter: parent.verticalCenter; leftMargin: manager.s * 18; rightMargin: manager.s * 12 } spacing: manager.s * 4
                        Text { text: qsTr("Carpeta predeterminada de instalación"); color: manager.ink; font.family: "Hanken Grotesk"; font.pixelSize: manager.s * 16; font.weight: Font.DemiBold }
                        Text { width: parent.width; text: api.installRoot || qsTr("Sin configurar; elige una ubicación"); color: manager.muted; font.family: "Hanken Grotesk"; font.pixelSize: manager.s * 12; elide: Text.ElideMiddle }
                    }
                    Rectangle { id: installRootButton; anchors { right: parent.right; verticalCenter: parent.verticalCenter; rightMargin: manager.s * 16 } width: manager.s * 148; height: manager.s * 40; radius: height / 2; color: manager.surface2
                        Text { anchors.centerIn: parent; text: qsTr("Elegir carpeta"); color: manager.ink; font.family: "Hanken Grotesk"; font.pixelSize: manager.s * 13 }
                        MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: installFolderDialog.open() }
                    }
                }
                Rectangle {
                    visible: manager.settingsSection === "general"
                    width: parent.width; height: manager.s * 86; radius: manager.s * 16; color: manager.surface
                    Column { anchors { left: parent.left; verticalCenter: parent.verticalCenter; leftMargin: manager.s * 18 } spacing: manager.s * 4
                        Text { text: qsTr("Buscar actualizaciones de ports"); color: manager.ink; font.family: "Hanken Grotesk"; font.pixelSize: manager.s * 16; font.weight: Font.DemiBold }
                        Text { text: qsTr("Avisa cuando un port instalado desde el catálogo tiene una versión nueva. Nunca se actualiza sin confirmar."); color: manager.muted; font.family: "Hanken Grotesk"; font.pixelSize: manager.s * 12 } }
                    Switch { anchors { right: parent.right; verticalCenter: parent.verticalCenter; rightMargin: manager.s * 18 }
                        checked: api.updateCheck
                        onToggled: api.setUpdateCheck(checked, function(status) { if (status !== 200) api.notify(qsTr("No se pudo guardar el ajuste.")) }) }
                }
                Rectangle {
                    visible: manager.settingsSection === "general"
                    width: parent.width; height: manager.s * 86; radius: manager.s * 16; color: manager.surface
                    Column { anchors { left: parent.left; verticalCenter: parent.verticalCenter; leftMargin: manager.s * 18 } spacing: manager.s * 4
                        Text { text: qsTr("Monitor de rendimiento en los juegos"); color: manager.ink; font.family: "Hanken Grotesk"; font.pixelSize: manager.s * 16; font.weight: Font.DemiBold }
                        Text { text: api.mangohudInstalled ? qsTr("Muestra FPS, GPU, CPU, VRAM y RAM en una sola línea, con el estilo de Omnia, sobre los juegos que lanzas desde aquí.") : qsTr("Necesita MangoHud: instálalo desde el gestor de paquetes."); color: manager.muted; font.family: "Hanken Grotesk"; font.pixelSize: manager.s * 12 } }
                    Switch { anchors { right: parent.right; verticalCenter: parent.verticalCenter; rightMargin: manager.s * 18 }
                        checked: api.mangohud
                        enabled: api.mangohudInstalled || api.mangohud
                        onToggled: api.setMangohud(checked, function(status, body) { if (status !== 200) { checked = api.mangohud; api.notify((body && body.error) || qsTr("No se pudo guardar el ajuste.")) } }) }
                }
                Rectangle {
                    visible: manager.settingsSection === "library"
                    width: parent.width; height: manager.s * 116; radius: manager.s * 16; color: manager.surface
                    Column { anchors { left: parent.left; top: parent.top; margins: manager.s * 18 } spacing: manager.s * 5
                        Text { text: qsTr("Carpetas de la biblioteca"); color: manager.ink; font.family: "Hanken Grotesk"; font.pixelSize: manager.s * 17; font.weight: Font.DemiBold }
                        Text { text: qsTr("Añade aquí tus carpetas de juegos y ROMs: Omnia las detecta solas, sin elegir emulador. Retirar una carpeta no elimina los archivos."); color: manager.muted; font.family: "Hanken Grotesk"; font.pixelSize: manager.s * 13 }
                    }
                    Row {
                        anchors { right: parent.right; bottom: parent.bottom; margins: manager.s * 14 } spacing: manager.s * 8
                        TextField { id: rootInput; width: manager.s * 420; height: manager.s * 40; placeholderText: qsTr("Ruta, por ejemplo /mnt/JUEGOS/Ports"); text: manager.rootPath; onTextEdited: manager.rootPath = text; color: manager.ink; font.family: "Hanken Grotesk"; font.pixelSize: manager.s * 14; background: Rectangle { radius: manager.s * 10; color: manager.surface2; border.color: rootInput.activeFocus ? "#45CFC9" : "#24FFFFFF" } }
                        Rectangle { width: manager.s * 40; height: manager.s * 40; radius: manager.s * 10; color: manager.surface2; LucideIcon { anchors.centerIn: parent; width: manager.s * 17; height: width; name: "folder-open"; color: manager.muted } MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: libraryFolderDialog.open() } }
                        Rectangle { width: manager.s * 126; height: manager.s * 40; radius: manager.s * 10; color: manager.accent; Text { anchors.centerIn: parent; text: qsTr("Añadir carpeta"); color: manager.ink; font.family: "Hanken Grotesk"; font.pixelSize: manager.s * 13; font.weight: Font.DemiBold } MouseArea { anchors.fill: parent; enabled: manager.rootPath.trim().length > 0; cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor; onClicked: manager.changeRoot("add", manager.rootPath.trim()) } }
                    }
                }
                Text { visible: manager.settingsSection === "library" && manager.libraryRoots.length === 0; text: qsTr("Aún no has añadido carpetas externas."); color: manager.muted; font.family: "Hanken Grotesk"; font.pixelSize: manager.s * 14 }
                Repeater {
                    model: manager.settingsSection === "library" ? manager.libraryRoots : []
                    delegate: Rectangle {
                        required property string modelData
                        width: parent.width; height: manager.s * 58; radius: manager.s * 13; color: manager.surface
                        LucideIcon { x: manager.s * 16; anchors.verticalCenter: parent.verticalCenter; width: manager.s * 20; height: width; name: "folder-open"; color: "#66D5D0" }
                        Text { anchors { left: parent.left; leftMargin: manager.s * 48; right: removeRoot.left; verticalCenter: parent.verticalCenter } text: modelData; color: manager.ink; font.family: "Hanken Grotesk"; font.pixelSize: manager.s * 14; elide: Text.ElideMiddle }
                        Rectangle { id: removeRoot; anchors { right: parent.right; verticalCenter: parent.verticalCenter; rightMargin: manager.s * 12 } width: manager.s * 90; height: manager.s * 34; radius: height / 2; color: "#27343F"; Text { anchors.centerIn: parent; text: qsTr("Retirar"); color: manager.muted; font.family: "Hanken Grotesk"; font.pixelSize: manager.s * 12 } MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: manager.changeRoot("remove", modelData) } }
                    }
                }
                Text { visible: !!manager.rootsMessage; text: manager.rootsMessage; color: "#E8B86D"; font.family: "Hanken Grotesk"; font.pixelSize: manager.s * 13; wrapMode: Text.WordWrap }
            }
            FolderDialog {
                id: libraryFolderDialog
                title: qsTr("Añadir carpeta de juegos")
                onAccepted: {
                    const path = selectedFolder.toString().replace(/^file:\/\//, "")
                    manager.rootPath = decodeURIComponent(path)
                }
            }
        }
    }

    Rectangle {
        anchors.fill: parent; visible: manager.detailGame !== null; z: 10; color: "#99000000"
        MouseArea { anchors.fill: parent; onClicked: manager.detailGame = null }
        Rectangle {
            anchors.centerIn: parent; width: Math.min(parent.width * 0.8, manager.s * 920); height: manager.s * 520; radius: manager.s * 24; color: manager.surface; clip: true
            MouseArea { anchors.fill: parent; onClicked: function(mouse) { mouse.accepted = true } }
            FadedImage { anchors.fill: parent; source: manager.imageFor(manager.detailGame, ["hero", "grid"]); cornerRadius: manager.s * 24; opacity: 0.3 }
            Rectangle { anchors.fill: parent; radius: manager.s * 24; gradient: Gradient { GradientStop { position: 0; color: "#B3151D27" } GradientStop { position: 1; color: "#F0151D27" } } }
            Text {
                id: catalogDetailTitle
                anchors { left: parent.left; right: parent.right; top: parent.top; margins: manager.s * 30 }
                text: manager.detailGame?.name || ""; color: manager.ink; font.family: "Hanken Grotesk"
                font.pixelSize: manager.s * 30; font.weight: Font.Bold; wrapMode: Text.Wrap
            }
            ScrollView {
                id: catalogFactsScroll
                anchors {
                    left: catalogDetailTitle.left; right: catalogDetailTitle.right; top: catalogDetailTitle.bottom
                    bottom: catalogPackageOptions.visible ? catalogPackageOptions.top : catalogDetailActions.top
                    topMargin: manager.s * 12; bottomMargin: manager.s * 12
                }
                clip: true; contentWidth: availableWidth
                GameFacts {
                    width: catalogFactsScroll.availableWidth
                    api: manager.desktopBackend; catalog: manager.detailGame; uiScale: manager.s
                    ink: manager.ink; muted: manager.muted
                    downloadBytes: manager.selectedPackage?.sizeBytes || 0
                }
            }
            Row {
                id: catalogDetailActions
                anchors { left: parent.left; bottom: parent.bottom; margins: manager.s * 30 }
                spacing: manager.s * 12
                Rectangle { visible: !!manager.localMatch(manager.detailGame) || manager.packageOptions.length === 0; width: manager.s * 180; height: manager.s * 44; radius: height/2; color: manager.localMatch(manager.detailGame) ? manager.accent : manager.surface2; Text { anchors.centerIn: parent; width: parent.width - manager.s * 10; horizontalAlignment: Text.AlignHCenter; text: manager.localMatch(manager.detailGame) ? qsTr("Jugar") : qsTr("Sin paquete publicado"); color: manager.ink; font.family: "Hanken Grotesk"; font.pixelSize: manager.s * 14; elide: Text.ElideRight } MouseArea { anchors.fill: parent; enabled: !!manager.localMatch(manager.detailGame); cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor; onClicked: manager.launch(manager.localMatch(manager.detailGame)) } }
                Rectangle { visible: !manager.localMatch(manager.detailGame) && manager.packageOptions.length > 0; width: manager.s * 150; height: manager.s * 44; radius: height/2; color: manager.acceptLicense && api.installRoot ? manager.accent : manager.surface2; opacity: manager.acceptLicense && api.installRoot ? 1 : 0.55; Text { anchors.centerIn: parent; text: qsTr("Instalar"); color: manager.ink; font.family: "Hanken Grotesk"; font.pixelSize: manager.s * 14; font.weight: Font.DemiBold } MouseArea { anchors.fill: parent; enabled: manager.acceptLicense && api.installRoot && !!manager.selectedPackage; cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor; onClicked: manager.startPackageInstall() } }
                Rectangle { width: manager.s * 110; height: manager.s * 44; radius: height/2; color: "#33434F5C"; Text { anchors.centerIn: parent; text: qsTr("Cerrar"); color: manager.ink; font.family: "Hanken Grotesk"; font.pixelSize: manager.s * 14 } MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: manager.detailGame = null } }
            }
            Column {
                id: catalogPackageOptions
                anchors { left: parent.left; right: parent.right; bottom: parent.bottom; bottomMargin: manager.s * 92; leftMargin: manager.s * 30; rightMargin: manager.s * 30 }
                visible: manager.detailGame && !manager.localMatch(manager.detailGame); spacing: manager.s * 7
                Text { visible: manager.packagesBusy; text: qsTr("Consultando paquetes…"); color: manager.muted; font.family: "Hanken Grotesk"; font.pixelSize: manager.s * 13 }
                Text { visible: !manager.packagesBusy && manager.packageOptions.length === 0; text: manager.packageMessage; color: manager.muted; font.family: "Hanken Grotesk"; font.pixelSize: manager.s * 12; wrapMode: Text.WordWrap }
                Row { visible: manager.packageOptions.length > 0; spacing: manager.s * 8
                    ComboBox { id: packageChoice; width: Math.min(manager.s * 640, Math.max(manager.s * 300, parent.parent.width - destButton.width - manager.s * 8)); height: manager.s * 36; model: manager.packageOptions.map(p => p.title + " · " + p.version); onActivated: manager.selectedPackage = manager.packageOptions[currentIndex] }
                    Rectangle { id: destButton; width: Math.max(manager.s * 160, destText.implicitWidth + manager.s * 28); height: manager.s * 36; radius: manager.s * 10; color: manager.surface2; Text { id: destText; anchors.centerIn: parent; text: api.installRoot ? qsTr("Destino predeterminado") : qsTr("Elegir destino"); color: manager.ink; font.family: "Hanken Grotesk"; font.pixelSize: manager.s * 12 } MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: installFolderDialog.open() } }
                }
                Text { visible: manager.selectedPackage !== null; width: parent.width; text: manager.selectedPackage ? qsTr("Fuente: ") + manager.selectedPackage.sourceName + " · " + qsTr("Licencia: ") + manager.selectedPackage.licenseName + " · " + (Number(manager.selectedPackage.sizeBytes) / 1073741824).toFixed(2) + " GiB" : ""; color: manager.muted; font.family: "Hanken Grotesk"; font.pixelSize: manager.s * 11; elide: Text.ElideRight }
                Row { visible: manager.selectedPackage !== null; spacing: manager.s * 8
                    Rectangle { width: manager.s * 20; height: width; radius: manager.s * 5; color: manager.acceptLicense ? manager.accent : "transparent"; border.color: manager.acceptLicense ? manager.accent : manager.muted; Text { anchors.centerIn: parent; text: manager.acceptLicense ? "✓" : ""; color: "white" } MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: manager.acceptLicense = !manager.acceptLicense } }
                    Text { width: parent.parent.width - manager.s * 28; text: qsTr("Acepto la licencia y la descarga desde la fuente indicada."); color: manager.muted; font.family: "Hanken Grotesk"; font.pixelSize: manager.s * 11; wrapMode: Text.WordWrap }
                }
                Text { visible: !!manager.packageMessage && !manager.packagesBusy && manager.packageOptions.length > 0; text: manager.packageMessage; color: "#E8B86D"; font.family: "Hanken Grotesk"; font.pixelSize: manager.s * 11 }
            }
        }
    }
    Rectangle {
        visible: manager.storeDetailItem !== null
        anchors.fill: parent
        z: 12
        color: "#B9000000"
        MouseArea { anchors.fill: parent; onClicked: manager.storeDetailItem = null }
        Rectangle {
            anchors.centerIn: parent
            width: Math.min(parent.width * 0.84, manager.s * 980)
            height: Math.min(parent.height * 0.78, manager.s * 560)
            radius: manager.s * 22
            color: manager.surface
            border.color: "#294253"
            clip: true
            MouseArea { anchors.fill: parent; onClicked: function(mouse) { mouse.accepted = true } }
            FadedImage {
                anchors { left: parent.left; top: parent.top; bottom: parent.bottom }
                width: parent.width * 0.38
                source: manager.storeDetailItem ? manager.storeDetailItem.hero || manager.storeDetailItem.art : ""
                cornerRadius: manager.s * 22
            }
            Rectangle {
                anchors { left: parent.left; right: parent.right; top: parent.top; bottom: parent.bottom }
                gradient: Gradient {
                    orientation: Gradient.Horizontal
                    GradientStop { position: 0; color: "#00111C27" }
                    GradientStop { position: 0.35; color: "#A8111C27" }
                    GradientStop { position: 0.48; color: manager.surface }
                    GradientStop { position: 1; color: manager.surface }
                }
            }
            Rectangle {
                anchors { top: parent.top; right: parent.right; margins: manager.s * 16 }
                width: manager.s * 38; height: width; radius: width / 2; color: "#253642"
                Text { anchors.centerIn: parent; text: "×"; color: manager.ink; font.pixelSize: manager.s * 24 }
                MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: manager.storeDetailItem = null }
            }
            Column {
                id: storeDetailHeading
                anchors { left: parent.left; right: parent.right; top: parent.top; leftMargin: parent.width * 0.43; rightMargin: manager.s * 34; topMargin: manager.s * 54 }
                spacing: manager.s * 12
                Row {
                    spacing: manager.s * 9
                    Image {
                        width: manager.s * 32; height: width
                        anchors.verticalCenter: parent.verticalCenter
                        source: manager.storeDetailItem ? manager.storeLogo(manager.storeDetailItem.store) : ""
                        fillMode: Image.PreserveAspectFit
                    }
                    Text { anchors.verticalCenter: parent.verticalCenter; text: manager.storeDetailItem ? (storesView.names[manager.storeDetailItem.store] || "") : ""; color: "#66D5D0"; font.family: "Hanken Grotesk"; font.pixelSize: manager.s * 12; font.weight: Font.Bold; font.letterSpacing: 1 }
                }
                Text { width: parent.width; text: manager.storeDetailItem ? manager.storeDetailItem.name : ""; color: manager.ink; font.family: "Hanken Grotesk"; font.pixelSize: manager.s * 30; font.weight: Font.Bold; wrapMode: Text.WordWrap; maximumLineCount: 3; elide: Text.ElideRight }
                Text { width: parent.width; text: manager.storeDetailItem ? ((manager.storeDetailItem.local && manager.storeDetailItem.local.platform) || "PC") + "  ·  " + (storesView.names[manager.storeDetailItem.store] || "") : ""; color: manager.muted; font.family: "Hanken Grotesk"; font.pixelSize: manager.s * 15 }
            }
            ScrollView {
                id: storeFactsScroll
                anchors { left: storeDetailHeading.left; right: storeDetailHeading.right; top: storeDetailHeading.bottom; bottom: storeDetailActions.top; topMargin: manager.s * 12; bottomMargin: manager.s * 12 }
                clip: true; contentWidth: availableWidth
                GameFacts {
                    width: storeFactsScroll.availableWidth
                    api: manager.desktopBackend; offer: manager.storeDetailItem; uiScale: manager.s
                    ink: manager.ink; muted: manager.muted
                }
            }
            Row {
                id: storeDetailActions
                anchors { left: parent.left; bottom: parent.bottom; leftMargin: parent.width * 0.43; bottomMargin: manager.s * 30 }
                spacing: manager.s * 10
                Rectangle {
                    width: manager.s * 176; height: manager.s * 42; radius: height / 2; color: manager.accent
                    Text { anchors.centerIn: parent; text: manager.storeDetailItem && manager.storeDetailItem.store === "steam" ? qsTr("Instalar en Steam") : qsTr("Instalar"); color: manager.ink; font.family: "Hanken Grotesk"; font.pixelSize: manager.s * 13; font.weight: Font.DemiBold }
                    MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: manager.installStoreDetail() }
                }
                Rectangle {
                    width: manager.s * 110; height: manager.s * 42; radius: height / 2; color: "#283844"
                    Text { anchors.centerIn: parent; text: qsTr("Cerrar"); color: manager.ink; font.family: "Hanken Grotesk"; font.pixelSize: manager.s * 13 }
                    MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: manager.storeDetailItem = null }
                }
            }
        }
    }

    FolderDialog {
        id: romScanFolderDialog
        title: qsTr("Elige la carpeta donde buscar ROMs")
        onAccepted: manager.scanRomFolder(decodeURIComponent(selectedFolder.toString().replace(/^file:\/\//, "")))
    }
    FolderDialog {
        id: installFolderDialog
        title: qsTr("Elige la carpeta predeterminada para instalar juegos")
        onAccepted: {
            const path = decodeURIComponent(selectedFolder.toString().replace(/^file:\/\//, ""))
            api.setInstallRoot(path, function(status, body) {
                if (status === 200) api.notify(qsTr("Carpeta de instalación guardada."))
                else api.notify((body && body.error) || qsTr("No se pudo guardar la carpeta de instalación."))
            })
        }
    }
    property var updateGame: null
    function updateFor(game) {              // «Actualización disponible»: confirma y superpone la versión nueva (conserva partidas y datos)
        if (!game || !game.updateAvailable) return
        updateGame = game
        updateDialog.open()
    }
    Dialog {
        id: updateDialog
        modal: true
        anchors.centerIn: parent
        title: qsTr("Actualizar port")
        standardButtons: Dialog.Yes | Dialog.Cancel
        Label {
            width: manager.s * 460; wrapMode: Text.WordWrap
            text: manager.updateGame && manager.updateGame.updateAvailable
                  ? qsTr("%1: %2 → %3 (%4 MB, %5).\nSe verifica su SHA-256 y se superpone sobre la carpeta actual; tus partidas y los archivos que el port preparó se conservan. Algunos ports rehacen su preparación (compilar el juego, shaders) la primera vez que se abren tras actualizar. Cierra el juego antes de actualizar.")
                        .arg(manager.updateGame.name).arg(manager.updateGame.updateAvailable.current || "?").arg(manager.updateGame.updateAvailable.version)
                        .arg(Math.round((manager.updateGame.updateAvailable.sizeBytes || 0) / 1048576)).arg(manager.updateGame.updateAvailable.sourceName || "")
                  : ""
        }
        onAccepted: api.updateInstallation(manager.updateGame.id, function(status, body) {
            if (status === 200) { api.notify(qsTr("Actualización iniciada: %1").arg(manager.updateGame.name)); manager.loadInstallations() }
            else api.notify((body && body.error) || qsTr("No se pudo iniciar la actualización."))
        })
    }
    property string removeGameId: ""
    readonly property var removalGame: api.games.find(game => game.id === removeGameId)
    function askUninstall() { if (removeGameId) uninstallDialog.open() }
    Dialog {
        id: uninstallDialog
        modal: true
        title: qsTr("Desinstalar juego")
        standardButtons: Dialog.Yes | Dialog.Cancel
        Label { width: manager.s * 460; text: gameActions.uninstallText(manager.removalGame?.installPath || manager.removalGame?.folder || ""); wrapMode: Text.Wrap; textFormat: Text.PlainText }
        onAccepted: api.removeInstallation(manager.removeGameId, function(status, body) {
            if (status === 200) { manager.removeGameId = ""; manager.loadInstallations(); api.refresh() }
            else api.notify((body && body.error) || qsTr("No se pudo desinstalar el juego."))
        })
    }
    Dialog {
        id: unlinkGameDialog
        modal: true
        title: qsTr("Quitar juego de Omnia")
        standardButtons: Dialog.Yes | Dialog.Cancel
        Label { text: qsTr("El juego dejará de aparecer en Omnia. Sus archivos no se borrarán del disco."); wrapMode: Text.WordWrap }
        onAccepted: api.removeGame({id: manager.unlinkGameId}, function(status, body) {
            if (status === 200) { manager.unlinkGameId = ""; api.refresh() }
            else api.notify((body && body.error) || qsTr("No se pudo quitar el juego de Omnia."))
        })
    }
    Rectangle {
        id: romScanDialog
        anchors.fill: parent; visible: false; z: 11; color: "#A5000000"
        function open() { visible = true }
        MouseArea { anchors.fill: parent; onClicked: romScanDialog.visible = false }
        Rectangle {
            anchors.centerIn: parent; width: Math.min(parent.width * 0.76, manager.s * 900); height: Math.min(parent.height * 0.82, manager.s * 680); radius: manager.s * 22; color: manager.surface; clip: true
            MouseArea { anchors.fill: parent; onClicked: function(mouse) { mouse.accepted = true } }
            Column {
                anchors.fill: parent; anchors.margins: manager.s * 22; spacing: manager.s * 12
                Row {
                    width: parent.width; spacing: manager.s * 12
                    Text { id: romDialogTitle; text: qsTr("ROMs y juegos de consola"); color: manager.ink; font.family: "Hanken Grotesk"; font.pixelSize: manager.s * 24; font.weight: Font.DemiBold }
                    Item { width: parent.width - romDialogTitle.implicitWidth - closeRomDialog.width - manager.s * 24; height: 1 }
                    Rectangle { id: closeRomDialog; width: manager.s * 38; height: manager.s * 38; radius: height / 2; color: manager.surface2; Text { anchors.centerIn: parent; text: "×"; color: manager.ink; font.pixelSize: manager.s * 23 } MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: romScanDialog.visible = false } }
                }
                Text { width: parent.width; text: manager.romMessage; color: manager.muted; font.family: "Hanken Grotesk"; font.pixelSize: manager.s * 14; wrapMode: Text.WordWrap }
                ListView {
                    width: parent.width; height: parent.height - manager.s * 86; spacing: manager.s * 8; clip: true; model: manager.romResults
                    delegate: Rectangle {
                        required property var modelData
                        width: ListView.view.width; height: manager.s * 82; radius: manager.s * 12; color: manager.surface2
                        property string selectedSystemId: modelData.system
                        property var selectedSystemOption: modelData.systemOptions.find(option => option.id === selectedSystemId) || modelData.systemOptions[0]
                        property var activeCatalogMatch: manager.catalogMatchFor(modelData, selectedSystemId)
                        property string proposedName: activeCatalogMatch ? activeCatalogMatch.name : modelData.name
                        property string selectedEmulatorId: selectedSystemOption && selectedSystemOption.emulators.length ? selectedSystemOption.emulators[0].id : ""
                        Column { anchors { left: parent.left; verticalCenter: parent.verticalCenter; leftMargin: manager.s * 14 } width: parent.width * 0.25; spacing: manager.s * 3; Text { width: parent.width; text: parent.parent.selectedSystemOption.name + " · " + modelData.format.toUpperCase(); color: manager.muted; font.family: "Hanken Grotesk"; font.pixelSize: manager.s * 11; elide: Text.ElideRight } Text { width: parent.width; text: modelData.internalTitle || modelData.fileName; color: manager.ink; font.family: "Hanken Grotesk"; font.pixelSize: manager.s * 14; elide: Text.ElideRight } Text { width: parent.width; visible: !!modelData.internalId || !!modelData.region || !!parent.parent.activeCatalogMatch; text: [modelData.internalId, modelData.region, parent.parent.activeCatalogMatch ? "Omnia · " + parent.parent.activeCatalogMatch.name : ""].filter(Boolean).join(" · "); color: parent.parent.activeCatalogMatch ? manager.accent : manager.muted; font.family: "Hanken Grotesk"; font.pixelSize: manager.s * 10; elide: Text.ElideRight } }
                        TextField { id: romName; anchors { left: parent.left; leftMargin: parent.width * 0.27; verticalCenter: parent.verticalCenter } width: parent.width * 0.24; height: manager.s * 38; text: parent.proposedName; color: manager.ink; font.family: "Hanken Grotesk"; font.pixelSize: manager.s * 13; background: Rectangle { radius: manager.s * 9; color: "#111923" } }
                        ComboBox { id: systemChoice; anchors { left: romName.right; leftMargin: manager.s * 6; verticalCenter: parent.verticalCenter } width: parent.width * 0.18; height: manager.s * 38; visible: modelData.systemOptions.length > 1; model: modelData.systemOptions.map(option => option.name); currentIndex: Math.max(0, modelData.systemOptions.findIndex(option => option.id === parent.selectedSystemId)); onActivated: { const row = parent; row.selectedSystemId = modelData.systemOptions[currentIndex].id; row.selectedEmulatorId = row.selectedSystemOption.emulators.length ? row.selectedSystemOption.emulators[0].id : "" } }
                        ComboBox { id: emulatorChoice; anchors { left: romName.right; leftMargin: systemChoice.visible ? systemChoice.width + manager.s * 12 : manager.s * 8; verticalCenter: parent.verticalCenter } width: parent.width * 0.16; height: manager.s * 38; visible: parent.selectedSystemOption && parent.selectedSystemOption.emulators.length > 0; model: parent.selectedSystemOption ? parent.selectedSystemOption.emulators.map(e => e.label) : []; onActivated: parent.selectedEmulatorId = parent.selectedSystemOption.emulators[currentIndex].id }
                        Text { anchors { left: romName.right; leftMargin: systemChoice.visible ? systemChoice.width + manager.s * 12 : manager.s * 8; verticalCenter: parent.verticalCenter } width: parent.width * 0.16; visible: !parent.selectedSystemOption || parent.selectedSystemOption.emulators.length === 0; text: qsTr("Sin emulador: se elige al jugar"); color: manager.muted; font.family: "Hanken Grotesk"; font.pixelSize: manager.s * 10; wrapMode: Text.WordWrap }
                        Rectangle { anchors { right: parent.right; verticalCenter: parent.verticalCenter; rightMargin: manager.s * 10 } width: manager.s * 76; height: manager.s * 38; radius: height / 2; color: manager.accent; opacity: romName.text.trim().length > 0 && !manager.romMatching ? 1 : 0.45; Text { anchors.centerIn: parent; text: qsTr("Añadir"); color: manager.ink; font.family: "Hanken Grotesk"; font.pixelSize: manager.s * 13; font.weight: Font.DemiBold } MouseArea { anchors.fill: parent; enabled: romName.text.trim().length > 0 && !manager.romMatching; cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor; onClicked: manager.addScannedRom(modelData, romName.text.trim(), parent.parent.selectedSystemId, parent.parent.selectedEmulatorId, parent.parent.activeCatalogMatch ? parent.parent.activeCatalogMatch.slug : "") } }
                    }
                    Text { visible: manager.romResults.length === 0 && !manager.romScanning; anchors.centerIn: parent; text: qsTr("No hay candidatos pendientes."); color: manager.muted; font.family: "Hanken Grotesk"; font.pixelSize: manager.s * 15 }
                }
            }
        }
        Keys.onEscapePressed: visible = false
    }

    Loader {
        anchors.fill: parent; z: 20
        active: manager.addWizardOpen || manager.importPanelOpen
        sourceComponent: manager.importPanelOpen ? importComponent : addGameComponent
        onLoaded: { if (item && item.hasOwnProperty("templateList")) { item.manager = manager; item.api = api } }
    }
    Component {
        id: addGameComponent
        ManagerAddGame {
            // `manager` y `api` se asignan desde el Loader (onLoaded): aquí el nombre de la propiedad ocultaría al id del anfitrión
            onFinished: manager.addWizardOpen = false
            onAdded: function(id) { manager.addWizardOpen = false; api.refresh(); manager.openGameInLibrary({id: id}); api.notify(qsTr("Juego añadido a la biblioteca.")) }
            onImportRequested: function(path) { manager.importPath = path; manager.addWizardOpen = false; manager.importPanelOpen = true }
        }
    }
    Component {
        id: importComponent
        ImportPanel {
            api: api
            path: manager.importPath
            onFinished: manager.importPanelOpen = false
            onImported: { manager.importPanelOpen = false; api.refresh() }
        }
    }

    Component {
        id: bigModeComponent
        Window {
            width: Screen.width; height: Screen.height; visibility: Window.FullScreen; color: manager.bg; title: "Omnia Big Mode"
            OmniaLibrary { anchors.fill: parent; backend: manager.desktopBackend; sharedBackend: true; onCloseRequested: manager.closeBigMode() }
            onClosing: { manager.bigModeWindow = null; api.controlsEnabled = false }
        }
    }
}

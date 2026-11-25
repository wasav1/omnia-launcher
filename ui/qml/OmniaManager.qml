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
    property int recommendationOffset: 0
    property bool recommendationsVisible: true
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
    property string unlinkGameId: ""
    property string catalogLinkTargetId: ""
    property var bigModeWindow: null
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
    readonly property var recommendationPair: {
        if (!onlineGames.length) return []
        const count = Math.min(10, onlineGames.length)
        return [onlineGames[recommendationOffset % count], onlineGames[(recommendationOffset + 1) % count]].filter(Boolean)
    }

    Api { id: api; controlsEnabled: false; systemEnabled: true }
    Component.onCompleted: loadOnline(1)
    Timer { interval: 6000; repeat: true; running: manager.visible; onTriggered: api.refresh() }
    Timer { interval: 1200; repeat: true; running: manager.visible && (manager.page === "installs" || manager.activeInstalls.length > 0); triggeredOnStart: true; onTriggered: manager.loadInstallations() }

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
    function gameAction(act, game) {
        if (!game) return
        if (act === "hide") api.call("POST", "/game/hide?id=" + encodeURIComponent(game.id), function(status) { if (status === 200) api.refresh(); else api.notify(qsTr("No se pudo actualizar el juego.")) })
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
            api.refresh()
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
        Text { visible: manager.activeInstalls.length > 0; anchors { left: parent.left; leftMargin: manager.cs * 18; verticalCenter: parent.verticalCenter }
            text: manager.activeInstalls.length > 0 ? qsTr("Descargando: %1 · %2 %").arg(manager.activeInstalls[0].name).arg(Math.round(Number(manager.activeInstalls[0].progress || 0))) : ""
            color: manager.muted; font.family: "Hanken Grotesk"; font.pixelSize: manager.cs * 12 }
        Row {
            anchors { right: parent.right; rightMargin: manager.cs * 18; verticalCenter: parent.verticalCenter }
            spacing: manager.cs * 22
            Text { anchors.verticalCenter: parent.verticalCenter; text: api.gameRunning ? qsTr("Jugando") : qsTr("Omnia independiente · la biblioteca vive en este equipo"); color: "#8495A8"; font.family: "Hanken Grotesk"; font.pixelSize: manager.cs * 12 }
        }
    }

    Item {
        id: content
        anchors { left: topbar.right; right: parent.right; top: parent.top; bottom: statusbar.top }
        property real pad: manager.s * 34
        readonly property real top0: manager.s * 30
        // Inicio: novedad del catálogo y «Seguir jugando»
        Item {
            anchors.fill: parent
            visible: manager.page === "home"
            readonly property var news: manager.onlineGames.length ? manager.onlineGames[0] : null
            Rectangle {
                id: banner
                anchors { left: parent.left; right: parent.right; top: parent.top; leftMargin: content.pad; rightMargin: content.pad; topMargin: content.top0 }
                height: manager.s * 230; radius: manager.s * 22; color: manager.surface; clip: true
                gradient: Gradient { GradientStop { position: 0; color: "#203C5C" } GradientStop { position: 1; color: manager.surface } }
                FadedImage {
                    anchors { right: parent.right; top: parent.top; bottom: parent.bottom }
                    width: parent.width * 0.7
                    source: parent.parent.news ? manager.imageFor(parent.parent.news, ["hero", "grid"]) : ""
                    fadeLeft: 0.6; cornerRadius: manager.s * 22
                }
                Column {
                    anchors { left: parent.left; leftMargin: manager.s * 34; verticalCenter: parent.verticalCenter }
                    width: parent.width * 0.42; spacing: manager.s * 8
                    Text { text: banner.parent.news ? qsTr("NOVEDAD DEL CATÁLOGO") : qsTr("BIENVENIDO A OMNIA"); color: "#66D5D0"; font.family: "Hanken Grotesk"; font.pixelSize: manager.s * 13; font.weight: Font.Bold; font.letterSpacing: 2 }
                    Text { width: parent.width; text: banner.parent.news ? (banner.parent.news.name || "") : qsTr("Tu espacio de juegos"); color: manager.ink; elide: Text.ElideRight
                        font.family: "Hanken Grotesk"; font.pixelSize: manager.s * 34; font.weight: Font.DemiBold }
                    Text { width: parent.width; text: banner.parent.news ? (banner.parent.news.platforms || []).map(p => p.name || p.slug).join(" · ") : qsTr("Tu biblioteca, tus plataformas y tus instalaciones."); color: manager.muted; elide: Text.ElideRight
                        font.family: "Hanken Grotesk"; font.pixelSize: manager.s * 16 }
                    Rectangle {
                        width: bannerBtn.implicitWidth + manager.s * 44; height: manager.s * 40; radius: height / 2; color: manager.accent
                        Text { id: bannerBtn; anchors.centerIn: parent; text: banner.parent.news ? qsTr("Ver ficha") : qsTr("Explorar el catálogo"); color: manager.ink; font.family: "Hanken Grotesk"; font.pixelSize: manager.s * 15; font.weight: Font.DemiBold }
                        MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: banner.parent.news ? manager.openCatalogDetail(banner.parent.news) : manager.selectPage("catalog") }
                    }
                }
            }
            Row {
                id: stats
                anchors { left: parent.left; leftMargin: content.pad; top: banner.bottom; topMargin: manager.s * 18 }
                spacing: manager.s * 12
                Repeater {
                    model: [
                        {value: api.games.length, label: qsTr("JUEGOS")},
                        {value: manager.recentGames.length, label: qsTr("RECIENTES")},
                        {value: api.gameRunning ? 1 : 0, label: qsTr("EN JUEGO")}
                    ]
                    delegate: Rectangle {
                        required property var modelData
                        width: manager.s * 150; height: manager.s * 46; radius: manager.s * 12; color: manager.surface
                        Row { anchors.centerIn: parent; spacing: manager.s * 8
                            Text { anchors.verticalCenter: parent.verticalCenter; text: modelData.value; color: manager.ink; font.family: "Hanken Grotesk"; font.pixelSize: manager.s * 20; font.weight: Font.Bold }
                            Text { anchors.verticalCenter: parent.verticalCenter; text: modelData.label; color: manager.muted; font.family: "Hanken Grotesk"; font.pixelSize: manager.s * 11; font.weight: Font.DemiBold; font.letterSpacing: 1 } }
                    }
                }
            }
            Text { id: continueTitle; x: content.pad; anchors.top: stats.bottom; anchors.topMargin: manager.s * 24; text: qsTr("Seguir jugando"); color: manager.ink; font.family: "Hanken Grotesk"; font.pixelSize: manager.s * 21; font.weight: Font.DemiBold }
            ListView {
                id: recentList
                x: content.pad; anchors.top: continueTitle.bottom; anchors.topMargin: manager.s * 12
                width: parent.width - content.pad * 2; height: manager.s * 180
                orientation: ListView.Horizontal; spacing: manager.s * 14; clip: true
                model: manager.recentGames
                delegate: Rectangle {
                    required property var modelData
                    width: manager.s * 250; height: recentList.height; radius: manager.s * 16; color: manager.surface; clip: true
                    FadedImage { anchors.fill: parent; source: modelData.fondo || modelData.portada || ""; cornerRadius: manager.s * 16 }
                    Rectangle { anchors.fill: parent; radius: manager.s * 16; gradient: Gradient { GradientStop { position: 0.42; color: "#00151D27" } GradientStop { position: 1; color: "#E6101720" } } }
                    Column { anchors { left: parent.left; right: parent.right; bottom: parent.bottom; margins: manager.s * 12 } Text { width: parent.width; text: modelData.name; color: manager.ink; font.family: "Hanken Grotesk"; font.pixelSize: manager.s * 16; font.weight: Font.DemiBold; elide: Text.ElideRight } Text { text: modelData.lastPlayed ? new Date(modelData.lastPlayed * 1000).toLocaleDateString(Qt.locale(api.language === "en" ? "en_US" : "es_CO"), "d MMM") : qsTr("En tu biblioteca"); color: manager.muted; font.family: "Hanken Grotesk"; font.pixelSize: manager.s * 12 } }
                    MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: manager.openGameInLibrary(modelData); onDoubleClicked: manager.launch(modelData) }
                }
                Text { visible: manager.recentGames.length === 0; anchors.verticalCenter: parent.verticalCenter; text: qsTr("Añade juegos para verlos aquí."); color: manager.muted; font.family: "Hanken Grotesk"; font.pixelSize: manager.s * 15 }
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

        // Explorar: recomendaciones, instalaciones recientes y cuadrícula unificada sin paginación.
        Item {
            id: explorePage
            anchors.fill: parent
            visible: manager.page === "catalog"
            Text {
                x: content.pad; y: content.top0
                text: qsTr("Explorar"); color: manager.ink
                font.family: "Hanken Grotesk"; font.pixelSize: manager.s * 28; font.weight: Font.Bold
            }
            Text {
                x: content.pad; y: content.top0 + manager.s * 34
                text: qsTr("Ports de Omnia y juegos de tus tiendas, en un solo lugar.")
                color: manager.muted; font.family: "Hanken Grotesk"; font.pixelSize: manager.s * 12
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
                x: content.pad; y: remoteSearch.y + remoteSearch.height + manager.s * 3
                width: parent.width - content.pad * 2
                text: manager.onlineWarning; visible: !!text
                color: "#E8B86D"; font.family: "Hanken Grotesk"; font.pixelSize: manager.s * 11; elide: Text.ElideRight
            }
            Flickable {
                id: exploreFlick
                anchors { left: parent.left; right: parent.right; top: exploreWarning.visible ? exploreWarning.bottom : remoteSearch.bottom; bottom: parent.bottom }
                anchors.topMargin: manager.s * 7
                clip: true
                contentWidth: width
                contentHeight: exploreContent.height
                boundsBehavior: Flickable.StopAtBounds
                Column {
                    id: exploreContent
                    x: content.pad
                    width: exploreFlick.width - content.pad * 2
                    spacing: manager.s * 15

                    Column {
                        width: parent.width
                        spacing: manager.s * 7
                        Text { text: qsTr("Recomendados"); color: manager.ink; font.family: "Hanken Grotesk"; font.pixelSize: manager.s * 17; font.weight: Font.DemiBold }
                        Row {
                            width: parent.width; height: manager.s * 132; spacing: manager.s * 10
                            opacity: manager.recommendationsVisible ? 1 : 0
                            Behavior on opacity { NumberAnimation { duration: 260; easing.type: Easing.InOutQuad } }
                            Repeater {
                                model: manager.recommendationPair
                                delegate: ManagerPosterCard {
                                    required property var modelData
                                    width: (parent.width - parent.spacing) / 2; height: parent.height
                                    scaleFactor: manager.s
                                    title: modelData.name || ""
                                    artwork: manager.imageFor(modelData, ["grid", "hero"])
                                    store: qsTr("Omnia · ports")
                                    sourceLogo: "images/stores/omnia.svg"
                                    installed: !!manager.localMatch(modelData)
                                    platform: (modelData.platforms || []).map(function(p) { return p.name || p.slug }).join(" · ")
                                    info: [modelData.year || modelData.releaseYear || "", (modelData.genres || []).slice(0, 2).join(" · ")].filter(Boolean).join(" · ")
                                    onActivated: {
                                        const local = manager.localMatch(modelData)
                                        if (local) manager.openLocalExploreDetail(local)
                                        else manager.openCatalogDetail(modelData)
                                    }
                                }
                            }
                            Text { visible: manager.recommendationPair.length === 0; anchors.centerIn: parent; text: manager.onlineBusy ? qsTr("Cargando recomendaciones…") : qsTr("Aún no hay recomendaciones."); color: manager.muted; font.family: "Hanken Grotesk"; font.pixelSize: manager.s * 12 }
                        }
                    }

                    Column {
                        width: parent.width
                        spacing: manager.s * 7
                        Row {
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
                        ListView {
                            id: installedList
                            width: parent.width; height: manager.s * 148
                            orientation: ListView.Horizontal; spacing: manager.s * 9; clip: true
                            model: manager.recentGames
                            delegate: ManagerPosterCard {
                                required property var modelData
                                width: (installedList.width - installedList.spacing * (installedList.visibleCount - 1)) / installedList.visibleCount; height: installedList.height
                                scaleFactor: manager.s * 0.92
                                title: modelData.name || ""
                                artwork: modelData.portada || modelData.fondo || ""
                                store: manager.sourceForGame(modelData).label
                                sourceLogo: manager.sourceForGame(modelData).logo
                                platform: modelData.platform || modelData.sub || "PC"
                                info: modelData.year || modelData.releaseYear || modelData.platform || ""
                                installed: true
                                onActivated: manager.openLocalExploreDetail(modelData)
                            }
                            readonly property int visibleCount: Math.max(1, Math.min(5, manager.recentGames.length))
                            Text { visible: installedList.count === 0; anchors.verticalCenter: parent.verticalCenter; text: qsTr("Tus juegos instalados aparecerán aquí."); color: manager.muted; font.family: "Hanken Grotesk"; font.pixelSize: manager.s * 12 }
                        }
                    }

                    Item {
                        id: inlineExploreFilters
                        width: parent.width; height: manager.s * 41
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
                                    width: (inlineFilterRow.width - inlineFilterRow.spacing * 5) / 6; height: manager.s * 31; radius: height / 2
                                    color: selected ? "#16434E" : "#101C27"
                                    border.color: selected ? "#45CFC9" : "#30414E"
                                    Row {
                                        anchors.centerIn: parent; spacing: manager.s * 6
                                        Image { visible: !!inlineChip.modelData.logo; anchors.verticalCenter: parent.verticalCenter; width: manager.s * 16; height: width; source: inlineChip.modelData.logo; sourceSize.width: 48; sourceSize.height: 48; fillMode: Image.PreserveAspectFit }
                                        Text { anchors.verticalCenter: parent.verticalCenter; text: inlineChip.modelData.label; color: inlineChip.selected ? "#72E0DA" : manager.muted; font.family: "Hanken Grotesk"; font.pixelSize: manager.s * 10; font.weight: inlineChip.selected ? Font.DemiBold : Font.Normal; elide: Text.ElideRight }
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
                            width: parent.width
                            readonly property real gap: manager.s * 12
                            readonly property real cardWidth: Math.max(manager.s * 112, Math.floor((width - gap * (columns - 1)) / columns))
                            readonly property real cardHeight: cardWidth * 1.42
                            columns: Math.max(2, Math.floor((width + gap) / (manager.s * 160 + gap)))
                            columnSpacing: gap; rowSpacing: gap
                            height: exploreGridRepeater.count ? Math.ceil(exploreGridRepeater.count / columns) * (cardHeight + rowSpacing) - rowSpacing : 0
                            Repeater {
                                id: exploreGridRepeater
                                model: manager.exploreItems
                                delegate: Item {
                                    id: exploreCell
                                    required property var modelData
                                    width: exploreGrid.cardWidth; height: exploreGrid.cardHeight
                                    ManagerPosterCard {
                                        anchors.fill: parent
                                        scaleFactor: manager.s
                                        title: exploreCell.modelData.name
                                        artwork: exploreCell.modelData.art
                                        store: exploreCell.modelData.store
                                        sourceLogo: exploreCell.modelData.logo
                                        platform: exploreCell.modelData.platform
                                        info: exploreCell.modelData.info
                                        installed: exploreCell.modelData.installed
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
                        Text { visible: exploreGridRepeater.count === 0 && !manager.onlineBusy; text: qsTr("No hay juegos para este filtro."); color: manager.muted; font.family: "Hanken Grotesk"; font.pixelSize: manager.s * 12 }
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
                height: manager.s * 41; color: "#F20B1118"
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
                            width: (pinnedFilterRow.width - pinnedFilterRow.spacing * 5) / 6; height: manager.s * 31; radius: height / 2
                            color: selected ? "#16434E" : "#101C27"
                            border.color: selected ? "#45CFC9" : "#30414E"
                            Row {
                                anchors.centerIn: parent; spacing: manager.s * 6
                                Image { visible: !!pinnedChip.modelData.logo; anchors.verticalCenter: parent.verticalCenter; width: manager.s * 16; height: width; source: pinnedChip.modelData.logo; sourceSize.width: 48; sourceSize.height: 48; fillMode: Image.PreserveAspectFit }
                                Text { anchors.verticalCenter: parent.verticalCenter; text: pinnedChip.modelData.label; color: pinnedChip.selected ? "#72E0DA" : manager.muted; font.family: "Hanken Grotesk"; font.pixelSize: manager.s * 10; font.weight: pinnedChip.selected ? Font.DemiBold : Font.Normal; elide: Text.ElideRight }
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
                        anchors { left: parent.left; right: parent.right; top: parent.top; margins: manager.s * 28 }
                        spacing: manager.s * 10
                        Row {
                            spacing: manager.s * 9
                            Image { anchors.verticalCenter: parent.verticalCenter; width: manager.s * 20; height: width; source: manager.exploreDetailGame ? manager.sourceForGame(manager.exploreDetailGame).logo : ""; sourceSize.width: 64; sourceSize.height: 64; fillMode: Image.PreserveAspectFit }
                            Text { anchors.verticalCenter: parent.verticalCenter; text: manager.exploreDetailGame ? (manager.sourceForGame(manager.exploreDetailGame).label + "  ·  " + (manager.exploreDetailGame.platform || manager.exploreDetailGame.sub || "PC")) : ""; color: "#70E0D9"; font.family: "Hanken Grotesk"; font.pixelSize: manager.s * 12; font.weight: Font.DemiBold }
                        }
                        Text { width: parent.width; text: manager.exploreDetailGame ? manager.exploreDetailGame.name || "" : ""; color: manager.ink; font.family: "Hanken Grotesk"; font.pixelSize: manager.s * 30; font.weight: Font.Bold; wrapMode: Text.WordWrap }
                        Text { width: parent.width; height: manager.s * 180; text: manager.exploreDetailGame ? manager.exploreDetailGame.description || manager.exploreDetailGame.s || qsTr("Sin descripción disponible.") : ""; color: manager.muted; font.family: "Hanken Grotesk"; font.pixelSize: manager.s * 14; wrapMode: Text.WordWrap; maximumLineCount: 7; elide: Text.ElideRight; verticalAlignment: Text.AlignTop }
                    }
                    Row {
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
            Timer {
                id: recommendationTimer
                interval: 10000; repeat: true
                running: manager.page === "catalog" && manager.onlineGames.length > 2
                onTriggered: { manager.recommendationsVisible = false; recommendationSwap.restart() }
            }
            Timer {
                id: recommendationSwap
                interval: 280; repeat: false
                onTriggered: {
                    const count = Math.min(10, manager.onlineGames.length)
                    manager.recommendationOffset = count > 0 ? (manager.recommendationOffset + 2) % count : 0
                    manager.recommendationsVisible = true
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
            visible: manager.page === "catalog"
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
                    model: [{ k: "general", l: qsTr("General") }, { k: "library", l: qsTr("Biblioteca") }, { k: "bigmode", l: qsTr("Big Mode") }, { k: "about", l: qsTr("Acerca de") }]
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
            Column { anchors { left: parent.left; right: parent.right; top: parent.top; margins: manager.s * 30 } spacing: manager.s * 12; Text { width: parent.width; text: manager.detailGame ? manager.detailGame.name || "" : ""; color: manager.ink; font.family: "Hanken Grotesk"; font.pixelSize: manager.s * 30; font.weight: Font.Bold; wrapMode: Text.WordWrap } Text { text: manager.detailGame ? manager.detailGame.description || qsTr("Sin descripción disponible.") : ""; color: manager.muted; font.family: "Hanken Grotesk"; font.pixelSize: manager.s * 16; wrapMode: Text.WordWrap; width: parent.width; maximumLineCount: 6; elide: Text.ElideRight } }
            Row { anchors { left: parent.left; bottom: parent.bottom; margins: manager.s * 30 } spacing: manager.s * 12
                Rectangle { visible: !!manager.localMatch(manager.detailGame) || manager.packageOptions.length === 0; width: manager.s * 180; height: manager.s * 44; radius: height/2; color: manager.localMatch(manager.detailGame) ? manager.accent : manager.surface2; Text { anchors.centerIn: parent; width: parent.width - manager.s * 10; horizontalAlignment: Text.AlignHCenter; text: manager.localMatch(manager.detailGame) ? qsTr("Jugar") : qsTr("Sin paquete publicado"); color: manager.ink; font.family: "Hanken Grotesk"; font.pixelSize: manager.s * 14; elide: Text.ElideRight } MouseArea { anchors.fill: parent; enabled: !!manager.localMatch(manager.detailGame); cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor; onClicked: manager.launch(manager.localMatch(manager.detailGame)) } }
                Rectangle { visible: !manager.localMatch(manager.detailGame) && manager.packageOptions.length > 0; width: manager.s * 150; height: manager.s * 44; radius: height/2; color: manager.acceptLicense && api.installRoot ? manager.accent : manager.surface2; opacity: manager.acceptLicense && api.installRoot ? 1 : 0.55; Text { anchors.centerIn: parent; text: qsTr("Instalar"); color: manager.ink; font.family: "Hanken Grotesk"; font.pixelSize: manager.s * 14; font.weight: Font.DemiBold } MouseArea { anchors.fill: parent; enabled: manager.acceptLicense && api.installRoot && !!manager.selectedPackage; cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor; onClicked: manager.startPackageInstall() } }
                Rectangle { width: manager.s * 110; height: manager.s * 44; radius: height/2; color: "#33434F5C"; Text { anchors.centerIn: parent; text: qsTr("Cerrar"); color: manager.ink; font.family: "Hanken Grotesk"; font.pixelSize: manager.s * 14 } MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: manager.detailGame = null } }
            }
            Column {
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
                source: manager.storeDetailItem ? manager.storeDetailItem.art : ""
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
                anchors { left: parent.left; right: parent.right; top: parent.top; leftMargin: parent.width * 0.43; rightMargin: manager.s * 34; topMargin: manager.s * 54 }
                spacing: manager.s * 12
                Text { text: manager.storeDetailItem ? (storesView.names[manager.storeDetailItem.store] || "") : ""; color: "#66D5D0"; font.family: "Hanken Grotesk"; font.pixelSize: manager.s * 12; font.weight: Font.Bold; font.letterSpacing: 1 }
                Text { width: parent.width; text: manager.storeDetailItem ? manager.storeDetailItem.name : ""; color: manager.ink; font.family: "Hanken Grotesk"; font.pixelSize: manager.s * 30; font.weight: Font.Bold; wrapMode: Text.WordWrap; maximumLineCount: 3; elide: Text.ElideRight }
                Text { width: parent.width; text: manager.storeDetailItem ? ((manager.storeDetailItem.local && manager.storeDetailItem.local.platform) || "PC") + "  ·  " + (storesView.names[manager.storeDetailItem.store] || "") : ""; color: manager.muted; font.family: "Hanken Grotesk"; font.pixelSize: manager.s * 15 }
                Text { width: parent.width; text: manager.storeDetailItem && manager.storeDetailItem.store === "steam" ? qsTr("Se abrirá Steam para que confirmes la instalación.") : qsTr("El juego se instalará usando la cuenta conectada de esta tienda."); color: manager.muted; font.family: "Hanken Grotesk"; font.pixelSize: manager.s * 14; wrapMode: Text.WordWrap }
            }
            Row {
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
    function askUninstall() { uninstallDialog.open() }
    Dialog {
        id: uninstallDialog
        modal: true
        title: qsTr("Desinstalar juego")
        standardButtons: Dialog.Yes | Dialog.Cancel
        Label { text: qsTr("Se quitará el juego y se borrarán sus archivos instalados por Omnia."); wrapMode: Text.WordWrap }
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
            OmniaLibrary { anchors.fill: parent; backend: api; sharedBackend: true; onCloseRequested: manager.closeBigMode() }
            onClosing: { manager.bigModeWindow = null; api.controlsEnabled = false }
        }
    }
}

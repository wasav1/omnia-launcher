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
    property var detailGame: null
    property var packageOptions: []
    property var selectedPackage: null
    property var installJobs: []
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
    readonly property color surface: "#151D27"
    readonly property color surface2: "#1D2936"
    readonly property color ink: "#F0F3F7"
    readonly property color muted: "#B8C3D0"
    readonly property color accent: "#3978B8"
    readonly property real s: Math.max(0.72, Math.min(width / 1440, height / 900))
    readonly property real cs: Math.min(s, 1)      // escala de los menús (barras): no crece con la ventana
    readonly property var recentGames: {
        const games = (api.games || []).filter(g => !g.hidden && g.ports && g.ports.length)
        games.sort((a,b) => Number(b.lastPlayed || 0) - Number(a.lastPlayed || 0))
        return games.slice(0, 5)
    }

    Api { id: api; controlsEnabled: false; systemEnabled: true }
    Component.onCompleted: loadOnline(1)
    Timer { interval: 6000; repeat: true; running: manager.visible; onTriggered: api.refresh() }
    Timer { interval: 1200; repeat: true; running: manager.visible && manager.page === "installs"; triggeredOnStart: true; onTriggered: manager.loadInstallations() }

    function loadOnline(page) {
        if (page !== undefined) onlinePage = Math.max(1, Number(page) || 1)
        onlineBusy = true
        api.catalogGames({page: onlinePage, pageSize: onlinePageSize, sort: "updatedAt", order: "desc", q: query}, function(status, body) {
            manager.onlineBusy = false
            if (status === 200 && body) {
                manager.onlineGames = body.items || []
                manager.onlineMeta = body.meta || {}
                if (manager.onlineMeta.page) manager.onlinePage = Number(manager.onlineMeta.page)
                const catalogNotice = body.warning ? (api.language === "en" ? api.localizeNotice(body.warning) : body.warning) : ""
                manager.onlineWarning = manager.catalogLinkTargetId
                    ? qsTr("Elige una ficha para vincularla con el juego seleccionado.") + (catalogNotice ? " · " + catalogNotice : "")
                    : catalogNotice
            } else manager.onlineWarning = (body && body.error) || qsTr("No se pudo cargar el catálogo.")
        })
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
    readonly property var activeInstalls: installJobs.filter(job => ["queued", "downloading", "verifying", "extracting", "paused"].includes(job.status))
    function openGameInLibrary(game) { page = "library"; if (game) managerLibrary.selId = game.id }
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
    function gameById(id) { return api.games.find(g => g.id === id) || null }
    function localMatch(remote) {
        if (!remote) return null
        const slug = String(remote.slug || "").toLowerCase().replace(/[^a-z0-9]+/g, "-").replace(/^-|-$/g, "")
        return api.games.find(g => g.catalogSlug === remote.slug || g.id === slug || String(g.id).endsWith("-" + slug)) || null
    }
    function launch(game) {
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
            if (item) return item.imageUrl.startsWith("/") ? (api.catalogBaseUrl + item.imageUrl) : item.imageUrl
        }
        return ""
    }
    function selectPage(key) {
        if (key === "home" && onlineGames.length === 0 && !onlineBusy) loadOnline(1)
        if (key !== "catalog" && catalogLinkTargetId) catalogLinkTargetId = ""
        page = key
        if (key === "catalog") loadOnline()
        if (key === "installs") loadInstallations()
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
            if (status === 200) {
                const active = (body.jobs || []).filter(job => job.status !== "completed")
                const installed = (body.installed || []).map(game => ({id: game.gameId, name: game.name, status: qsTr("Instalado"), progress: 100, destination: game.path, gameId: game.gameId, installed: true}))
                manager.installJobs = active.concat(installed)
            }
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

    // ---------------- barra superior (menú principal)
    Rectangle {
        id: topbar
        anchors { left: parent.left; right: parent.right; top: parent.top }
        height: manager.cs * 46
        color: "#0E141B"
        Rectangle { anchors { left: parent.left; right: parent.right; bottom: parent.bottom } height: 1; color: "#1c2733" }
        Row {
            id: brandRow
            anchors { left: parent.left; leftMargin: manager.cs * 18; verticalCenter: parent.verticalCenter }
            spacing: manager.cs * 8
            Image { width: manager.cs * 24; height: manager.cs * 24; anchors.verticalCenter: parent.verticalCenter; source: Qt.resolvedUrl("../../assets/branding/omnia-logo.svg"); fillMode: Image.PreserveAspectFit; sourceSize.height: 96 }
            Text { anchors.verticalCenter: parent.verticalCenter; text: "Omnia"; color: manager.ink; font.family: "Hanken Grotesk"; font.pixelSize: manager.cs * 18; font.weight: Font.DemiBold }
        }
        Row {
            anchors { left: brandRow.right; leftMargin: manager.cs * 26; verticalCenter: parent.verticalCenter }
            spacing: manager.cs * 20
            Repeater {
                model: [
                    {key:"home",label:qsTr("Inicio")},
                    {key:"library",label:qsTr("Biblioteca")},
                    {key:"catalog",label:qsTr("Explorar")},
                    {key:"installs",label:qsTr("Instalaciones")}
                ]
                delegate: Item {
                    id: menuItem
                    required property var modelData
                    readonly property bool on: manager.page === modelData.key
                    width: menuLabel.implicitWidth; height: manager.cs * 46
                    Text { id: menuLabel; anchors.verticalCenter: parent.verticalCenter; text: menuItem.modelData.label; color: menuItem.on || navMouse.containsMouse ? manager.ink : manager.muted
                        font.family: "Hanken Grotesk"; font.pixelSize: manager.cs * 14; font.weight: menuItem.on ? Font.DemiBold : Font.Normal }
                    Rectangle { anchors { left: parent.left; right: parent.right; bottom: parent.bottom } height: 3; color: "#5B9BE0"; visible: menuItem.on }
                    MouseArea { id: navMouse; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: manager.selectPage(menuItem.modelData.key) }
                }
            }
        }
        Row {
            anchors { right: parent.right; rightMargin: manager.cs * 22; verticalCenter: parent.verticalCenter }
            spacing: manager.cs * 10
            Rectangle {
                height: manager.cs * 30; width: bigModeLabel.implicitWidth + manager.cs * 44; radius: height / 2; color: manager.accent
                Row { anchors.centerIn: parent; spacing: manager.cs * 8; LucideIcon { anchors.verticalCenter: parent.verticalCenter; width: manager.cs * 15; height: width; name: "gamepad-2"; color: manager.ink } Text { id: bigModeLabel; anchors.verticalCenter: parent.verticalCenter; text: qsTr("Big Mode"); color: manager.ink; font.family: "Hanken Grotesk"; font.pixelSize: manager.cs * 13; font.weight: Font.DemiBold } }
                MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: manager.openBigMode() }
            }
            Rectangle {
                width: manager.cs * 30; height: width; radius: width / 2
                color: manager.page === "settings" ? "#2A4770" : (gearMouse.containsMouse ? "#26FFFFFF" : "transparent")
                LucideIcon { anchors.centerIn: parent; width: manager.cs * 17; height: width; name: "settings"; color: manager.page === "settings" ? "#9CC8F4" : manager.muted }
                ToolTip.visible: gearMouse.containsMouse; ToolTip.text: qsTr("Ajustes"); ToolTip.delay: 400
                MouseArea { id: gearMouse; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: manager.selectPage("settings") }
            }
        }
    }

    // ---------------- barra inferior (añadir juego, descargas y estado)
    Rectangle {
        id: statusbar
        anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
        height: manager.cs * 26
        color: "#0E141B"
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
        anchors { left: parent.left; right: parent.right; top: topbar.bottom; bottom: statusbar.top }
        property real pad: manager.s * 42
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
                    Text { text: banner.parent.news ? qsTr("NOVEDAD DEL CATÁLOGO") : qsTr("BIENVENIDO A OMNIA"); color: "#9CC8F4"; font.family: "Hanken Grotesk"; font.pixelSize: manager.s * 13; font.weight: Font.Bold; font.letterSpacing: 2 }
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

        // Catálogo en línea
        Item {
            anchors { left: parent.left; right: parent.right; top: parent.top; bottom: parent.bottom }
            visible: manager.page === "catalog"
            TextField {
                id: remoteSearch
                x: content.pad; y: content.top0; width: manager.s * 520; height: manager.s * 44
                placeholderText: manager.catalogLinkTargetId ? qsTr("Buscar una ficha para vincular") : qsTr("Buscar en el catálogo Omnia")
                color: manager.ink; font.family: "Hanken Grotesk"; font.pixelSize: manager.s * 16
                onAccepted: { manager.query = text; manager.loadOnline(1) }
                background: Rectangle { radius: manager.s * 13; color: manager.surface2; border.color: remoteSearch.activeFocus ? "#5B9BE0" : "#24FFFFFF" }
            }
            Text { x: remoteSearch.x; y: remoteSearch.y + remoteSearch.height + manager.s * 10; text: manager.onlineWarning; visible: !!text; color: "#E8B86D"; font.family: "Hanken Grotesk"; font.pixelSize: manager.s * 13 }
            GridView {
                anchors { left: parent.left; right: parent.right; top: remoteSearch.bottom; bottom: catalogPagination.top; leftMargin: content.pad; rightMargin: content.pad; topMargin: manager.s * 40; bottomMargin: manager.s * 10 }
                cellWidth: manager.s * 250; cellHeight: manager.s * 300; clip: true
                model: manager.onlineGames
                delegate: Rectangle {
                    required property var modelData
                    width: manager.s * 232; height: manager.s * 280; radius: manager.s * 18; color: manager.surface; clip: true
                    FadedImage { anchors.fill: parent; source: manager.imageFor(modelData, ["grid", "hero"]); cornerRadius: manager.s * 18 }
                    Rectangle { anchors.fill: parent; radius: manager.s * 18; gradient: Gradient { GradientStop { position: 0.4; color: "#00151D27" } GradientStop { position: 1; color: "#ED0B0F14" } } }
                    Column { anchors { left: parent.left; right: parent.right; bottom: parent.bottom; margins: manager.s * 14 } spacing: manager.s * 4; Text { width: parent.width; text: modelData.name || ""; color: manager.ink; font.family: "Hanken Grotesk"; font.pixelSize: manager.s * 17; font.weight: Font.DemiBold; elide: Text.ElideRight } Text { width: parent.width; text: (modelData.platforms || []).map(p => p.name || p.slug).join(" · "); color: manager.muted; font.family: "Hanken Grotesk"; font.pixelSize: manager.s * 12; elide: Text.ElideRight } }
                    Rectangle {
                        visible: !!manager.catalogLinkTargetId
                        anchors { right: parent.right; top: parent.top; margins: manager.s * 10 }
                        width: manager.s * 88; height: manager.s * 30; radius: height / 2; color: manager.accent
                        Text { anchors.centerIn: parent; text: qsTr("Vincular"); color: manager.ink; font.family: "Hanken Grotesk"; font.pixelSize: manager.s * 12; font.weight: Font.DemiBold }
                    }
                    MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: manager.catalogLinkTargetId ? manager.linkCatalogGame(modelData) : manager.openCatalogDetail(modelData) }
                }
                Text { visible: manager.onlineBusy || manager.onlineGames.length === 0; anchors.centerIn: parent; text: manager.onlineBusy ? qsTr("Cargando catálogo…") : qsTr("No hay resultados disponibles."); color: manager.muted; font.family: "Hanken Grotesk"; font.pixelSize: manager.s * 16 }
            }
            Rectangle {
                visible: !!manager.catalogLinkTargetId
                anchors { right: parent.right; top: parent.top; rightMargin: content.pad; topMargin: content.top0 }
                width: manager.s * 110; height: manager.s * 44; radius: manager.s * 13; color: manager.surface2
                Text { anchors.centerIn: parent; text: qsTr("Cancelar vínculo"); color: manager.ink; font.family: "Hanken Grotesk"; font.pixelSize: manager.s * 12 }
                MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: manager.cancelCatalogLink() }
            }
            Row {
                id: catalogPagination
                anchors { horizontalCenter: parent.horizontalCenter; bottom: parent.bottom; bottomMargin: manager.s * 16 }
                height: manager.s * 40
                spacing: manager.s * 6
                readonly property int total: Math.max(1, Number(manager.onlineMeta.totalPages) || 1)
                readonly property var pages: {
                    const cur = manager.onlinePage, t = total, out = []
                    const add = function(n) { if (n >= 1 && n <= t && out.indexOf(n) < 0) out.push(n) }
                    add(1); add(cur - 1); add(cur); add(cur + 1); add(t)
                    out.sort(function(a, b) { return a - b })
                    const res = []
                    out.forEach(function(n, i) { if (i > 0 && n - out[i - 1] > 1) res.push(0); res.push(n) })
                    return res
                }
                component PageButton: Rectangle {
                    id: pb
                    property string icon: ""
                    property string label: ""
                    property bool current: false
                    property bool enabledBtn: true
                    signal activated()
                    width: label !== "" ? Math.max(manager.s * 40, lbl.implicitWidth + manager.s * 20) : manager.s * 40
                    height: manager.s * 40; radius: manager.s * 12
                    color: current ? manager.accent : (enabledBtn && pbMa.containsMouse ? "#2E3F52" : "transparent")
                    border.color: current ? "#5B9BE0" : (enabledBtn && pbMa.containsMouse ? "#3B516A" : "transparent")
                    scale: enabledBtn && pbMa.containsMouse && !current ? 1.08 : (pbMa.pressed && enabledBtn ? 0.95 : 1)
                    opacity: enabledBtn ? 1 : 0.35
                    Behavior on color { ColorAnimation { duration: 140 } }
                    Behavior on scale { NumberAnimation { duration: 120; easing.type: Easing.OutCubic } }
                    LucideIcon { visible: pb.icon !== ""; anchors.centerIn: parent; width: manager.s * 18; height: width; name: pb.icon; color: pb.current || pbMa.containsMouse ? manager.ink : manager.muted }
                    Text { id: lbl; visible: pb.label !== ""; anchors.centerIn: parent; text: pb.label; color: pb.current || pbMa.containsMouse ? manager.ink : manager.muted
                        font.family: "Hanken Grotesk"; font.pixelSize: manager.s * 15; font.weight: pb.current ? Font.DemiBold : Font.Normal }
                    MouseArea { id: pbMa; anchors.fill: parent; hoverEnabled: true; enabled: pb.enabledBtn; cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor; onClicked: pb.activated() }
                }
                PageButton { icon: "chevrons-left"; enabledBtn: manager.onlinePage > 1 && !manager.onlineBusy; onActivated: manager.goOnlinePage(1) }
                PageButton { icon: "chevron-left"; enabledBtn: manager.onlinePage > 1 && !manager.onlineBusy; onActivated: manager.changeOnlinePage(-1) }
                Repeater {
                    model: catalogPagination.pages
                    delegate: Loader {
                        id: pgLoader
                        required property int modelData
                        sourceComponent: modelData === 0 ? gap : numberBtn
                        Component { id: gap; Item { width: manager.s * 26; height: manager.s * 40; Text { anchors.centerIn: parent; text: "…"; color: manager.muted; font.pixelSize: manager.s * 16 } } }
                        Component { id: numberBtn; PageButton { label: String(pgLoader.modelData); current: pgLoader.modelData === manager.onlinePage; enabledBtn: !manager.onlineBusy; onActivated: manager.goOnlinePage(pgLoader.modelData) } }
                    }
                }
                PageButton { icon: "chevron-right"; enabledBtn: manager.onlinePage < catalogPagination.total && !manager.onlineBusy; onActivated: manager.changeOnlinePage(1) }
                PageButton { icon: "chevrons-right"; enabledBtn: manager.onlinePage < catalogPagination.total && !manager.onlineBusy; onActivated: manager.goOnlinePage(catalogPagination.total) }
                Text { anchors.verticalCenter: parent.verticalCenter; leftPadding: manager.s * 12
                    text: qsTr("%1 juegos").arg(Number(manager.onlineMeta.total) || manager.onlineGames.length)
                    color: manager.muted; font.family: "Hanken Grotesk"; font.pixelSize: manager.s * 13 }
            }
        }

        // Cola local de descargas y verificaciones
        Item {
            anchors { left: parent.left; right: parent.right; top: parent.top; bottom: parent.bottom }
            visible: manager.page === "installs"
            ListView {
                anchors { left: parent.left; right: parent.right; top: parent.top; margins: content.pad; topMargin: content.top0 }
                height: manager.s * 134
                clip: true; spacing: manager.s * 10; model: manager.installJobs
                delegate: Rectangle {
                    required property var modelData
                    width: ListView.view.width; height: manager.s * 92; radius: manager.s * 15; color: manager.surface
                    Column { anchors { left: parent.left; right: installActions.left; verticalCenter: parent.verticalCenter; leftMargin: manager.s * 18; rightMargin: manager.s * 12 } spacing: manager.s * 7
                        Row { width: parent.width; Text { width: parent.width; text: modelData.name + " · " + manager.installationStatusLabel(modelData.status); color: manager.ink; font.family: "Hanken Grotesk"; font.pixelSize: manager.s * 15; elide: Text.ElideRight } }
                        Rectangle { width: parent.width; height: manager.s * 6; radius: height/2; color: manager.surface2; Rectangle { width: parent.width * Math.max(0, Math.min(1, Number(modelData.progress || 0) / 100)); height: parent.height; radius: height/2; color: manager.accent } }
                        Text { width: parent.width; text: modelData.error ? manager.installationErrorText(modelData.error) : (modelData.destination || ""); color: modelData.error ? "#E8B86D" : manager.muted; font.family: "Hanken Grotesk"; font.pixelSize: manager.s * 11; elide: Text.ElideMiddle }
                    }
                    Row { id: installActions; anchors { right: parent.right; verticalCenter: parent.verticalCenter; rightMargin: manager.s * 14 } spacing: manager.s * 6
                        Rectangle {
                            visible: ["queued", "downloading", "extracting", "paused"].includes(modelData.status)
                            width: manager.s * 72; height: manager.s * 34; radius: height/2; color: manager.surface2
                            Text { anchors.centerIn: parent; text: modelData.status === "paused" ? qsTr("Reanudar") : qsTr("Pausar"); color: manager.ink; font.family: "Hanken Grotesk"; font.pixelSize: manager.s * 10 }
                            MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: {
                                const done = function() { manager.loadInstallations() }
                                if (modelData.status === "paused") api.resumeInstallation(modelData.id, done)
                                else api.pauseInstallation(modelData.id, done)
                            } }
                        }
                        Rectangle {
                            visible: ["queued", "downloading", "verifying", "extracting", "paused"].includes(modelData.status)
                            width: manager.s * 72; height: manager.s * 34; radius: height/2; color: "#50343A"
                            Text { anchors.centerIn: parent; text: qsTr("Cancelar"); color: manager.ink; font.family: "Hanken Grotesk"; font.pixelSize: manager.s * 10 }
                            MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: api.cancelInstallation(modelData.id, function() { manager.loadInstallations() }) }
                        }
                    }
                    Rectangle { visible: modelData.installed === true; anchors { right: parent.right; verticalCenter: parent.verticalCenter; rightMargin: manager.s * 14 } width: manager.s * 72; height: manager.s * 34; radius: height/2; color: "#50343A"; Text { anchors.centerIn: parent; text: qsTr("Quitar"); color: manager.ink; font.family: "Hanken Grotesk"; font.pixelSize: manager.s * 11 } MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: { manager.removeGameId = modelData.gameId; uninstallDialog.open() } } }
                }
                Text { visible: manager.installJobs.length === 0; anchors.centerIn: parent; text: qsTr("Aún no hay instalaciones."); color: manager.muted; font.family: "Hanken Grotesk"; font.pixelSize: manager.s * 16 }
            }
            Text { x: content.pad; y: manager.s * 178; text: qsTr("Juegos en este equipo"); color: manager.ink; font.family: "Hanken Grotesk"; font.pixelSize: manager.s * 20; font.weight: Font.DemiBold }
            ListView {
                anchors { left: parent.left; right: parent.right; top: parent.top; bottom: parent.bottom; leftMargin: content.pad; rightMargin: content.pad; topMargin: manager.s * 218; bottomMargin: manager.s * 24 }
                clip: true; spacing: manager.s * 8; model: api.games.filter(g => !g.hidden)
                delegate: Rectangle {
                    required property var modelData
                    width: ListView.view.width; height: manager.s * 74; radius: manager.s * 14; color: manager.surface
                    FadedImage { x: manager.s * 10; anchors.verticalCenter: parent.verticalCenter; width: manager.s * 54; height: manager.s * 54; source: modelData.portada || ""; cornerRadius: manager.s * 10 }
                    Column { anchors { left: parent.left; leftMargin: manager.s * 78; verticalCenter: parent.verticalCenter } width: parent.width * 0.68; spacing: manager.s * 2; Text { width: parent.width; text: modelData.name; color: manager.ink; font.family: "Hanken Grotesk"; font.pixelSize: manager.s * 15; font.weight: Font.DemiBold; elide: Text.ElideRight } Text { width: parent.width; text: modelData.folder || (modelData.ports.length ? modelData.ports[0].name : qsTr("Ubicación no disponible")); color: manager.muted; font.family: "Hanken Grotesk"; font.pixelSize: manager.s * 11; elide: Text.ElideMiddle } }
                    Rectangle { anchors { right: parent.right; verticalCenter: parent.verticalCenter; rightMargin: manager.s * 12 } width: manager.s * 94; height: manager.s * 36; radius: height / 2; color: manager.accent; Text { anchors.centerIn: parent; text: qsTr("Jugar"); color: manager.ink; font.family: "Hanken Grotesk"; font.pixelSize: manager.s * 13; font.weight: Font.DemiBold } MouseArea { anchors.fill: parent; enabled: !modelData.running; cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor; onClicked: manager.launch(modelData) } }
                }
                Text { visible: api.games.length === 0; anchors.centerIn: parent; text: qsTr("Aún no hay juegos instalados o importados."); color: manager.muted; font.family: "Hanken Grotesk"; font.pixelSize: manager.s * 15 }
            }
        }

        // Preferencias
        Item {
            anchors { left: parent.left; right: parent.right; top: parent.top; bottom: parent.bottom }
            visible: manager.page === "settings"
            Column {
                x: content.pad; y: content.top0; width: manager.s * 190; spacing: manager.s * 4
                Repeater {
                    model: [{ k: "general", l: qsTr("General") }, { k: "library", l: qsTr("Biblioteca") }, { k: "bigmode", l: qsTr("Big Mode") }, { k: "about", l: qsTr("Acerca de") }]
                    delegate: Rectangle {
                        id: setTab
                        required property var modelData
                        readonly property bool on: manager.settingsSection === modelData.k
                        width: parent.width; height: manager.s * 42; radius: manager.s * 10
                        color: on ? "#2A4770" : (setMa.containsMouse ? "#14FFFFFF" : "transparent")
                        Text { anchors { left: parent.left; leftMargin: manager.s * 14; verticalCenter: parent.verticalCenter } text: setTab.modelData.l; color: manager.ink; font.family: "Hanken Grotesk"; font.pixelSize: manager.s * 16; font.weight: setTab.on ? Font.DemiBold : Font.Normal }
                        MouseArea { id: setMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: manager.settingsSection = setTab.modelData.k }
                    }
                }
            }
            Column {
                x: content.pad + manager.s * 214; y: content.top0; width: parent.width - content.pad * 2 - manager.s * 214; spacing: manager.s * 14
                Rectangle {
                    visible: manager.settingsSection === "about"
                    width: parent.width; height: manager.s * 150; radius: manager.s * 16; color: manager.surface
                    Row { anchors { left: parent.left; verticalCenter: parent.verticalCenter; leftMargin: manager.s * 22 } spacing: manager.s * 18
                        Image { width: manager.s * 72; height: width; anchors.verticalCenter: parent.verticalCenter; source: Qt.resolvedUrl("../../assets/branding/omnia-icon.svg"); sourceSize.height: 192; fillMode: Image.PreserveAspectFit }
                        Column { anchors.verticalCenter: parent.verticalCenter; spacing: manager.s * 5
                            Text { text: "Omnia Desktop Suite"; color: manager.ink; font.family: "Hanken Grotesk"; font.pixelSize: manager.s * 22; font.weight: Font.DemiBold }
                            Text { text: qsTr("Biblioteca de juegos y Big Mode para Linux. En la interfaz se llama simplemente Omnia."); color: manager.muted; font.family: "Hanken Grotesk"; font.pixelSize: manager.s * 14 }
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
                    visible: manager.settingsSection === "library"
                    width: parent.width; height: manager.s * 116; radius: manager.s * 16; color: manager.surface
                    Column { anchors { left: parent.left; top: parent.top; margins: manager.s * 18 } spacing: manager.s * 5
                        Text { text: qsTr("Carpetas de la biblioteca"); color: manager.ink; font.family: "Hanken Grotesk"; font.pixelSize: manager.s * 17; font.weight: Font.DemiBold }
                        Text { text: qsTr("Añade aquí tus carpetas de juegos y ROMs: Omnia las detecta solas, sin elegir emulador. Retirar una carpeta no elimina los archivos."); color: manager.muted; font.family: "Hanken Grotesk"; font.pixelSize: manager.s * 13 }
                    }
                    Row {
                        anchors { right: parent.right; bottom: parent.bottom; margins: manager.s * 14 } spacing: manager.s * 8
                        TextField { id: rootInput; width: manager.s * 420; height: manager.s * 40; placeholderText: qsTr("Ruta, por ejemplo /mnt/JUEGOS/Ports"); text: manager.rootPath; onTextEdited: manager.rootPath = text; color: manager.ink; font.family: "Hanken Grotesk"; font.pixelSize: manager.s * 14; background: Rectangle { radius: manager.s * 10; color: manager.surface2; border.color: rootInput.activeFocus ? "#5B9BE0" : "#24FFFFFF" } }
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
                        LucideIcon { x: manager.s * 16; anchors.verticalCenter: parent.verticalCenter; width: manager.s * 20; height: width; name: "folder-open"; color: "#9CC8F4" }
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
            anchors.centerIn: parent; width: Math.min(parent.width * 0.68, manager.s * 800); height: manager.s * 480; radius: manager.s * 24; color: manager.surface; clip: true
            MouseArea { anchors.fill: parent; onClicked: function(mouse) { mouse.accepted = true } }
            FadedImage { anchors.fill: parent; source: manager.imageFor(manager.detailGame, ["hero", "grid"]); cornerRadius: manager.s * 24; opacity: 0.3 }
            Rectangle { anchors.fill: parent; radius: manager.s * 24; gradient: Gradient { GradientStop { position: 0; color: "#B3151D27" } GradientStop { position: 1; color: "#F0151D27" } } }
            Column { anchors { left: parent.left; right: parent.right; top: parent.top; margins: manager.s * 30 } spacing: manager.s * 12; Text { width: parent.width; text: manager.detailGame ? manager.detailGame.name || "" : ""; color: manager.ink; font.family: "Hanken Grotesk"; font.pixelSize: manager.s * 30; font.weight: Font.Bold; wrapMode: Text.WordWrap } Text { text: manager.detailGame ? manager.detailGame.description || qsTr("Sin descripción disponible.") : ""; color: manager.muted; font.family: "Hanken Grotesk"; font.pixelSize: manager.s * 16; wrapMode: Text.WordWrap; width: parent.width; maximumLineCount: 6; elide: Text.ElideRight } }
            Row { anchors { left: parent.left; bottom: parent.bottom; margins: manager.s * 30 } spacing: manager.s * 12
                Rectangle { width: manager.s * 180; height: manager.s * 44; radius: height/2; color: manager.localMatch(manager.detailGame) ? manager.accent : manager.surface2; Text { anchors.centerIn: parent; width: parent.width - manager.s * 10; horizontalAlignment: Text.AlignHCenter; text: manager.localMatch(manager.detailGame) ? qsTr("Jugar") : qsTr("Sin paquete publicado"); color: manager.ink; font.family: "Hanken Grotesk"; font.pixelSize: manager.s * 14; elide: Text.ElideRight } MouseArea { anchors.fill: parent; enabled: !!manager.localMatch(manager.detailGame); cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor; onClicked: manager.launch(manager.localMatch(manager.detailGame)) } }
                Rectangle { visible: !manager.localMatch(manager.detailGame) && manager.packageOptions.length > 0; width: manager.s * 150; height: manager.s * 44; radius: height/2; color: manager.acceptLicense && api.installRoot ? manager.accent : manager.surface2; opacity: manager.acceptLicense && api.installRoot ? 1 : 0.55; Text { anchors.centerIn: parent; text: qsTr("Instalar"); color: manager.ink; font.family: "Hanken Grotesk"; font.pixelSize: manager.s * 14; font.weight: Font.DemiBold } MouseArea { anchors.fill: parent; enabled: manager.acceptLicense && api.installRoot && !!manager.selectedPackage; cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor; onClicked: manager.startPackageInstall() } }
                Rectangle { width: manager.s * 110; height: manager.s * 44; radius: height/2; color: "#33434F5C"; Text { anchors.centerIn: parent; text: qsTr("Cerrar"); color: manager.ink; font.family: "Hanken Grotesk"; font.pixelSize: manager.s * 14 } MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: manager.detailGame = null } }
            }
            Column {
                anchors { left: parent.left; right: parent.right; bottom: parent.bottom; bottomMargin: manager.s * 92; leftMargin: manager.s * 30; rightMargin: manager.s * 30 }
                visible: manager.detailGame && !manager.localMatch(manager.detailGame); spacing: manager.s * 7
                Text { visible: manager.packagesBusy; text: qsTr("Consultando paquetes…"); color: manager.muted; font.family: "Hanken Grotesk"; font.pixelSize: manager.s * 13 }
                Text { visible: !manager.packagesBusy && manager.packageOptions.length === 0; text: manager.packageMessage; color: manager.muted; font.family: "Hanken Grotesk"; font.pixelSize: manager.s * 12; wrapMode: Text.WordWrap }
                Row { visible: manager.packageOptions.length > 0; spacing: manager.s * 8
                    ComboBox { id: packageChoice; width: manager.s * 300; height: manager.s * 36; model: manager.packageOptions.map(p => p.title + " · " + p.version); onActivated: manager.selectedPackage = manager.packageOptions[currentIndex] }
                    Rectangle { width: manager.s * 145; height: manager.s * 36; radius: manager.s * 10; color: manager.surface2; Text { anchors.centerIn: parent; text: api.installRoot ? qsTr("Destino predeterminado") : qsTr("Elegir destino"); color: manager.ink; font.family: "Hanken Grotesk"; font.pixelSize: manager.s * 12; elide: Text.ElideRight; width: parent.width - manager.s * 12; horizontalAlignment: Text.AlignHCenter } MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: installFolderDialog.open() } }
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
    property string removeGameId: ""
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
    }
    Component {
        id: addGameComponent
        AddGame {
            api: api
            onFinished: manager.addWizardOpen = false
            onAdded: function(id) { manager.addWizardOpen = false; api.refresh(); api.notify(qsTr("Juego añadido a la biblioteca.")) }
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

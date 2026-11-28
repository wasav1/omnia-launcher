pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls
import "Theme.js" as Theme

/** Catálogo de Big Mode (antes «Tienda»; estilo D desde la fase 5b). El foco se conserva por tarjeta al volver de una ficha. */
Item {
    id: bigStore
    required property var host
    required property var accounts
    readonly property var api: host.api
    readonly property real s: host.s
    readonly property var sources: [
        {id:"all", name:qsTr("Todas")}, {id:"omnia", name:qsTr("Omnia")},
        {id:"steam", name:"Steam"}, {id:"epic", name:"Epic"}, {id:"gog", name:"GOG"}, {id:"amazon", name:"Amazon"},
        {id:"ubisoft", name:"Ubisoft"}, {id:"ea", name:"EA"}
    ]
    property int filter: 0
    property string query: ""
    property int zone: 2                 // 2 tiendas y consola (barra fija de arriba) · 3 cuadrícula
    property int gridIndex: 0
    property string gridSelection: ""
    readonly property real cardWidth: host.libraryCoverWidth
    readonly property real cardHeight: host.libraryCoverHeight
    readonly property real cardGap: s * 20
    readonly property int columns: Math.max(1, Math.floor((width + cardGap) / (cardWidth + cardGap)))
    property var catalog: []
    property int catalogPage: 0
    property int totalPages: 1
    property var consoles: []
    property int consoleIndex: 0
    property bool consoleFocused: false
    readonly property string consoleSlug: activeSource === "omnia" && consoleIndex > 0 ? consoles[consoleIndex - 1]?.slug || "" : ""
    function loadConsoles() {
        if (consoles.length) return
        api.catalogPlatforms((status, response) => {
            if (status === 200) bigStore.consoles = (response.items || []).filter(platform => !!platform.slug)
        })
    }
    function pickConsole(index) {
        const count = consoles.length + 1
        consoleIndex = (index + count) % count
        consoleFocused = true
    }
    onConsoleSlugChanged: {
        catalogRequest++
        catalogLoading = false
        catalogPage = 0
        catalog = []
        gridIndex = 0
        gridSelection = ""
        if (visible) loadCatalog(false)
    }
    property int catalogRequest: 0
    property bool catalogLoading: false
    property string catalogMessage: ""
    property var detail: null
    property var packages: []
    property bool detailLoading: false
    property bool installing: false
    property string detailMessage: ""
    property int detailIndex: 0
    property int detailRequest: 0
    readonly property string activeSource: sources[filter].id

    function matchLocal(game) {
        return (api.games || []).find(g => !g.hidden && g.catalogSlug === game.slug && !g.portAvailable) || null
    }
    function art(game, kinds) {
        const entries = game.artwork || []
        for (const kind of kinds) {
            const entry = entries.find(a => a.type === kind && a.imageUrl)
            if (entry) return entry.localUrl || (entry.imageUrl.startsWith("/") ? api.catalogBaseUrl : "") + entry.imageUrl
        }
        return ""
    }
    function catalogEntry(game) {
        return {
            id: "catalog:" + game.slug, name: game.name, store: "omnia", game: game,
            art: art(game, ["grid", "hero"]), local: matchLocal(game)
        }
    }
    function matches(item) {
        return (activeSource === "all" || item.store === activeSource)
            && (!query || item.name.toLowerCase().includes(query.toLowerCase()))
            && (!consoleSlug || item.local?.platform === consoleSlug
                || ({switch:"sw1", switch2:"sw2", gamecube:"gcwii", wii:"gcwii"})[consoleSlug] === item.local?.platform && !!item.local?.platform)
    }
    readonly property var available: {
        const remote = accounts.allItems.filter(item => !item.installed && matches(item))
        if (activeSource !== "all" && activeSource !== "omnia") return remote
        const ports = catalog.map(catalogEntry).filter(item => !item.local)
        if (activeSource === "omnia") return ports
        const combined = []
        for (let i = 0; i < Math.max(ports.length, remote.length); i++) {
            if (ports[i]) combined.push(ports[i])
            if (remote[i]) combined.push(remote[i])
        }
        return combined
    }
    function installedSource(game) {
        const id = accounts.storeOf(game)
        return id || (game.src === "Omnia" || game.installPackageId ? "omnia" : "local")
    }
    readonly property var installed: (api.games || [])
        .filter(game => !game.hidden && (game.ports || []).some(port => port.canLaunch))
        .sort((a, b) => Number(b.added || 0) - Number(a.added || 0) || a.name.localeCompare(b.name))
        .map(game => ({ id: game.id, name: game.name, store: installedSource(game),
                         art: game.portada || game.fondo || "", hero: game.fondo || "", local: game }))

    readonly property var gridGames: available.concat(installed.filter(matches))
    readonly property bool hasOmnia: activeSource === "all" || activeSource === "omnia"
    function storeLogo(id) {
        return !id || id === "local" || id === "all" ? "" : Qt.resolvedUrl("images/stores/" + id + ".svg")
    }

    function loadCatalog(next) {
        if (next && (catalogLoading || catalogPage >= totalPages)) return
        const page = next ? catalogPage + 1 : 1
        const request = ++catalogRequest
        catalogLoading = true
        catalogMessage = ""
        api.catalogGames({page: page, pageSize: 30, q: query, platform: consoleSlug, sort: "updatedAt", order: "desc"}, function(status, body) {
            if (request !== bigStore.catalogRequest) return
            bigStore.catalogLoading = false
            if (status !== 200) {
                bigStore.catalogMessage = qsTr("No se pudo cargar el catálogo. Pulsa A en el filtro actual para reintentar.")
                return
            }
            const items = body.items || []
            const known = new Set(bigStore.catalog.map(game => game.slug))
            bigStore.catalog = next ? bigStore.catalog.concat(items.filter(game => !known.has(game.slug))) : items
            bigStore.catalogPage = page
            bigStore.totalPages = Number(body.meta?.totalPages || 1)
            bigStore.catalogMessage = body.warning || ""
        })
    }
    function open() {
        if (!catalogPage && !catalogLoading) loadCatalog(false)
        loadConsoles()
        accounts.refreshStores()
    }
    function setFilter(index) {
        gridSelection = ""
        gridIndex = 0
        filter = (index + sources.length) % sources.length
        zone = 2
        consoleFocused = false
        revealFocus()
    }
    function search() {
        let pending = query
        host.openKeyboardFor(query, value => pending = value, function(accepted) {
            if (!accepted) return
            const value = pending.trim()
            if (value === bigStore.query) return
            bigStore.gridSelection = ""
            bigStore.gridIndex = 0
            bigStore.query = value
            bigStore.catalog = []
            bigStore.catalogPage = 0
            bigStore.focusZone(2)
            bigStore.loadCatalog(false)
        })
    }
    onGridGamesChanged: {
        const index = gridGames.findIndex(item => item.id === gridSelection)
        gridIndex = index < 0 ? Math.min(gridIndex, Math.max(0, gridGames.length - 1)) : index
        if (gridSelection) gridSelection = gridGames[gridIndex]?.id || ""
        if (zone === 3 && !detail) revealFocus()
    }

    function focusZone(value) {
        zone = value
        revealFocus()
    }
    function revealFocus() {
        Qt.callLater(function() {
            if (!bigStore.visible || bigStore.detail) return
            if (bigStore.zone === 3 && bigStore.gridGames.length) {
                const card = grid.itemAtIndex(bigStore.gridIndex)
                if (!card) { grid.positionViewAtIndex(bigStore.gridIndex, GridView.Contain); return }
                smoothGrid.showRange(card.y, card.y + card.height, bigStore.s * 12)
                return
            }
            if (bigStore.zone === 2) smoothGrid.scrollTo(grid.originY)
        })
    }
    function selectGrid(index) {
        if (index < 0 || index >= gridGames.length) return
        gridIndex = index
        gridSelection = gridGames[index].id
        focusZone(3)
        if (hasOmnia && index >= gridGames.length - columns * 2) loadCatalog(true)
    }
    function openDetail(item) {
        if (!item) return
        detail = item
        detailIndex = 0
        packages = []
        detailMessage = ""
        detailLoading = !!item.game && !item.local
        if (!detailLoading) return
        const request = ++detailRequest
        api.catalogInstallPackages(item.game.slug, function(status, body) {
            if (request !== bigStore.detailRequest || bigStore.detail?.id !== item.id) return
            bigStore.detailLoading = false
            bigStore.packages = status === 200 && !body.offline
                ? (body.items || []).filter(pkg => pkg.platformSlug === "pc") : []
            if (!bigStore.packages.length)
                bigStore.detailMessage = status === 200 && !body.offline ? qsTr("No hay un paquete instalable publicado.")
                    : qsTr("No se pudieron consultar los paquetes publicados.")
        })
    }
    function closeDetail() {
        if (installing) return
        detailRequest++
        detail = null
        forceActiveFocus()
    }
    readonly property var detailActions: {
        if (!detail) return []
        const rows = []
        if (detail.local) {
            rows.push({id:"play", label:qsTr("Jugar")})
            rows.push({id:"details", label:qsTr("Ver en Biblioteca")})
        } else if (!detail.game && detail.store === "steam") {
            rows.push({id:"steam", label:qsTr("Instalar en Steam")})
        } else if (!detail.game || packages.length) {
            if (!api.installRoot) rows.push({id:"root", label:qsTr("Elegir carpeta de instalación")})
            else if (!detail.game) rows.push({id:"install", label:qsTr("Instalar")})
            else packages.forEach(pkg => rows.push({id:"port", label:qsTr("Instalar %1").arg(pkg.version || pkg.title), pkg:pkg}))
        }
        rows.push({id:"back", label:qsTr("Volver")})
        return rows
    }
    onDetailActionsChanged: detailIndex = Math.min(detailIndex, Math.max(0, detailActions.length - 1))
    function action(row) {
        if (!row || !detail || installing) return
        const item = detail
        if (row.id === "back") closeDetail()
        else if (row.id === "play") host.play(item.local)
        else if (row.id === "details") {
            closeDetail()
            host.openLocalFromHome(item.local.id)
        } else if (row.id === "root") {
            host.chooseStoreInstallRoot(message => bigStore.detailMessage = message)
        } else if (row.id === "steam") {
            accounts.installSteam(item)
        } else if (row.id === "port") {
            const pkg = row.pkg
            host.openStorePort(item.name, {
                slug: item.game.slug, packageId: pkg.id, title: pkg.title, version: pkg.version,
                sizeBytes: pkg.sizeBytes, licenseName: pkg.licenseName, sourceName: pkg.sourceName
            })
        } else if (row.id === "install") {
            installing = true
            detailMessage = qsTr("Añadiendo a la cola…")
            api.storeInstall(item.store, item.rawId, item.name, api.installRoot, function(status, body) {
                bigStore.installing = false
                if (status === 200 && body.launcher) bigStore.detailMessage = qsTr("Se abrió %1: instala «%2» desde allí y Omnia lo añadirá a la biblioteca.").arg(body.name).arg(item.name)
                else if (status === 200) { bigStore.closeDetail(); host.openDownloads() }
                else bigStore.detailMessage = body.error || qsTr("No se pudo iniciar la instalación.")
            })
        }
    }
    readonly property var contextGame: detail?.local || (zone === 3 ? gridGames[gridIndex]?.local : null)
    function pad(key) {
        if ((key === "Y" || key === "MENU") && contextGame) {
            host.openMenu(contextGame)
            return
        }
        if (detail) {
            if (key === "B") closeDetail()
            else if (key === "l" || key === "r") detailIndex = Math.max(0, Math.min(detailActions.length - 1, detailIndex + (key === "l" ? -1 : 1)))
            else if (key === "u" || key === "d") detailsList.contentY = Math.max(0, Math.min(
                detailsList.contentHeight - detailsList.height, detailsList.contentY + bigStore.s * (key === "u" ? -96 : 96)))
            else if (key === "A") action(detailActions[detailIndex])
            return
        }
        if (key === "LB" || key === "RB") { setFilter(filter + (key === "LB" ? -1 : 1)); return }
        if (key === "X") { search(); return }
        if (key === "Y") { host.openDownloads(); return }
        if (key === "B") { host.back(); return }
        if (key === "u" || key === "d") {
            if (zone === 3) {
                const next = gridIndex + (key === "u" ? -columns : columns)
                if (next < 0) { consoleFocused = activeSource === "omnia"; focusZone(2) }
                else if (next < gridGames.length) selectGrid(next)
                else if (key === "d" && Math.floor(gridIndex / columns) < Math.floor((gridGames.length - 1) / columns))
                    selectGrid(gridGames.length - 1)
                else if (key === "d" && hasOmnia) loadCatalog(true)
            } else if (zone === 2 && activeSource === "omnia" && key === "d" && !consoleFocused) consoleFocused = true
            else if (zone === 2 && key === "u" && consoleFocused) consoleFocused = false
            else if (zone === 2 && key === "u") host.focusMainNav()           // tiendas → barra superior
            else if (key === "d" && zone === 2 && gridGames.length) selectGrid(gridIndex)
            return
        }
        if (key === "A") {
            if (zone === 2) {
                if (catalogMessage && !catalog.length && hasOmnia) loadCatalog(false)
                else if (gridGames.length) selectGrid(gridIndex)
            } else openDetail(gridGames[gridIndex])
            return
        }
        if (key !== "l" && key !== "r") return
        const step = key === "r" ? 1 : -1
        if (zone === 2 && consoleFocused) pickConsole(consoleIndex + step)
        else if (zone === 2) setFilter(filter + step)
        else if (zone === 3 && Math.floor((gridIndex + step) / columns) === Math.floor(gridIndex / columns))
            selectGrid(gridIndex + step)
    }
    function key(event) {
        const mapping = {
            [Qt.Key_Up]:"u", [Qt.Key_Down]:"d", [Qt.Key_Left]:"l", [Qt.Key_Right]:"r",
            [Qt.Key_Return]:"A", [Qt.Key_Enter]:"A", [Qt.Key_Escape]:"B", [Qt.Key_Slash]:"X",
            [Qt.Key_Tab]:"RB", [Qt.Key_Backtab]:"LB", [Qt.Key_Y]:"Y", [Qt.Key_M]:"MENU", [Qt.Key_Menu]:"MENU"
        }
        if (!mapping[event.key]) return false
        pad(mapping[event.key])
        return true
    }

    component Action: Rectangle {
        id: button
        property string label: ""
        property bool selected: false
        property bool focused: false
        property string icon: ""
        property url logo: ""
        signal choose()
        width: labelRow.implicitWidth + bigStore.s * 30
        height: bigStore.s * 38; radius: height / 2
        color: selected ? Theme.color.accentSoft : (actionMa.containsMouse ? Theme.color.glassFillStrong : Qt.rgba(1, 1, 1, 0.06))
        border { width: focused ? 3 : 1; color: focused ? Theme.color.accent : (selected ? Theme.color.accent : Theme.color.glassBorderStrong) }
        Row {
            id: labelRow
            anchors.centerIn: parent
            spacing: bigStore.s * 7
            LucideIcon { visible: !!button.icon; name: button.icon; width: bigStore.s * 19; height: width; color: bigStore.host.ink; anchors.verticalCenter: parent.verticalCenter }
            Image { visible: !!button.logo.toString(); source: button.logo; width: bigStore.s * 25; height: width; fillMode: Image.PreserveAspectFit; anchors.verticalCenter: parent.verticalCenter }
            Text { text: button.label; color: button.selected ? Theme.color.accentLight : bigStore.host.ink; font.family: bigStore.host.uiFont; font.pixelSize: bigStore.s * 18; font.weight: button.selected ? Font.DemiBold : Font.Normal; anchors.verticalCenter: parent.verticalCenter }
        }
        MouseArea { id: actionMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: button.choose() }
    }
    component FilterBar: Row {
        spacing: bigStore.s * 10
        Repeater {
            model: bigStore.sources
            delegate: Action {
                id: chip
                required property int index
                required property var modelData
                height: bigStore.s * 48
                label: modelData.name
                selected: bigStore.filter === index
                focused: bigStore.zone === 2 && !bigStore.consoleFocused && selected && bigStore.host.mainNavIndex < 0
                logo: bigStore.storeLogo(modelData.id)
                onChoose: bigStore.setFilter(index)
            }
        }
    }

    component StoreFilters: Column {
        spacing: bigStore.s * 12
        FilterBar { }
        Row {
            visible: bigStore.activeSource === "omnia"
            spacing: bigStore.s * 10
            Text { anchors.verticalCenter: parent.verticalCenter; text: qsTr("Consola"); color: bigStore.host.ink2; font.family: bigStore.host.uiFont; font.pixelSize: bigStore.s * 18; rightPadding: bigStore.s * 4 }
            Action {
                icon: "chevron-left"
                label: ""
                onChoose: bigStore.pickConsole(bigStore.consoleIndex - 1)
            }
            Action {
                icon: "gamepad-2"
                label: bigStore.consoleIndex ? bigStore.consoles[bigStore.consoleIndex - 1]?.name || qsTr("Todas las consolas") : qsTr("Todas las consolas")
                focused: bigStore.zone === 2 && bigStore.consoleFocused && bigStore.host.mainNavIndex < 0
                onChoose: bigStore.pickConsole(bigStore.consoleIndex + 1)
            }
            Action {
                icon: "chevron-right"
                label: ""
                onChoose: bigStore.pickConsole(bigStore.consoleIndex + 1)
            }
        }
    }

    // ---- barra fija: título, buscar, tiendas en pestañas y (en Omnia) la consola
    Column {
        id: topBar
        anchors { left: parent.left; right: parent.right; top: parent.top }
        spacing: bigStore.s * 16
        topPadding: bigStore.s * 6
        Item {
            width: parent.width; height: bigStore.s * 48
            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: qsTr("Catálogo"); color: bigStore.host.ink; font.family: bigStore.host.uiFont
                font.pixelSize: bigStore.s * 34; font.weight: Font.Bold
            }
            Action {
                anchors { right: parent.right; verticalCenter: parent.verticalCenter }
                label: bigStore.query ? qsTr("Buscar: %1").arg(bigStore.query.slice(0, 20)) : qsTr("Buscar")
                icon: "search"
                onChoose: bigStore.search()
            }
        }
        StoreFilters { id: filters; width: parent.width }
        Rectangle { width: parent.width; height: 1; color: Theme.color.glassBorder }
    }

    GridView {
        id: grid
        anchors { left: parent.left; right: parent.right; top: topBar.bottom; bottom: parent.bottom; topMargin: bigStore.s * 14 }
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        keyNavigationEnabled: false
        SmoothScroll { id: smoothGrid; view: grid }
        cellWidth: Math.max(1, Math.floor(width / bigStore.columns))
        cellHeight: bigStore.cardHeight + bigStore.cardGap
        model: bigStore.accounts.ready ? bigStore.gridGames : []
        currentIndex: bigStore.gridIndex
        ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }
        onMovementEnded: {
            if (bigStore.hasOmnia && contentY + height >= contentHeight - cellHeight * 2)
                bigStore.loadCatalog(true)
        }
        header: Column {
            id: header
            width: grid.width
            spacing: bigStore.s * 12
            topPadding: bigStore.s * 6
            bottomPadding: visible && (loadingRow.visible || statusText.visible) ? bigStore.s * 12 : 0
            StoreLoading {
                id: loadingRow
                width: parent.width
                visible: bigStore.accounts.loadingContent
                ink: bigStore.host.ink2
                uiScale: bigStore.s * 1.24
            }
            Text {
                id: statusText
                width: parent.width; wrapMode: Text.WordWrap; visible: !!text
                color: bigStore.host.ink2; font.family: bigStore.host.uiFont; font.pixelSize: bigStore.s * 16
                text: bigStore.catalogLoading && !bigStore.gridGames.length ? qsTr("Cargando catálogo…")
                    : bigStore.catalogMessage || (!bigStore.gridGames.length && !bigStore.accounts.loadingContent ? qsTr("No hay juegos para este filtro.") : "")
            }
        }
        delegate: Item {
            id: cell
            required property var modelData
            required property int index
            width: grid.cellWidth; height: grid.cellHeight
            Cover {
                anchors.horizontalCenter: parent.horizontalCenter
                width: bigStore.cardWidth; height: bigStore.cardHeight
                game: cell.modelData
                focused: bigStore.host.mainNavIndex < 0 && bigStore.zone === 3 && bigStore.gridIndex === cell.index
                onChoose: {
                    bigStore.gridIndex = cell.index
                    bigStore.gridSelection = game.id
                    bigStore.zone = 3
                    bigStore.openDetail(game)
                }
            }
        }
    }
    component Cover: Item {
        id: cover
        required property var game
        property bool focused: false
        property bool preferHero: false
        signal choose()
        ManagerPosterCard {
            anchors.fill: parent
            scaleFactor: bigStore.s * 1.15
            selected: cover.focused
            highlightColor: bigStore.host.ring
            title: cover.game.name || ""
            artwork: (cover.preferHero && cover.game.hero) || cover.game.art || ""
            store: cover.game.store === "omnia" ? "Omnia" : bigStore.accounts.names[cover.game.store] || qsTr("Local")
            sourceLogo: bigStore.storeLogo(cover.game.store)
            installed: !!cover.game.local
            platform: cover.game.local ? bigStore.host.platformLabel(cover.game.local) : ""
            onContextRequested: {
                if (cover.game.local) bigStore.host.openMenu(cover.game.local)
                else bigStore.openDetail(cover.game)
            }
            onActivated: cover.choose()
        }

    }

    Rectangle {
        anchors.fill: parent; visible: !!bigStore.detail; z: 4; color: "#D50B111A"
        MouseArea { anchors.fill: parent; onClicked: bigStore.closeDetail() }
        Rectangle {
            id: detailPanel
            anchors.centerIn: parent
            width: Math.min(parent.width - bigStore.s * 42, bigStore.s * 1120)
            height: Math.min(parent.height * 0.78, bigStore.s * 478)
            radius: bigStore.s * 22
            color: "#B8111D2A"
            clip: true
            MouseArea { anchors.fill: parent }
            FadedImage {
                anchors.fill: parent
                source: bigStore.detail?.hero || (bigStore.detail?.game
                    ? bigStore.art(bigStore.detail.game, ["hero", "grid"]) : bigStore.detail?.art || "")
                cornerRadius: detailPanel.radius
                fadeBottom: 0.78
                opacity: 0.55
            }
            Rectangle {
                anchors.fill: parent
                radius: detailPanel.radius
                gradient: Gradient {
                    orientation: Gradient.Horizontal
                    GradientStop { position: 0; color: "#EC0E1925" }
                    GradientStop { position: 0.57; color: "#AD0E1925" }
                    GradientStop { position: 1; color: "#47101D2B" }
                }
                border.color: "#526678"
            }
            Column {
                id: detailHeading
                anchors { top: parent.top; left: parent.left; right: parent.right; margins: bigStore.s * 26 }
                spacing: bigStore.s * 7
                Row {
                    spacing: bigStore.s * 10
                    Image {
                        visible: !!source.toString()
                        width: bigStore.s * 32; height: width
                        fillMode: Image.PreserveAspectFit
                        source: bigStore.storeLogo(bigStore.detail?.store || "")
                    }
                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: bigStore.detail?.local ? qsTr("En tu biblioteca") : qsTr("Sin instalar")
                        color: bigStore.host.ink2; font.family: bigStore.host.uiFont; font.pixelSize: bigStore.s * 16
                    }
                }
                Text {
                    width: parent.width
                    text: bigStore.detail?.name || ""
                    color: bigStore.host.ink; font.family: bigStore.host.uiFont; font.pixelSize: bigStore.s * 34
                    font.weight: Font.Bold; maximumLineCount: 2; elide: Text.ElideRight; wrapMode: Text.Wrap
                }
            }
            Flickable {
                id: detailsList
                anchors { top: detailHeading.bottom; bottom: detailFooter.top; left: parent.left; right: parent.right; margins: bigStore.s * 26; topMargin: bigStore.s * 12; bottomMargin: bigStore.s * 12 }
                contentWidth: width; contentHeight: detailFacts.height
                clip: true; boundsBehavior: Flickable.StopAtBounds
                ScrollBar.vertical: ScrollBar { }
                GameFacts {
                    id: detailFacts
                    width: detailsList.width - bigStore.s * 17
                    api: bigStore.api; uiScale: bigStore.s; uiFont: bigStore.host.uiFont
                    ink: bigStore.host.ink; muted: bigStore.host.ink2
                    game: bigStore.detail?.local || null
                    catalog: bigStore.detail?.game || null
                    offer: bigStore.detail
                    downloadBytes: bigStore.detailActions[bigStore.detailIndex]?.pkg?.sizeBytes ||
                        (bigStore.packages.length === 1 ? (bigStore.packages[0].sizeBytes || 0) : 0)
                }
            }
            Column {
                id: detailFooter
                anchors { left: parent.left; right: parent.right; bottom: parent.bottom; margins: bigStore.s * 26 }
                spacing: bigStore.s * 8
                Text {
                    width: parent.width; wrapMode: Text.Wrap
                    visible: !!text
                    text: bigStore.detailLoading ? qsTr("Consultando paquetes…") : bigStore.detailMessage ||
                          (bigStore.detail?.store === "steam" && !bigStore.detail?.local ? qsTr("La confirmación se hace en Steam.") :
                           bigStore.api.installRoot && !bigStore.detail?.local ? qsTr("Destino: %1").arg(bigStore.api.installRoot) : "")
                    color: bigStore.host.ink2; font.family: bigStore.host.uiFont; font.pixelSize: bigStore.s * 14
                }
                Flow {
                    width: parent.width; spacing: bigStore.s * 10
                    Repeater {
                        model: bigStore.detailActions
                        delegate: Action {
                            required property int index
                            required property var modelData
                            label: modelData.label; selected: index === 0; focused: bigStore.detailIndex === index
                            onChoose: { bigStore.detailIndex = index; bigStore.action(modelData) }
                        }
                    }
                }
            }
        }
    }
    onDetailChanged: detailsList.contentY = 0
}

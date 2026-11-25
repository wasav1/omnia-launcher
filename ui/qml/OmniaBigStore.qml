pragma ComponentBehavior: Bound

import QtQuick

/** Tienda de Big Mode. El foco se conserva por estantería al volver de una ficha. */
Item {
    id: bigStore
    required property var host
    required property var accounts
    readonly property var api: host.api
    readonly property real s: host.s
    readonly property var sources: [
        {id:"all", name:qsTr("Todas")}, {id:"omnia", name:qsTr("Omnia")},
        {id:"steam", name:"Steam"}, {id:"epic", name:"Epic"}, {id:"gog", name:"GOG"}, {id:"amazon", name:"Amazon"}
    ]
    property int filter: 0
    property string query: ""
    property int zone: 0                 // filtros, destacado, catálogo, instalados
    property int availableIndex: 0
    property int installedIndex: 0
    property var catalog: []
    property int catalogPage: 0
    property int totalPages: 1
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
    readonly property bool showFeatured: filter === 0 && !query && !!featured
    readonly property var featured: catalog[0] || null
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
            art: art(game, ["grid", "hero"]), hero: art(game, ["hero", "grid"]), local: matchLocal(game)
        }
    }
    function matches(item) {
        return (activeSource === "all" || item.store === activeSource)
            && (!query || item.name.toLowerCase().includes(query.toLowerCase()))
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
        .filter(matches)

    function loadCatalog(next) {
        if (next && (catalogLoading || catalogPage >= totalPages)) return
        const page = next ? catalogPage + 1 : 1
        const request = ++catalogRequest
        catalogLoading = true
        catalogMessage = ""
        api.catalogGames({page: page, pageSize: 30, q: query, sort: "updatedAt", order: "desc"}, function(status, body) {
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
        accounts.refreshStores()
    }
    function setFilter(index) {
        filter = (index + sources.length) % sources.length
        availableIndex = 0
        installedIndex = 0
        zone = 0
    }
    function search() {
        let pending = query
        host.openKeyboardFor(query, value => pending = value, function(accepted) {
            if (!accepted) return
            const value = pending.trim()
            if (value === bigStore.query) return
            bigStore.query = value
            bigStore.catalog = []
            bigStore.catalogPage = 0
            bigStore.availableIndex = 0
            bigStore.installedIndex = 0
            bigStore.zone = 0
            bigStore.loadCatalog(false)
        })
    }
    onAvailableChanged: availableIndex = Math.min(availableIndex, Math.max(0, available.length - 1))
    onInstalledChanged: installedIndex = Math.min(installedIndex, Math.max(0, installed.length - 1))

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
                if (status === 200) { bigStore.closeDetail(); host.openDownloads() }
                else bigStore.detailMessage = body.error || qsTr("No se pudo iniciar la instalación.")
            })
        }
    }
    function pad(key) {
        if (detail) {
            if (key === "B") closeDetail()
            else if (key === "u" || key === "d") detailIndex = Math.max(0, Math.min(detailActions.length - 1, detailIndex + (key === "u" ? -1 : 1)))
            else if (key === "A") action(detailActions[detailIndex])
            return
        }
        if (key === "LB" || key === "RB") { setFilter(filter + (key === "LB" ? -1 : 1)); return }
        if (key === "X") { search(); return }
        if (key === "Y" || key === "START") { host.openDownloads(); return }
        if (key === "B") { host.openLibrary(); return }
        if (key === "u" || key === "d") {
            const zones = [0]
            if (showFeatured) zones.push(1)
            if (available.length) zones.push(2)
            if (installed.length) zones.push(3)
            if (zone === 0 && key === "u") { host.focusMainNav(); return }
            const next = zones.indexOf(zone) + (key === "u" ? -1 : 1)
            zone = zones[Math.max(0, Math.min(zones.length - 1, next))]
            return
        }
        if (key === "A") {
            if (zone === 0 && catalogMessage && !catalog.length) loadCatalog(false)
            else if (zone === 0) pad("d")
            else if (zone === 1 && featured) openDetail(catalogEntry(featured))
            else if (zone === 2) openDetail(available[availableIndex])
            else if (zone === 3) openDetail(installed[installedIndex])
            return
        }
        if (key !== "l" && key !== "r") return
        const step = key === "r" ? 1 : -1
        if (zone === 0) setFilter(filter + step)
        else if (zone === 2) {
            availableIndex = Math.max(0, Math.min(available.length - 1, availableIndex + step))
            if (step > 0 && availableIndex >= available.length - 3 && (activeSource === "all" || activeSource === "omnia"))
                loadCatalog(true)
        } else if (zone === 3) installedIndex = Math.max(0, Math.min(installed.length - 1, installedIndex + step))
    }
    function key(event) {
        const mapping = {
            [Qt.Key_Up]:"u", [Qt.Key_Down]:"d", [Qt.Key_Left]:"l", [Qt.Key_Right]:"r",
            [Qt.Key_Return]:"A", [Qt.Key_Enter]:"A", [Qt.Key_Escape]:"B", [Qt.Key_Slash]:"X",
            [Qt.Key_Tab]:"RB", [Qt.Key_Backtab]:"LB", [Qt.Key_Y]:"Y"
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
        signal choose()
        width: text.implicitWidth + bigStore.s * 30
        height: bigStore.s * 38; radius: height / 2
        color: selected ? bigStore.host.accent : "#223141"
        border { width: focused ? 3 : 1; color: focused ? bigStore.host.ring : "#46586A" }
        Text { id: text; anchors.centerIn: parent; text: button.label; color: bigStore.host.ink; font.family: bigStore.host.uiFont; font.pixelSize: bigStore.s * 18 }
        MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: button.choose() }
    }
    component Shelf: Column {
        id: shelf
        required property string label
        required property var games
        required property int selected
        required property bool focused
        signal picked(int at)
        signal reachEnd()
        property real tileHeight: bigStore.s * 152
        spacing: bigStore.s * 7
        visible: games.length > 0
        Text { text: shelf.label; color: bigStore.host.ink; font.family: bigStore.host.uiFont; font.pixelSize: bigStore.s * 23; font.weight: Font.DemiBold }
        ListView {
            id: strip
            width: parent.width; height: shelf.tileHeight + bigStore.s * 12
            orientation: ListView.Horizontal; spacing: bigStore.s * 12
            model: shelf.games
            currentIndex: shelf.selected
            boundsBehavior: Flickable.StopAtBounds
            clip: true
            onCurrentIndexChanged: if (currentIndex >= 0) positionViewAtIndex(currentIndex, ListView.Contain)
            onMovementEnded: if (atXEnd) shelf.reachEnd()
            delegate: Item {
                id: tile
                required property int index
                required property var modelData
                width: bigStore.s * 192; height: strip.height
                ManagerPosterCard {
                    anchors.fill: parent
                    anchors.margins: bigStore.s * 5
                    scaleFactor: bigStore.s * 1.1
                    title: tile.modelData.name || ""
                    artwork: tile.modelData.art || ""
                    store: tile.modelData.store === "omnia" ? "Omnia" : bigStore.accounts.names[tile.modelData.store] || qsTr("Local")
                    sourceLogo: tile.modelData.store === "local" ? "" : "images/stores/" + tile.modelData.store + ".svg"
                    installed: !!tile.modelData.local
                    onActivated: shelf.picked(tile.index)
                }
                Rectangle {
                    anchors.fill: parent; radius: bigStore.s * 14; color: "transparent"
                    border.width: 3; border.color: bigStore.host.ring
                    visible: shelf.focused && tile.index === shelf.selected
                }
            }
        }
    }
    Flickable {
        id: contentView
        anchors.fill: parent
        contentWidth: width
        contentHeight: body.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        Column {
            id: body
            width: contentView.width
            spacing: bigStore.s * 16
            Row {
                spacing: bigStore.s * 10
                Repeater {
                    model: bigStore.sources
                    delegate: Action {
                        required property int index
                        required property var modelData
                        label: modelData.name
                        selected: bigStore.filter === index
                        focused: bigStore.zone === 0 && selected && bigStore.host.mainNavIndex < 0
                        onChoose: bigStore.setFilter(index)
                    }
                }
                Action { label: bigStore.query ? qsTr("Buscar: %1").arg(bigStore.query.slice(0, 18)) : qsTr("Buscar"); onChoose: bigStore.search() }
            }
            Rectangle {
                visible: bigStore.showFeatured
                width: parent.width; height: bigStore.s * 205; radius: bigStore.s * 18
                color: "#202D3C"
                FadedImage { anchors.fill: parent; source: bigStore.featured ? bigStore.art(bigStore.featured, ["hero","grid"]) : ""; cornerRadius: parent.radius; fadeLeft: 0.8; opacity: 0.65 }
                Column {
                    anchors { left: parent.left; verticalCenter: parent.verticalCenter; leftMargin: bigStore.s * 25 }
                    width: parent.width * 0.68; spacing: bigStore.s * 12
                    Text { text: qsTr("Destacado de Omnia"); color: bigStore.host.ink2; font.family: bigStore.host.uiFont; font.pixelSize: bigStore.s * 17 }
                    Text { width: parent.width; text: bigStore.featured?.name || ""; color: bigStore.host.ink; font.family: bigStore.host.uiFont; font.pixelSize: bigStore.s * 32; font.weight: Font.DemiBold; elide: Text.ElideRight }
                    Action { label: qsTr("Ver ficha"); selected: true; focused: bigStore.zone === 1 && bigStore.host.mainNavIndex < 0; onChoose: { bigStore.zone = 1; bigStore.pad("A") } }
                }
            }
            Shelf {
                id: availableShelf
                width: parent.width; label: qsTr("Para descubrir")
                games: bigStore.available; selected: bigStore.availableIndex
                focused: bigStore.zone === 2 && bigStore.host.mainNavIndex < 0
                onPicked: function(at) { bigStore.zone = 2; bigStore.availableIndex = at; bigStore.pad("A") }
                onReachEnd: if (bigStore.activeSource === "all" || bigStore.activeSource === "omnia") bigStore.loadCatalog(true)
            }
            Shelf {
                id: installedShelf
                width: parent.width; label: qsTr("En tu biblioteca")
                games: bigStore.installed; selected: bigStore.installedIndex
                focused: bigStore.zone === 3 && bigStore.host.mainNavIndex < 0
                onPicked: function(at) { bigStore.zone = 3; bigStore.installedIndex = at; bigStore.pad("A") }
            }
            Text {
                width: parent.width; wrapMode: Text.WordWrap
                visible: !!text; color: bigStore.host.ink2; font.family: bigStore.host.uiFont; font.pixelSize: bigStore.s * 16
                text: bigStore.catalogLoading && !bigStore.available.length ? qsTr("Cargando catálogo…")
                    : bigStore.catalogMessage || (!bigStore.available.length && !bigStore.installed.length
                        ? qsTr("No hay juegos para este filtro. Las cuentas se gestionan en Ajustes.") : "")
            }
        }
    }
    onZoneChanged: {
        const shelf = zone === 2 ? availableShelf : zone === 3 ? installedShelf : null
        if (!shelf) contentView.contentY = 0
        else if (shelf.y + shelf.height > contentView.contentY + contentView.height)
            contentView.contentY = Math.min(contentView.contentHeight - contentView.height, shelf.y + shelf.height - contentView.height)
        else if (shelf.y < contentView.contentY) contentView.contentY = shelf.y
    }
    Rectangle {
        anchors.fill: parent; visible: !!bigStore.detail; z: 4; color: "#D50B111A"
        MouseArea { anchors.fill: parent; onClicked: bigStore.closeDetail() }
        Rectangle {
            anchors.centerIn: parent; width: Math.min(parent.width - bigStore.s * 28, bigStore.s * 720)
            height: Math.min(parent.height, detailsList.contentHeight + bigStore.s * 36)
            radius: bigStore.s * 18; color: "#193049"; clip: true
            MouseArea { anchors.fill: parent }
            Flickable {
                id: detailsList
                anchors { fill: parent; margins: bigStore.s * 18 }
                contentWidth: width; contentHeight: detailBody.implicitHeight; clip: true
                Column {
                    id: detailBody
                    width: detailsList.width; spacing: bigStore.s * 10
                    Text { width: parent.width; text: bigStore.detail?.name || ""; wrapMode: Text.WordWrap; color: bigStore.host.ink; font.family: bigStore.host.uiFont; font.pixelSize: bigStore.s * 30; font.weight: Font.Bold }
                    Text {
                        width: parent.width; wrapMode: Text.WordWrap; maximumLineCount: 4; elide: Text.ElideRight
                        textFormat: Text.PlainText; visible: !!text
                        text: bigStore.detail?.game?.description || bigStore.detail?.local?.description || ""
                        color: bigStore.host.ink2; font.family: bigStore.host.uiFont; font.pixelSize: bigStore.s * 18
                    }
                    Text {
                        width: parent.width; wrapMode: Text.WordWrap; visible: !!text
                        text: bigStore.detailLoading ? qsTr("Consultando paquetes…") : bigStore.detailMessage ||
                              (bigStore.detail?.store === "steam" && !bigStore.detail.local ? qsTr("La confirmación se hace en Steam.") :
                               bigStore.api.installRoot && !bigStore.detail?.local ? qsTr("Destino: %1").arg(bigStore.api.installRoot) : "")
                        color: bigStore.host.ink2; font.family: bigStore.host.uiFont; font.pixelSize: bigStore.s * 16
                    }
                    Repeater {
                        id: actions
                        model: bigStore.detailActions
                        delegate: Action {
                            required property int index
                            required property var modelData
                            label: modelData.label; focused: bigStore.detailIndex === index
                            onChoose: { bigStore.detailIndex = index; bigStore.action(modelData) }
                        }
                    }
                }
            }
        }
    }
    onDetailChanged: detailsList.contentY = 0
    onDetailIndexChanged: {
        const item = actions.itemAt(detailIndex)
        if (item && item.y + item.height > detailsList.contentY + detailsList.height)
            detailsList.contentY = item.y + item.height - detailsList.height
        else if (item && item.y < detailsList.contentY) detailsList.contentY = item.y
    }
}

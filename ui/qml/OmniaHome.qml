pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Dialogs
import "Theme.js" as Theme

/** Inicio de Big Mode, con la misma estructura que el Inicio de Desktop: arriba el destacado (las mismas novedades:
 *  juegos gratis, la novedad de Omnia y las ofertas grandes) junto a «Seguir jugando» y los accesos a Biblioteca y
 *  Catálogo; debajo, «Novedades de tus tiendas» en cuadrícula (columnas según el ancho, desplazamiento vertical).
 *  Mando: flechas entre zonas y tarjetas, A abre, LB/RB cambian de tienda, LT/RT cambian el destacado. */
Item {
    id: home
    property var api
    property var localGames: []
    property string searchText: ""
    property real uiScale: 1
    property real footerSpace: 0
    property color ink: "#F0F3F7"
    property color ink2: "#B8C3D0"
    property color surface: "#151D27"
    property color accent: "#336599"
    property var catalog: []
    property var catalogMeta: ({})
    // El destacado es lo último que jugaste; el catálogo solo lo ocupa si la biblioteca no tiene actividad.
    readonly property bool useCatalogFeatured: catalog.length > 0 && !localFeaturedGame()
    readonly property int catalogOffset: useCatalogFeatured ? 1 : 0
    property bool catalogLoading: false
    property bool offline: false
    property bool cacheExpired: false
    property string warning: ""
    property var detail: null
    property bool detailLoading: false
    property var packages: []
    property var selectedPackage: null
    property string installMessage: ""
    property bool installBusy: false
    property bool acceptLicense: false
    signal openLocalGame(string id)
    signal installRequested(var game)
    signal playLocalGame(string id)
    signal openSection(string section)            // library | favorites | system | settings
    signal headerRequested()                      // ↑ desde la primera fila: foco a la barra superior

    // ---------- novedades de tus tiendas (fase 5c) ----------
    property var deals: []
    property string storeFilter: "all"
    readonly property var storeKeys: ["all", "steam", "epic", "gog", "omnia"]
    function storeName(key) { return ({ all: qsTr("Todas"), steam: "Steam", epic: "Epic", gog: "GOG", omnia: "Omnia" })[key] || key }
    function loadDeals() {
        if (!api || !api.call) return
        api.call("GET", "/stores/deals?lang=" + (api.language === "en" ? "en" : "es"), function(status, body) {
            if (status === 200 && body && Array.isArray(body.items)) {
                home.deals = body.items
                if (body.loading) dealsRetry.restart()
            } else dealsRetry.restart()
        })
    }
    Timer { id: dealsRetry; interval: 5000; onTriggered: home.loadDeals() }
    function stepStore(d) {
        const i = storeKeys.indexOf(storeFilter)
        storeFilter = storeKeys[(i + d + storeKeys.length) % storeKeys.length]
        sectionIndex = 0; itemIndex = 0
        if (zone === "deals" && !dealSections.length) zone = "hero"
    }
    readonly property var omniaReleases: (catalog || []).slice(useCatalogFeatured ? 1 : 0, 10).map(g => ({
        source: "omnia", kind: "release", title: g.name || "", game: g, artwork: artwork(g, ["hero", "grid"]), price: "", discount: 0 }))
    readonly property var dealSections: {
        const pick = list => list.filter(i => storeFilter === "all" || i.source === storeFilter)
        return [
            { key: "free", title: qsTr("Gratis por tiempo limitado"), items: pick(deals.filter(i => i.kind === "free" || i.kind === "upcoming")) },
            { key: "deal", title: qsTr("Ofertas"), items: pick(deals.filter(i => i.kind === "deal")) },
            { key: "release", title: qsTr("Lanzamientos y novedades"), items: pick(omniaReleases.concat(deals.filter(i => i.kind === "release"))) }
        ].filter(s => s.items.length > 0)
    }
    property int sectionIndex: 0
    property int itemIndex: 0
    readonly property var focusedDeal: zone === "deals" && dealSections[sectionIndex] ? dealSections[sectionIndex].items[itemIndex] || null : null
    function kindBadge(item) {
        if (item.kind === "deal") return item.discount > 0 ? "−" + item.discount + " %" : qsTr("Oferta")
        if (item.kind === "free") return qsTr("Gratis")
        if (item.kind === "upcoming") return qsTr("Próximamente gratis")
        return item.source === "omnia" ? qsTr("Nuevo port") : qsTr("Nuevo")
    }
    function kindColor(item) {
        return item.kind === "deal" ? Theme.color.ok : (item.kind === "free" || item.kind === "upcoming") ? Theme.color.favorite : Theme.color.accentLight
    }
    function dealDate(ts) {
        return ts > 0 ? new Date(ts * 1000).toLocaleDateString(Qt.locale(api && api.language === "en" ? "en_US" : "es_CO"), "d MMM") : ""
    }
    function dealSubtitle(item) {
        if (item.kind === "free") return item.endsAt ? qsTr("Gratis hasta el %1").arg(dealDate(item.endsAt)) : qsTr("Gratis por tiempo limitado")
        if (item.kind === "upcoming") return item.startsAt ? qsTr("Gratis desde el %1").arg(dealDate(item.startsAt)) : qsTr("Próximamente")
        if (item.kind === "deal") return item.endsAt ? qsTr("Termina el %1").arg(dealDate(item.endsAt)) : ""
        return item.source === "omnia" ? qsTr("Port nativo para Linux") : storeName(item.source)
    }
    function openDeal(item) {
        if (!item) return
        if (item.game) openCatalogDetails(item.game)
        else if (item.url) Qt.openUrlExternally(item.url)
    }

    function refresh() {
        if (!api || !api.catalogGames) {
            catalogLoading = false
            offline = true
            warning = qsTr("No se pudo conectar con el catálogo de Omnia.")
            return
        }
        catalogLoading = true
        api.catalogGames({page: 1, pageSize: 12, sort: "updatedAt", order: "desc", q: searchText}, function(status, body) {
            home.catalogLoading = false
            if (status === 200 && body) {
                home.catalog = body.items || []
                home.catalogMeta = body.meta || {}
                home.offline = body.offline === true
                home.cacheExpired = body.cache_expired === true
                home.warning = body.warning ? (api.language === "en" ? api.localizeNotice(body.warning) : body.warning) : ""
            } else {
                home.offline = true
                home.cacheExpired = false
                home.warning = (body && body.error) || qsTr("No se pudo cargar el catálogo.")
            }
        })
    }
    function artwork(game, types) {
        const list = game && game.artwork ? Array.from(game.artwork) : []   // en delegados los arreglos anidados llegan como listas QML
        for (let type of types) {
            const item = list.find(a => a && a.type === type && a.imageUrl)
            if (item) {
                if (item.localUrl) return String(item.localUrl)     // copia en caché local: carga inmediata
                const url = String(item.imageUrl)
                return url.startsWith("/") ? ((api.catalogBaseUrl || "") + url) : url
            }
        }
        return ""
    }
    function platforms(game) {
        const list = game && game.platforms ? Array.from(game.platforms) : []
        return list.map(p => p.name || p.slug).join(" · ")
    }
    // Una ficha solo describe a un juego local de su misma plataforma (Ocarina N64 ≠ remake de Switch 2).
    readonly property var localToCatalog: ({n64: ["n64"], nes: ["nes"], snes: ["snes"], gba: ["gba"], nds: ["nds"], ps1: ["ps1"], ps2: ["ps2"],
        gcwii: ["gamecube", "wii"], gamecube: ["gamecube"], wii: ["wii"], dreamcast: ["dreamcast"], xbox: ["xbox"],
        sw1: ["switch"], switch: ["switch"], sw2: ["switch2"], switch2: ["switch2"], pc: ["pc"]})
    function platformCompatible(local, game) {
        const allowed = localToCatalog[String(local && local.platform || "").toLowerCase()]
        const known = game && game.platforms ? Array.from(game.platforms).map(p => String(p.slug || "").toLowerCase()) : []
        return !allowed || known.length === 0 || allowed.some(p => known.indexOf(p) >= 0)
    }
    function localMatch(game) {
        if (!game) return null
        const slug = String(game.slug || "").toLowerCase().replace(/[^a-z0-9]+/g, "-").replace(/^-|-$/g, "")
        for (let local of localGames) {
            if (!platformCompatible(local, game)) continue
            if (String(local.catalogSlug || "").toLowerCase() === String(game.slug || "").toLowerCase()) return local
            if (String(local.id || "").toLowerCase() === slug || String(local.id || "").toLowerCase().endsWith("-" + slug)) return local
        }
        return null
    }
    function recentGames() {
        const list = (localGames || []).filter(g => !g.hidden && g.ports && g.ports.length > 0).slice()
        list.sort((a, b) => Number(b.lastPlayed || (b.played || {}).last || 0) - Number(a.lastPlayed || (a.played || {}).last || 0))
        return list.slice(0, 3)
    }
    function localFeaturedGame() {
        const recent = recentGames()
        return recent.length ? recent[0] : null
    }
    function openCatalogDetails(game) {
        if (!game) return
        detail = game
        detailLoading = true
        packages = []
        selectedPackage = null
        installMessage = ""
        acceptLicense = false
        api.catalogInstallPackages(game.slug || "", function(packageStatus, packageBody) {
            if (home.detail && home.detail.slug === game.slug) {
                if (packageStatus === 200) {
                    home.packages = packageBody.items || []
                    if (home.packages.length) home.selectedPackage = home.packages[0]
                    else home.installMessage = packageBody.unsupported ? qsTr("El backend todavía no tiene habilitadas las instalaciones.") : packageBody.offline ? qsTr("Sin conexión; los paquetes guardados no se pueden instalar.") : qsTr("No hay un paquete instalable publicado para este juego.")
                } else home.installMessage = (packageBody && packageBody.error) || qsTr("No se pudieron consultar las opciones de instalación.")
            }
        })
        api.catalogGame(game.slug, function(status, body) {
            if (home.detail && home.detail.slug === game.slug) {
                if (status === 200 && body && body.data && Object.keys(body.data).length) home.detail = body.data
                detailLoading = false
            }
        })
    }
    function beginInstall() {
        if (!detail || !selectedPackage || !api.installRoot || !acceptLicense || installBusy) return
        installBusy = true
        installMessage = qsTr("Añadiendo a la cola de instalación…")
        api.startInstallation(detail.slug, selectedPackage.id, api.installRoot, function(status, body) {
            home.installBusy = false
            if (status === 200) {
                home.installMessage = qsTr("Instalación añadida. El progreso está en Instalaciones del gestor.")
                if (home.api && home.api.notify) home.api.notify(qsTr("Descarga añadida a Instalaciones del gestor."))
                home.closeCatalogDetails()
            } else home.installMessage = (body && body.error) || qsTr("No se pudo iniciar la instalación.")
        })
    }
    function closeCatalogDetails() { detail = null; detailLoading = false }
    // ---------- destacado, seguir jugando y accesos (como el Inicio de Desktop) ----------
    // Zonas de foco: "hero" (destacado), "play" / "details" (Seguir jugando), "library" / "catalog" (accesos) y "deals" (cuadrícula).
    property string zone: "hero"
    property var news: []
    function loadNews() {
        if (!api || !api.call) return
        api.call("GET", "/stores/news?lang=" + (api.language === "en" ? "en" : "es"), function(status, body) {
            if (status === 200 && body && Array.isArray(body.items)) home.news = body.items
        })
    }
    // Mismo destacado que Desktop: juegos gratis, la novedad de Omnia, las ofertas grandes y un port nuevo.
    readonly property var featured: {
        const out = []
        const free = deals.filter(i => i.kind === "free")
        const big = deals.filter(i => i.kind === "deal" && i.artwork).sort((a, b) => (b.discount || 0) - (a.discount || 0))
        const omnia = news.filter(n => n.source === "omnia" && n.artwork).map(n => Object.assign({ kind: "news" }, n))
        for (const list of [free.slice(0, 2), omnia.slice(0, 1), big.slice(0, 3), omniaReleases.filter(i => i.artwork).slice(0, 1)])
            for (const i of list) out.push(i)
        return out.slice(0, 6)
    }
    property int featuredIndex: 0
    readonly property var currentFeatured: featured.length ? featured[featuredIndex % featured.length] : null
    function stepFeatured(d) { if (featured.length) featuredIndex = (featuredIndex + d + featured.length) % featured.length }
    Timer { interval: 9000; repeat: true; running: home.visible && home.featured.length > 1 && home.zone !== "hero"; onTriggered: home.stepFeatured(1) }
    function featuredAction(item) {
        if (!item) return ""
        if (item.game || item.slug) return qsTr("Ver ficha")
        if (item.kind === "free") return qsTr("Obtener")
        if (item.kind === "deal") return qsTr("Ver oferta")
        return qsTr("Leer noticia")
    }
    function openFeatured(item) {
        if (!item) return
        if (item.game) { openCatalogDetails(item.game); return }
        if (item.slug) {
            api.catalogGame(item.slug, function(status, body) {
                if (status === 200 && body && body.data) home.openCatalogDetails(body.data)
                else if (item.url) Qt.openUrlExternally(item.url)
            })
            return
        }
        if (item.url) Qt.openUrlExternally(item.url)
    }

    readonly property var heroLocal: localFeaturedGame()
    readonly property int gameCount: (localGames || []).filter(g => !g.hidden).length
    readonly property string acceptLabel: zone === "hero" ? featuredAction(currentFeatured)
        : zone === "play" ? (heroLocal && heroLocal.portAvailable ? qsTr("Instalar port") : qsTr("Jugar"))
        : zone === "details" ? qsTr("Detalles")
        : zone === "deals" ? (focusedDeal && focusedDeal.game ? qsTr("Ver ficha") : focusedDeal && focusedDeal.kind === "free" ? qsTr("Obtener") : qsTr("Ver oferta"))
        : qsTr("Abrir")
    function clamp(v, lo, hi) { return Math.max(lo, Math.min(hi, v)) }

    // ---------- cuadrícula de novedades: columnas fijas por ancho, tarjetas que crecen, máx. 5 por fila ----------
    readonly property int dealColumns: Math.max(2, Math.min(5, Math.floor((stack.width + u * 20) / (u * 330 + u * 20))))
    readonly property real dealCardWidth: (stack.width - (dealColumns - 1) * u * 20) / dealColumns
    readonly property real dealCardHeight: Math.round(dealCardWidth * 0.46) + u * 128
    function enterDeals(col) {
        if (!dealSections.length) return false
        zone = "deals"; sectionIndex = 0
        itemIndex = clamp(col === undefined ? 0 : col, 0, dealSections[0].items.length - 1)
        return true
    }

    function nav(dir) {
        if (dir === "tabprev" || dir === "tabnext") { stepStore(dir === "tabprev" ? -1 : 1); return }
        if (dir === "featprev" || dir === "featnext") { stepFeatured(dir === "featprev" ? -1 : 1); return }
        const z = zone
        if (z === "hero") {
            if (dir === "up") headerRequested()
            else if (dir === "right") zone = heroLocal ? "play" : "library"
            else if (dir === "left") stepFeatured(-1)
            else if (dir === "down") enterDeals(0)
        } else if (z === "play" || z === "details") {
            if (dir === "up") headerRequested()
            else if (dir === "left") zone = z === "details" ? "play" : "hero"
            else if (dir === "right" && z === "play") zone = "details"
            else if (dir === "down") zone = z === "play" ? "library" : "catalog"
        } else if (z === "library" || z === "catalog") {
            if (dir === "up") zone = heroLocal ? (z === "library" ? "play" : "details") : "hero"
            else if (dir === "left") zone = z === "catalog" ? "library" : "hero"
            else if (dir === "right" && z === "library") zone = "catalog"
            else if (dir === "down") enterDeals(dealColumns - 1)
        } else if (z === "deals") {
            const sec = dealSections[sectionIndex]
            if (!sec) { zone = "hero"; return }
            const cols = dealColumns
            const col = itemIndex % cols
            if (dir === "left") itemIndex = Math.max(0, itemIndex - 1)
            else if (dir === "right") itemIndex = Math.min(sec.items.length - 1, itemIndex + 1)
            else if (dir === "down") {
                if (itemIndex + cols < sec.items.length) itemIndex += cols
                else if (Math.floor(itemIndex / cols) < Math.floor((sec.items.length - 1) / cols)) itemIndex = sec.items.length - 1
                else if (sectionIndex < dealSections.length - 1) { sectionIndex++; itemIndex = Math.min(col, dealSections[sectionIndex].items.length - 1) }
            } else if (dir === "up") {
                if (itemIndex - cols >= 0) itemIndex -= cols
                else if (sectionIndex > 0) {
                    sectionIndex--
                    const prev = dealSections[sectionIndex].items.length
                    const lastRow = Math.floor((prev - 1) / cols) * cols
                    itemIndex = Math.min(prev - 1, lastRow + col)
                } else zone = "hero"
            }
        }
    }
    function accept() {
        if (zone === "hero") openFeatured(currentFeatured)
        else if (zone === "play") { if (heroLocal) playLocalGame(heroLocal.id); else openSection("library") }
        else if (zone === "details") { if (heroLocal) openLocalGame(heroLocal.id) }
        else if (zone === "library") openSection("library")
        else if (zone === "catalog") openSection("store")
        else if (zone === "deals") openDeal(focusedDeal)
    }
    onZoneChanged: Qt.callLater(home.revealFocus)
    onSectionIndexChanged: Qt.callLater(home.revealFocus)
    onItemIndexChanged: Qt.callLater(home.revealFocus)
    function revealFocus() {
        if (zone !== "deals") { page.scrollTo(0); return }
        const sec = dealRows.itemAt(sectionIndex)
        if (!sec) return
        const card = sec["cardAt"](itemIndex)                 // qmllint disable missing-property
        if (card) page.reveal(card, itemIndex < dealColumns ? Number(sec["titleHeight"]) : 0)   // qmllint disable missing-property
    }
    Keys.onPressed: function(event) {
        if (detail) {
            if (event.key === Qt.Key_Escape || event.key === Qt.Key_Back) { closeCatalogDetails(); event.accepted = true }
            else event.accepted = false
            return
        }
        if (event.key === Qt.Key_Left) nav("left")
        else if (event.key === Qt.Key_Right) nav("right")
        else if (event.key === Qt.Key_Up) nav("up")
        else if (event.key === Qt.Key_Down) nav("down")
        else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) accept()
        else if (event.key === Qt.Key_Tab) nav(event.modifiers & Qt.ShiftModifier ? "tabprev" : "tabnext")
        else if (event.key === Qt.Key_Backtab) nav("tabprev")
        else { event.accepted = false; return }
        event.accepted = true
    }

    Timer { interval: 15 * 60 * 1000; repeat: true; running: home.visible; onTriggered: home.refresh() }
    Timer { id: initialRefresh; interval: 360; repeat: false; onTriggered: home.refresh() }
    onVisibleChanged: if (visible) { initialRefresh.start(); loadDeals(); loadNews() }
    // Si Inicio nace visible no hay cambio de visibilidad: sin esto el catálogo no se pedía nunca.
    Component.onCompleted: { initialRefresh.start(); loadDeals(); loadNews() }
    Timer { interval: 10 * 60 * 1000; repeat: true; running: home.visible; onTriggered: { home.loadDeals(); home.loadNews() } }
    onSearchTextChanged: searchDelay.restart()
    Timer { id: searchDelay; interval: 420; repeat: false; onTriggered: home.refresh() }

    // ---------- datos de presentación ----------
    readonly property real u: uiScale
    // color del fondo animado: el de la tienda del destacado; azul de Omnia por defecto
    readonly property color effectTint: currentFeatured ? (Theme.color.store[currentFeatured.source] || "#336599") : "#336599"
    function lastPlayedText(game) {
        const ts = Number(game && (game.lastPlayed || (game.played || {}).last) || 0)
        if (!ts) return qsTr("En tu biblioteca")
        const days = Math.floor((Date.now() / 1000 - ts) / 86400)
        let text = days <= 0 ? qsTr("Jugado hoy") : days === 1 ? qsTr("Jugado ayer")
            : new Date(ts * 1000).toLocaleDateString(Qt.locale(api && api.language === "en" ? "en_US" : "es_CO"), "d MMM")
        const secs = Number(game && (game.played || {}).secs || 0)
        if (secs >= 60) text += " · " + (secs >= 3600 ? Math.floor(secs / 3600) + " h " + Math.round((secs % 3600) / 60) + " min" : Math.round(secs / 60) + " min")
        return text
    }

    // Botón de Big Mode (foco con mando: borde blanco y un poco más grande)
    component PadButton: Rectangle {
        id: pb
        property string text: ""
        property string icon: ""
        property bool primary: false
        property bool focused: false
        signal clicked()
        width: pbRow.implicitWidth + home.u * 44; height: home.u * 52; radius: home.u * 14
        scale: focused ? 1.05 : 1
        color: primary ? (pbMa.containsMouse ? Theme.color.accentLight : Theme.color.accent) : (pbMa.containsMouse ? "#2EFFFFFF" : "#1AFFFFFF")
        border.width: focused ? home.u * 3 : 1
        border.color: focused ? "#FFFFFF" : (primary ? "transparent" : "#40FFFFFF")
        Behavior on scale { NumberAnimation { duration: 120 } }
        Row {
            id: pbRow
            anchors.centerIn: parent; spacing: home.u * 10
            LucideIcon { visible: !!pb.icon; anchors.verticalCenter: parent.verticalCenter; width: home.u * 22; height: width; name: pb.icon; color: pb.primary ? Theme.color.accentInk : home.ink }
            Text { anchors.verticalCenter: parent.verticalCenter; text: pb.text; color: pb.primary ? Theme.color.accentInk : home.ink; font.family: "Hanken Grotesk"; font.pixelSize: home.u * 20; font.weight: Font.Bold }
        }
        MouseArea { id: pbMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: pb.clicked() }
    }

    Flickable {
        id: page
        anchors { fill: parent; topMargin: home.u * 100; bottomMargin: home.u * 96 + home.footerSpace }
        contentWidth: width
        contentHeight: stack.height + home.u * 40
        boundsBehavior: Flickable.StopAtBounds
        clip: true
        Behavior on contentY { enabled: !page.dragging && !page.flicking; NumberAnimation { duration: 260; easing.type: Easing.OutCubic } }
        function scrollTo(y) { contentY = Math.max(0, Math.min(Math.max(0, contentHeight - height), y)) }
        function reveal(item, extraTop) {
            if (!item) return
            const top = item.mapToItem(page.contentItem, 0, 0).y - home.u * 24 - (extraTop || 0)
            const bottom = item.mapToItem(page.contentItem, 0, 0).y + item.height + home.u * 30
            if (top < contentY) scrollTo(top)
            else if (bottom > contentY + height) scrollTo(bottom - height)
        }

        Column {
            id: stack
            x: home.u * 96
            width: page.width - home.u * 192
            spacing: home.u * 30

            // ---- fila superior: destacado + (seguir jugando, accesos)
            Item {
                id: topRow
                width: parent.width
                height: home.u * 420
                Rectangle {
                    id: hero
                    readonly property bool focused: home.zone === "hero"
                    width: parent.width - side.width - home.u * 26; height: parent.height
                    radius: home.u * 28; color: "#111A26"; clip: true
                    border.width: focused ? home.u * 4 : 1
                    border.color: focused ? "#FFFFFF" : "#33FFFFFF"
                    FadedImage { anchors.fill: parent; anchors.margins: hero.border.width; source: home.currentFeatured ? (home.currentFeatured.artwork || "") : ""; cornerRadius: home.u * 25; alignX: 0.7 }
                    Rectangle {
                        anchors.fill: parent; radius: hero.radius
                        gradient: Gradient {
                            orientation: Gradient.Horizontal
                            GradientStop { position: 0.0; color: "#EB060A10" }
                            GradientStop { position: 0.7; color: "#30060A10" }
                        }
                    }
                    Column {
                        visible: !!home.currentFeatured
                        anchors { left: parent.left; bottom: parent.bottom; margins: home.u * 40 }
                        width: Math.min(hero.width * 0.6, home.u * 760)
                        spacing: home.u * 14
                        Row {
                            spacing: home.u * 10
                            Rectangle {
                                height: home.u * 36; width: heroStore.implicitWidth + home.u * 30; radius: height / 2; color: "#2EFFFFFF"; border.color: "#40FFFFFF"
                                Row { id: heroStore; anchors.centerIn: parent; spacing: home.u * 8
                                    Rectangle { anchors.verticalCenter: parent.verticalCenter; width: home.u * 10; height: width; radius: home.u * 3; color: home.currentFeatured ? (Theme.color.store[home.currentFeatured.source] || Theme.color.accent) : "transparent" }
                                    Text { text: home.currentFeatured ? home.storeName(home.currentFeatured.source) : ""; color: home.ink; font.family: "Hanken Grotesk"; font.pixelSize: home.u * 17; font.weight: Font.Bold } }
                            }
                            Rectangle {
                                visible: !!home.currentFeatured && home.currentFeatured.kind !== "news"
                                height: home.u * 36; width: heroKind.implicitWidth + home.u * 28; radius: height / 2
                                color: home.currentFeatured ? home.kindColor(home.currentFeatured) : "transparent"
                                Text { id: heroKind; anchors.centerIn: parent; text: home.currentFeatured ? home.kindBadge(home.currentFeatured) : ""; color: Theme.color.accentInk; font.family: "Hanken Grotesk"; font.pixelSize: home.u * 17; font.weight: Font.ExtraBold }
                            }
                        }
                        Text { width: parent.width; text: home.currentFeatured ? home.currentFeatured.title : ""; color: "#FFFFFF"; font.family: "Hanken Grotesk"; font.pixelSize: home.u * 50; font.weight: Font.Bold; wrapMode: Text.WordWrap; maximumLineCount: 2; elide: Text.ElideRight; lineHeight: 1.05 }
                        Text { width: parent.width; visible: !!text; text: home.currentFeatured ? (home.currentFeatured.kind === "news" ? (home.currentFeatured.summary || "") : home.dealSubtitle(home.currentFeatured)) : ""; color: Theme.color.soft; font.family: "Hanken Grotesk"; font.pixelSize: home.u * 20; wrapMode: Text.WordWrap; maximumLineCount: 2; elide: Text.ElideRight }
                        Row {
                            spacing: home.u * 16
                            PadButton {
                                primary: true; focused: hero.focused
                                text: home.featuredAction(home.currentFeatured)
                                onClicked: { home.zone = "hero"; home.openFeatured(home.currentFeatured) }
                            }
                            Text { anchors.verticalCenter: parent.verticalCenter; text: home.currentFeatured && home.currentFeatured.price ? home.currentFeatured.price : ""; color: "#FFFFFF"; font.family: "Hanken Grotesk"; font.pixelSize: home.u * 24; font.weight: Font.Bold }
                            Text { anchors.verticalCenter: parent.verticalCenter; visible: !!home.currentFeatured && home.currentFeatured.kind === "deal" && !!home.currentFeatured.originalPrice; text: home.currentFeatured ? (home.currentFeatured.originalPrice || "") : ""; color: home.ink2; font.family: "Hanken Grotesk"; font.pixelSize: home.u * 18; font.strikeout: true }
                        }
                    }
                    Text {
                        visible: !home.currentFeatured
                        anchors.centerIn: parent
                        text: qsTr("Buscando novedades de tus tiendas…")
                        color: home.ink2; font.family: "Hanken Grotesk"; font.pixelSize: home.u * 22
                    }
                    Row {        // puntos: cuál destacado se ve (←/→ con el foco en el destacado)
                        anchors { right: parent.right; bottom: parent.bottom; margins: home.u * 30 }
                        spacing: home.u * 10
                        Repeater {
                            model: home.featured.length > 1 ? home.featured.length : 0
                            delegate: Rectangle {
                                id: dot
                                required property int index
                                readonly property bool on: home.featuredIndex % home.featured.length === index
                                width: on ? home.u * 34 : home.u * 12; height: home.u * 12; radius: height / 2
                                color: on ? "#FFFFFF" : "#66FFFFFF"
                                Behavior on width { NumberAnimation { duration: 160 } }
                                MouseArea { anchors.fill: parent; anchors.margins: -home.u * 8; cursorShape: Qt.PointingHandCursor; onClicked: home.featuredIndex = dot.index }
                            }
                        }
                    }
                    MouseArea { anchors.fill: parent; z: -1; onClicked: home.zone = "hero" }
                }

                Column {
                    id: side
                    anchors.right: parent.right
                    width: Math.min(home.u * 640, parent.width * 0.38)
                    height: parent.height
                    spacing: home.u * 20
                    // seguir jugando: arte de fondo desvanecido hacia la izquierda
                    Rectangle {
                        id: continueCard
                        width: parent.width; height: parent.height - tiles.height - parent.spacing
                        radius: home.u * 26; color: "#141D28"; clip: true
                        border.width: 1; border.color: "#33FFFFFF"
                        FadedImage {
                            anchors { right: parent.right; top: parent.top; bottom: parent.bottom }
                            width: parent.width * 0.8
                            source: home.heroLocal ? (home.heroLocal.fondo || home.heroLocal.portada || "") : ""
                            cornerRadius: home.u * 26; fadeLeft: 0.75; alignX: 0.7; opacity: 0.85
                        }
                        Rectangle {
                            anchors.fill: parent; radius: parent.radius
                            gradient: Gradient {
                                orientation: Gradient.Horizontal
                                GradientStop { position: 0.30; color: "#D90A0F17" }
                                GradientStop { position: 0.85; color: "#000A0F17" }
                            }
                        }
                        Rectangle {
                            id: cover
                            x: home.u * 22; anchors.verticalCenter: parent.verticalCenter
                            height: parent.height - home.u * 44; width: Math.round(height * 0.75); radius: home.u * 16
                            color: "#22FFFFFF"; border.color: "#40FFFFFF"
                            FadedImage { anchors.fill: parent; source: home.heroLocal ? (home.heroLocal.portada || "") : ""; cornerRadius: home.u * 16 }
                        }
                        Column {
                            anchors { left: cover.right; right: parent.right; verticalCenter: parent.verticalCenter; leftMargin: home.u * 24; rightMargin: home.u * 20 }
                            spacing: home.u * 8
                            Text { text: (home.heroLocal ? qsTr("Seguir jugando") : qsTr("Tu biblioteca")).toUpperCase(); color: Theme.color.accentLight; font.family: "Hanken Grotesk"; font.pixelSize: home.u * 15; font.weight: Font.Bold; font.letterSpacing: home.u * 2 }
                            Text { width: parent.width; text: home.heroLocal ? home.heroLocal.name : qsTr("Aún no has jugado"); color: "#FFFFFF"; font.family: "Hanken Grotesk"; font.pixelSize: home.u * 30; font.weight: Font.Bold; wrapMode: Text.WordWrap; maximumLineCount: 2; elide: Text.ElideRight }
                            Text { width: parent.width; text: home.heroLocal ? [home.heroLocal.sub || home.heroLocal.platform || "", home.lastPlayedText(home.heroLocal)].filter(x => x).join(" · ") : qsTr("Abre la biblioteca para empezar."); color: home.ink2; font.family: "Hanken Grotesk"; font.pixelSize: home.u * 17; elide: Text.ElideRight }
                            Item { width: 1; height: home.u * 6 }
                            Row {
                                visible: !!home.heroLocal
                                spacing: home.u * 12
                                PadButton { primary: true; icon: "play"; focused: home.zone === "play"
                                    text: home.heroLocal && home.heroLocal.portAvailable ? qsTr("Instalar port") : qsTr("Jugar")
                                    onClicked: { home.zone = "play"; home.accept() } }
                                PadButton { text: qsTr("Detalles"); focused: home.zone === "details"
                                    onClicked: { home.zone = "details"; home.accept() } }
                            }
                        }
                    }
                    // accesos: Biblioteca y Catálogo
                    Row {
                        id: tiles
                        width: parent.width; height: home.u * 112
                        spacing: home.u * 20
                        Repeater {
                            model: [
                                { id: "library", icon: "layout-grid", title: qsTr("Biblioteca"), sub: home.gameCount === 1 ? qsTr("1 juego") : qsTr("%1 juegos").arg(home.gameCount) },
                                { id: "catalog", icon: "package-plus", title: qsTr("Catálogo"), sub: qsTr("Ports y tiendas") }
                            ]
                            delegate: Rectangle {
                                id: tile
                                required property var modelData
                                readonly property bool focused: home.zone === modelData.id
                                width: (tiles.width - tiles.spacing) / 2; height: tiles.height
                                radius: home.u * 22
                                color: focused || tileMa.containsMouse ? "#2EFFFFFF" : "#16FFFFFF"
                                scale: focused ? 1.03 : 1
                                border.width: focused ? home.u * 4 : 1
                                border.color: focused ? "#FFFFFF" : "#33FFFFFF"
                                Behavior on scale { NumberAnimation { duration: 120 } }
                                LucideIcon { x: home.u * 22; anchors.verticalCenter: parent.verticalCenter; width: home.u * 34; height: width; name: tile.modelData.icon; color: tile.focused ? Theme.color.accentLight : home.ink2 }
                                Column {
                                    anchors { left: parent.left; leftMargin: home.u * 74; right: parent.right; rightMargin: home.u * 12; verticalCenter: parent.verticalCenter }
                                    spacing: home.u * 2
                                    Text { text: tile.modelData.title; color: home.ink; font.family: "Hanken Grotesk"; font.pixelSize: home.u * 24; font.weight: Font.DemiBold }
                                    Text { width: parent.width; text: tile.modelData.sub; color: home.ink2; font.family: "Hanken Grotesk"; font.pixelSize: home.u * 16; elide: Text.ElideRight }
                                }
                                MouseArea { id: tileMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: { home.zone = tile.modelData.id; home.accept() } }
                            }
                        }
                    }
                }
            }

            // ---- novedades de tus tiendas: filtro por tienda y secciones en cuadrícula
            Item {
                width: parent.width; height: home.u * 56
                Text {
                    anchors { left: parent.left; verticalCenter: parent.verticalCenter }
                    text: qsTr("Novedades de tus tiendas")
                    color: home.ink; font.family: "Hanken Grotesk"; font.pixelSize: home.u * 32; font.weight: Font.Bold
                }
                Row {
                    anchors { right: parent.right; verticalCenter: parent.verticalCenter }
                    spacing: home.u * 8
                    OmniaControlHint {
                        anchors.verticalCenter: parent.verticalCenter
                        visible: !!home.api && home.api.padOn === true
                        uiScale: home.u; uiFont: "Hanken Grotesk"; ink: home.ink; muted: home.ink2; roundButton: true
                        padFamily: home.api && home.api.padFamily ? home.api.padFamily : "xbox"
                        padKeys: ["LB"]; label: ""
                    }
                    Repeater {
                        model: home.storeKeys
                        delegate: Rectangle {
                            id: storeChip
                            required property string modelData
                            readonly property bool on: home.storeFilter === modelData
                            height: home.u * 42; width: storeLabel.implicitWidth + home.u * 34; radius: height / 2
                            color: on ? Theme.color.accentSoft : (chipMa.containsMouse ? "#24FFFFFF" : "#14FFFFFF")
                            border.width: on ? home.u * 2 : 1
                            border.color: on ? Theme.color.accent : "#26FFFFFF"
                            Row {
                                id: storeLabel
                                anchors.centerIn: parent; spacing: home.u * 8
                                Rectangle { visible: storeChip.modelData !== "all"; anchors.verticalCenter: parent.verticalCenter; width: home.u * 9; height: width; radius: home.u * 3; color: Theme.color.store[storeChip.modelData] || Theme.color.accent }
                                Text { text: home.storeName(storeChip.modelData); color: storeChip.on ? Theme.color.accentLight : home.ink; font.family: "Hanken Grotesk"; font.pixelSize: home.u * 18; font.weight: storeChip.on ? Font.DemiBold : Font.Normal }
                            }
                            MouseArea { id: chipMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: { home.storeFilter = storeChip.modelData; home.sectionIndex = 0; home.itemIndex = 0 } }
                        }
                    }
                    OmniaControlHint {
                        anchors.verticalCenter: parent.verticalCenter
                        visible: !!home.api && home.api.padOn === true
                        uiScale: home.u; uiFont: "Hanken Grotesk"; ink: home.ink; muted: home.ink2; roundButton: true
                        padFamily: home.api && home.api.padFamily ? home.api.padFamily : "xbox"
                        padKeys: ["RB"]; label: ""
                    }
                }
            }
            Text {
                visible: home.dealSections.length === 0
                text: home.deals.length ? qsTr("No hay novedades de esta tienda por ahora.") : qsTr("Cargando novedades…")
                color: home.ink2; font.family: "Hanken Grotesk"; font.pixelSize: home.u * 20
            }
            Repeater {
                id: dealRows
                model: home.dealSections
                delegate: Column {
                    id: dealSection
                    required property var modelData
                    required property int index
                    readonly property bool active: home.zone === "deals" && home.sectionIndex === index
                    readonly property real titleHeight: sectionTitleRow.height + spacing
                    function cardAt(i) { return cards.itemAt(i) }
                    width: stack.width
                    spacing: home.u * 16
                    Row {
                        id: sectionTitleRow
                        spacing: home.u * 12
                        Text { id: dealTitle; text: dealSection.modelData.title; color: dealSection.active ? home.ink : home.ink2; font.family: "Hanken Grotesk"; font.pixelSize: home.u * 26; font.weight: Font.DemiBold }
                        Text { anchors.baseline: dealTitle.baseline; text: String(dealSection.modelData.items.length); color: home.ink2; font.family: "Hanken Grotesk"; font.pixelSize: home.u * 19 }
                    }
                    Grid {
                        columns: home.dealColumns
                        columnSpacing: home.u * 20; rowSpacing: home.u * 20
                        Repeater {
                            id: cards
                            model: dealSection.modelData.items
                            delegate: Rectangle {
                                id: dealCard
                                required property var modelData
                                required property int index
                                readonly property bool focused: dealSection.active && home.itemIndex === index
                                readonly property real artHeight: Math.round(width * 0.46)
                                width: home.dealCardWidth; height: home.dealCardHeight
                                radius: home.u * 22
                                color: focused || cardMa.containsMouse ? "#24FFFFFF" : "#14FFFFFF"
                                border.width: focused ? home.u * 4 : 1
                                border.color: focused ? "#FFFFFF" : (cardMa.containsMouse ? Theme.color.accent : "#26FFFFFF")
                                scale: focused ? 1.03 : 1
                                z: focused ? 2 : 0
                                Behavior on scale { NumberAnimation { duration: 120 } }
                                Item {      // arte con las esquinas de arriba redondeadas
                                    id: dealArt
                                    x: dealCard.border.width; y: dealCard.border.width
                                    width: parent.width - 2 * x; height: dealCard.artHeight
                                    clip: true
                                    Rectangle { width: parent.width; height: parent.height + home.u * 20; radius: home.u * 19; color: "#141E2B" }
                                    FadedImage { width: parent.width; height: parent.height + home.u * 20; source: dealCard.modelData.artwork || ""; cornerRadius: home.u * 19 }
                                    Rectangle {
                                        x: home.u * 10; y: home.u * 10; height: home.u * 30; width: dealStore.implicitWidth + home.u * 22; radius: height / 2
                                        color: "#B305090F"; border.color: "#33FFFFFF"
                                        Row { id: dealStore; anchors.centerIn: parent; spacing: home.u * 7
                                            Rectangle { anchors.verticalCenter: parent.verticalCenter; width: home.u * 8; height: width; radius: home.u * 2; color: Theme.color.store[dealCard.modelData.source] || Theme.color.accent }
                                            Text { text: home.storeName(dealCard.modelData.source); color: home.ink; font.family: "Hanken Grotesk"; font.pixelSize: home.u * 15; font.weight: Font.Bold } }
                                    }
                                    Rectangle {
                                        anchors { right: parent.right; top: parent.top; margins: home.u * 10 }
                                        height: home.u * 30; width: dealBadge.implicitWidth + home.u * 22; radius: height / 2
                                        color: home.kindColor(dealCard.modelData)
                                        Text { id: dealBadge; anchors.centerIn: parent; text: home.kindBadge(dealCard.modelData); color: Theme.color.accentInk; font.family: "Hanken Grotesk"; font.pixelSize: home.u * 15; font.weight: Font.ExtraBold }
                                    }
                                }
                                Column {
                                    anchors { left: parent.left; right: parent.right; top: dealArt.bottom; margins: home.u * 18; topMargin: home.u * 14 }
                                    spacing: home.u * 5
                                    Text { width: parent.width; text: dealCard.modelData.title; elide: Text.ElideRight; color: home.ink; font.family: "Hanken Grotesk"; font.pixelSize: home.u * 22; font.weight: Font.Bold }
                                    Text { width: parent.width; text: home.dealSubtitle(dealCard.modelData); elide: Text.ElideRight; color: home.ink2; font.family: "Hanken Grotesk"; font.pixelSize: home.u * 17 }
                                }
                                Row {
                                    anchors { left: parent.left; bottom: parent.bottom; margins: home.u * 18 }
                                    spacing: home.u * 8
                                    Text { anchors.verticalCenter: parent.verticalCenter; text: dealCard.modelData.price || ""; color: home.ink; font.family: "Hanken Grotesk"; font.pixelSize: home.u * 22; font.weight: Font.Bold }
                                    Text { anchors.verticalCenter: parent.verticalCenter; visible: dealCard.modelData.kind === "deal" && !!dealCard.modelData.originalPrice; text: dealCard.modelData.originalPrice || ""; color: home.ink2; font.family: "Hanken Grotesk"; font.pixelSize: home.u * 16; font.strikeout: true }
                                }
                                MouseArea {
                                    id: cardMa
                                    anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                                    onClicked: { home.zone = "deals"; home.sectionIndex = dealSection.index; home.itemIndex = dealCard.index; home.openDeal(dealCard.modelData) }
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    // Ficha de catálogo; la acción de instalación se conecta cuando exista un manifiesto firmado.
    Rectangle {
        anchors.fill: parent
        visible: home.detail !== null
        color: "#99000000"
        z: 10
        MouseArea { anchors.fill: parent; onClicked: home.closeCatalogDetails() }
        Rectangle {
            anchors.centerIn: parent
            width: Math.min(parent.width * 0.78, home.uiScale * 1050)
            height: Math.min(parent.height * 0.76, home.uiScale * 620)
            radius: home.uiScale * 26
            color: "#F0111720"
            border.color: "#335B9BE0"
            clip: true
            MouseArea { anchors.fill: parent; onClicked: function(mouse) { mouse.accepted = true } }
            Image { anchors.fill: parent; source: home.detail ? home.artwork(home.detail, ["hero", "grid"]) : ""; fillMode: Image.PreserveAspectCrop; asynchronous: true; opacity: 0.42 }
            Rectangle { anchors.fill: parent; gradient: Gradient { GradientStop { position: 0; color: "#E8111720" } GradientStop { position: 1; color: "#F0111720" } } }
            Column {
                anchors { left: parent.left; right: parent.right; top: parent.top; margins: home.uiScale * 34 }
                spacing: home.uiScale * 14
                Text { width: parent.width; text: home.detail ? home.detail.name || "" : ""; color: home.ink; font.family: "Hanken Grotesk"; font.pixelSize: home.uiScale * 34; font.weight: Font.Bold; wrapMode: Text.WordWrap; maximumLineCount: 2 }
                Text { width: parent.width; text: home.detail ? [home.platforms(home.detail), home.detail.releaseYear || "", home.detail.developer || ""].filter(x => x).join(" · ") : ""; color: home.ink2; font.family: "Hanken Grotesk"; font.pixelSize: home.uiScale * 17 }
                Text { width: parent.width; text: home.detail ? home.detail.description || qsTr("Todavía no hay una descripción para este juego.") : ""; color: home.ink; font.family: "Hanken Grotesk"; font.pixelSize: home.uiScale * 19; lineHeight: 1.25; wrapMode: Text.WordWrap; elide: Text.ElideRight; maximumLineCount: 7 }
                Text { width: parent.width; text: home.detailLoading ? qsTr("Actualizando ficha…") : (home.detail && home.detail.compatibility ? qsTr("Compatibilidad: %1").arg(home.detail.compatibility) : ""); color: home.ink2; font.family: "Hanken Grotesk"; font.pixelSize: home.uiScale * 16 }
            }
            Column {
                anchors { left: parent.left; right: parent.right; bottom: parent.bottom; bottomMargin: home.uiScale * 102; leftMargin: home.uiScale * 34; rightMargin: home.uiScale * 34 }
                visible: home.detail && !home.localMatch(home.detail)
                spacing: home.uiScale * 8
                Text { visible: home.packages.length === 0; width: parent.width; text: home.installMessage; color: home.ink2; font.family: "Hanken Grotesk"; font.pixelSize: home.uiScale * 14; wrapMode: Text.WordWrap }
                Row {
                    visible: home.packages.length > 0; width: parent.width; spacing: home.uiScale * 12
                    Rectangle {
                        width: home.uiScale * 34; height: width; radius: home.uiScale * 8
                        color: home.acceptLicense ? home.accent : "#27343F"; border.color: home.acceptLicense ? home.accent : "#7890A8"
                        Text { anchors.centerIn: parent; text: home.acceptLicense ? "✓" : ""; color: "white"; font.pixelSize: home.uiScale * 18 }
                        MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: home.acceptLicense = !home.acceptLicense }
                    }
                    Column { width: parent.width - home.uiScale * 48; spacing: home.uiScale * 3
                        Text { width: parent.width; text: home.selectedPackage ? qsTr("Fuente: %1 · Licencia: %2 · %3 GiB").arg(home.selectedPackage.sourceName).arg(home.selectedPackage.licenseName).arg((Number(home.selectedPackage.sizeBytes) / 1073741824).toFixed(2)) : ""; color: home.ink2; font.family: "Hanken Grotesk"; font.pixelSize: home.uiScale * 13; elide: Text.ElideRight }
                        Text { width: parent.width; text: qsTr("Acepto la licencia y la descarga desde la fuente indicada."); color: home.ink2; font.family: "Hanken Grotesk"; font.pixelSize: home.uiScale * 12; wrapMode: Text.WordWrap }
                    }
                }
                Rectangle {
                    visible: home.packages.length > 0; width: home.uiScale * 178; height: home.uiScale * 38; radius: height / 2; color: home.surface
                    Text { anchors.centerIn: parent; text: home.api.installRoot ? qsTr("Destino predeterminado") : qsTr("Elegir destino"); color: home.ink; font.family: "Hanken Grotesk"; font.pixelSize: home.uiScale * 13 }
                    MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: installFolderDialog.open() }
                }
            }
            Row {
                anchors { left: parent.left; bottom: parent.bottom; margins: home.uiScale * 34 }
                spacing: home.uiScale * 12
                Rectangle {
                    width: home.uiScale * 200; height: home.uiScale * 48; radius: height / 2
                    color: home.localMatch(home.detail) || (home.selectedPackage && home.api.installRoot && home.acceptLicense) ? home.accent : "#33434F5C"
                    Text { anchors.centerIn: parent; text: home.localMatch(home.detail) ? qsTr("Jugar") : home.packages.length ? (home.installBusy ? qsTr("Preparando…") : qsTr("Instalar")) : qsTr("Sin paquete"); color: home.ink; font.family: "Hanken Grotesk"; font.pixelSize: home.uiScale * 17; font.weight: Font.DemiBold; elide: Text.ElideRight; width: parent.width - home.uiScale * 18; horizontalAlignment: Text.AlignHCenter }
                    MouseArea { anchors.fill: parent; enabled: !!home.localMatch(home.detail) || (!!home.selectedPackage && !!home.api.installRoot && home.acceptLicense && !home.installBusy); cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor; onClicked: { const local = home.localMatch(home.detail); if (local) home.openLocalGame(local.id); else home.beginInstall() } }
                }
                Rectangle {
                    width: home.uiScale * 120; height: home.uiScale * 48; radius: height / 2
                    color: "#33434F5C"
                    Text { anchors.centerIn: parent; text: qsTr("Cerrar"); color: home.ink; font.family: "Hanken Grotesk"; font.pixelSize: home.uiScale * 17 }
                    MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: home.closeCatalogDetails() }
                }
            }
        }
    }
    FolderDialog {
        id: installFolderDialog
        title: qsTr("Elige la carpeta predeterminada para instalar juegos")
        onAccepted: {
            const path = decodeURIComponent(selectedFolder.toString().replace(/^file:\/\//, ""))
            home.api.setInstallRoot(path, function(status, body) {
                if (status === 200 && home.api.notify) home.api.notify(qsTr("Carpeta de instalación guardada."))
                else if (status !== 200 && home.api.notify) home.api.notify((body && body.error) || qsTr("No se pudo guardar la carpeta de instalación."))
            })
        }
    }
}

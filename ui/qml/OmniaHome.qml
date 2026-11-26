pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Dialogs

/** Inicio de Big Mode: contenido público del backend y actividad que ya existe en la biblioteca local. */
Item {
    id: home
    property real exitShelfProgress: 0
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
    // ---------- carrusel automático, juego actual y mosaico de accesos ----------
    property int zone: 1                    // 0 carrusel, 1 «seguir jugando» + mosaico
    property int gridRow: 0
    property int gridCol: 0
    readonly property var heroLocal: localFeaturedGame()
    readonly property var heroActions: heroLocal ? [{ id: "play", label: heroLocal.portAvailable ? qsTr("Instalar port") : qsTr("Jugar") }, { id: "library", label: qsTr("Detalles") }]
                                                 : [{ id: "library", label: qsTr("Abrir biblioteca") }]
    readonly property int favoriteCount: (localGames || []).filter(g => g.fav && !g.hidden).length
    readonly property int gameCount: (localGames || []).filter(g => !g.hidden).length
    readonly property var tiles: [
        { id: "library", icon: "layout-grid", title: qsTr("Biblioteca"), sub: gameCount + " " + (gameCount === 1 ? qsTr("juego") : qsTr("juegos")) },
        { id: "favorites", icon: "star", title: qsTr("Favoritos"), sub: favoriteCount > 0 ? favoriteCount + " " + (favoriteCount === 1 ? qsTr("juego") : qsTr("juegos")) : qsTr("Aún no hay favoritos") },
        { id: "system", icon: "activity", title: qsTr("Sistema"), sub: qsTr("Estado del equipo") },
        { id: "settings", icon: "settings", title: qsTr("Ajustes"), sub: qsTr("Mando, idioma y biblioteca") }
    ]
    readonly property string acceptLabel: {
        if (zone === 0) return carousel.current?.slug ? qsTr("Ver ficha") : qsTr("Leer noticia")
        if (gridCol < 2) return heroActions[Math.min(gridCol, heroActions.length - 1)].label
        return qsTr("Abrir")
    }
    function clamp(v, lo, hi) { return Math.max(lo, Math.min(hi, v)) }
    function cellExists(r, c) { return c < 2 ? (r === 0 && c < heroActions.length) : true }
    onZoneChanged: Qt.callLater(function() { page.reveal(zone === 0 ? carousel : bottomRow) })
    function nav(dir) {
        if (zone === 0) {
            if (dir === "left") carousel.advance(-1)
            else if (dir === "right") carousel.advance(1)
            else if (dir === "down") { zone = 1; gridRow = 0; gridCol = cellExists(0, 0) ? 0 : 2 }
            return
        }
        if (dir === "up") {
            if (gridRow === 1) gridRow = 0
            else if (carousel.current) zone = 0
        } else if (dir === "down") {
            if (gridRow === 0 && cellExists(1, gridCol)) gridRow = 1
        } else {
            const d = dir === "left" ? -1 : 1
            let c = gridCol + d
            while (c >= 0 && c <= 3 && !cellExists(gridRow, c)) c += d
            if (c >= 0 && c <= 3) gridCol = c
        }
    }
    function accept() {
        if (zone === 0) {
            carousel.openCurrent()
            return
        }
        if (gridCol < 2) {
            const action = heroActions[Math.min(gridCol, heroActions.length - 1)].id
            if (action === "play" && heroLocal) playLocalGame(heroLocal.id)
            else if (heroLocal) openLocalGame(heroLocal.id)
            else openSection("library")
        } else {
            openSection(tiles[(gridCol - 2) + gridRow * 2].id)
        }
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
        else { event.accepted = false; return }
        event.accepted = true
    }

    Timer { interval: 15 * 60 * 1000; repeat: true; running: home.visible; onTriggered: home.refresh() }
    Timer { id: initialRefresh; interval: 360; repeat: false; onTriggered: home.refresh() }
    onVisibleChanged: if (visible) initialRefresh.start()
    // Si Inicio nace visible no hay cambio de visibilidad: sin esto el catálogo no se pedía nunca.
    Component.onCompleted: initialRefresh.start()
    onSearchTextChanged: searchDelay.restart()
    Timer { id: searchDelay; interval: 420; repeat: false; onTriggered: home.refresh() }

    // ---------- datos de presentación ----------
    readonly property real u: uiScale
    // color del fondo animado: el de la consola de la novedad que muestra el carrusel (o del juego actual); azul de Omnia por defecto
    readonly property var platformTints: ({ pc: "#3a8f8a", switch: "#d9544a", sw1: "#d9544a", switch2: "#4a8fe0", sw2: "#4a8fe0", n64: "#d9a441",
        ps1: "#4a6fd0", ps2: "#4a6fd0", ps3: "#4a6fd0", ps4: "#4a6fd0", ps5: "#4a6fd0", psp: "#4a6fd0",
        xbox: "#4aa54a", x360: "#4aa54a", xseries: "#4aa54a", gba: "#8a6bd0", gb: "#8a6bd0", gbc: "#8a6bd0", nds: "#8a6bd0", "3ds": "#8a6bd0",
        gamecube: "#7a6bd0", wii: "#6bb0d0", wiiu: "#6bb0d0", snes: "#b0907a", nes: "#b0907a", genesis: "#4a8fd9", saturn: "#4a8fd9", dreamcast: "#e08a4a" })
    readonly property color effectTint: {
        const slug = carousel.current?.slug ? "sw2" : platformSlug(heroLocal)
        return platformTints[slug] || "#336599"
    }
    readonly property var catalogIcons: ({ switch: "sw1", switch2: "sw2", n64: "n64", pc: "pc", ps3: "ps3", ps4: "ps4", ps5: "ps5", sw1: "sw1", sw2: "sw2" })
    function platformSlug(game) {
        if (!game) return ""
        if (game.platforms) { const list = Array.from(game.platforms); return list.length ? String(list[0].slug || "").toLowerCase() : "" }
        return String(game.platform || "").toLowerCase()
    }
    function tint(slug, light) {
        let h = 0
        for (let i = 0; i < slug.length; i++) h = (h * 31 + slug.charCodeAt(i)) % 360
        return Qt.hsla(h / 360, 0.30, light === undefined ? 0.3 : light, 1)
    }
    function initials(name) {
        const words = String(name || "").split(/\s+/).filter(w => /^[A-Za-z0-9À-ɏ]/.test(w))
        return words.slice(0, 3).map(w => w[0]).join("").toUpperCase()
    }
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

    // El contenido solo se desplaza (rueda o arrastre) cuando no cabe en la pantalla.
    Flickable {
        id: page
        anchors { fill: parent; topMargin: home.u * 100; bottomMargin: home.u * 96 + home.footerSpace }
        contentWidth: width
        contentHeight: stack.height
        interactive: contentHeight > height + 1
        boundsBehavior: Flickable.StopAtBounds
        clip: true
        Behavior on contentY { enabled: !page.dragging && !page.flicking; NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }
        function reveal(item) {
            if (!item || !interactive) return
            const top = item.mapToItem(page.contentItem, 0, 0).y - home.u * 20
            const bottom = top + item.height + home.u * 40
            if (top < contentY) contentY = Math.max(0, top)
            else if (bottom > contentY + height) contentY = Math.min(contentHeight - height, bottom - height)
        }

        Column {
            id: stack
            x: home.u * 96
            width: page.width - home.u * 192
            spacing: home.u * 22

            // ---- cabecera ----
            Item {
                width: parent.width; height: home.u * 80
                Text {
                    text: qsTr("Inicio")
                    color: home.ink
                    font.family: "Hanken Grotesk"; font.pixelSize: home.u * 34; font.weight: Font.DemiBold
                }
                Text {
                    visible: !home.offline
                    anchors { left: parent.left; bottom: parent.bottom }
                    text: qsTr("Novedades del catálogo y tus partidas")
                    color: home.ink2
                    font.family: "Hanken Grotesk"; font.pixelSize: home.u * 18
                }
                Rectangle {          // aviso sin conexión discreto, con reintento
                    visible: home.offline
                    anchors { left: parent.left; bottom: parent.bottom }
                    height: home.u * 32; width: offlineRow.width + home.u * 28; radius: height / 2
                    color: "#26E8B86D"; border.width: 1; border.color: "#59E8B86D"
                    Row {
                        id: offlineRow
                        anchors.centerIn: parent
                        spacing: home.u * 10
                        LucideIcon { anchors.verticalCenter: parent.verticalCenter; width: home.u * 16; height: width; name: "triangle-alert"; color: "#E8B86D" }
                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            text: home.cacheExpired ? qsTr("Sin conexión · catálogo guardado desactualizado") : qsTr("Catálogo sin conexión · datos guardados")
                            color: "#E8B86D"; font.family: "Hanken Grotesk"; font.pixelSize: home.u * 15
                        }
                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            text: qsTr("Reintentar")
                            color: home.ink; font.family: "Hanken Grotesk"; font.pixelSize: home.u * 15; font.weight: Font.DemiBold
                            font.underline: true
                            MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: home.refresh() }
                        }
                    }
                }
            }

            ManagerStoreNews {
                id: carousel
                width: parent.width
                manager: QtObject {
                    readonly property real s: home.u
                    readonly property color ink: home.ink
                    readonly property color ring: home.accent
                    function storeLogo(source) { return Qt.resolvedUrl("images/stores/" + source + ".svg") }
                }
                api: home.api
                active: home.visible
                bannerHeight: home.u * 326
                controllerFocused: home.zone === 0
                onOpenGame: game => home.openCatalogDetails(game)
            }

            Row {
                id: bottomRow
                opacity: 1 - home.exitShelfProgress
                transform: Translate { y: home.u * 30 * home.exitShelfProgress }
                width: parent.width; spacing: home.u * 22
                // juego actual
                Rectangle {
                    id: currentCard
                    width: parent.width * 0.47; height: home.u * 310
                    radius: home.u * 24
                    color: "#16ffffff"          // translúcida, como el resto de tarjetas
                    clip: true
                    border.width: 1; border.color: "#26FFFFFF"
                    readonly property string slug: home.platformSlug(home.heroLocal)
                    Item {
                        id: coverBox
                        x: home.u * 22; y: home.u * 22
                        width: home.u * 168; height: parent.height - home.u * 44
                        Rectangle {
                            anchors.fill: parent; radius: home.u * 14
                            color: home.tint(currentCard.slug || "inicio", 0.24)
                            Text { anchors.centerIn: parent; text: home.initials(home.heroLocal ? home.heroLocal.name : ""); color: "#FFFFFF"; opacity: 0.85
                                font.family: "Hanken Grotesk"; font.pixelSize: home.u * 40; font.weight: Font.Bold }
                        }
                        FadedImage {
                            anchors.fill: parent
                            source: home.heroLocal ? (home.heroLocal.portada || "") : ""
                            cornerRadius: home.u * 14      // portada con esquinas redondeadas
                        }
                    }
                    Column {
                        x: coverBox.x + coverBox.width + home.u * 24
                        anchors.verticalCenter: parent.verticalCenter
                        width: parent.width - x - home.u * 22; spacing: home.u * 8
                        Text {
                            text: home.heroLocal ? qsTr("SEGUIR JUGANDO") : qsTr("TU BIBLIOTECA")
                            color: "#9CC8F4"
                            font.family: "Hanken Grotesk"; font.pixelSize: home.u * 14; font.weight: Font.Bold; font.letterSpacing: home.u * 2
                        }
                        Text {
                            width: parent.width
                            text: home.heroLocal ? (home.heroLocal.name || "") : qsTr("Aún no has jugado")
                            color: home.ink
                            font.family: "Hanken Grotesk"; font.pixelSize: home.u * 30; font.weight: Font.Bold
                            wrapMode: Text.WordWrap; maximumLineCount: 2; elide: Text.ElideRight
                        }
                        Text {
                            width: parent.width
                            text: home.heroLocal ? [home.heroLocal.sub || home.heroLocal.platform || "", home.lastPlayedText(home.heroLocal)].filter(x => x).join(" · ")
                                                 : qsTr("Abre la biblioteca para empezar.")
                            color: home.ink2
                            font.family: "Hanken Grotesk"; font.pixelSize: home.u * 17
                            wrapMode: Text.WordWrap; maximumLineCount: 2; elide: Text.ElideRight
                        }
                        Row {
                            spacing: home.u * 10
                            topPadding: home.u * 8
                            Repeater {
                                model: home.heroActions
                                delegate: Rectangle {
                                    id: heroBtn
                                    required property var modelData
                                    required property int index
                                    readonly property bool focused: home.zone === 1 && home.gridRow === 0 && home.gridCol === index
                                    width: home.u * 138; height: home.u * 46; radius: height / 2
                                    scale: focused ? 1.05 : 1
                                    color: index === 0 ? home.accent : "#B3151D27"
                                    border.width: focused ? home.u * 3 : 1
                                    border.color: focused ? "#FFFFFF" : (index === 0 ? home.accent : "#66FFFFFF")
                                    Behavior on scale { NumberAnimation { duration: 120 } }
                                    Text { anchors.centerIn: parent; text: heroBtn.modelData.label; color: home.ink; font.family: "Hanken Grotesk"; font.pixelSize: home.u * 17; font.weight: Font.DemiBold }
                                    MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor
                                        onClicked: { home.zone = 1; home.gridRow = 0; home.gridCol = heroBtn.index; home.accept() } }
                                }
                            }
                        }
                    }
                }
                // mosaico de accesos 2×2
                Grid {
                    id: mosaic
                    width: parent.width - currentCard.width - parent.spacing
                    columns: 2; spacing: home.u * 16
                    Repeater {
                        model: home.tiles
                        delegate: Rectangle {
                            id: tile
                            required property var modelData
                            required property int index
                            readonly property bool focused: home.zone === 1 && home.gridRow === Math.floor(index / 2) && home.gridCol === 2 + (index % 2)
                            width: (mosaic.width - mosaic.spacing) / 2; height: (currentCard.height - mosaic.spacing) / 2
                            radius: home.u * 22
                            color: focused ? "#2effffff" : "#16ffffff"      // sin arte: translúcida
                            scale: focused ? 1.03 : 1
                            border.width: focused ? home.u * 3 : 1
                            border.color: focused ? "#5B9BE0" : "#26FFFFFF"
                            Behavior on scale { NumberAnimation { duration: 120 } }
                            Column {
                                anchors { left: parent.left; leftMargin: home.u * 24; verticalCenter: parent.verticalCenter }
                                spacing: home.u * 8
                                LucideIcon { width: home.u * 30; height: width; name: tile.modelData.icon; color: tile.focused ? "#9CC8F4" : home.ink2 }
                                Text { text: tile.modelData.title; color: home.ink; font.family: "Hanken Grotesk"; font.pixelSize: home.u * 24; font.weight: Font.DemiBold }
                                Text { text: tile.modelData.sub; color: home.ink2; font.family: "Hanken Grotesk"; font.pixelSize: home.u * 16 }
                            }
                            MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor
                                onClicked: { home.zone = 1; home.gridRow = Math.floor(tile.index / 2); home.gridCol = 2 + (tile.index % 2); home.accept() } }
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

pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls
import "Theme.js" as Theme

/** Inicio de Desktop (rediseño D, fase 4): novedades de las tiendas antes que nada.
 *  Arriba, un destacado que rota (juegos gratis, ofertas grandes y novedades de Omnia) junto a «Seguir jugando»
 *  y las descargas. Debajo, «Novedades de tus tiendas» con filtro por tienda y secciones: Ofertas, Gratis por
 *  tiempo limitado, Lanzamientos y novedades, y Actualizaciones de tus juegos.
 *  Datos: /stores/deals (ofertas, gratis y lanzamientos; caché del núcleo), /stores/news (noticias y novedades
 *  de tus juegos de Steam) y el catálogo de Omnia (ports nuevos). Solo se muestran datos reales. */
Item {
    id: home
    required property var manager
    required property var api
    property Item backdrop: null
    visible: home.manager.page === "home"

    property var deals: []
    property var news: []
    property int dealsUpdated: 0
    property bool loading: true
    property string storeFilter: "all"          // all | steam | epic | gog | amazon | omnia
    property int featuredIndex: 0
    property var expanded: ({})                 // secciones abiertas con «Ver todo» (por defecto, dos filas)

    readonly property var stores: [
        { k: "all", l: qsTr("Todas") }, { k: "steam", l: "Steam" }, { k: "epic", l: "Epic" },
        { k: "gog", l: "GOG" }, { k: "amazon", l: "Amazon" }, { k: "omnia", l: "Omnia" }
    ]
    function storeName(key) { return ({ steam: "Steam", epic: "Epic", gog: "GOG", amazon: "Amazon", omnia: "Omnia", ubisoft: "Ubisoft", ea: "EA" })[key] || key }
    function storeColor(key) { return Theme.color.store[key] || Theme.color.accent }

    // ---- datos
    function refresh() {
        const lang = home.api.language === "en" ? "en" : "es"
        home.api.call("GET", "/stores/deals?lang=" + lang, function(status, body) {
            if (status !== 200 || !body) { retry.restart(); return }        // el servicio aún no responde: se reintenta
            home.deals = body.items || []
            home.dealsUpdated = body.updated || 0
            home.loading = !!body.loading
            if (body.loading) retry.restart()
        })
        home.api.call("GET", "/stores/news?lang=" + lang, function(status, body) {
            if (status === 200 && body && Array.isArray(body.items)) home.news = body.items
            if (status === 200 && body && body.loading) retry.restart()
        })
    }
    Timer { id: retry; interval: 4000; onTriggered: home.refresh() }
    Timer { interval: 10 * 60 * 1000; repeat: true; running: home.visible; onTriggered: home.refresh() }
    onVisibleChanged: if (visible) refresh()
    Component.onCompleted: if (visible) refresh()
    Connections { target: home.api; function onOkChanged() { if (home.api.ok && home.visible) home.refresh() } }
    Connections { target: home.api; function onCurrencyChanged() { home.refresh() } }     // otra moneda: precios nuevos

    // Ports de Omnia recién publicados (el catálogo ya viene ordenado por actualización).
    readonly property var omniaReleases: (home.manager.onlineGames || []).slice(0, 8).map(g => ({
        source: "omnia", kind: "release", title: g.name || "", url: "", game: g,
        artwork: home.manager.imageFor(g, ["hero", "grid"]), discount: 0, price: "", originalPrice: "",
        summary: (g.platforms || g.platform || "") + "" }))
    // Noticias: las de Steam son de tus juegos (actualizaciones); el resto, novedades de cada tienda.
    readonly property var updates: home.news.filter(n => n.source === "steam").map(n => Object.assign({ kind: "update" }, n))
        .concat((home.api.games || []).filter(g => g.updateAvailable && !g.hidden).map(g => ({
            source: "omnia", kind: "update", title: g.name, url: "", local: g, artwork: g.fondo || g.portada || "",
            summary: qsTr("Versión %1 disponible").arg(g.updateAvailable.version || "") })))
    readonly property var storeNews: home.news.filter(n => n.source !== "steam").map(n => Object.assign({ kind: "news" }, n))

    function matches(item) { return home.storeFilter === "all" || item.source === home.storeFilter }
    readonly property var sections: {
        const pick = list => list.filter(home.matches)
        return [
            { key: "deal", title: qsTr("Ofertas"), items: pick(home.deals.filter(i => i.kind === "deal")) },
            { key: "free", title: qsTr("Gratis por tiempo limitado"), items: pick(home.deals.filter(i => i.kind === "free" || i.kind === "upcoming")) },
            { key: "release", title: qsTr("Lanzamientos y novedades"), items: pick(home.omniaReleases.concat(home.storeNews, home.deals.filter(i => i.kind === "release"))) },
            { key: "update", title: qsTr("Actualizaciones de tus juegos"), items: pick(home.updates) }
        ].filter(s => s.items.length > 0)
    }
    readonly property var featured: {
        const out = []
        const free = home.deals.filter(i => i.kind === "free")
        const big = home.deals.filter(i => i.kind === "deal" && i.artwork).sort((a, b) => (b.discount || 0) - (a.discount || 0))
        const omnia = home.news.filter(n => n.source === "omnia" && n.artwork)
        for (const list of [free.slice(0, 2), omnia.slice(0, 1), big.slice(0, 3), home.omniaReleases.filter(i => i.artwork).slice(0, 1)])
            for (const i of list) if (home.matches(i)) out.push(i)
        return out.slice(0, 6)
    }
    readonly property var current: featured.length ? featured[featuredIndex % featured.length] : null
    Timer { interval: 9000; repeat: true; running: home.visible && home.featured.length > 1; onTriggered: home.featuredIndex = (home.featuredIndex + 1) % home.featured.length }

    function kindBadge(item) {
        if (item.kind === "deal") return item.discount > 0 ? "−" + item.discount + " %" : qsTr("Oferta")
        if (item.kind === "free") return qsTr("Gratis")
        if (item.kind === "upcoming") return qsTr("Próximamente gratis")
        if (item.kind === "release") return item.source === "omnia" ? qsTr("Nuevo port") : qsTr("Nuevo")
        if (item.kind === "update") return qsTr("Actualización")
        return qsTr("Novedad")
    }
    function kindColor(item) {
        return item.kind === "deal" ? Theme.color.ok : item.kind === "free" || item.kind === "upcoming" ? Theme.color.favorite
             : item.kind === "update" ? Theme.color.warning : Theme.color.accentLight
    }
    function dateText(ts) {
        return ts > 0 ? new Date(ts * 1000).toLocaleDateString(Qt.locale(home.api.language === "en" ? "en_US" : "es_CO"), "d MMM") : ""
    }
    function subtitle(item) {
        if (item.kind === "free") return item.endsAt ? qsTr("Gratis hasta el %1").arg(home.dateText(item.endsAt)) : qsTr("Gratis por tiempo limitado")
        if (item.kind === "upcoming") return item.startsAt ? qsTr("Gratis desde el %1").arg(home.dateText(item.startsAt)) : qsTr("Próximamente")
        if (item.kind === "deal") return item.endsAt ? qsTr("Termina el %1").arg(home.dateText(item.endsAt)) : (item.originalPrice ? qsTr("Antes %1").arg(item.originalPrice) : "")
        if (item.kind === "release" && item.source === "omnia") return qsTr("Port nativo para Linux")
        return item.summary || home.storeName(item.source)
    }
    function actionLabel(item) {
        if (item.local) return qsTr("Ver ficha")
        if (item.game) return qsTr("Ver ficha")
        if (item.kind === "free") return qsTr("Obtener")
        if (item.kind === "deal") return qsTr("Ver oferta")
        if (item.slug) return qsTr("Ver ficha")
        return qsTr("Abrir")
    }
    function open(item) {
        if (!item) return
        if (item.local) { home.manager.openGameInLibrary(item.local); return }
        if (item.game) { home.manager.openCatalogDetail(item.game); return }
        if (item.slug) {
            home.api.catalogGame(item.slug, function(status, body) {
                if (status === 200 && body && body.data) home.manager.openCatalogDetail(body.data)
                else if (item.url) Qt.openUrlExternally(item.url)
            })
            return
        }
        if (item.url) Qt.openUrlExternally(item.url)
    }
    function backdropRectOf(item) {
        if (!backdrop || !item) return Qt.rect(0, 0, 0, 0)
        void (item.x + item.y + item.width + item.height + flick.contentY + home.width)
        const p = item.mapToItem(backdrop, 0, 0)
        return Qt.rect(p.x, p.y, item.width, item.height)
    }

    Flickable {
        id: flick
        anchors.fill: parent
        clip: true
        contentWidth: width
        contentHeight: body.height + Theme.size.pageMargin * 2
        boundsBehavior: Flickable.StopAtBounds
        ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

        Column {
            id: body
            x: Theme.size.pageMargin; y: Theme.size.panelGap
            width: flick.width - 2 * Theme.size.pageMargin
            spacing: 22

            // ---------------- destacado + columna lateral
            Item {
                id: topRow
                readonly property bool side: width >= 1100
                width: parent.width
                height: side ? 300 : 300 + 20 + sideCol.implicitHeight

                Rectangle {
                    id: hero
                    width: topRow.side ? parent.width - 436 - 20 : parent.width
                    height: 300; radius: 24
                    color: "#111A26"
                    clip: true
                    border.color: Theme.color.glassBorderStrong
                    FadedImage {
                        anchors.fill: parent
                        source: home.current ? (home.current.artwork || "") : ""
                        cornerRadius: 24
                        alignX: 0.7
                    }
                    Rectangle {
                        anchors.fill: parent; radius: 24
                        gradient: Gradient {
                            orientation: Gradient.Horizontal
                            GradientStop { position: 0.0; color: "#E6060A10" }
                            GradientStop { position: 0.65; color: "#40060A10" }
                        }
                    }
                    Column {
                        visible: !!home.current
                        anchors { left: parent.left; top: parent.top; bottom: parent.bottom; margins: 28 }
                        width: Math.min(560, hero.width - 56)
                        Row {
                            spacing: 8
                            Rectangle {
                                height: 28; width: heroStore.implicitWidth + 26; radius: 14
                                color: "#24FFFFFF"; border.color: "#33FFFFFF"
                                Row { id: heroStore; anchors.centerIn: parent; spacing: 6
                                    Rectangle { anchors.verticalCenter: parent.verticalCenter; width: 8; height: 8; radius: 3; color: home.current ? home.storeColor(home.current.source) : "transparent" }
                                    Text { text: home.current ? home.storeName(home.current.source) : ""; color: Theme.color.ink; font.family: Theme.font.family; font.pixelSize: 12; font.weight: Font.Bold } }
                            }
                            Rectangle {
                                height: 28; width: heroKind.implicitWidth + 24; radius: 14
                                color: home.current ? home.kindColor(home.current) : "transparent"
                                Text { id: heroKind; anchors.centerIn: parent; text: home.current ? home.kindBadge(home.current) : ""; color: Theme.color.accentInk; font.family: Theme.font.family; font.pixelSize: 12; font.weight: Font.ExtraBold }
                            }
                        }
                        Item { width: 1; height: 300 - 56 - 28 - heroText.height - 44 }
                        Column {
                            id: heroText
                            width: parent.width
                            spacing: 8
                            Text { width: parent.width; text: home.current ? home.current.title : ""; color: Theme.color.inkStrong; font.family: Theme.font.display; font.pixelSize: 38; font.weight: Font.Bold; wrapMode: Text.WordWrap; maximumLineCount: 2; elide: Text.ElideRight; lineHeight: 1.05 }
                            Text { width: parent.width; text: home.current ? home.subtitle(home.current) : ""; color: Theme.color.soft; font.family: Theme.font.family; font.pixelSize: 15; elide: Text.ElideRight; bottomPadding: 10 }
                        }
                        Row {
                            spacing: 12
                            Rectangle {
                                height: 44; width: heroAction.implicitWidth + 44; radius: 14
                                color: heroMa.containsMouse ? Theme.color.accentLight : Theme.color.accent
                                Text { id: heroAction; anchors.centerIn: parent; text: home.current ? home.actionLabel(home.current) : ""; color: Theme.color.accentInk; font.family: Theme.font.family; font.pixelSize: 15; font.weight: Font.Bold }
                                MouseArea { id: heroMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: home.open(home.current) }
                            }
                            Text {
                                anchors.verticalCenter: parent.verticalCenter
                                text: home.current && home.current.price ? home.current.price + (home.current.originalPrice ? "   " : "") : ""
                                color: Theme.color.ink; font.family: Theme.font.family; font.pixelSize: 17; font.weight: Font.Bold
                            }
                            Text {
                                anchors.verticalCenter: parent.verticalCenter
                                visible: !!home.current && !!home.current.originalPrice && home.current.kind === "deal"
                                text: home.current ? home.current.originalPrice : ""
                                color: Theme.color.muted; font.family: Theme.font.family; font.pixelSize: 14; font.strikeout: true
                            }
                        }
                    }
                    Text {
                        visible: !home.current
                        anchors.centerIn: parent
                        text: home.loading ? qsTr("Buscando novedades de tus tiendas…") : qsTr("No hay novedades para esta tienda.")
                        color: Theme.color.muted; font.family: Theme.font.family; font.pixelSize: 16
                    }
                    Row {
                        anchors { right: parent.right; bottom: parent.bottom; margins: 22 }
                        spacing: 8
                        Repeater {
                            model: home.featured.length > 1 ? home.featured.length : 0
                            delegate: Rectangle {
                                id: dot
                                required property int index
                                readonly property bool on: home.featuredIndex % home.featured.length === index
                                width: on ? 26 : 9; height: 9; radius: 5
                                color: on ? Theme.color.ink : "#66FFFFFF"
                                Behavior on width { NumberAnimation { duration: 160 } }
                                MouseArea { anchors.fill: parent; anchors.margins: -6; cursorShape: Qt.PointingHandCursor; onClicked: home.featuredIndex = dot.index }
                            }
                        }
                    }
                }

                Grid {          // al lado del destacado; en ventanas angostas, debajo y en dos columnas
                    id: sideCol
                    x: topRow.side ? hero.width + 20 : 0
                    y: topRow.side ? 0 : 320
                    width: topRow.side ? 436 : parent.width
                    columns: topRow.side || !continueCard.visible ? 1 : 2
                    spacing: 20
                    readonly property real cellWidth: columns === 1 ? width : (width - spacing) / 2
                    // seguir jugando
                    GlassPanel {
                        id: continueCard
                        readonly property var g: (home.manager.recentGames || [])[0] || null
                        // Alto: lo que deja libre la tarjeta de abajo (que solo mide lo que necesita su contenido).
                        width: sideCol.cellWidth
                        height: topRow.side ? 300 - sideCol.spacing - dlCard.height : 190
                        visible: !!g
                        backdrop: home.backdrop
                        backdropRect: home.backdropRectOf(continueCard)
                        FadedImage {        // arte de fondo: nítido a la derecha, se desvanece hacia la izquierda
                            anchors { right: parent.right; top: parent.top; bottom: parent.bottom }
                            width: parent.width * 0.78
                            source: continueCard.g ? (continueCard.g.fondo || continueCard.g.portada || "") : ""
                            cornerRadius: Theme.radius.xl
                            fadeLeft: 0.75
                            alignX: 0.7
                            opacity: 0.85
                        }
                        Rectangle {         // sombra suave detrás del texto para que el título se lea sobre el arte
                            anchors.fill: parent
                            radius: Theme.radius.xl
                            gradient: Gradient {
                                orientation: Gradient.Horizontal
                                GradientStop { position: 0.30; color: "#CC0A0F17" }
                                GradientStop { position: 0.80; color: "#000A0F17" }
                            }
                        }
                        Rectangle {
                            id: continueArt
                            x: 16; anchors.verticalCenter: parent.verticalCenter
                            height: Math.min(parent.height - 32, 172); width: Math.round(height * 0.75); radius: 12; color: Theme.color.inset
                            border.color: Theme.color.glassBorderStrong
                            FadedImage { anchors.fill: parent; source: continueCard.g ? (continueCard.g.portada || continueCard.g.fondo || "") : ""; cornerRadius: 12 }
                        }
                        Column {
                            anchors { left: continueArt.right; leftMargin: 18; right: parent.right; rightMargin: 16; verticalCenter: parent.verticalCenter }
                            spacing: 6
                            Text { text: qsTr("Seguir jugando").toUpperCase(); color: Theme.color.accentLight; font.family: Theme.font.family; font.pixelSize: 12; font.weight: Font.Bold; font.letterSpacing: 1.2 }
                            Text { width: parent.width; text: continueCard.g ? continueCard.g.name : ""; wrapMode: Text.WordWrap; maximumLineCount: 2; elide: Text.ElideRight; color: Theme.color.inkStrong; font.family: Theme.font.family; font.pixelSize: 21; font.weight: Font.Bold }
                            Text { width: parent.width; text: continueCard.g ? (home.manager.sourceForGame(continueCard.g).label + (continueCard.g.lastPlayed ? " · " + home.dateText(continueCard.g.lastPlayed) : "")) : ""; elide: Text.ElideRight; color: Theme.color.muted; font.family: Theme.font.family; font.pixelSize: 13 }
                            Item { width: 1; height: 4 }
                            Rectangle {
                                width: playText.implicitWidth + 44; height: 38; radius: 12
                                color: playMa.containsMouse ? Theme.color.accentLight : Theme.color.accent
                                Text { id: playText; anchors.centerIn: parent; text: continueCard.g && continueCard.g.running ? qsTr("Jugando") : qsTr("Jugar"); color: Theme.color.accentInk; font.family: Theme.font.family; font.pixelSize: 14; font.weight: Font.Bold }
                                MouseArea { id: playMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; enabled: !!continueCard.g && !continueCard.g.running; onClicked: home.manager.launch(continueCard.g) }
                            }
                        }
                    }
                    // descargas (o un resumen de la biblioteca si no hay ninguna)
                    GlassPanel {
                        id: dlCard
                        readonly property var jobs: home.manager.activeInstalls || []
                        // Solo mide lo que necesita: una fila (biblioteca) o la cabecera y hasta dos descargas.
                        width: sideCol.cellWidth
                        height: !continueCard.visible && topRow.side ? 300 : dlColumn.implicitHeight + 2 * 16
                        backdrop: home.backdrop
                        backdropRect: home.backdropRectOf(dlCard)
                        Item {          // sin descargas: «n juegos · n favoritos   Ver todo» en una sola fila
                            visible: !dlCard.jobs.length
                            anchors { left: parent.left; right: parent.right; verticalCenter: parent.verticalCenter; leftMargin: 18; rightMargin: 18 }
                            height: 24
                            Row {
                                anchors.verticalCenter: parent.verticalCenter
                                spacing: 8
                                LucideIcon { anchors.verticalCenter: parent.verticalCenter; width: 18; height: 18; name: "gamepad-2"; color: Theme.color.soft }
                                Text {
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: qsTr("%1 juegos · %2 favoritos").arg((home.api.games || []).filter(g => !g.hidden).length).arg((home.api.games || []).filter(g => g.fav && !g.hidden).length)
                                    color: Theme.color.ink; font.family: Theme.font.family; font.pixelSize: 15; font.weight: Font.DemiBold
                                }
                            }
                            Text {
                                anchors { right: parent.right; verticalCenter: parent.verticalCenter }
                                text: qsTr("Ver todo"); color: libMa.containsMouse ? Theme.color.ink : Theme.color.accentLight
                                font.family: Theme.font.family; font.pixelSize: 14; font.weight: Font.Bold
                                MouseArea { id: libMa; anchors.fill: parent; anchors.margins: -6; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: home.manager.selectPage("library") }
                            }
                        }
                        Column {
                            id: dlColumn
                            anchors { left: parent.left; right: parent.right; top: parent.top; margins: 16; leftMargin: 18; rightMargin: 18 }
                            spacing: 9
                            Item {
                                visible: dlCard.jobs.length > 0
                                width: parent.width; height: 18
                                Text { text: qsTr("Descargas"); color: Theme.color.muted; font.family: Theme.font.family; font.pixelSize: 13 }
                                Text {
                                    anchors.right: parent.right
                                    text: qsTr("Ver todo"); color: Theme.color.accentLight; font.family: Theme.font.family; font.pixelSize: 13; font.weight: Font.Bold
                                    MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: home.manager.selectPage("installs") }
                                }
                            }
                            Repeater {
                                model: dlCard.jobs.slice(0, 2)
                                delegate: Column {
                                    id: job
                                    required property var modelData
                                    width: parent.width; spacing: 6
                                    Item {
                                        width: parent.width; height: 18
                                        Text { anchors { left: parent.left; right: jobPct.left; rightMargin: 8 } text: job.modelData.name || ""; elide: Text.ElideRight; color: Theme.color.ink; font.family: Theme.font.family; font.pixelSize: 14; font.weight: Font.DemiBold }
                                        Text { id: jobPct; anchors.right: parent.right; text: job.modelData.status === "queued" ? qsTr("En cola") : Math.round(Number(job.modelData.progress || 0)) + " %"; color: Theme.color.muted; font.family: Theme.font.family; font.pixelSize: 14 }
                                    }
                                    Rectangle {
                                        width: parent.width; height: 6; radius: 3; color: "#1FFFFFFF"
                                        Rectangle { width: parent.width * Math.max(0, Math.min(1, Number(job.modelData.progress || 0) / 100)); height: parent.height; radius: 3; color: Theme.color.accent }
                                    }
                                }
                            }
                            Item { visible: !dlCard.jobs.length; width: 1; height: 24 }     // alto de la fila de la biblioteca
                        }
                    }
                }
            }

            // ---------------- novedades de tus tiendas
            Flow {
                width: parent.width
                spacing: 8
                Text { height: 34; verticalAlignment: Text.AlignVCenter; text: qsTr("Novedades de tus tiendas"); color: Theme.color.ink; font.family: Theme.font.display; font.pixelSize: Theme.font.size.heading; font.weight: Font.Bold; rightPadding: 12 }
                Repeater {
                    model: home.stores
                    delegate: Rectangle {
                        id: chip
                        required property var modelData
                        readonly property bool on: home.storeFilter === modelData.k
                        height: 34; width: chipRow.implicitWidth + 26; radius: 12
                        color: on ? Theme.color.accentSoft : (chipMa.containsMouse ? Theme.color.glassFill : "#0FFFFFFF")
                        border.color: on ? Theme.color.accent : Theme.color.glassBorder
                        Row { id: chipRow; anchors.centerIn: parent; spacing: 7
                            Rectangle { visible: chip.modelData.k !== "all"; anchors.verticalCenter: parent.verticalCenter; width: 8; height: 8; radius: 3; color: home.storeColor(chip.modelData.k) }
                            Text { text: chip.modelData.l; color: chip.on ? Theme.color.accentLight : Theme.color.soft; font.family: Theme.font.family; font.pixelSize: 13; font.weight: Font.DemiBold } }
                        MouseArea { id: chipMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: { home.storeFilter = chip.modelData.k; home.featuredIndex = 0 } }
                    }
                }
                Text {
                    height: 34; verticalAlignment: Text.AlignVCenter; leftPadding: 8
                    visible: home.dealsUpdated > 0
                    text: home.loading ? qsTr("Actualizando…") : qsTr("Actualizado a las %1").arg(new Date(home.dealsUpdated * 1000).toLocaleTimeString(Qt.locale(home.api.language === "en" ? "en_US" : "es_CO"), "h:mm ap"))
                    color: Theme.color.muted; font.family: Theme.font.family; font.pixelSize: 12
                }
            }

            Text {
                visible: home.sections.length === 0
                text: home.loading ? qsTr("Cargando novedades…") : qsTr("No hay novedades para esta tienda por ahora.")
                color: Theme.color.muted; font.family: Theme.font.family; font.pixelSize: 15
            }

            Repeater {
                model: home.sections
                delegate: Column {
                    id: homeSection
                    required property var modelData
                    // Cuadrícula como la del Catálogo: mínimo fijo, crecen hasta llenar el ancho, máx. 6 por fila.
                    readonly property var grid: Theme.cardGrid(width, Theme.size.newsCardMinWidth, Theme.size.newsCardMaxColumns, Theme.size.newsCardGap)
                    readonly property int cardHeight: Math.round(grid.width * 0.43) + 104
                    readonly property bool expanded: !!home.expanded[modelData.key]
                    readonly property int shown: expanded ? modelData.items.length : Math.min(modelData.items.length, grid.columns * 2)
                    width: body.width
                    spacing: 12
                    Item {
                        width: parent.width; height: 26
                        Row {
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: 10
                            Text { id: sectionTitle; text: homeSection.modelData.title; color: Theme.color.ink; font.family: Theme.font.family; font.pixelSize: 18; font.weight: Font.Bold }
                            Text { anchors.baseline: sectionTitle.baseline; text: String(homeSection.modelData.items.length); color: Theme.color.muted; font.family: Theme.font.numeric; font.pixelSize: 15; font.weight: Font.DemiBold }
                        }
                        Text {
                            visible: homeSection.modelData.items.length > homeSection.grid.columns * 2
                            anchors { right: parent.right; verticalCenter: parent.verticalCenter }
                            text: homeSection.expanded ? qsTr("Ver menos") : qsTr("Ver todo (%1)").arg(homeSection.modelData.items.length)
                            color: moreMa.containsMouse ? Theme.color.ink : Theme.color.accentLight
                            font.family: Theme.font.family; font.pixelSize: 13; font.weight: Font.DemiBold
                            MouseArea {
                                id: moreMa
                                anchors.fill: parent; anchors.margins: -6
                                hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    const next = Object.assign({}, home.expanded)
                                    next[homeSection.modelData.key] = !homeSection.expanded
                                    home.expanded = next
                                }
                            }
                        }
                    }
                    Grid {
                        columns: homeSection.grid.columns
                        columnSpacing: Theme.size.newsCardGap
                        rowSpacing: Theme.size.newsCardGap
                        Repeater {
                            model: homeSection.modelData.items.slice(0, homeSection.shown)
                            delegate: Rectangle {
                                id: card
                                required property var modelData
                                readonly property int artHeight: Math.round(width * 0.43)
                                width: homeSection.grid.width; height: homeSection.cardHeight; radius: 18
                                color: cardMa.containsMouse ? "#17FFFFFF" : Theme.color.glassFill
                                border.color: cardMa.containsMouse ? Theme.color.accent : Theme.color.glassBorder
                                Item {      // arte con solo las esquinas de arriba redondeadas
                                    id: art
                                    x: 1; y: 1
                                    width: parent.width - 2; height: card.artHeight
                                    clip: true
                                    Rectangle { width: parent.width; height: parent.height + 17; radius: 17; color: "#141E2B" }
                                    FadedImage { width: parent.width; height: parent.height + 17; source: card.modelData.artwork || ""; cornerRadius: 17 }
                                    Rectangle { anchors { left: parent.left; right: parent.right; bottom: parent.bottom } height: 1; color: Theme.color.glassBorder }
                                    Rectangle {
                                        x: 8; y: 8; height: 22; width: artStore.implicitWidth + 16; radius: 11
                                        color: "#A605090F"; border.color: "#2EFFFFFF"
                                        Row { id: artStore; anchors.centerIn: parent; spacing: 6
                                            Rectangle { anchors.verticalCenter: parent.verticalCenter; width: 7; height: 7; radius: 2; color: home.storeColor(card.modelData.source) }
                                            Text { text: home.storeName(card.modelData.source); color: Theme.color.ink; font.family: Theme.font.family; font.pixelSize: 11; font.weight: Font.Bold } }
                                    }
                                    Rectangle {
                                        anchors { right: parent.right; top: parent.top; margins: 8 }
                                        height: 22; width: badgeText.implicitWidth + 16; radius: 11
                                        color: home.kindColor(card.modelData)
                                        Text { id: badgeText; anchors.centerIn: parent; text: home.kindBadge(card.modelData); color: Theme.color.accentInk; font.family: Theme.font.family; font.pixelSize: 11; font.weight: Font.ExtraBold }
                                    }
                                }
                                Column {
                                    anchors { left: parent.left; right: parent.right; top: art.bottom; margins: 14; topMargin: 11 }
                                    spacing: 4
                                    Text { width: parent.width; text: card.modelData.title; elide: Text.ElideRight; color: Theme.color.ink; font.family: Theme.font.family; font.pixelSize: 15; font.weight: Font.Bold }
                                    Text { width: parent.width; text: home.subtitle(card.modelData); elide: Text.ElideRight; color: Theme.color.muted; font.family: Theme.font.family; font.pixelSize: 12 }
                                }
                                Row {
                                    id: priceRow
                                    anchors { left: parent.left; right: action.left; rightMargin: 8; bottom: parent.bottom; margins: 14 }
                                    spacing: 6
                                    clip: true
                                    Text { id: nowPrice; anchors.verticalCenter: parent.verticalCenter; text: card.modelData.price || ""; color: Theme.color.ink; font.family: Theme.font.family; font.pixelSize: 14; font.weight: Font.Bold }
                                    // el precio anterior solo si cabe entero (con monedas de textos largos no se corta a medias)
                                    Text { anchors.verticalCenter: parent.verticalCenter; visible: card.modelData.kind === "deal" && !!card.modelData.originalPrice && nowPrice.implicitWidth + 6 + implicitWidth <= priceRow.width
                                           text: card.modelData.originalPrice || ""; color: Theme.color.muted; font.family: Theme.font.family; font.pixelSize: 11; font.strikeout: true }
                                }
                                Rectangle {
                                    id: action
                                    anchors { right: parent.right; bottom: parent.bottom; margins: 12 }
                                    height: 30; width: actionText.implicitWidth + 26; radius: 10
                                    color: cardMa.containsMouse ? Theme.color.accent : "#14FFFFFF"
                                    border.color: cardMa.containsMouse ? "transparent" : "#2EFFFFFF"
                                    Text { id: actionText; anchors.centerIn: parent; text: home.actionLabel(card.modelData); color: cardMa.containsMouse ? Theme.color.accentInk : Theme.color.ink; font.family: Theme.font.family; font.pixelSize: 12; font.weight: Font.DemiBold }
                                }
                                MouseArea { id: cardMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: home.open(card.modelData) }
                            }
                        }
                    }
                }
            }
            Item { width: 1; height: 8 }
        }
    }
}

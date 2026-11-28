pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls
import "Theme.js" as Theme

/** Biblioteca de Desktop (rediseño D, fase 2) en tres paneles de cristal con anchos fijos:
 *  Instalados (lista con su propio buscador), Catálogo (CatalogPanel, antes «Explorar») y la ficha del
 *  juego. La ficha está oculta hasta elegir un juego; con ella cerrada el Catálogo se ensancha. Por debajo
 *  de Theme.breakpoint.threePanels la ficha flota sobre el Catálogo en vez de quitarle espacio. */
Item {
    id: ml
    property var manager: null
    property var api: null
    property var stores: null                // ManagerStores: datos de las tiendas para el Catálogo
    property Item backdrop: null             // fondo ambiental que desenfocan los paneles
    property bool detailOpen: false
    readonly property bool detailShown: detailOpen && current !== null
    readonly property bool detailFloating: width < Theme.breakpoint.threePanels
    property alias catalog: catalog
    property string chosenCollection: ""        // "" (automática) | all | fav | recent
    readonly property string collection: chosenCollection ||
        (search.trim() ? "all" : (libraryGames.some(g => g.fav) ? "fav" : "all"))
    readonly property var libraryGames: api?.games || []
    readonly property var visibleLibrary: libraryGames.filter(g => !g.hidden || manager.showHiddenGames)
    readonly property var gameById: new Map(libraryGames.map(g => [g.id, g]))
    // La lista de IDs permanece estable al actualizar sesiones u otros campos.
    readonly property string installedOrder: JSON.stringify(visibleLibrary
        .filter(g => (g.ports || []).some(port => port.canLaunch))
        .sort((a, b) => Number(b.added || 0) - Number(a.added || 0) || a.name.localeCompare(b.name) || a.id.localeCompare(b.id))
        .map(g => g.id))
    readonly property var installedIds: JSON.parse(installedOrder)
    property string search: ""
    property string selId: ""
    property string tab: "summary"           // summary | saves | manage
    property var activity: null
    readonly property string font: "Hanken Grotesk"

    function norm(t) { return (t || "").toString().toLowerCase() }
    function platKey(g) { return norm(g.platform) }
    function platName(g) {
        const names = { pc: "PC", n64: "Nintendo 64", sw1: "Nintendo Switch", sw2: "Nintendo Switch 2", ps1: "PlayStation", ps2: "PlayStation 2",
                        ps3: "PlayStation 3", ps4: "PlayStation 4", ps5: "PlayStation 5", psp: "PSP", nes: "NES", snes: "Super Nintendo",
                        gb: "Game Boy", gbc: "Game Boy Color", gba: "Game Boy Advance", nds: "Nintendo DS", "3ds": "Nintendo 3DS",
                        gcwii: "GameCube / Wii", wiiu: "Wii U", genesis: "Mega Drive", dreamcast: "Dreamcast", saturn: "Saturn" }
        return names[platKey(g)] || g.platform || g.src || qsTr("Juegos")
    }
    function lastOf(g) { return Number(g.lastPlayed || (g.played || {}).last || 0) }
    readonly property var visibleGames: {
        const q = norm(search).trim()
        let list = visibleLibrary.filter(function(g) {
            if (q && norm(g.name + " " + (g.sub || "")).indexOf(q) < 0) return false
            if (collection === "fav") return !!g.fav
            if (collection === "recent") return lastOf(g) > 0
            return true
        })
        if (collection === "recent") list.sort(function(a, b) { return lastOf(b) - lastOf(a) })
        else list.sort(function(a, b) {
            const p = platName(a).localeCompare(platName(b)); if (p) return p
            return norm(a.name).localeCompare(norm(b.name))
        })
        return list.map(function(g) { return { game: g, plat: collection === "recent" ? qsTr("Jugados recientemente") : platName(g) } })
    }
    readonly property var current: gameById.get(selId) || null
    onVisibleGamesChanged: {
        const game = gameById.get(selId)
        if (!game || (game.hidden && !manager.showHiddenGames))
            selId = visibleGames.length ? visibleGames[0].game.id : (visibleLibrary[0]?.id || "")
    }
    // reveal = false: solo cambia la selección (búsqueda, colecciones) sin abrir la ficha.
    function selectGame(id, reveal) {
        selId = id
        if (reveal !== false) detailOpen = true
        tab = "summary"
        if (summaryScroll.contentItem) summaryScroll.contentItem.contentY = 0
    }
    onSearchChanged: if (search.trim() && visibleGames.length && !visibleGames.some(row => row.game.id === selId))
        selectGame(visibleGames[0].game.id, false)
    function closeDetail() { detailOpen = false }
    function backdropRectOf(item) {
        if (!backdrop || !item) return Qt.rect(0, 0, 0, 0)
        void (item.x + item.y + item.width + item.height + ml.x + ml.y + ml.width + ml.height)
        const p = item.mapToItem(backdrop, 0, 0)
        return Qt.rect(p.x, p.y, item.width, item.height)
    }
    onSelIdChanged: {
        activity = null
        tab = "summary"
        actDelay.restart()
    }
    Timer {
        id: actDelay
        interval: 200
        onTriggered: {
            const id = ml.selId
            if (!id) return
            api.call("GET", "/game/activity?id=" + encodeURIComponent(id), function(status, data) { if (status === 200 && ml.selId === id) ml.activity = data })
        }
    }
    function duration(secs) {
        const m = Math.round(secs / 60)
        return secs < 1 ? "—" : secs < 60 ? Math.round(secs) + " s" : m < 60 ? m + " min" : Math.floor(m / 60) + " h " + (m % 60) + " min"
    }
    function dateText(ts) {
        return ts > 0 ? new Date(ts * 1000).toLocaleDateString(Qt.locale(api.language === "en" ? "en_US" : "es_CO"), "d MMM yyyy") : "—"
    }


    // ---------------- panel izquierdo: Instalados
    GlassPanel {
        id: left
        anchors { left: parent.left; top: parent.top; bottom: parent.bottom
                  leftMargin: Theme.size.pageMargin; topMargin: Theme.size.panelGap; bottomMargin: Theme.size.pageMargin }
        width: Theme.size.panelInstalled
        backdrop: ml.backdrop
        backdropRect: ml.backdropRectOf(left)
        Text { x: 18; y: 16; text: qsTr("Instalados"); color: Theme.color.ink; font.family: ml.font; font.pixelSize: Theme.font.size.title + 3; font.weight: Font.Bold }
        Text { anchors { right: parent.right; rightMargin: 18 } y: 21; text: String(ml.visibleLibrary.length); color: Theme.color.muted; font.family: Theme.font.numeric; font.pixelSize: Theme.font.size.bodyLarge; font.weight: Font.DemiBold }
        TextField {
            id: searchField
            anchors { left: parent.left; right: parent.right; top: parent.top; leftMargin: 14; rightMargin: 14; topMargin: 50 }
            height: Theme.size.control
            placeholderText: qsTr("Buscar en instalados")
            placeholderTextColor: Theme.color.muted
            text: ml.search
            onTextChanged: ml.search = text
            Keys.onEscapePressed: text = ""
            color: Theme.color.ink; font.family: ml.font; font.pixelSize: Theme.font.size.body
            leftPadding: 38
            background: Rectangle { radius: Theme.radius.md; color: Theme.color.inset; border.color: searchField.activeFocus ? Theme.color.accent : Theme.color.glassBorder
                LucideIcon { x: 12; anchors.verticalCenter: parent.verticalCenter; width: 16; height: 16; name: "search"; color: Theme.color.muted } }
        }
        Flow {
            id: collections
            anchors { left: parent.left; right: parent.right; top: searchField.bottom; topMargin: 10; leftMargin: 14; rightMargin: 14 }
            spacing: 6
            Repeater {
                model: [{ k: "all", l: qsTr("Todos") }, { k: "fav", l: qsTr("Favoritos") }, { k: "recent", l: qsTr("Recientes") }]
                delegate: Rectangle {
                    id: chip
                    required property var modelData
                    readonly property bool on: ml.collection === modelData.k
                    height: Theme.size.chip + 2; width: chipText.implicitWidth + 24; radius: height / 2
                    color: on ? Theme.color.accentSoft : (chipMa.containsMouse ? Theme.color.glassFill : "transparent")
                    border.color: on ? Theme.color.accent : Theme.color.glassBorder
                    Text { id: chipText; anchors.centerIn: parent; text: chip.modelData.l; color: chip.on ? Theme.color.accentLight : Theme.color.soft; font.family: ml.font; font.pixelSize: Theme.font.size.small; font.weight: Font.DemiBold }
                    MouseArea { id: chipMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: {
                            ml.chosenCollection = chip.modelData.k
                            if (ml.visibleGames.length && !ml.visibleGames.some(row => row.game.id === ml.selId))
                                ml.selectGame(ml.visibleGames[0].game.id, false)
                        } }
                }
            }
        }
        ListView {
            id: gameList
            anchors { left: parent.left; right: parent.right; top: collections.bottom; bottom: actions.top; topMargin: 8; bottomMargin: 6; leftMargin: 6; rightMargin: 6 }
            clip: true
            model: ml.visibleGames
            boundsBehavior: Flickable.StopAtBounds
            ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }
            section.property: "plat"
            section.criteria: ViewSection.FullString
            section.delegate: Item {
                id: sec
                required property string section
                width: gameList.width; height: 30
                Text { anchors { left: parent.left; leftMargin: 10; bottom: parent.bottom; bottomMargin: 6 } text: sec.section.toUpperCase(); color: Theme.color.muted; font.family: ml.font; font.pixelSize: Theme.font.size.caption; font.weight: Font.DemiBold; font.letterSpacing: 0.8 }
            }
            delegate: Rectangle {
                id: row
                required property var modelData
                readonly property var g: modelData.game
                readonly property bool on: g.id === ml.selId && ml.detailShown
                width: gameList.width; height: Theme.size.listRow; radius: Theme.radius.sm
                color: on ? Theme.color.accentSoft : (rowMa.containsMouse ? Theme.color.glassFill : "transparent")
                Row {
                    anchors { left: parent.left; leftMargin: 8; right: parent.right; rightMargin: 8; verticalCenter: parent.verticalCenter }
                    spacing: 10
                    Item {
                        width: Theme.size.listThumb; height: Theme.size.listThumb; anchors.verticalCenter: parent.verticalCenter
                        Rectangle { anchors.fill: parent; radius: 9; color: Theme.color.inset }
                        FadedImage { anchors.fill: parent; source: row.g.portada || ""; cornerRadius: 9 }
                    }
                    Text { anchors.verticalCenter: parent.verticalCenter; width: parent.width - Theme.size.listThumb - 10; text: row.g.name + (row.g.fav ? "  ★" : "") + (row.g.portAvailable ? "  ⬇" : (row.g.updateAvailable ? "  ⟳" : "")); elide: Text.ElideRight
                        color: row.g.hidden ? Theme.color.muted : Theme.color.ink; font.family: ml.font; font.pixelSize: Theme.font.size.bodyLarge + 1; font.weight: row.on ? Font.DemiBold : Font.Normal }
                }
                MouseArea { id: rowMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; acceptedButtons: Qt.LeftButton | Qt.RightButton
                    onClicked: mouse => { if (mouse.button === Qt.RightButton) manager.openGameMenu(row.g); else ml.selectGame(row.g.id) }
                    onDoubleClicked: mouse => { if (mouse.button === Qt.LeftButton) manager.launch(row.g) } }
            }
            Text { visible: ml.visibleGames.length === 0; anchors.centerIn: parent; width: parent.width - 40; horizontalAlignment: Text.AlignHCenter; wrapMode: Text.WordWrap
                text: ml.search ? qsTr("Ningún juego coincide.") : ml.collection === "fav" ? qsTr("Aún no tienes favoritos.") : qsTr("Añade juegos para verlos aquí."); color: Theme.color.muted; font.family: ml.font; font.pixelSize: Theme.font.size.body }
        }
        Row {
            id: actions
            anchors { left: parent.left; right: parent.right; bottom: parent.bottom; margins: 12 }
            spacing: 6
            Repeater {
                model: [
                    { icon: "plus", tip: qsTr("Añadir juego"), act: "add" },
                    { icon: "search", tip: qsTr("Escanear ROMs"), act: "roms" },
                    { icon: "refresh-cw", tip: qsTr("Actualizar biblioteca"), act: "refresh" },
                    { icon: manager.showHiddenGames ? "eye" : "eye-off", tip: manager.showHiddenGames ? qsTr("Ocultos incluidos") : qsTr("Mostrar juegos ocultos"), act: "hidden" }
                ]
                delegate: Rectangle {
                    id: ab
                    required property var modelData
                    width: (actions.width - 18) / 4; height: Theme.size.control; radius: Theme.radius.sm
                    color: ab.modelData.act === "add" ? Theme.color.accent : (abMa.containsMouse ? Theme.color.glassFillStrong : Theme.color.inset)
                    border.color: ab.modelData.act === "add" ? "transparent" : Theme.color.glassBorder
                    LucideIcon { anchors.centerIn: parent; width: 17; height: 17; name: ab.modelData.icon; color: ab.modelData.act === "add" ? Theme.color.accentInk : Theme.color.ink }
                    ToolTip.visible: abMa.containsMouse; ToolTip.text: ab.modelData.tip; ToolTip.delay: 400
                    MouseArea { id: abMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: manager.libraryAction(ab.modelData.act) }
                }
            }
        }
    }

    // ---------------- centro: Catálogo
    CatalogPanel {
        id: catalog
        anchors { left: left.right; top: left.top; bottom: left.bottom; leftMargin: Theme.size.panelGap }
        width: Theme.catalogWidth(ml.width, ml.detailShown)
        manager: ml.manager
        stores: ml.stores
        backdrop: ml.backdrop
        backdropRect: ml.backdropRectOf(catalog)
        onLocalGameChosen: game => ml.selectGame(game.id)
    }

    // ---------------- derecha: ficha del juego (oculta hasta elegir uno; flotante bajo 1360 px)
    Rectangle {      // sombra de la ficha flotante
        visible: detail.visible && ml.detailFloating
        anchors.fill: detail; anchors.margins: -1
        radius: Theme.radius.xl + 1
        color: "transparent"
        border.color: "#66000000"; border.width: 1
        z: 4
    }
    GlassPanel {
        id: detail
        anchors { right: parent.right; top: left.top; bottom: left.bottom; rightMargin: Theme.size.pageMargin }
        width: Theme.size.panelDetail
        visible: ml.detailShown
        z: 5
        // Casi opaca siempre (anclada o flotante): el texto de la ficha se lee sobre un fondo parejo.
        strong: true
        glass: false
        fill: "#D90A0F17"
        backdrop: ml.backdrop
        backdropRect: ml.backdropRectOf(detail)

        Item {
            id: page
            anchors.fill: parent
            readonly property var g: ml.current
            Item {
                id: hero
                anchors { left: parent.left; right: parent.right; top: parent.top }
                height: Theme.size.detailArtHeight
                Item {      // arte con solo las esquinas superiores redondeadas
                    anchors.fill: parent
                    clip: true
                    FadedImage {
                        width: parent.width; height: parent.height + Theme.radius.xl
                        source: page.g ? (page.g.fondo || page.g.portada || "") : ""
                        cornerRadius: Theme.radius.xl
                        fadeBottom: 0.65
                        alignX: 0.5
                    }
                    Rectangle { width: parent.width; height: parent.height + Theme.radius.xl; radius: Theme.radius.xl
                        gradient: Gradient { GradientStop { position: 0.3; color: "#000B0F14" } GradientStop { position: 0.88; color: "#D90B0F14" } } }
                }
                Rectangle {      // cerrar la ficha
                    anchors { right: parent.right; top: parent.top; margins: 12 }
                    width: 32; height: 32; radius: 16
                    color: closeMa.containsMouse ? "#B3000000" : "#80000000"
                    border.color: Theme.color.glassBorder
                    LucideIcon { anchors.centerIn: parent; width: 16; height: 16; name: "x"; color: Theme.color.ink }
                    ToolTip.visible: closeMa.containsMouse; ToolTip.text: qsTr("Cerrar ficha"); ToolTip.delay: 400
                    MouseArea { id: closeMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: ml.closeDetail() }
                }
                Column {
                    anchors { left: parent.left; bottom: parent.bottom; leftMargin: 20; bottomMargin: 14 }
                    width: parent.width - 40
                    spacing: 4
                    Row {
                        spacing: 8
                        PlatIcon { anchors.verticalCenter: parent.verticalCenter; key: page.g ? ml.platKey(page.g) : ""; size: 18; color: Theme.color.soft }
                        Text { anchors.verticalCenter: parent.verticalCenter; text: page.g ? (ml.platName(page.g) + (page.g.variant || page.g.src ? " · " + (page.g.variant || page.g.src) : "")).toUpperCase() : ""
                            color: Theme.color.soft; font.family: ml.font; font.pixelSize: Theme.font.size.caption + 1; font.letterSpacing: 1.1 }
                    }
                    Text { width: parent.width; text: page.g ? page.g.name : ""; elide: Text.ElideRight; maximumLineCount: 2; wrapMode: Text.WordWrap
                        color: Theme.color.inkStrong; font.family: ml.font; font.pixelSize: Theme.font.size.heading + 2; font.weight: Font.Bold }
                }
            }
            Item {      // barra de acción: Jugar + favorito; debajo, última sesión y tiempo jugado
                id: playBar
                anchors { left: parent.left; right: parent.right; top: hero.bottom; leftMargin: 20; rightMargin: 20; topMargin: 6 }
                height: Theme.size.controlLarge + 56
                Rectangle {
                    id: playButton
                    readonly property bool offer: !!page.g && !!page.g.portAvailable
                    anchors { left: parent.left; right: favButton.left; rightMargin: 10; top: parent.top }
                    height: Theme.size.controlLarge; radius: Theme.radius.md
                    color: offer ? Theme.color.accent : (page.g && page.g.running ? Theme.color.inset : "#2E8B57")
                    Row { anchors.centerIn: parent; spacing: 8
                        LucideIcon { anchors.verticalCenter: parent.verticalCenter; width: 18; height: 18; name: playButton.offer ? "download" : "play"; color: playButton.offer ? Theme.color.accentInk : "white" }
                        Text { anchors.verticalCenter: parent.verticalCenter; color: playButton.offer ? Theme.color.accentInk : "white"; font.family: ml.font; font.pixelSize: Theme.font.size.title; font.weight: Font.DemiBold
                               text: playButton.offer ? qsTr("Instalar port") : (page.g && page.g.running ? qsTr("Jugando") : qsTr("Jugar")) } }
                    MouseArea { anchors.fill: parent; enabled: playButton.offer || (!!page.g && !page.g.running); cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
                        onClicked: playButton.offer ? manager.installPortFor(page.g) : manager.launch(page.g) }
                }
                Rectangle {
                    id: favButton
                    anchors { right: parent.right; top: parent.top }
                    width: Theme.size.controlLarge; height: width; radius: Theme.radius.md
                    color: favMa.containsMouse ? Theme.color.glassFillStrong : Theme.color.inset
                    border.color: Theme.color.glassBorder
                    LucideIcon { anchors.centerIn: parent; width: 20; height: 20; name: "star"; color: page.g && page.g.fav ? Theme.color.favorite : Theme.color.muted }
                    ToolTip.visible: favMa.containsMouse; ToolTip.text: page.g && page.g.fav ? qsTr("Quitar de favoritos") : qsTr("Añadir a favoritos"); ToolTip.delay: 400
                    MouseArea { id: favMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: api.toggleFav(page.g) }
                }
                Row {
                    anchors { left: parent.left; bottom: parent.bottom }
                    spacing: 28
                    Column { spacing: 2
                        Text { text: qsTr("Última sesión"); color: Theme.color.muted; font.family: ml.font; font.pixelSize: Theme.font.size.small }
                        Text { text: ml.dateText(ml.activity ? ml.activity.lastPlayed : (page.g ? ml.lastOf(page.g) : 0)); color: Theme.color.ink; font.family: ml.font; font.pixelSize: Theme.font.size.bodyLarge; font.weight: Font.DemiBold } }
                    Column { spacing: 2
                        Text { text: qsTr("Tiempo jugado"); color: Theme.color.muted; font.family: ml.font; font.pixelSize: Theme.font.size.small }
                        Text { text: ml.activity && ml.activity.totalSecs > 0 ? ml.duration(ml.activity.totalSecs) : "—"; color: Theme.color.ink; font.family: ml.font; font.pixelSize: Theme.font.size.bodyLarge; font.weight: Font.DemiBold } }
                }
            }
            Row {      // pestañas
                id: tabs
                anchors { left: parent.left; top: playBar.bottom; leftMargin: 20; topMargin: 14 }
                spacing: 20
                Repeater {
                    model: [{ k: "summary", l: qsTr("Resumen") }, { k: "saves", l: qsTr("Partidas") }, { k: "manage", l: qsTr("Administrar") }]
                    delegate: Item {
                        id: tb
                        required property var modelData
                        readonly property bool on: ml.tab === modelData.k
                        width: tbText.implicitWidth; height: 30
                        Text { id: tbText; text: tb.modelData.l; color: tb.on ? Theme.color.ink : Theme.color.muted; font.family: ml.font; font.pixelSize: Theme.font.size.bodyLarge; font.weight: tb.on ? Font.DemiBold : Font.Normal }
                        Rectangle { anchors { left: parent.left; right: parent.right; bottom: parent.bottom } height: 2; radius: 1; color: Theme.color.accent; visible: tb.on }
                        MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: ml.tab = tb.modelData.k }
                    }
                }
            }
            Rectangle { anchors { left: parent.left; right: parent.right; top: tabs.bottom } height: 1; color: Theme.color.glassBorder }
            Item {
                anchors { left: parent.left; right: parent.right; top: tabs.bottom; bottom: parent.bottom; margins: 20; topMargin: 14 }
                clip: true
                // Resumen
                ScrollView {
                    id: summaryScroll
                    anchors.fill: parent
                    visible: ml.tab === "summary"
                    contentWidth: availableWidth
                    ScrollBar.horizontal.policy: ScrollBar.AlwaysOff
                    Column {
                        width: summaryScroll.availableWidth
                        spacing: 12
                        bottomPadding: 12
                        Rectangle {      // actualización disponible
                            visible: !!page.g && !!page.g.updateAvailable && !page.g.portAvailable
                            width: parent.width; height: updNote.implicitHeight + 24; radius: 12; color: "#2F2A1B"; border.color: "#8A6D2F"
                            Text { id: updNote; anchors { left: parent.left; right: updBtn.left; verticalCenter: parent.verticalCenter; margins: 16 }
                                wrapMode: Text.WordWrap; color: manager.ink; font.family: ml.font; font.pixelSize: 15
                                text: page.g && page.g.updateAvailable ? qsTr("Actualización disponible: %1 → %2. Se conservan tus partidas y los datos del juego.").arg(page.g.updateAvailable.current || "?").arg(page.g.updateAvailable.version) : "" }
                            Rectangle { id: updBtn; anchors { right: parent.right; rightMargin: 16; verticalCenter: parent.verticalCenter }
                                width: 130; height: 38; radius: 10; color: page.g && page.g.running ? manager.surface2 : "#B8862F"
                                Text { anchors.centerIn: parent; text: qsTr("Actualizar"); color: "white"; font.family: ml.font; font.pixelSize: 15; font.weight: Font.DemiBold }
                                MouseArea { anchors.fill: parent; enabled: !!page.g && !page.g.running; cursorShape: Qt.PointingHandCursor; onClicked: manager.updateFor(page.g) } }
                        }
                        Rectangle {      // port disponible
                            visible: !!page.g && !!page.g.portAvailable
                            width: parent.width; height: portNote.implicitHeight + 24; radius: 12; color: "#1F2F44"; border.color: "#3B6A99"
                            Text { id: portNote; anchors { left: parent.left; right: parent.right; verticalCenter: parent.verticalCenter; margins: 16 }
                                wrapMode: Text.WordWrap; color: manager.ink; font.family: ml.font; font.pixelSize: 15
                                text: page.g && page.g.portAvailable ? qsTr("Port disponible: %1 · %2 · licencia %3. Detectamos tu copia del juego; pulsa «Instalar port» para descargarlo y verificarlo.").arg(page.g.portAvailable.title).arg(page.g.portAvailable.version).arg(page.g.portAvailable.licenseName) : "" }
                        }
                        GameFacts {
                            width: parent.width
                            api: ml.api; game: page.g; uiScale: 1; uiFont: ml.font
                            ink: manager.ink; muted: manager.muted
                        }
                        Row {
                            spacing: 8
                            Repeater {
                                model: [
                                    { l: qsTr("Fuente"), v: page.g ? (page.g.variant || page.g.src || "—") : "—" },
                                    { l: qsTr("Consola"), v: page.g ? ml.platName(page.g) : "—" },
                                    { l: qsTr("Carpeta"), v: page.g && page.g.folder ? page.g.folder : "—" }
                                ]
                                delegate: Rectangle {
                                    id: card
                                    required property var modelData
                                    width: (summaryScroll.availableWidth - 16) / 3; height: 62; radius: Theme.radius.sm; color: Theme.color.inset; border.color: Theme.color.glassBorder
                                    Column { anchors { left: parent.left; right: parent.right; verticalCenter: parent.verticalCenter; margins: 12 } spacing: 3
                                        Text { text: card.modelData.l; color: manager.muted; font.family: ml.font; font.pixelSize: 12 }
                                        Text { width: parent.width; text: card.modelData.v; elide: Text.ElideMiddle; color: manager.ink; font.family: ml.font; font.pixelSize: 14; font.weight: Font.DemiBold } }
                                }
                            }
                        }
                        Text {      // tu copia del juego (volcado .nup o carpeta exefs+romfs que Omnia unió con este port)
                            visible: !!page.g && !!page.g.romCopy
                            width: parent.width; wrapMode: Text.WrapAnywhere; color: manager.muted; font.family: ml.font; font.pixelSize: 13
                            text: page.g && page.g.romCopy ? qsTr("Tu copia del juego: %1").arg(page.g.romCopy.path) + (page.g.romCopy.buildId ? "  ·  build " + page.g.romCopy.buildId.substring(0, 12) : "") : ""
                        }
                        Text {      // ¿la copia es la versión que acepta el port? (build ID del exefs/main contra el descriptor del port)
                            visible: !!page.g && !!page.g.romCopy && !!page.g.romCopy.compat
                            width: parent.width; wrapMode: Text.WordWrap; font.family: ml.font; font.pixelSize: 13
                            readonly property string st: page.g && page.g.romCopy && page.g.romCopy.compat ? page.g.romCopy.compat.state : ""
                            color: st === "ok" ? "#7fd69f" : (st === "mismatch" ? "#e8a24b" : manager.muted)
                            text: st === "ok" ? qsTr("Es la versión que acepta este port.")
                                : (st === "mismatch" ? qsTr("Esta copia es de otra versión (build %1); el port espera %2.").arg((page.g.romCopy.compat.found || "").substring(0, 8)).arg(page.g.romCopy.compat.expected.join(", "))
                                : qsTr("No se pudo comprobar la versión de esta copia (un archivo .nup no se lee todavía); el port espera el build %1.").arg(page.g && page.g.romCopy && page.g.romCopy.compat ? page.g.romCopy.compat.expected.join(", ") : ""))
                        }
                        Rectangle {      // el port cerró con un código que él mismo explica (exit_codes de su descriptor)
                            visible: !!page.g && !!page.g.lastExit
                            width: parent.width; height: exitNote.implicitHeight + 20; radius: 10; color: "#3A2A1E"; border.color: "#8A5A2F"
                            Text { id: exitNote; anchors { left: parent.left; right: parent.right; verticalCenter: parent.verticalCenter; margins: 14 }
                                wrapMode: Text.WordWrap; color: manager.ink; font.family: ml.font; font.pixelSize: 14
                                text: page.g && page.g.lastExit ? qsTr("La última vez, el juego se cerró con este aviso: %1").arg(page.g.lastExit.message) : "" }
                        }
                        Text {      // requisitos que declara el port (glibc, Vulkan…) y si este PC los cumple
                            visible: !!page.g && !!page.g.requirements && page.g.requirements.length > 0
                            width: parent.width; wrapMode: Text.WordWrap; font.family: ml.font; font.pixelSize: 13
                            readonly property var bad: page.g && page.g.requirements ? page.g.requirements.filter(function(r) { return r.ok === false }) : []
                            color: bad.length > 0 ? "#e8a24b" : manager.muted
                            text: page.g && page.g.requirements
                                  ? qsTr("Requisitos: %1").arg(page.g.requirements.map(function(r) { return r.label + " " + r.need + (r.ok === false ? " ✗ (este PC: " + r.have + ")" : (r.ok === true ? " ✓" : "")) }).join("  ·  "))
                                    + (bad.length > 0 ? "  " + qsTr("El juego puede no arrancar.") : "") : ""
                        }
                    }
                }
                // Partidas
                Column {
                    visible: ml.tab === "saves"
                    width: parent.width; spacing: 12
                    Text { width: parent.width; text: qsTr("Respalda las partidas guardadas o abre su carpeta."); color: manager.muted; wrapMode: Text.WordWrap; font.family: ml.font; font.pixelSize: 15 }
                    Flow {
                        width: parent.width; spacing: 10
                        Repeater {
                            model: [{ l: qsTr("Respaldar partidas"), k: "backup" }, { l: qsTr("Abrir carpeta de partidas"), k: "open" }]
                            delegate: Rectangle {
                                id: sb
                                required property var modelData
                                width: sbText.implicitWidth + 40; height: 42; radius: 10; color: Theme.color.inset; border.color: Theme.color.glassBorder
                                Text { id: sbText; anchors.centerIn: parent; text: sb.modelData.l; color: manager.ink; font.family: ml.font; font.pixelSize: 14 }
                                MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor
                                    onClicked: {
                                        if (sb.modelData.k === "backup") api.savesBackup(page.g, function(st, b) { api.notify(st === 200 ? qsTr("Respaldo creado.") : ((b && b.error) || qsTr("No se pudo respaldar."))) })
                                        else api.savesOpen(page.g, function() { })
                                    } }
                            }
                        }
                    }
                    Flow {       // carpetas que declara el port (partidas, logs, carpeta del juego…)
                        visible: !!page.g && !!page.g.folderActions && page.g.folderActions.length > 0
                        width: parent.width; spacing: 10
                        Repeater {
                            model: page.g && page.g.folderActions ? page.g.folderActions : []
                            delegate: Rectangle {
                                id: fb
                                required property var modelData
                                width: fbText.implicitWidth + 40; height: 42; radius: 10; color: Theme.color.inset; border.color: Theme.color.glassBorder
                                Text { id: fbText; anchors.centerIn: parent; text: fb.modelData.label; color: manager.ink; font.family: ml.font; font.pixelSize: 14 }
                                MouseArea { id: fbMa; anchors.fill: parent; cursorShape: Qt.PointingHandCursor; hoverEnabled: true
                                    onClicked: api.openFolder(page.g.id, fb.modelData.folder, function(st, b) { if (st !== 200) api.notify((b && b.error) || qsTr("No se pudo abrir la carpeta.")) }) }
                                ToolTip.visible: fbMa.containsMouse && fb.modelData.help !== ""; ToolTip.text: fb.modelData.help
                            }
                        }
                    }
                }
                // Administrar
                Flow {
                    visible: ml.tab === "manage"
                    width: parent.width; spacing: 10
                    Repeater {
                        model: page.g ? [
                            { l: page.g.hidden ? qsTr("Mostrar en biblioteca") : qsTr("Ocultar de la biblioteca"), k: "hide" },
                            { l: page.g.catalogSlug ? qsTr("Cambiar ficha del catálogo…") : qsTr("Vincular con el catálogo…"), k: "link" },
                            { l: qsTr("Quitar vínculo del catálogo"), k: "unlink", only: !!page.g.catalogSlug },
                            { l: qsTr("Desinstalar juego"), k: "uninstall", only: (page.g.canUninstall || page.g.installPackageId) && !page.g.running, danger: true },
                            { l: qsTr("Quitar de Omnia…"), k: "remove", danger: true }
                        ].filter(function(x) { return x.only === undefined || x.only }) : []
                        delegate: Rectangle {
                            id: mb
                            required property var modelData
                            width: mbText.implicitWidth + 40; height: 42; radius: 10
                            color: modelData.danger ? "#50343A" : Theme.color.inset
                            Text { id: mbText; anchors.centerIn: parent; text: mb.modelData.l; color: manager.ink; font.family: ml.font; font.pixelSize: 14 }
                            MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: manager.gameAction(mb.modelData.k, page.g) }
                        }
                    }
                }
            }
        }
    }
}

pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls

/** Página de Explorar del gestor: combina novedades, instalaciones recientes, filtros y el catálogo en una cuadrícula.
 * El anfitrión conserva navegación/datos; este componente recibe las referencias de composición que necesita. */
Item {
    id: explorePage
    required property var manager
    required property var api
    required property var stores
    required property real contentPad
    required property real contentTop
    readonly property var newsTheme: explorePage.manager
    readonly property var newsApi: explorePage.api
    anchors.fill: parent
    visible: explorePage.manager.page === "catalog"
    Column {
        id: exploreHeading
        x: explorePage.contentPad; y: explorePage.contentTop
        width: remoteSearch.x - x - explorePage.manager.s * 12
        spacing: explorePage.manager.s * 3
        Text {
            text: qsTranslate("OmniaManager", "Explorar"); color: explorePage.manager.ink
            font.family: "Hanken Grotesk"; font.pixelSize: explorePage.manager.s * 28; font.weight: Font.Bold
        }
        Text {
            width: parent.width
            text: qsTranslate("OmniaManager", "Ports de Omnia y juegos de tus tiendas, en un solo lugar.")
            color: explorePage.manager.muted; font.family: "Hanken Grotesk"; font.pixelSize: explorePage.manager.s * 13
            wrapMode: Text.WordWrap
        }
    }
    TextField {
        id: remoteSearch
        anchors.right: parent.right; anchors.rightMargin: explorePage.contentPad
        y: explorePage.contentTop - explorePage.manager.s * 1
        width: Math.min(parent.width * 0.43, explorePage.manager.s * 510); height: explorePage.manager.s * 36
        placeholderText: explorePage.manager.catalogLinkTargetId ? qsTranslate("OmniaManager", "Buscar una ficha para vincular") : qsTranslate("OmniaManager", "Buscar juegos, tiendas o plataformas")
        color: explorePage.manager.ink; font.family: "Hanken Grotesk"; font.pixelSize: explorePage.manager.s * 14
        onAccepted: { explorePage.manager.query = text; explorePage.manager.loadOnline(1); exploreFlick.contentY = 0 }
        background: Rectangle { radius: explorePage.manager.s * 11; color: explorePage.manager.surface2; border.color: remoteSearch.activeFocus ? "#45CFC9" : "#24FFFFFF" }
    }
    Rectangle {
        visible: !!explorePage.manager.catalogLinkTargetId
        anchors { right: parent.right; verticalCenter: remoteSearch.verticalCenter; rightMargin: explorePage.contentPad }
        width: explorePage.manager.s * 112; height: explorePage.manager.s * 34; radius: explorePage.manager.s * 11; color: explorePage.manager.surface2
        Text { anchors.centerIn: parent; text: qsTranslate("OmniaManager", "Cancelar vínculo"); color: explorePage.manager.ink; font.family: "Hanken Grotesk"; font.pixelSize: explorePage.manager.s * 11 }
        MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: explorePage.manager.cancelCatalogLink() }
    }
    Text {
        id: exploreWarning
        x: explorePage.contentPad; y: Math.max(exploreHeading.y + exploreHeading.height, remoteSearch.y + remoteSearch.height) + explorePage.manager.s * 4
        width: parent.width - explorePage.contentPad * 2
        text: explorePage.manager.onlineWarning; visible: !!text
        color: "#E8B86D"; font.family: "Hanken Grotesk"; font.pixelSize: explorePage.manager.s * 11; elide: Text.ElideRight
    }
    Button {
        anchors { right: parent.right; rightMargin: explorePage.contentPad; top: remoteSearch.bottom; topMargin: explorePage.manager.s * 5 }
        z: 3
        text: qsTranslate("OmniaManager", "Cuentas de tiendas")
        onClicked: explorePage.manager.openStoreSettings()
    }
    Flickable {
        id: exploreFlick
        anchors { left: parent.left; right: parent.right; top: exploreWarning.bottom; bottom: parent.bottom }
        anchors.topMargin: explorePage.manager.s * 40
        clip: true
        contentWidth: width
        contentHeight: exploreContent.height
        boundsBehavior: Flickable.StopAtBounds
        Column {
            id: exploreContent
            x: explorePage.contentPad
            width: exploreFlick.width - explorePage.contentPad * 2
            spacing: explorePage.manager.s * 17

            ManagerStoreNews {
                width: parent.width
                manager: explorePage.newsTheme
                api: explorePage.newsApi
                active: explorePage.visible
                onOpenGame: game => explorePage.manager.openCatalogDetail(game)
            }

            Column {
                width: parent.width
                spacing: explorePage.manager.s * 7
                Item {
                    width: parent.width; height: explorePage.manager.s * 24
                    Text { anchors.verticalCenter: parent.verticalCenter; text: qsTranslate("OmniaManager", "Últimos instalados"); color: explorePage.manager.ink; font.family: "Hanken Grotesk"; font.pixelSize: explorePage.manager.s * 17; font.weight: Font.DemiBold }
                    Rectangle {
                        anchors { right: parent.right; verticalCenter: parent.verticalCenter }
                        width: moreInstalled.implicitWidth + explorePage.manager.s * 22; height: explorePage.manager.s * 25; radius: height / 2
                        color: moreInstalledMouse.containsMouse ? "#16434E" : explorePage.manager.surface2
                        Text { id: moreInstalled; anchors.centerIn: parent; text: qsTranslate("OmniaManager", "Ver más"); color: "#72E0DA"; font.family: "Hanken Grotesk"; font.pixelSize: explorePage.manager.s * 10; font.weight: Font.DemiBold }
                        MouseArea { id: moreInstalledMouse; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: explorePage.manager.selectPage("library") }
                    }
                }
                Flickable {
                    id: installedList
                    width: parent.width
                    height: cardHeight + 2 * zoomMargin
                    readonly property real cardHeight: explorePage.manager.s * 178
                    readonly property int visibleCount: Math.max(1, explorePage.manager.recentGames.length)
                    readonly property real cardWidth: Math.max(explorePage.manager.s * 175,
                        (width - 2 * zoomMargin - installedRow.spacing * (visibleCount - 1)) / visibleCount)
                    readonly property real zoomMargin: Math.ceil(0.023 * Math.max(width / visibleCount, explorePage.manager.s * 178)) + 2
                    contentWidth: installedRow.width + 2 * zoomMargin
                    contentHeight: height
                    clip: true
                    flickableDirection: Flickable.HorizontalFlick
                    boundsBehavior: Flickable.StopAtBounds
                    Row {
                        id: installedRow
                        x: installedList.zoomMargin; y: installedList.zoomMargin
                        width: installedList.cardWidth * installedList.visibleCount + spacing * (installedList.visibleCount - 1)
                        spacing: explorePage.manager.s * 12
                        Repeater {
                            // Los delegados sobreviven a cada actualización de la biblioteca.
                            model: 5
                            delegate: ManagerPosterCard {
                                id: recentCard
                                required property int index
                                readonly property var game: explorePage.manager.recentGames[index] || null
                                visible: !!game
                                width: installedList.cardWidth; height: installedList.cardHeight
                                scaleFactor: explorePage.manager.s
                                viewport: installedList
                                title: game?.name || ""
                                artwork: game?.fondo || game?.portada || ""
                                store: game ? explorePage.manager.sourceForGame(game).label : ""
                                sourceLogo: game ? explorePage.manager.sourceForGame(game).logo : ""
                                platform: game?.platform || game?.sub || ""
                                info: String(game?.year || game?.releaseYear || "")
                                installed: true
                                onContextRequested: explorePage.manager.openGameMenu(game)
                                onActivated: explorePage.manager.openLocalExploreDetail(game)
                            }
                        }
                    }
                    Text {
                        visible: explorePage.manager.recentGames.length === 0
                        x: installedList.zoomMargin
                        anchors.verticalCenter: parent.verticalCenter
                        text: qsTranslate("OmniaManager", "Tus juegos instalados aparecerán aquí.")
                        color: explorePage.manager.muted
                        font.family: "Hanken Grotesk"
                        font.pixelSize: explorePage.manager.s * 12
                    }
                }
            }

            Item {
                id: inlineExploreFilters
                width: parent.width; height: inlineFilterRow.implicitHeight
                Grid {
                    id: inlineFilterRow
                    width: parent.width
                    columns: explorePage.manager.narrowContent ? 3 : 6
                    rowSpacing: explorePage.manager.s * 6
                    columnSpacing: explorePage.manager.s * 6
                    readonly property real chipWidth: (width - columnSpacing * (columns - 1)) / columns
                    Repeater {
                        model: explorePage.manager.exploreSources
                        delegate: Rectangle {
                            id: inlineChip
                            required property var modelData
                            readonly property bool selected: explorePage.manager.exploreFilter === modelData.k
                            width: inlineFilterRow.chipWidth; height: explorePage.manager.s * 36; radius: height / 2
                            color: selected ? "#16434E" : "#101C27"
                            border.color: selected ? "#45CFC9" : "#30414E"
                            Row {
                                anchors.centerIn: parent; spacing: explorePage.manager.s * 6
                                LucideIcon { visible: inlineChip.modelData.k === "all"; anchors.verticalCenter: parent.verticalCenter; width: explorePage.manager.s * 19; height: width; name: "layout-grid"; color: inlineChip.selected ? "#72E0DA" : explorePage.manager.muted }
                                Image { visible: !!inlineChip.modelData.logo; anchors.verticalCenter: parent.verticalCenter; width: explorePage.manager.s * 26; height: width; source: inlineChip.modelData.logo; sourceSize.width: 48; sourceSize.height: 48; fillMode: Image.PreserveAspectFit }
                                Text { anchors.verticalCenter: parent.verticalCenter; text: inlineChip.modelData.label; color: inlineChip.selected ? "#72E0DA" : explorePage.manager.muted; font.family: "Hanken Grotesk"; font.pixelSize: explorePage.manager.s * 13; font.weight: Font.DemiBold; elide: Text.ElideRight }
                            }
                            MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: { explorePage.manager.exploreFilter = inlineChip.modelData.k; exploreFlick.contentY = inlineExploreFilters.y } }
                        }
                    }
                }
            }

            Column {
                width: parent.width
                spacing: explorePage.manager.s * 9
                Row {
                    width: parent.width; height: explorePage.manager.s * 25; spacing: explorePage.manager.s * 8
                    Text { id: exploreGridTitle; anchors.verticalCenter: parent.verticalCenter; text: explorePage.manager.exploreFilter === "all" ? qsTranslate("OmniaManager", "Todos los juegos") : explorePage.manager.exploreSources.find(function(s) { return s.k === explorePage.manager.exploreFilter }).label; color: explorePage.manager.ink; font.family: "Hanken Grotesk"; font.pixelSize: explorePage.manager.s * 17; font.weight: Font.DemiBold }
                    Text { id: exploreGridCount; anchors.verticalCenter: parent.verticalCenter; text: qsTranslate("OmniaManager", "%1 juegos").arg(exploreGridRepeater.count); color: explorePage.manager.muted; font.family: "Hanken Grotesk"; font.pixelSize: explorePage.manager.s * 10 }
                    Item { width: Math.max(0, parent.width - sortControl.width - exploreGridTitle.implicitWidth - exploreGridCount.implicitWidth - parent.spacing * 3); height: 1 }
                    ComboBox {
                        id: sortControl
                        width: explorePage.manager.s * 168; height: explorePage.manager.s * 30
                        model: [qsTranslate("OmniaManager", "Año · recientes"), qsTranslate("OmniaManager", "Año · antiguos"), qsTranslate("OmniaManager", "Nombre · A–Z"), qsTranslate("OmniaManager", "Nombre · Z–A")]
                        currentIndex: ["year-desc", "year-asc", "name-asc", "name-desc"].indexOf(explorePage.manager.exploreSort)
                        onActivated: explorePage.manager.exploreSort = ["year-desc", "year-asc", "name-asc", "name-desc"][currentIndex]
                        contentItem: Text { leftPadding: explorePage.manager.s * 10; rightPadding: explorePage.manager.s * 24; text: sortControl.displayText; color: explorePage.manager.ink; font.family: "Hanken Grotesk"; font.pixelSize: explorePage.manager.s * 10; verticalAlignment: Text.AlignVCenter; elide: Text.ElideRight }
                        background: Rectangle { radius: explorePage.manager.s * 9; color: explorePage.manager.surface2; border.color: sortControl.activeFocus ? "#45CFC9" : "#30414E" }
                    }
                }
                Grid {
                    id: exploreGrid
                    x: zoomInset
                    width: parent.width - 2 * zoomInset
                    readonly property real gap: explorePage.manager.s * 16
                    readonly property real zoomInset: Math.ceil(parent.width / columns * 0.023) + 2
                    readonly property real cardWidth: Math.max(explorePage.manager.s * 112, Math.floor((width - gap * (columns - 1)) / columns))
                    readonly property real cardHeight: cardWidth * 1.42
                    columns: Math.max(2, Math.floor((parent.width + gap) / (explorePage.manager.s * 185 + gap)))
                    columnSpacing: gap; rowSpacing: gap
                    height: exploreGridRepeater.count ? Math.ceil(exploreGridRepeater.count / columns) * (cardHeight + rowSpacing) - rowSpacing : 0
                    Repeater {
                        id: exploreGridRepeater
                        model: explorePage.stores.ready ? explorePage.manager.exploreItems : []
                        delegate: Item {
                            id: exploreCell
                            required property var modelData
                            width: exploreGrid.cardWidth; height: exploreGrid.cardHeight
                            z: explorePoster.hovered ? 1 : 0
                            ManagerPosterCard {
                                id: explorePoster
                                anchors.fill: parent
                                scaleFactor: explorePage.manager.s
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
                                    const local = offer.item?.local || explorePage.manager.localMatch(offer.game)
                                    if (local) explorePage.manager.openGameMenu(local)
                                    else explorePage.manager.openOfferMenu(offer)
                                }
                                onActivated: {
                                    if (exploreCell.modelData.kind === "omnia") {
                                        const local = explorePage.manager.localMatch(exploreCell.modelData.game)
                                        if (local && !explorePage.manager.catalogLinkTargetId) explorePage.manager.openLocalExploreDetail(local)
                                        else if (explorePage.manager.catalogLinkTargetId) explorePage.manager.linkCatalogGame(exploreCell.modelData.game)
                                        else explorePage.manager.openCatalogDetail(exploreCell.modelData.game)
                                    }
                                    else if (exploreCell.modelData.item.local) explorePage.manager.openLocalExploreDetail(exploreCell.modelData.item.local)
                                    else explorePage.manager.openStoreDetail(exploreCell.modelData.item)
                                }
                            }
                        }
                    }
                }
                StoreLoading {
                    width: parent.width
                    visible: explorePage.stores.loadingContent
                    ink: explorePage.manager.muted
                    uiScale: explorePage.manager.s
                }
                Text { visible: exploreGridRepeater.count === 0 && !explorePage.manager.onlineBusy && !explorePage.stores.loadingContent; text: qsTranslate("OmniaManager", "No hay juegos para este filtro."); color: explorePage.manager.muted; font.family: "Hanken Grotesk"; font.pixelSize: explorePage.manager.s * 12 }
                Text { visible: explorePage.manager.onlineBusy; text: qsTranslate("OmniaManager", "Cargando más juegos…"); color: explorePage.manager.muted; font.family: "Hanken Grotesk"; font.pixelSize: explorePage.manager.s * 11 }
            }
            Item { width: 1; height: explorePage.manager.s * 22 }
        }
        onContentYChanged: {
            if (contentY + height >= contentHeight - explorePage.manager.s * 420) explorePage.manager.loadNextOnline()
        }
    }
    Rectangle {
        id: pinnedExploreFilters
        visible: exploreFlick.contentY >= inlineExploreFilters.y && exploreFlick.contentHeight > exploreFlick.height
        z: 10
        anchors { left: exploreFlick.left; right: exploreFlick.right; top: exploreFlick.top; leftMargin: explorePage.contentPad; rightMargin: explorePage.contentPad }
        height: explorePage.manager.s * 46; color: "#F20B1118"
        Row {
            id: pinnedFilterRow
            width: parent.width
            anchors.verticalCenter: parent.verticalCenter
            spacing: explorePage.manager.s * 6
            Repeater {
                model: explorePage.manager.exploreSources
                delegate: Rectangle {
                    id: pinnedChip
                    required property var modelData
                    readonly property bool selected: explorePage.manager.exploreFilter === modelData.k
                    width: (pinnedFilterRow.width - pinnedFilterRow.spacing * 5) / 6; height: explorePage.manager.s * 36; radius: height / 2
                    color: selected ? "#16434E" : "#101C27"
                    border.color: selected ? "#45CFC9" : "#30414E"
                    Row {
                        anchors.centerIn: parent; spacing: explorePage.manager.s * 6
                        LucideIcon { visible: pinnedChip.modelData.k === "all"; anchors.verticalCenter: parent.verticalCenter; width: explorePage.manager.s * 19; height: width; name: "layout-grid"; color: pinnedChip.selected ? "#72E0DA" : explorePage.manager.muted }
                        Image { visible: !!pinnedChip.modelData.logo; anchors.verticalCenter: parent.verticalCenter; width: explorePage.manager.s * 26; height: width; source: pinnedChip.modelData.logo; sourceSize.width: 48; sourceSize.height: 48; fillMode: Image.PreserveAspectFit }
                        Text { anchors.verticalCenter: parent.verticalCenter; text: pinnedChip.modelData.label; color: pinnedChip.selected ? "#72E0DA" : explorePage.manager.muted; font.family: "Hanken Grotesk"; font.pixelSize: explorePage.manager.s * 13; font.weight: Font.DemiBold; elide: Text.ElideRight }
                    }
                    MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: { explorePage.manager.exploreFilter = pinnedChip.modelData.k; exploreFlick.contentY = inlineExploreFilters.y } }
                }
            }
        }
    }
    Rectangle {
        id: localExploreDetail
        visible: !!explorePage.manager.exploreDetailGame
        anchors.fill: parent
        z: 30
        color: "#C9000000"
        MouseArea { anchors.fill: parent; onClicked: explorePage.manager.exploreDetailGame = null }
        Rectangle {
            id: localDetailPanel
            anchors.centerIn: parent
            width: Math.min(parent.width - explorePage.manager.s * 64, explorePage.manager.s * 760)
            height: Math.min(parent.height - explorePage.manager.s * 64, explorePage.manager.s * 430)
            radius: explorePage.manager.s * 18; color: explorePage.manager.surface; clip: true
            MouseArea { anchors.fill: parent }
            FadedImage {
                anchors.fill: parent
                source: explorePage.manager.exploreDetailGame ? (explorePage.manager.exploreDetailGame.fondo || explorePage.manager.exploreDetailGame.portada || "") : ""
                cornerRadius: explorePage.manager.s * 18; fadeBottom: 0.55; opacity: 0.42
            }
            Rectangle { anchors.fill: parent; radius: explorePage.manager.s * 18; color: "#A90B1118" }
            Column {
                id: localDetailHeading
                anchors { left: parent.left; right: parent.right; top: parent.top; margins: explorePage.manager.s * 28 }
                spacing: explorePage.manager.s * 10
                Row {
                    spacing: explorePage.manager.s * 9
                    Image { anchors.verticalCenter: parent.verticalCenter; width: explorePage.manager.s * 32; height: width; source: explorePage.manager.exploreDetailGame ? explorePage.manager.sourceForGame(explorePage.manager.exploreDetailGame).logo : ""; sourceSize.width: 64; sourceSize.height: 64; fillMode: Image.PreserveAspectFit }
                    Text { anchors.verticalCenter: parent.verticalCenter; text: explorePage.manager.exploreDetailGame ? (explorePage.manager.sourceForGame(explorePage.manager.exploreDetailGame).label + "  ·  " + (explorePage.manager.exploreDetailGame.platform || explorePage.manager.exploreDetailGame.sub || "PC")) : ""; color: "#70E0D9"; font.family: "Hanken Grotesk"; font.pixelSize: explorePage.manager.s * 12; font.weight: Font.DemiBold }
                }
                Text { width: parent.width; text: explorePage.manager.exploreDetailGame ? explorePage.manager.exploreDetailGame.name || "" : ""; color: explorePage.manager.ink; font.family: "Hanken Grotesk"; font.pixelSize: explorePage.manager.s * 30; font.weight: Font.Bold; wrapMode: Text.WordWrap }
            }
            ScrollView {
                id: localFactsScroll
                anchors { left: parent.left; right: parent.right; top: localDetailHeading.bottom; bottom: localDetailActions.top; margins: explorePage.manager.s * 28; topMargin: explorePage.manager.s * 10; bottomMargin: explorePage.manager.s * 12 }
                clip: true; contentWidth: availableWidth
                GameFacts {
                    width: localFactsScroll.availableWidth
                    api: explorePage.manager.desktopBackend; game: explorePage.manager.exploreDetailGame; uiScale: explorePage.manager.s
                    ink: explorePage.manager.ink; muted: explorePage.manager.muted
                }
            }
            Row {
                id: localDetailActions
                anchors { left: parent.left; bottom: parent.bottom; margins: explorePage.manager.s * 28 }
                spacing: explorePage.manager.s * 10
                Rectangle {
                    width: explorePage.manager.s * 140; height: explorePage.manager.s * 40; radius: height / 2; color: "#15915F"
                    Text { anchors.centerIn: parent; text: qsTranslate("OmniaManager", "Jugar"); color: "white"; font.family: "Hanken Grotesk"; font.pixelSize: explorePage.manager.s * 13; font.weight: Font.DemiBold }
                    MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: { const game = explorePage.manager.exploreDetailGame; explorePage.manager.exploreDetailGame = null; if (game) explorePage.manager.launch(game) } }
                }
                Rectangle {
                    width: explorePage.manager.s * 112; height: explorePage.manager.s * 40; radius: height / 2; color: explorePage.manager.surface2
                    Text { anchors.centerIn: parent; text: qsTranslate("OmniaManager", "Cerrar"); color: explorePage.manager.ink; font.family: "Hanken Grotesk"; font.pixelSize: explorePage.manager.s * 13 }
                    MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: explorePage.manager.exploreDetailGame = null }
                }
            }
        }
    }

}

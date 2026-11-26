pragma ComponentBehavior: Bound

import QtQuick

/** Inicio del gestor: novedades, resumen, estanterías y transferencias activas. */
Item {
    id: home
    required property var manager
    required property var api
    required property real contentPad
    required property real contentTop
Flickable {
    id: homePage
    anchors.fill: parent
    visible: home.manager.page === "home"
    clip: true
    contentWidth: width
    contentHeight: homeContent.height + 2 * home.contentTop
    boundsBehavior: Flickable.StopAtBounds
    Column {
        id: homeContent
        x: home.contentPad
        y: home.contentTop
        width: homePage.width - 2 * x
        spacing: home.manager.s * 18
        ManagerStoreNews {
            width: parent.width
            manager: home.manager
            api: home.api
            active: homePage.visible
            onOpenGame: game => home.manager.openCatalogDetail(game)
        }
        Row {
            spacing: home.manager.s * 12
            Repeater {
                model: [
                    {count: home.api.games.filter(g => !g.hidden).length, label: qsTranslate("OmniaManager", "JUEGOS")},
                    {count: home.manager.recentGames.length, label: qsTranslate("OmniaManager", "RECIENTES")},
                    {count: home.api.gameRunning ? 1 : 0, label: qsTranslate("OmniaManager", "EN JUEGO")}
                ]
                delegate: Rectangle {
                    id: statCard
                    required property var modelData
                    width: home.manager.s * 150; height: home.manager.s * 40; radius: home.manager.s * 12
                    color: home.manager.surface
                    Text {
                        anchors.centerIn: parent
                        text: statCard.modelData.count + "  " + statCard.modelData.label
                        color: home.manager.ink; font.family: "Hanken Grotesk"
                        font.pixelSize: home.manager.s * 13; font.weight: Font.DemiBold
                    }
                }
            }
        }
        HomeShelf {
            heading: qsTranslate("OmniaManager", "Seguir jugando")
            games: home.manager.recentGames
        }
        HomeShelf {
            visible: games.length > 0
            heading: qsTranslate("OmniaManager", "Favoritos")
            games: home.api.games.filter(g => g.fav && !g.hidden).slice(0, 5)
        }
        Rectangle {
            visible: home.manager.activeInstalls.length > 0
            width: parent.width; height: home.manager.s * 64
            radius: home.manager.s * 14
            color: home.manager.surface
            LucideIcon {
                anchors { left: parent.left; leftMargin: home.manager.s * 16; verticalCenter: parent.verticalCenter }
                width: home.manager.s * 24; height: width; name: "download"; color: home.manager.ink
            }
            Text {
                x: home.manager.s * 55; anchors.verticalCenter: parent.verticalCenter
                text: qsTranslate("OmniaManager", "Descargas en curso") + " · " + home.manager.activeInstalls.length
                color: home.manager.ink; font.family: "Hanken Grotesk"; font.pixelSize: home.manager.s * 17; font.weight: Font.DemiBold
            }
            MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: home.manager.selectPage("installs") }
        }
    }
}

component HomeShelf: Column {
    id: homeShelf
    property string heading
    property var games: []
    width: parent ? parent.width : 0
    spacing: home.manager.s * 4
    Text { text: homeShelf.heading; color: home.manager.ink; font.family: "Hanken Grotesk"; font.pixelSize: home.manager.s * 21; font.weight: Font.DemiBold }
    Flickable {
        id: homeRow
        width: parent.width; height: home.manager.s * 197
        contentWidth: homeCards.implicitWidth + 2 * homeCards.x
        contentHeight: height
        flickableDirection: Flickable.HorizontalFlick
        boundsBehavior: Flickable.StopAtBounds
        clip: true
        Row {
            id: homeCards
            x: home.manager.s * 10; y: home.manager.s * 9
            spacing: home.manager.s * 16
            Repeater {
                model: homeShelf.games
                delegate: ManagerPosterCard {
                    required property var modelData
                    width: home.manager.s * 250; height: home.manager.s * 179
                    viewport: homeRow
                    scaleFactor: home.manager.s
                    artwork: modelData.fondo || modelData.portada || ""
                    title: modelData.name
                    sourceLogo: home.manager.sourceForGame(modelData).logo
                    info: modelData.lastPlayed
                        ? new Date(modelData.lastPlayed * 1000).toLocaleDateString(Qt.locale(home.api.language === "en" ? "en_US" : "es_CO"), "d MMM")
                        : qsTranslate("OmniaManager", "En tu biblioteca")
                    onContextRequested: home.manager.openGameMenu(modelData)
                    onActivated: home.manager.openGameInLibrary(modelData)
                    onDoubleActivated: home.manager.launch(modelData)
                }
            }
        }
        Text { visible: !homeShelf.games.length; anchors.verticalCenter: parent.verticalCenter; text: qsTranslate("OmniaManager", "Añade juegos para verlos aquí."); color: home.manager.muted; font.family: "Hanken Grotesk"; font.pixelSize: home.manager.s * 15 }
    }
}
}

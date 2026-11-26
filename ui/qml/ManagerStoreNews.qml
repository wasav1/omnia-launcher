pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls

Column {
    id: news
    required property var api
    required property var manager
    property bool active: false
    property bool controllerFocused: false
    property real uiScale: manager.s
    property real bannerHeight: uiScale * 210
    property int direction: 1
    property bool opening: false
    readonly property bool canOpen: !!current?.url && slide.opacity === 1 && !opening
    signal openGame(var game)
    function openCurrent() {
        if (!canOpen) return
        const article = current
        if (!article.slug) {
            Qt.openUrlExternally(article.url)
            return
        }
        opening = true
        api.catalogGame(article.slug, function(status, body) {
            news.opening = false
            if (!news.active) return
            if (status === 200 && body?.data) news.openGame(body.data)
            else Qt.openUrlExternally(article.url)
        })
    }
    function advance(step) {
        if (items.length < 2 || transitionSlide.running) return
        direction = step
        transitionSlide.start()
    }
    function fallbackItems() {
        const english = api?.language === "en"
        return [{
            source: "omnia",
            title: english ? "The Legend of Zelda: Ocarina of Time — Longshot" : "The Legend of Zelda: Ocarina of Time — Longshot",
            summary: english
                ? "Explore the native Linux port of Ocarina of Time. It requires your own copy of the game."
                : "Conoce el port nativo de Ocarina of Time para Linux. Requiere tu propia copia del juego.",
            url: "https://git.magicbean.dev/MagicBeanDev/Longshot/releases",
            slug: "the-legend-of-zelda-ocarina-of-time-switch-2",
            originalLanguage: api?.language === "en" ? "en" : "es"
        }]
    }
    property var items: []
    property var pendingItems: null
    property int currentIndex: 0
    property bool busy: false
    property bool loading: true
    readonly property var current: items[currentIndex] || null
    spacing: uiScale * 8

    function refresh() {
        if (!api || busy) return
        const language = api.language || "es"
        busy = true
        api.call("GET", "/stores/news?lang=" + language, function(status, body) {
            news.busy = false
            if (language !== (news.api.language || "es")) { news.refresh(); return }
            news.loading = status === 200 && !!body.loading
            if (status !== 200 || !Array.isArray(body.items) || !body.items.length) {
                if (!news.items.length) news.items = news.fallbackItems()
                return
            }
            if (news.loading && news.items.length) return
            if (news.items.length <= 1) {
                news.items = body.items
                news.currentIndex = 0
            } else {
                news.pendingItems = body.items
            }
        })
    }

    Component.onCompleted: if (active) refresh()
    onActiveChanged: if (active) refresh()
    Connections {
        target: news.api
        ignoreUnknownSignals: true
        function onLanguageChanged() { if (news.active) news.refresh() }
    }
    Timer {
        interval: news.loading ? 2000 : 60000
        repeat: true
        running: news.active
        onTriggered: news.refresh()
    }
    Timer {
        interval: 10000
        repeat: true
        running: news.active && news.items.length > 1 && !news.controllerFocused
        onTriggered: news.advance(1)
    }

    Text {
        text: qsTr("Novedades")
        color: news.manager.ink
        font.family: "Hanken Grotesk"
        font.pixelSize: news.uiScale * 17
        font.weight: Font.DemiBold
    }

    Rectangle {
        id: banner
        width: parent.width
        height: news.bannerHeight
        radius: news.uiScale * 15
        color: "#172938"
        clip: true

        Item {
            id: slide
            anchors.fill: parent
            FadedImage {
                anchors.fill: parent
                source: news.current?.artwork || ""
                cornerRadius: banner.radius
                fadeLeft: 0.75
                opacity: 0.65
            }
            Rectangle {
                anchors.fill: parent
                radius: banner.radius
                gradient: Gradient {
                    orientation: Gradient.Horizontal
                    GradientStop { position: 0; color: "#F00B141E" }
                    GradientStop { position: 1; color: "#140B141E" }
                }
            }
            Image {
                anchors { top: parent.top; left: parent.left; margins: news.uiScale * 18 }
                width: news.uiScale * 39
                height: width
                source: news.current ? news.manager.storeLogo(news.current.source) : ""
                sourceSize: Qt.size(128, 128)
                fillMode: Image.PreserveAspectFit
            }
            Column {
                anchors { left: parent.left; right: parent.right; bottom: parent.bottom; margins: news.uiScale * 18 }
                spacing: news.uiScale * 5
                Text {
                    visible: !!news.current
                    text: news.current ? ({steam: "Steam", gog: "GOG", epic: "Epic Games Store", amazon: "Amazon Game Studios", omnia: "Omnia"})[news.current.source]
                        + (news.current.game ? " · " + news.current.game : "")
                        + ((news.api.language === "es" && news.current.originalLanguage === "en")
                           ? " · " + qsTr("En inglés") : "") : ""
                    textFormat: Text.PlainText
                    color: "#A2E5E2"
                    font.pixelSize: news.uiScale * 13
                }
                Text {
                    width: parent.width
                    text: news.current ? news.current.title : (news.loading ? qsTr("Cargando novedades…") : qsTr("Por ahora no hay novedades disponibles."))
                    textFormat: Text.PlainText
                    color: news.manager.ink
                    font.family: "Hanken Grotesk"
                    font.weight: Font.Bold
                    font.pixelSize: news.uiScale * 27
                    maximumLineCount: 2
                    wrapMode: Text.Wrap
                    elide: Text.ElideRight
                }
                Text {
                    visible: !!news.current?.summary
                    width: parent.width * 0.86
                    text: news.current?.summary || ""
                    textFormat: Text.PlainText
                    color: news.manager.ink
                    font.pixelSize: news.uiScale * 14
                    wrapMode: Text.Wrap
                    maximumLineCount: 2
                    elide: Text.ElideRight
                }
                Button {
                    text: news.current?.slug ? qsTr("Ver ficha") : qsTr("Leer noticia")
                    visible: !!news.current
                    enabled: news.canOpen
                    highlighted: news.controllerFocused
                    onClicked: news.openCurrent()
                }
            }
        }
        Rectangle {
            anchors.fill: parent
            radius: banner.radius
            color: "transparent"
            border { width: Math.max(2, news.uiScale * 2); color: news.manager.ring || "#5b9be0" }
            visible: news.controllerFocused
        }
        SequentialAnimation {
            id: transitionSlide
            NumberAnimation { target: slide; property: "opacity"; to: 0; duration: 230 }
            ScriptAction {
                script: {
                    const previous = news.current?.url
                    if (news.pendingItems !== null) {
                        news.items = news.pendingItems
                        news.pendingItems = null
                    }
                    const index = news.items.findIndex(item => item.url === previous)
                    const size = Math.max(1, news.items.length)
                    news.currentIndex = (Math.max(0, index) + news.direction + size) % size
                }
            }
            NumberAnimation { target: slide; property: "opacity"; to: 1; duration: 270 }
        }
    }
}

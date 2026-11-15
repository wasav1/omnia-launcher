import QtQuick

// Estantería de Omnia (primer corte): tarjetas de los juegos detectados, selección con teclado o ratón y lanzamiento.
Rectangle {
    id: shell
    color: "#0b1f16"
    focus: true

    property int bottomInset: 0          // en modo escritorio la capa cubre también la zona del panel: se deja ese margen
    Api { id: api }
    Timer { interval: 5000; running: !api.covered; repeat: true; onTriggered: api.refresh() }   // tapada: no hace falta sondear

    readonly property var current: (api.games.length > 0 && list.currentIndex >= 0 && list.currentIndex < api.games.length)
                                   ? api.games[list.currentIndex] : null
    property string clockText: Qt.formatTime(new Date(), "hh:mm")
    Timer { interval: 1000; running: !api.covered; repeat: true; onTriggered: shell.clockText = Qt.formatTime(new Date(), "hh:mm") }

    Component.onCompleted: forceActiveFocus()

    // Mando: los mismos gestos que el teclado. La confirmación es siempre «A» (en Nintendo, el botón derecho).
    Connections {
        target: api
        function onPadKey(key) {
            if (key === "r") list.incrementCurrentIndex()
            else if (key === "l") list.decrementCurrentIndex()
            else if (key === "RB") list.currentIndex = Math.min(api.games.length - 1, list.currentIndex + 5)
            else if (key === "LB") list.currentIndex = Math.max(0, list.currentIndex - 5)
            else if (key === "A") api.launch(shell.current)
            else if (key === "Y") api.toggleFav(shell.current)
        }
    }
    Keys.onPressed: function (e) {
        if (e.key === Qt.Key_Right) { list.incrementCurrentIndex(); e.accepted = true }
        else if (e.key === Qt.Key_Left) { list.decrementCurrentIndex(); e.accepted = true }
        else if (e.key === Qt.Key_Return || e.key === Qt.Key_Enter || e.key === Qt.Key_Space) { api.launch(current); e.accepted = true }
        else if (e.key === Qt.Key_F) { api.toggleFav(current); e.accepted = true }
        else if (e.key === Qt.Key_Home) { list.currentIndex = 0; e.accepted = true }
        else if (e.key === Qt.Key_End) { list.currentIndex = Math.max(0, api.games.length - 1); e.accepted = true }
    }

    // --- telón: fondo del juego seleccionado (SteamGridDB) con un velo que mantiene legibles los textos
    Backdrop {
        id: backdrop
        anchors.fill: parent
        source: shell.current && shell.current.fondo ? shell.current.fondo : ""
    }
    Rectangle {
        anchors.fill: parent
        gradient: Gradient {
            GradientStop { position: 0.0; color: Qt.rgba(0.04, 0.12, 0.09, 0.80) }
            GradientStop { position: 0.45; color: Qt.rgba(0.04, 0.12, 0.09, 0.55) }
            GradientStop { position: 1.0; color: Qt.rgba(0.04, 0.12, 0.09, 0.94) }
        }
    }

    // --- cabecera
    Row {
        anchors { top: parent.top; left: parent.left; margins: 48 }
        spacing: 16
        Text { text: "Omnia"; color: "#e6d9a0"; font.pixelSize: 34; font.bold: true }
        Text { text: api.games.length > 0 ? api.games.length + " juegos" : ""; color: "#c9bf8a"; font.pixelSize: 20; y: 12 }
    }
    Column {
        anchors { top: parent.top; right: parent.right; margins: 48 }
        spacing: 2
        Text { anchors.right: parent.right; text: shell.clockText; color: "#e6d9a0"; font.pixelSize: 34 }
        Text { anchors.right: parent.right; visible: api.padOn; text: "🎮 " + api.padName; color: "#c9bf8a"; font.pixelSize: 15 }
    }

    // --- estantería
    ListView {
        id: list
        anchors { left: parent.left; right: parent.right; verticalCenter: parent.verticalCenter; verticalCenterOffset: -30 - shell.bottomInset / 2 }
        height: 340
        orientation: ListView.Horizontal
        spacing: 24
        model: api.games
        clip: false
        highlightRangeMode: ListView.StrictlyEnforceRange
        preferredHighlightBegin: width / 2 - 110
        preferredHighlightEnd: width / 2 + 110
        highlightMoveDuration: 220
        keyNavigationEnabled: false          // las flechas las gestiona shell, para no perder el foco de teclado
        delegate: GameCard {
            required property var modelData
            required property int index
            anchors.verticalCenter: parent ? parent.verticalCenter : undefined
            game: modelData
            current: ListView.isCurrentItem
            onActivated: { if (ListView.isCurrentItem) api.launch(modelData); else list.currentIndex = index }
        }
    }

    // --- estados vacíos
    Text {
        visible: !api.ok || api.games.length === 0
        anchors.centerIn: parent
        width: parent.width * 0.6; horizontalAlignment: Text.AlignHCenter; wrapMode: Text.WordWrap
        color: "#c9bf8a"; font.pixelSize: 24
        text: !api.ok ? api.error : "No se detectó ningún juego instalado.\nInstala algo en Steam, Heroic o Lutris y aparecerá aquí."
    }

    // --- ficha del juego seleccionado
    Column {
        visible: shell.current !== null
        anchors { left: parent.left; bottom: parent.bottom; margins: 48; bottomMargin: 48 + shell.bottomInset }
        spacing: 10
        Text { text: shell.current ? shell.current.name : ""; color: "#f4efd8"; font.pixelSize: 40; font.bold: true }
        Row {
            spacing: 14
            Rectangle {
                width: playTxt.width + 56; height: 52; radius: 26
                color: playArea.containsMouse ? "#3aa06a" : "#2e8b57"
                Text { id: playTxt; anchors.centerIn: parent; text: shell.current && shell.current.running ? "En ejecución" : "Jugar"; color: "white"; font.pixelSize: 22; font.bold: true }
                MouseArea { id: playArea; anchors.fill: parent; hoverEnabled: true; onClicked: api.launch(shell.current) }
            }
            Rectangle {
                width: 52; height: 52; radius: 26; color: favArea.containsMouse ? "#2a4a3a" : "#1c3a2c"
                border.color: "#e6d9a0"; border.width: shell.current && shell.current.fav ? 2 : 0
                Text { anchors.centerIn: parent; text: shell.current && shell.current.fav ? "★" : "☆"; color: "#e6d9a0"; font.pixelSize: 28 }
                MouseArea { id: favArea; anchors.fill: parent; hoverEnabled: true; onClicked: api.toggleFav(shell.current) }
            }
        }
    }
    Text {
        anchors { right: parent.right; bottom: parent.bottom; margins: 48; bottomMargin: 48 + shell.bottomInset }
        horizontalAlignment: Text.AlignRight
        color: api.toast ? "#f4efd8" : "#8c8560"; font.pixelSize: 17
        text: api.toast ? api.toast : "← → elegir   ·   Enter jugar   ·   F favorito"
    }
}

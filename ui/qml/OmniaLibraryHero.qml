pragma ComponentBehavior: Bound
pragma Translator: OmniaLibrary

import QtQuick

/** Ficha principal del juego seleccionado en la biblioteca de Big Mode. */
Item {
    id: hero
    required property var host
    visible: hero.host.page === "library" && hero.host.current !== null
    property string gameId: hero.host.current ? hero.host.current.id : ""
    onGameIdChanged: heroIn.restart()
    transform: Translate { id: heroShift }
    ParallelAnimation {
        id: heroIn
        NumberAnimation { target: hero; property: "opacity"; from: 0; to: 1; duration: 320; easing.type: Easing.OutCubic }
        NumberAnimation { target: heroShift; property: "y"; from: hero.host.s * 16; to: 0; duration: 320; easing.type: Easing.OutCubic }
    }
    x: hero.host.contentInset
    y: hero.host.s * 104
    width: hero.host.s * 760
    height: hero.host.s * 330

    // logo del juego o, si no hay, el nombre en grande
    Item {
        id: logoBox
        width: hero.host.s * 540; height: hero.host.s * 182
        Image {
            id: logoImg
            anchors.fill: parent
            source: hero.host.current && hero.host.current.logo ? hero.host.current.logo : ""
            fillMode: Image.PreserveAspectFit
            horizontalAlignment: Image.AlignLeft
            verticalAlignment: Image.AlignBottom
            asynchronous: true
            smooth: true
            mipmap: true
            sourceSize.width: Math.round(hero.host.s * 1080)
            visible: status === Image.Ready
        }
        Text {
            visible: logoImg.status !== Image.Ready
            anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
            text: hero.host.current ? hero.host.current.name : ""
            color: hero.host.ink
            font.family: hero.host.current && hero.host.current.font ? hero.host.current.font : hero.host.uiFont
            font.pixelSize: hero.host.s * 64
            font.weight: Font.Bold
            wrapMode: Text.WordWrap
            maximumLineCount: 2
            elide: Text.ElideRight
            lineHeight: 0.95
        }
    }
    Rectangle { id: rule; anchors { top: logoBox.bottom; topMargin: hero.host.s * 18 } width: hero.host.s * 46; height: hero.host.s * 3; radius: 2; color: hero.host.ring }
    Text {
        id: blurb
        anchors { top: rule.bottom; topMargin: hero.host.s * 16 }
        width: hero.host.s * 560
        text: hero.host.current ? (hero.host.current.description || "").replace(/\s+/g, " ").trim() : ""
        visible: text.length > 0
        height: visible ? implicitHeight : 0
        color: hero.host.ink
        opacity: 0.92
        font.family: hero.host.uiFont
        font.pixelSize: hero.host.s * 22
        lineHeight: 1.25
        wrapMode: Text.WordWrap
        maximumLineCount: 2
        elide: Text.ElideRight
    }
    Text {
        id: sessionSummary
        anchors { top: blurb.bottom; topMargin: visible ? hero.host.s * 8 : 0 }
        visible: text.length > 0
        height: text.length > 0 ? implicitHeight : 0
        text: {
            const data = hero.host.gameActivity
            const parts = hero.host.current ? [hero.host.subtitle(hero.host.current)] : []
            if (data?.lastPlayed > 0)
                parts.push("Última sesión: " + Qt.formatDate(new Date(data.lastPlayed * 1000), Locale.ShortFormat))
            if (data?.totalSecs > 0)
                parts.push("Tiempo jugado: " + hero.host.duration(data.totalSecs))
            return parts.join(" · ")
        }
        color: hero.host.ink2
        font.family: hero.host.uiFont
        font.pixelSize: hero.host.s * 16
        leftPadding: (summaryIcon.visible ? summaryIcon.width : 0) + hero.host.s * 10      // el logo de consola puede ser ancho (p. ej. Switch 2)
        PlatIcon {
            id: summaryIcon
            visible: hero.host.current !== null
            anchors { left: parent.left; verticalCenter: parent.verticalCenter }
            key: hero.host.current ? hero.host.norm(hero.host.current.platform) : ""
            size: hero.host.s * 20; color: hero.host.ink2
        }
    }
    Row {
        anchors { top: sessionSummary.bottom; topMargin: hero.host.s * 18 }
        spacing: hero.host.s * 14
        Rectangle {      // Jugar
            id: playBtn
            readonly property bool running: hero.host.current && hero.host.current.running
            width: hero.host.s * 265; height: hero.host.s * 50
            radius: hero.host.s * 10
            opacity: running ? 0.7 : 1
            gradient: Gradient {
                GradientStop { position: 0; color: playMa.containsMouse ? Qt.lighter(hero.host.accent, 1.35) : Qt.lighter(hero.host.accent, 1.2) }
                GradientStop { position: 1; color: playMa.containsMouse ? Qt.lighter(hero.host.accent, 1.1) : hero.host.accent }
            }
            border.width: 1
            border.color: Qt.rgba(1, 1, 1, 0.22)
            Row {
                anchors.centerIn: parent
                spacing: hero.host.s * 12
                LucideIcon { width: hero.host.s * 22; height: hero.host.s * 22; name: hero.host.current && hero.host.current.portAvailable ? "download" : "play"; color: hero.host.ink; anchors.verticalCenter: parent.verticalCenter; visible: !playBtn.running }
                Text { text: playBtn.running ? qsTr("En ejecución") : (hero.host.current && hero.host.current.portAvailable ? qsTr("Instalar port") : qsTr("Jugar")); color: hero.host.ink; font.family: hero.host.uiFont; font.pixelSize: hero.host.s * 22; font.weight: Font.Medium; anchors.verticalCenter: parent.verticalCenter }
            }
            MouseArea { id: playMa; anchors.fill: parent; enabled: !playBtn.running; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: hero.host.play() }
        }
        Rectangle {      // Detalles
            width: hero.host.s * 160; height: hero.host.s * 50
            radius: height / 2
            color: detMa.containsMouse ? Qt.rgba(1, 1, 1, 0.14) : Qt.rgba(0.05, 0.08, 0.12, 0.45)
            border.width: 1
            border.color: Qt.rgba(1, 1, 1, 0.40)
            Text { anchors.centerIn: parent; text: qsTr("Detalles"); color: hero.host.ink; font.family: hero.host.uiFont; font.pixelSize: hero.host.s * 20; font.weight: Font.Medium }
            MouseArea { id: detMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: hero.host.openDetails() }
        }
    }
    }


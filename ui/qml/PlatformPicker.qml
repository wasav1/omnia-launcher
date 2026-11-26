pragma ComponentBehavior: Bound

import QtQuick

/** Selector de plataforma de la barra superior.
 *  Mando: una sola pill con la plataforma activa entre LB y RB; al cambiar, el contenido se desliza y se funde (y unos puntos
 *  indican la posición). Teclado y ratón: la misma pill con una flecha que abre un desplegable (icono, nombre y cantidad). */
Item {
    id: pick
    property var options: []            // [{ key, label }]
    property string current: "all"
    property var games: []
    property bool padMode: false
    property string padFamily: "xbox"
    property real uiScale: 1
    property color ink: "#F0F3F7"
    property color ink2: "#B8C3D0"
    property color accent: "#336599"
    property string uiFont: "Hanken Grotesk"
    signal picked(string key)
    signal platformColorRequested()
    property var colorOf: function(key) { return ink2 }

    readonly property int idx: { for (let i = 0; i < options.length; i++) if (options[i].key === current) return i; return 0 }
    readonly property var cur: options.length ? options[idx] : { key: "all", label: "" }
    property bool dropOpen: false
    property int dir: 1                 // sentido del último cambio (para el deslizamiento)
    property int lastIdx: 0
    onIdxChanged: { dir = idx >= lastIdx ? 1 : -1; lastIdx = idx; slide.restart() }
    onPadModeChanged: dropOpen = false

    function countOf(key) {
        let n = 0
        for (let i = 0; i < games.length; i++) {
            const g = games[i]
            if (g.hidden) continue
            if (key === "all" || (key === "fav" ? g.fav : String(g.platform || "").toLowerCase() === key)) n++
        }
        return n
    }

    implicitWidth: row.implicitWidth
    implicitHeight: uiScale * 38
    height: implicitHeight

    Row {
        id: row
        anchors.verticalCenter: parent.verticalCenter
        spacing: pick.uiScale * 4
        PadGlyph { visible: pick.padMode; anchors.verticalCenter: parent.verticalCenter; key: "LB"; family: pick.padFamily; size: pick.uiScale * 30 }
        Rectangle {
            id: pill
            height: pick.uiScale * 38
            width: content.implicitWidth + pick.uiScale * 22
            radius: height / 2
            color: !pick.padMode && pillMa.containsMouse ? "#1fffffff" : "transparent"      // sin estilo de botón; solo un velo al pasar el ratón
            clip: true
            Behavior on width { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }
            Item {
                id: content
                anchors.centerIn: parent
                implicitWidth: inner.implicitWidth
                width: inner.implicitWidth; height: inner.implicitHeight
                Row {
                    id: inner
                    spacing: pick.uiScale * 9
                    opacity: 1
                    transform: Translate { id: shift; x: 0 }
                    Item {
                        width: pick.uiScale * 22; height: pick.uiScale * 22; anchors.verticalCenter: parent.verticalCenter
                        PlatIcon { anchors.centerIn: parent; key: pick.cur.key === "fav" || pick.cur.key === "all" ? "" : pick.cur.key; size: pick.uiScale * 20; color: pick.ink; visible: pick.cur.key !== "fav" && pick.cur.key !== "all" }
                        LucideIcon { anchors.fill: parent; name: "star"; color: pick.ink; visible: pick.cur.key === "fav" }
                        LucideIcon { anchors.fill: parent; name: "layout-grid"; color: pick.ink; visible: pick.cur.key === "all" }
                    }
                    Text { anchors.verticalCenter: parent.verticalCenter; text: pick.cur.label; color: pick.ink; font.family: pick.uiFont; font.pixelSize: pick.uiScale * 19; font.weight: Font.DemiBold }
                    LucideIcon { visible: !pick.padMode; anchors.verticalCenter: parent.verticalCenter; width: pick.uiScale * 18; height: width; name: "chevron-down"; rotation: pick.dropOpen ? 180 : 0; color: pick.ink; Behavior on rotation { NumberAnimation { duration: 160 } } }
                }
                ParallelAnimation {
                    id: slide
                    NumberAnimation { target: shift; property: "x"; from: pick.dir * pick.uiScale * 26; to: 0; duration: 240; easing.type: Easing.OutCubic }
                    NumberAnimation { target: inner; property: "opacity"; from: 0; to: 1; duration: 240; easing.type: Easing.OutCubic }
                }
            }
            MouseArea {
                id: pillMa
                anchors.fill: parent
                hoverEnabled: true
                enabled: !pick.padMode
                cursorShape: Qt.PointingHandCursor
                onClicked: pick.dropOpen = !pick.dropOpen
            }
        }
        PadGlyph { visible: pick.padMode; anchors.verticalCenter: parent.verticalCenter; key: "RB"; family: pick.padFamily; size: pick.uiScale * 30 }
    }

    Row {      // posición (solo con mando)
        visible: pick.padMode && pick.options.length > 1
        anchors { horizontalCenter: row.horizontalCenter; top: row.bottom; topMargin: pick.uiScale * 2 }
        spacing: pick.uiScale * 5
        Repeater {
            model: pick.options.length
            delegate: Rectangle {
                required property int index
                width: index === pick.idx ? pick.uiScale * 16 : pick.uiScale * 6; height: pick.uiScale * 6; radius: height / 2
                color: index === pick.idx ? pick.ink : "#55ffffff"
                Behavior on width { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }
            }
        }
    }

    // desplegable (ratón / teclado)
    Item {
        id: drop
        visible: pick.dropOpen && !pick.padMode
        z: 20
        x: 0; y: pick.height + pick.uiScale * 8
        width: pick.uiScale * 300; height: list.height
        opacity: pick.dropOpen ? 1 : 0
        Behavior on opacity { NumberAnimation { duration: 140 } }
        MouseArea {      // cierra al pulsar fuera
            x: -3000; y: -3000; width: 6000; height: 6000
            onClicked: pick.dropOpen = false
        }
        Rectangle {
            anchors.fill: list
            anchors.margins: -pick.uiScale * 6
            radius: pick.uiScale * 18
            color: "#F2101820"; border.color: "#2effffff"
        }
        Column {
            id: list
            width: parent.width
            spacing: pick.uiScale * 3
            Repeater {
                model: pick.options
                delegate: Rectangle {
                    id: it
                    required property var modelData
                    required property int index
                    readonly property bool on: pick.current === modelData.key
                    width: list.width; height: pick.uiScale * 42; radius: pick.uiScale * 12
                    color: on ? pick.accent : (itMa.containsMouse ? "#1fffffff" : "transparent")
                    Row {
                        anchors { left: parent.left; leftMargin: pick.uiScale * 12; verticalCenter: parent.verticalCenter }
                        spacing: pick.uiScale * 11
                        Item {
                            width: pick.uiScale * 22; height: width; anchors.verticalCenter: parent.verticalCenter
                            PlatIcon { anchors.centerIn: parent; key: it.modelData.key === "fav" || it.modelData.key === "all" ? "" : it.modelData.key; size: pick.uiScale * 20; color: it.on ? pick.ink : pick.colorOf(it.modelData.key); visible: it.modelData.key !== "fav" && it.modelData.key !== "all" }
                            LucideIcon { anchors.fill: parent; name: "star"; color: pick.ink; visible: it.modelData.key === "fav" }
                            LucideIcon { anchors.fill: parent; name: "layout-grid"; color: pick.ink; visible: it.modelData.key === "all" }
                        }
                        Text { anchors.verticalCenter: parent.verticalCenter; text: it.modelData.label; color: pick.ink; font.family: pick.uiFont; font.pixelSize: pick.uiScale * 18; font.weight: it.on ? Font.DemiBold : Font.Normal }
                    }
                    Text { anchors { right: parent.right; rightMargin: pick.uiScale * 14; verticalCenter: parent.verticalCenter }
                        text: pick.countOf(it.modelData.key); color: it.on ? pick.ink : pick.ink2; font.family: pick.uiFont; font.pixelSize: pick.uiScale * 15 }
                    MouseArea { id: itMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: { pick.dropOpen = false; pick.picked(it.modelData.key) } }
                }
            }
        }
    }
}

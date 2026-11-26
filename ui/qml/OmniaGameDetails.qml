pragma ComponentBehavior: Bound

import QtQuick

/**
 * Ficha de un juego en BigMode (pantalla completa): volver a Biblioteca, banner con degradado, título, plataforma y
 * origen, «Jugar» y «⋯», y las pestañas Descripción · Partidas · Actividad con datos reales del núcleo.
 * Teclado: ←→ botones/pestañas · ↑↓ zonas y scroll · Enter acepta · Esc atrás.  Mando: A, B, LB/RB (pestañas).
 */
Item {
    id: det
    required property var host                // OmniaLibrary (paleta, escala, api y acciones)
    property var game: null
    property int tab: 0                       // 0 Descripción · 1 Partidas · 2 Actividad
    property string zone: "play"              // play | more | tabs | body
    property bool menuOpen: false
    property int menuIdx: 0
    property var activity: null               // /game/activity
    property var saves: null                  // /saves
    property bool loading: false
    readonly property real s: det.host.s
    readonly property color ink: det.host.ink
    readonly property color ink2: det.host.ink2
    signal back()

    readonly property var menuItems: {
        const g = det.game, out = [];
        if (!g) return out;
        out.push({ id: "fav", label: g.fav ? qsTr("Quitar de favoritos") : qsTr("Añadir a favoritos") });
        if (g.folder) out.push({ id: "folder", label: qsTr("Abrir carpeta del juego") });
        if (g.canUninstall || g.installPackageId || g.canUnlink)
            out.push({ id: "manage", label: qsTr("Gestionar instalación") });
        return out;
    }

    function load() {
        activity = null; saves = null
        if (!game) return
        loading = true
        const id = game.id
        det.host.api.call("GET", "/game/activity?id=" + encodeURIComponent(id), function(st, b) { if (det.game && det.game.id === id) { det.activity = st === 200 ? b : ({}); det.loading = false } })
        const port = game.ports && game.ports.length ? game.ports[0].id : ""
        det.host.api.call("GET", "/saves?id=" + encodeURIComponent(id) + "&port=" + encodeURIComponent(port), function(st, b) { if (det.game && det.game.id === id) det.saves = st === 200 ? b : ({}) })
    }
    readonly property string gameId: game ? game.id : ""       // solo cambia al cambiar de juego (no al refrescar los datos)
    onTabChanged: bodyFlick.contentY = 0
    onGameIdChanged: { tab = 0; zone = "play"; menuOpen = false; load() }
    onVisibleChanged: if (visible) { zone = "play"; menuOpen = false; load(); forceActiveFocus() }

    function relDate(ts) {
        if (!ts) return qsTr("Sin datos")
        const d = new Date(ts * 1000), days = Math.floor((Date.now() - d.getTime()) / 86400000)
        if (days <= 0) return qsTr("Hoy")
        if (days === 1) return qsTr("Ayer")
        if (days < 30) return qsTr("Hace %1 días").arg(days)
        return d.toLocaleDateString(Qt.locale(det.host.api.language === "en" ? "en_US" : "es_CO"), "d MMM yyyy")
    }
    function fullDate(ts) { return new Date(ts * 1000).toLocaleString(Qt.locale(det.host.api.language === "en" ? "en_US" : "es_CO"), "ddd d MMM yyyy · HH:mm") }
    function bytes(n) { return n > 1048576 ? (n / 1048576).toFixed(1) + " MB" : Math.max(1, Math.round(n / 1024)) + " KB" }

    function runMenu(i) {
        const it = menuItems[i]
        if (!it || !game) return
        if (it.id === "fav") det.host.api.toggleFav(game)
        else if (it.id === "folder") Qt.openUrlExternally("file://" + game.folder)      // gestor de archivos del escritorio
        else if (it.id === "manage") det.host.openMenu(game)
        menuOpen = false; zone = "more"
    }
    function nav(k) {
        if (menuOpen) {
            const n = menuItems.length
            if (k === "up") menuIdx = (menuIdx - 1 + n) % n
            else if (k === "down") menuIdx = (menuIdx + 1) % n
            else if (k === "accept") runMenu(menuIdx)
            else if (k === "back" || k === "menu") { menuOpen = false; zone = "more" }
            return
        }
        if (k === "back") { back(); return }
        if (k === "tabprev") { tab = (tab + 2) % 3; return }
        if (k === "tabnext") { tab = (tab + 1) % 3; return }
        if (k === "menu") { if (menuItems.length) { menuIdx = 0; menuOpen = true } return }
        if (zone === "back") {
            if (k === "accept") back()
            else if (k === "down") zone = "play"
            return
        }
        if (zone === "play" || zone === "more") {
            if (k === "right") zone = "more"
            else if (k === "left") zone = "play"
            else if (k === "up") zone = "back"
            else if (k === "down") zone = "tabs"
            else if (k === "accept") { if (zone === "play") det.host.play(game); else if (menuItems.length) { menuIdx = 0; menuOpen = true } }
        } else if (zone === "tabs") {
            if (k === "left") tab = (tab + 2) % 3
            else if (k === "right") tab = (tab + 1) % 3
            else if (k === "up") zone = "play"
            else if (k === "down") zone = "body"
            else if (k === "accept") zone = "body"
        } else if (zone === "body") {
            if (k === "up") { if (bodyFlick.contentY <= 0) zone = "tabs"; else bodyFlick.contentY = Math.max(0, bodyFlick.contentY - 90 * s) }
            else if (k === "down") bodyFlick.contentY = Math.max(0, Math.min(bodyFlick.contentHeight - bodyFlick.height, bodyFlick.contentY + 90 * s))
            else if (k === "left") tab = (tab + 2) % 3
            else if (k === "right") tab = (tab + 1) % 3
        }
    }
    Keys.onPressed: function(e) {
        host.keySound(e)
        const m = {}
        m[Qt.Key_Up] = "up"; m[Qt.Key_Down] = "down"; m[Qt.Key_Left] = "left"; m[Qt.Key_Right] = "right"
        m[Qt.Key_Return] = "accept"; m[Qt.Key_Enter] = "accept"; m[Qt.Key_Escape] = "back"; m[Qt.Key_Backspace] = "back"
        m[Qt.Key_M] = "menu"; m[Qt.Key_Menu] = "menu"; m[Qt.Key_PageUp] = "tabprev"; m[Qt.Key_PageDown] = "tabnext"
        const k = m[e.key]
        if (k === undefined) return
        e.accepted = true
        nav(k)
    }

    Rectangle { anchors.fill: parent; z: -5; color: det.host.base }       // tapa la biblioteca que queda debajo

    // ---------- fondo: el mismo de la biblioteca (zona arriba a la derecha, nítido, se desliza de derecha a izquierda) ----------
    readonly property real bannerH: height * 0.50
    OmniaBackdrop {
        anchors.fill: parent
        base: det.host.base
        animate: det.visible && !det.host.api.gameRunning
        source: det.game && det.game.fondo ? det.game.fondo : ""
    }
    Rectangle {      // sin fondo propio: degradado con la paleta del juego
        anchors.fill: parent
        visible: !(det.game && det.game.fondo)
        gradient: Gradient {
            GradientStop { position: 0; color: det.game && det.game.pal ? Qt.darker(det.game.pal[1] || "#1b2a3b", 1.9) : "#101722" }
            GradientStop { position: 1; color: det.host.base }
        }
    }
    Rectangle {      // oscurece la izquierda y abajo, igual que la biblioteca
        anchors.fill: parent
        gradient: Gradient {
            orientation: Gradient.Horizontal
            GradientStop { position: 0.00; color: Qt.rgba(0.043, 0.059, 0.078, 0.96) }
            GradientStop { position: 0.22; color: Qt.rgba(0.043, 0.059, 0.078, 0.82) }
            GradientStop { position: 0.45; color: Qt.rgba(0.043, 0.059, 0.078, 0.46) }
            GradientStop { position: 0.64; color: Qt.rgba(0.043, 0.059, 0.078, 0.14) }
            GradientStop { position: 0.80; color: "transparent" }
        }
    }
    Rectangle {
        anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
        height: parent.height * 0.62
        gradient: Gradient {
            GradientStop { position: 0.00; color: "transparent" }
            GradientStop { position: 0.38; color: Qt.rgba(0.043, 0.059, 0.078, 0.58) }
            GradientStop { position: 0.72; color: Qt.rgba(0.043, 0.059, 0.078, 0.90) }
            GradientStop { position: 1.00; color: Qt.rgba(0.043, 0.059, 0.078, 0.98) }
        }
    }
    Rectangle {
        anchors { left: parent.left; right: parent.right; top: parent.top }
        height: det.s * 150
        gradient: Gradient {
            GradientStop { position: 0.0; color: Qt.rgba(0.043, 0.059, 0.078, 0.78) }
            GradientStop { position: 1.0; color: "transparent" }
        }
    }

    // volver (botón claro; también Esc / B)
    Rectangle {
        id: backB
        x: det.host.contentInset; y: det.s * 27
        width: backRow.implicitWidth + det.s * 44; height: det.s * 54; radius: height / 2
        color: backMa.containsMouse ? Qt.rgba(1, 1, 1, 0.20) : Qt.rgba(0.05, 0.08, 0.12, 0.70)
        border.width: det.zone === "back" ? 3 : 1
        border.color: det.zone === "back" ? det.host.ring : Qt.rgba(1, 1, 1, 0.26)
        Row {
            id: backRow
            anchors.centerIn: parent
            spacing: det.s * 10
            LucideIcon { width: det.s * 26; height: det.s * 26; name: "chevron-left"; color: det.ink; anchors.verticalCenter: parent.verticalCenter }
            Text { text: qsTr("Big Mode"); color: det.ink; font.family: det.host.uiFont; font.pixelSize: det.s * 24; font.weight: Font.Medium; anchors.verticalCenter: parent.verticalCenter }
        }
        MouseArea { id: backMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: det.back() }
    }
    Row {
        anchors { left: backB.right; leftMargin: det.s * 24; verticalCenter: backB.verticalCenter }
        spacing: det.s * 10
        Image {
            width: det.s * 36; height: width
            anchors.verticalCenter: parent.verticalCenter
            source: Qt.resolvedUrl("images/omnia-mark.svg")
            fillMode: Image.PreserveAspectFit
        }
        Text { text: "Omnia"; anchors.verticalCenter: parent.verticalCenter; color: det.ink; font.family: det.host.uiFont; font.pixelSize: det.s * 28 }
    }

    PadBattery {
        api: det.host.api; uiScale: det.s; uiFont: det.host.uiFont; ink: det.ink; muted: det.ink2
        anchors { right: detClock.left; rightMargin: det.s * 18; verticalCenter: backB.verticalCenter }
    }
    Text {
        id: detClock
        anchors { right: parent.right; rightMargin: det.host.contentInset; verticalCenter: backB.verticalCenter }
        text: det.host.clockLabel
        color: det.ink2
        font.family: det.host.uiFont
        font.pixelSize: det.s * 22
    }

    // título + acciones
    Column {
        x: det.host.contentInset
        y: det.bannerH - height - det.s * 38
        spacing: det.s * 12
        Image {
            id: detailLogo
            width: det.s * 520
            height: visible ? det.s * 175 : 0
            source: det.game?.logo || ""
            fillMode: Image.PreserveAspectFit
            horizontalAlignment: Image.AlignLeft
            asynchronous: true
            visible: status === Image.Ready
        }
        Text {
            width: det.s * 900
            visible: !detailLogo.visible
            text: det.game ? det.game.name : ""
            color: det.ink
            font.family: det.game && det.game.font ? det.game.font : det.host.uiFont
            font.pixelSize: det.s * 70
            font.weight: Font.Bold
            elide: Text.ElideRight
        }
        Rectangle { width: det.s * 46; height: det.s * 3; radius: 2; color: det.host.ring }
        Row {
            spacing: det.s * 10
            PlatIcon {
                visible: key.length > 0
                key: det.game?.platform || ""
                size: det.s * 20
                color: det.host.platformColor(key)
                anchors.verticalCenter: parent.verticalCenter
            }
            Text {
                text: det.game ? det.host.subtitle(det.game) : ""
                color: det.ink2
                font.family: det.host.uiFont
                font.pixelSize: det.s * 22
                anchors.verticalCenter: parent.verticalCenter
            }
        }
        Row {
            topPadding: det.s * 10
            spacing: det.s * 16
            Rectangle {
                id: playB
                readonly property bool running: det.game && det.game.running
                width: det.s * 280; height: det.s * 58; radius: det.s * 13
                opacity: running ? 0.7 : 1
                color: playMa.containsMouse ? Qt.lighter(det.host.accent, 1.2) : det.host.accent
                border.width: det.zone === "play" && !det.menuOpen ? 3 : 0
                border.color: det.host.ring
                Row {
                    anchors.centerIn: parent
                    spacing: det.s * 14
                    LucideIcon { width: det.s * 26; height: det.s * 26; name: det.game && det.game.portAvailable ? "download" : "play"; color: det.ink; visible: !playB.running; anchors.verticalCenter: parent.verticalCenter }
                    Text { text: playB.running ? qsTr("En ejecución") : (det.game && det.game.portAvailable ? qsTr("Instalar port") : qsTr("Jugar")); color: det.ink; font.family: det.host.uiFont; font.pixelSize: det.s * 28; font.weight: Font.Medium; anchors.verticalCenter: parent.verticalCenter }
                }
                MouseArea { id: playMa; anchors.fill: parent; enabled: !!det.game && !det.game.running; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: { det.zone = "play"; det.host.play(det.game) } }
            }
            Rectangle {
                id: moreB
                width: det.s * 58; height: det.s * 58; radius: width / 2
                color: moreMa.containsMouse || det.menuOpen ? Qt.rgba(1, 1, 1, 0.20) : Qt.rgba(1, 1, 1, 0.10)
                border.width: det.zone === "more" ? 3 : 0
                border.color: det.host.ring
                LucideIcon { anchors.centerIn: parent; width: det.s * 30; height: det.s * 30; name: "ellipsis"; color: det.ink }
                MouseArea { id: moreMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: { det.zone = "more"; det.menuIdx = 0; det.menuOpen = !det.menuOpen } }
            }
        }
    }

    Item {
        anchors { left: parent.left; right: parent.right; bottom: parent.bottom; leftMargin: det.host.contentInset; rightMargin: det.host.contentInset; bottomMargin: det.s * 94 }
        height: parent.height - det.bannerH - anchors.bottomMargin

        Row {
            id: tabs
            spacing: det.s * 40
            Repeater {
                model: [qsTr("Descripción"), qsTr("Partidas"), qsTr("Actividad")]
                delegate: Item {
                    id: tb
                    required property string modelData
                    required property int index
                    readonly property bool on: det.tab === index
                    width: tx.implicitWidth + det.s * 14; height: det.s * 54
                    Rectangle {
                        anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
                        height: det.s * 3
                        color: det.host.ring
                        visible: tb.on
                        opacity: det.zone === "tabs" ? 1 : 0.78
                    }
                    Text { id: tx; anchors.centerIn: parent; text: tb.modelData; color: tb.on || tma.containsMouse ? det.ink : det.ink2; font.family: det.host.uiFont; font.pixelSize: det.s * 24; font.weight: tb.on ? Font.Medium : Font.Normal }
                    MouseArea { id: tma; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: { det.tab = tb.index; det.zone = "tabs" } }
                }
            }
        }
        Rectangle { id: rule; anchors { left: parent.left; right: parent.right; top: tabs.bottom; topMargin: -1 } height: 1; color: Qt.rgba(1, 1, 1, 0.14) }

        Flickable {
            id: bodyFlick
            anchors { left: parent.left; right: parent.right; top: rule.bottom; bottom: parent.bottom; topMargin: det.s * 28 }
            contentWidth: width
            contentHeight: bodyLoader.item ? Number(bodyLoader.item["implicitHeight"] || 0) : 0 // qmllint disable missing-property
            clip: true
            boundsBehavior: Flickable.StopAtBounds
            Loader {
                id: bodyLoader
                width: bodyFlick.width
                sourceComponent: det.tab === 0 ? descComp : det.tab === 1 ? savesComp : activityComp
            }
        }
    }

    // ---------- pestaña Descripción ----------
    Component {
        id: descComp
        Item {
            implicitHeight: Math.max(leftCol.implicitHeight, stats.implicitHeight + det.s * 40)
            Column {
                id: leftCol
                width: parent.width * 0.55
                spacing: det.s * 16
                GameFacts {
                    width: parent.width
                    api: det.host.api; game: det.game
                    uiScale: det.s * 1.22; uiFont: det.host.uiFont
                    ink: det.ink; muted: det.ink2
                }
                Text {      // el port cerró con un código que él mismo explica (exit_codes de su descriptor)
                    visible: !!det.game && !!det.game.lastExit
                    width: parent.width; wrapMode: Text.WordWrap; color: "#E8A24B"; font.family: det.host.uiFont; font.pixelSize: det.s * 21
                    text: det.game && det.game.lastExit ? qsTr("La última vez, el juego se cerró con este aviso: %1").arg(det.game.lastExit.message) : ""
                }
                Text {      // requisitos que declara el port que este PC no cumple
                    readonly property var bad: det.game && det.game.requirements ? det.game.requirements.filter(function(r) { return r.ok === false }) : []
                    visible: bad.length > 0
                    width: parent.width; wrapMode: Text.WordWrap; color: "#E8A24B"; font.family: det.host.uiFont; font.pixelSize: det.s * 21
                    text: qsTr("Este PC no cumple: %1. El juego puede no arrancar.").arg(bad.map(function(r) { return r.label + " " + r.need + " (" + r.have + ")" }).join(", "))
                }
                Text {      // la copia del jugador no es la versión que acepta el port
                    readonly property string st: det.game && det.game.romCopy && det.game.romCopy.compat ? det.game.romCopy.compat.state : ""
                    visible: st === "mismatch"
                    width: parent.width; wrapMode: Text.WordWrap; color: "#E8A24B"; font.family: det.host.uiFont; font.pixelSize: det.s * 21
                    text: qsTr("Tu copia del juego es de otra versión que la que acepta este port.")
                }
            }
            Rectangle {
                x: parent.width * 0.60
                width: parent.width * 0.40
                height: stats.implicitHeight + det.s * 40
                radius: det.s * 18
                color: det.host.surface
                border.color: Qt.rgba(1, 1, 1, 0.12)
            }
            Column {
                id: stats
                x: parent.width * 0.60 + det.s * 20
                y: det.s * 20
                width: parent.width * 0.40 - det.s * 40
                spacing: det.s * 14
                Text { text: qsTr("Tu partida"); color: det.ink; font.family: det.host.uiFont; font.pixelSize: det.s * 26; font.weight: Font.DemiBold }
                Repeater {
                    model: [
                        { icon: "clock", label: qsTr("Tiempo jugado"), value: det.activity && det.activity.totalSecs > 0 ? det.host.duration(det.activity.totalSecs) : qsTr("Sin datos") },
                        { icon: "calendar", label: qsTr("Última sesión"), value: det.activity && det.activity.lastPlayed > 0 ? det.relDate(det.activity.lastPlayed) : qsTr("Sin datos") },
                        { icon: "save", label: qsTr("Respaldo"), value: det.game?.lastBackup > 0 ? det.relDate(det.game.lastBackup)
                            : det.saves?.backups?.length > 0 ? qsTr("Disponible") : det.saves?.configured ? qsTr("Sin respaldo") : qsTr("Sin configurar") }
                    ]
                    delegate: Item {
                        id: st
                        required property var modelData
                        width: stats.width; height: det.s * 48
                        LucideIcon { width: det.s * 30; height: det.s * 30; name: st.modelData.icon; color: det.ink2; anchors.verticalCenter: parent.verticalCenter }
                        Text { x: det.s * 44; anchors.verticalCenter: parent.verticalCenter; text: st.modelData.label; color: det.ink; font.family: det.host.uiFont; font.pixelSize: det.s * 21 }
                        Rectangle { anchors { left: parent.left; right: parent.right; bottom: parent.bottom } height: 1; color: "#20ffffff" }
                        Text { anchors { right: parent.right; verticalCenter: parent.verticalCenter } text: st.modelData.value; color: st.modelData.value === "Sin datos" ? det.ink2 : det.ink; font.family: det.host.uiFont; font.pixelSize: det.s * 21 }
                    }
                }
            }
        }
    }

    // ---------- pestaña Partidas (archivos de guardado y respaldos) ----------
    Component {
        id: savesComp
        Column {
            id: sc
            spacing: det.s * 12
            readonly property var slots: det.saves && det.saves.slots ? det.saves.slots.filter(function(x) { return x.used }) : []
            readonly property var backups: det.saves && det.saves.backups ? det.saves.backups : []
            Text {
                visible: det.saves === null
                text: qsTr("Cargando…"); color: det.ink2; font.family: det.host.uiFont; font.pixelSize: det.s * 24
            }
            Text {
                visible: det.saves !== null && sc.slots.length === 0 && sc.backups.length === 0
                width: sc.width
                text: det.saves && det.saves.configured ? qsTr("Aún no hay partidas guardadas ni respaldos de este juego.") : qsTr("Omnia no conoce la carpeta de partidas de este juego. Configúrala desde los ajustes de partidas.")
                color: det.ink2; font.family: det.host.uiFont; font.pixelSize: det.s * 24; wrapMode: Text.WordWrap
            }
            Text { visible: sc.slots.length > 0; text: qsTr("Partidas guardadas"); color: det.ink2; font.family: det.host.uiFont; font.pixelSize: det.s * 20 }
            Repeater {
                model: sc.slots
                delegate: Row {
                    id: sl
                    required property var modelData
                    spacing: det.s * 20
                    Text { width: det.s * 420; text: sl.modelData.name; color: det.ink; font.family: det.host.uiFont; font.pixelSize: det.s * 24; elide: Text.ElideRight }
                    Text { text: det.fullDate(sl.modelData.mtime); color: det.ink2; font.family: det.host.uiFont; font.pixelSize: det.s * 22 }
                }
            }
            Text { visible: sc.backups.length > 0; topPadding: det.s * 8; text: qsTr("Respaldos"); color: det.ink2; font.family: det.host.uiFont; font.pixelSize: det.s * 20 }
            Repeater {
                model: sc.backups
                delegate: Row {
                    id: bk
                    required property var modelData
                    spacing: det.s * 20
                    Text { width: det.s * 560; text: bk.modelData.name; color: det.ink; font.family: det.host.uiFont; font.pixelSize: det.s * 22; elide: Text.ElideMiddle }
                    Text { text: det.fullDate(bk.modelData.mtime); color: det.ink2; font.family: det.host.uiFont; font.pixelSize: det.s * 22 }
                    Text { text: det.bytes(bk.modelData.size); color: det.ink2; font.family: det.host.uiFont; font.pixelSize: det.s * 22 }
                }
            }
        }
    }

    // ---------- pestaña Actividad (sesiones) ----------
    Component {
        id: activityComp
        Column {
            id: ac
            spacing: det.s * 12
            readonly property var rows: det.activity && det.activity.sessions ? det.activity.sessions : []
            Text { visible: det.activity === null; text: qsTr("Cargando…"); color: det.ink2; font.family: det.host.uiFont; font.pixelSize: det.s * 24 }
            Text {
                visible: det.activity !== null && ac.rows.length === 0
                width: ac.width
                text: det.activity && det.activity.totalSecs > 0 ? qsTr("Has jugado %1, pero Omnia no tiene el detalle de las sesiones (proviene del historial de otro lanzador).").arg(det.host.duration(det.activity.totalSecs))
                                                                : qsTr("Aún no hay sesiones registradas. Aparecerán aquí cuando juegues desde Omnia.")
                color: det.ink2; font.family: det.host.uiFont; font.pixelSize: det.s * 24; wrapMode: Text.WordWrap
            }
            Repeater {
                model: ac.rows
                delegate: Row {
                    id: ar
                    required property var modelData
                    spacing: det.s * 24
                    LucideIcon { width: det.s * 26; height: det.s * 26; name: "calendar"; color: det.ink2; anchors.verticalCenter: parent.verticalCenter }
                    Text { width: det.s * 480; text: det.fullDate(ar.modelData.start); color: det.ink; font.family: det.host.uiFont; font.pixelSize: det.s * 24; anchors.verticalCenter: parent.verticalCenter }
                    Text { text: det.host.duration(ar.modelData.secs); color: det.ink2; font.family: det.host.uiFont; font.pixelSize: det.s * 24; anchors.verticalCenter: parent.verticalCenter }
                }
            }
        }
    }

    // ---------- menú ⋯ ----------
    Item {
        visible: det.menuOpen
        anchors.fill: parent
        z: 40
        MouseArea { anchors.fill: parent; onClicked: { det.menuOpen = false; det.zone = "more" } }
        Rectangle {
            x: moreB.mapToItem(det, 0, 0).x
            y: moreB.mapToItem(det, 0, moreB.height).y + det.s * 10
            width: det.s * 380
            height: mcol.implicitHeight + det.s * 16
            radius: det.s * 18
            color: det.host.surfaceFocus
            border.width: 1; border.color: Qt.rgba(1, 1, 1, 0.14)
            Column {
                id: mcol
                anchors { left: parent.left; right: parent.right; top: parent.top; margins: det.s * 8 }
                spacing: 2
                Repeater {
                    model: det.menuItems
                    delegate: Rectangle {
                        id: mi
                        required property var modelData
                        required property int index
                        width: parent.width; height: det.s * 54; radius: det.s * 12
                        color: det.menuIdx === index ? Qt.rgba(0.2, 0.396, 0.6, 0.9) : (mma.containsMouse ? Qt.rgba(1, 1, 1, 0.08) : "transparent")
                        Text { anchors { left: parent.left; leftMargin: det.s * 18; verticalCenter: parent.verticalCenter } text: mi.modelData.label; color: det.ink; font.family: det.host.uiFont; font.pixelSize: det.s * 22 }
                        MouseArea { id: mma; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onEntered: det.menuIdx = mi.index; onClicked: det.runMenu(mi.index) }
                    }
                }
            }
        }
    }

    Rectangle {
        anchors { left: parent.left; right: parent.right; bottom: footer.top; margins: det.host.contentInset; bottomMargin: det.s * 14 }
        height: 1
        color: "#24ffffff"
    }
    Row {
        id: footer
        anchors { left: parent.left; leftMargin: det.host.contentInset; bottom: parent.bottom; bottomMargin: det.s * 31 }
        spacing: det.s * 26

        component Hint: OmniaControlHint {
            uiScale: det.s
            uiFont: det.host.uiFont
            ink: det.ink
            muted: det.ink2
            roundButton: det.host.padOn
            padFamily: det.host.api.padFamily || "xbox"
            anchors.verticalCenter: parent.verticalCenter
        }

        LucideIcon {
            anchors.verticalCenter: parent.verticalCenter
            width: det.s * 25
            height: width
            name: det.host.padOn ? "gamepad-2" : "keyboard"
            color: det.ink2
        }
        Hint { padKeys: det.host.padOn ? ["A"] : []; glyph: "Enter"; label: qsTr("Aceptar") }
        Hint { visible: det.host.padOn && det.menuItems.length > 0; padKeys: ["X"]; label: qsTr("Menú") }
        Hint { padKeys: det.host.padOn ? ["LB", "RB"] : []; glyph: "RePág / AvPág"; label: qsTr("Cambiar pestaña") }
        Hint { visible: !det.host.padOn; icon: "mouse"; label: qsTr("Clic en una pestaña") }
        Hint { padKeys: det.host.padOn ? ["B"] : []; glyph: "Esc"; label: qsTr("Volver") }
    }
}

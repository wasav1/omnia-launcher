pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls

/** Biblioteca de la app de escritorio (estilo Steam con identidad Omnia): a la izquierda colecciones y juegos agrupados por
 *  consola; a la derecha la página del juego con banner, barra de acción (Jugar, última sesión, tiempo jugado) y pestañas. */
Item {
    id: ml
    property var manager: null
    property var api: null
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
    readonly property real s: manager ? manager.s : 1
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
    function selectGame(id) {
        selId = id
        tab = "summary"
        if (summaryScroll.contentItem) summaryScroll.contentItem.contentY = 0
    }
    onSearchChanged: if (search.trim() && visibleGames.length && !visibleGames.some(row => row.game.id === selId))
        selectGame(visibleGames[0].game.id)
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

    // ---------------- panel izquierdo
    Rectangle {
        id: left
        anchors { left: parent.left; top: parent.top; bottom: parent.bottom }
        width: Math.min(310, Math.max(230, parent.width * 0.29))
        color: "#0E141B"
        Rectangle { anchors.right: parent.right; width: 1; height: parent.height; color: "#1c2733" }
        Text { x: ml.s * 16; y: ml.s * 14; text: qsTr("Biblioteca"); color: manager.ink; font.family: ml.font; font.pixelSize: ml.s * 21; font.weight: Font.Bold }
        TextField {
            id: searchField
            anchors { left: parent.left; right: parent.right; top: parent.top; leftMargin: ml.s * 14; rightMargin: ml.s * 14; topMargin: ml.s * 48 }
            height: ml.s * 40
            placeholderText: qsTr("Buscar en tu biblioteca")
            text: ml.search
            onTextChanged: ml.search = text
            color: manager.ink; font.family: ml.font; font.pixelSize: ml.s * 15
            leftPadding: ml.s * 38
            background: Rectangle { radius: ml.s * 12; color: manager.surface2; border.color: searchField.activeFocus ? "#45CFC9" : "#24FFFFFF"
                LucideIcon { x: ml.s * 12; anchors.verticalCenter: parent.verticalCenter; width: ml.s * 17; height: width; name: "search"; color: manager.muted } }
        }
        Flow {
            id: collections
            anchors { left: parent.left; right: parent.right; top: searchField.bottom; topMargin: ml.s * 10; leftMargin: ml.s * 14; rightMargin: ml.s * 14 }
            spacing: ml.s * 6
            Repeater {
                model: [{ k: "all", l: qsTr("Todos") }, { k: "fav", l: qsTr("Favoritos") }, { k: "recent", l: qsTr("Recientes") }]
                delegate: Rectangle {
                    id: chip
                    required property var modelData
                    readonly property bool on: ml.collection === modelData.k
                    height: ml.s * 32; width: chipText.implicitWidth + ml.s * 26; radius: height / 2
                    color: on ? "#16434E" : (chipMa.containsMouse ? "#1AFFFFFF" : "transparent")
                    border.color: on ? "#45CFC9" : "#334352"
                    Text { id: chipText; anchors.centerIn: parent; text: chip.modelData.l; color: manager.ink; font.family: ml.font; font.pixelSize: ml.s * 14 }
                    MouseArea { id: chipMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: {
                            ml.chosenCollection = chip.modelData.k
                            if (ml.visibleGames.length && !ml.visibleGames.some(row => row.game.id === ml.selId))
                                ml.selectGame(ml.visibleGames[0].game.id)
                        } }
                }
            }
        }
        ListView {
            id: gameList
            anchors { left: parent.left; right: parent.right; top: collections.bottom; bottom: actions.top; topMargin: ml.s * 8; bottomMargin: ml.s * 6 }
            clip: true
            model: ml.visibleGames
            boundsBehavior: Flickable.StopAtBounds
            ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }
            section.property: "plat"
            section.criteria: ViewSection.FullString
            section.delegate: Item {
                id: sec
                required property string section
                width: gameList.width; height: ml.s * 34
                Row {
                    anchors { left: parent.left; leftMargin: ml.s * 16; verticalCenter: parent.verticalCenter }
                    spacing: ml.s * 8
                    Text { anchors.verticalCenter: parent.verticalCenter; text: sec.section.toUpperCase(); color: "#7f8da0"; font.family: ml.font; font.pixelSize: ml.s * 12; font.weight: Font.DemiBold; font.letterSpacing: 0.8 }
                }
            }
            delegate: Rectangle {
                id: row
                required property var modelData
                readonly property var g: modelData.game
                readonly property bool on: g.id === ml.selId
                width: gameList.width; height: ml.s * 49
                color: on ? "#16434E" : (rowMa.containsMouse ? "#14FFFFFF" : "transparent")
                Row {
                    anchors { left: parent.left; leftMargin: ml.s * 14; right: parent.right; rightMargin: ml.s * 10; verticalCenter: parent.verticalCenter }
                    spacing: ml.s * 10
                    Item {
                        width: ml.s * 32; height: width; anchors.verticalCenter: parent.verticalCenter
                        Rectangle { anchors.fill: parent; radius: ml.s * 6; color: manager.surface2 }
                        FadedImage { anchors.fill: parent; source: row.g.portada || ""; cornerRadius: ml.s * 6 }
                    }
                    Text { anchors.verticalCenter: parent.verticalCenter; width: parent.width - ml.s * 60; text: row.g.name + (row.g.fav ? "  ★" : "") + (row.g.portAvailable ? "  ⬇" : (row.g.updateAvailable ? "  ⟳" : "")); elide: Text.ElideRight
                        color: row.g.hidden ? manager.muted : manager.ink; font.family: ml.font; font.pixelSize: ml.s * 15; font.weight: row.on ? Font.DemiBold : Font.Normal }
                }
                MouseArea { id: rowMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; acceptedButtons: Qt.LeftButton | Qt.RightButton
                    onClicked: mouse => { if (mouse.button === Qt.RightButton) manager.openGameMenu(row.g); else ml.selectGame(row.g.id) }
                    onDoubleClicked: mouse => { if (mouse.button === Qt.LeftButton) manager.launch(row.g) } }
            }
            Text { visible: ml.visibleGames.length === 0; anchors.centerIn: parent; width: parent.width - ml.s * 40; horizontalAlignment: Text.AlignHCenter; wrapMode: Text.WordWrap
                text: ml.search ? qsTr("Ningún juego coincide.") : ml.collection === "fav" ? qsTr("Aún no tienes favoritos.") : qsTr("Añade juegos para verlos aquí."); color: manager.muted; font.family: ml.font; font.pixelSize: ml.s * 14 }
        }
        Row {
            id: actions
            anchors { left: parent.left; right: parent.right; bottom: parent.bottom; margins: ml.s * 12 }
            spacing: ml.s * 6
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
                    width: (actions.width - ml.s * 18) / 4; height: ml.s * 38; radius: ml.s * 10
                    color: ab.modelData.act === "add" ? manager.accent : (abMa.containsMouse ? "#26FFFFFF" : manager.surface2)
                    LucideIcon { anchors.centerIn: parent; width: ml.s * 18; height: width; name: ab.modelData.icon; color: manager.ink }
                    ToolTip.visible: abMa.containsMouse; ToolTip.text: ab.modelData.tip; ToolTip.delay: 400
                    MouseArea { id: abMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: manager.libraryAction(ab.modelData.act) }
                }
            }
        }
    }

    // ---------------- página del juego
    Item {
        id: page
        anchors { left: left.right; right: parent.right; top: parent.top; bottom: parent.bottom }
        visible: ml.current !== null
        readonly property var g: ml.current
        Item {
            id: hero
            anchors { left: parent.left; right: parent.right; top: parent.top }
            height: ml.s * 250
            Rectangle { anchors.fill: parent; color: manager.surface }
            FadedImage {
                anchors.fill: parent
                source: page.g ? (page.g.fondo || page.g.portada || "") : ""
                fadeBottom: 0.65
                alignX: 0.5
            }
            Rectangle { anchors.fill: parent; gradient: Gradient { GradientStop { position: 0.35; color: "#00090D12" } GradientStop { position: 1; color: "#E60B0F14" } } }
            Column {
                anchors { left: parent.left; bottom: parent.bottom; leftMargin: ml.s * 32; bottomMargin: ml.s * 20 }
                width: parent.width - ml.s * 64
                spacing: ml.s * 6
                Row {
                    spacing: ml.s * 8
                    PlatIcon { anchors.verticalCenter: parent.verticalCenter; key: page.g ? ml.platKey(page.g) : ""; size: ml.s * 20; color: manager.muted }
                    Text { anchors.verticalCenter: parent.verticalCenter; text: page.g ? (ml.platName(page.g) + (page.g.variant || page.g.src ? " · " + (page.g.variant || page.g.src) : "")).toUpperCase() : ""
                        color: manager.muted; font.family: ml.font; font.pixelSize: ml.s * 13; font.letterSpacing: 1.2 }
                }
                Text { width: parent.width; text: page.g ? page.g.name : ""; elide: Text.ElideRight; color: manager.ink; font.family: ml.font; font.pixelSize: ml.s * 38; font.weight: Font.Bold }
            }
        }
        Rectangle {      // barra de acción
            id: playBar
            anchors { left: parent.left; right: parent.right; top: hero.bottom }
            height: ml.s * 78
            color: "#0E141B"
            Row {
                anchors { left: parent.left; leftMargin: ml.s * 32; verticalCenter: parent.verticalCenter }
                spacing: ml.s * 22
                Rectangle {
                    readonly property bool offer: !!page.g && !!page.g.portAvailable
                    width: ml.s * 190; height: ml.s * 48; radius: ml.s * 10
                    color: offer ? manager.accent : (page.g && page.g.running ? manager.surface2 : "#2E8B57")
                    Row { anchors.centerIn: parent; spacing: ml.s * 8
                        LucideIcon { anchors.verticalCenter: parent.verticalCenter; width: ml.s * 18; height: width; name: parent.parent.offer ? "download" : "play"; color: "white" }
                        Text { anchors.verticalCenter: parent.verticalCenter; color: "white"; font.family: ml.font; font.pixelSize: ml.s * 18; font.weight: Font.DemiBold
                               text: parent.parent.offer ? qsTr("Instalar port") : (page.g && page.g.running ? qsTr("Jugando") : qsTr("Jugar")) } }
                    MouseArea { anchors.fill: parent; enabled: parent.offer || (!!page.g && !page.g.running); cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
                        onClicked: parent.offer ? manager.installPortFor(page.g) : manager.launch(page.g) }
                }
                Column { anchors.verticalCenter: parent.verticalCenter; spacing: ml.s * 2
                    Text { text: qsTr("Última sesión"); color: manager.muted; font.family: ml.font; font.pixelSize: ml.s * 12 }
                    Text { text: ml.dateText(ml.activity ? ml.activity.lastPlayed : (page.g ? ml.lastOf(page.g) : 0)); color: manager.ink; font.family: ml.font; font.pixelSize: ml.s * 16; font.weight: Font.DemiBold } }
                Column { anchors.verticalCenter: parent.verticalCenter; spacing: ml.s * 2
                    Text { text: qsTr("Tiempo jugado"); color: manager.muted; font.family: ml.font; font.pixelSize: ml.s * 12 }
                    Text { text: ml.activity && ml.activity.totalSecs > 0 ? ml.duration(ml.activity.totalSecs) : "—"; color: manager.ink; font.family: ml.font; font.pixelSize: ml.s * 16; font.weight: Font.DemiBold } }
            }
            Rectangle {      // favorito
                anchors { right: parent.right; rightMargin: ml.s * 32; verticalCenter: parent.verticalCenter }
                width: ml.s * 48; height: width; radius: ml.s * 10
                color: favMa.containsMouse ? "#26FFFFFF" : manager.surface2
                LucideIcon { anchors.centerIn: parent; width: ml.s * 20; height: width; name: "star"; color: page.g && page.g.fav ? "#f5b83d" : manager.muted }
                ToolTip.visible: favMa.containsMouse; ToolTip.text: page.g && page.g.fav ? qsTr("Quitar de favoritos") : qsTr("Añadir a favoritos"); ToolTip.delay: 400
                MouseArea { id: favMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: api.toggleFav(page.g) }
            }
        }
        Row {      // pestañas
            id: tabs
            anchors { left: parent.left; top: playBar.bottom; leftMargin: ml.s * 32; topMargin: ml.s * 16 }
            spacing: ml.s * 24
            Repeater {
                model: [{ k: "summary", l: qsTr("Resumen") }, { k: "saves", l: qsTr("Partidas") }, { k: "manage", l: qsTr("Administrar") }]
                delegate: Item {
                    id: tb
                    required property var modelData
                    readonly property bool on: ml.tab === modelData.k
                    width: tbText.implicitWidth; height: ml.s * 32
                    Text { id: tbText; text: tb.modelData.l; color: tb.on ? manager.ink : manager.muted; font.family: ml.font; font.pixelSize: ml.s * 17; font.weight: tb.on ? Font.DemiBold : Font.Normal }
                    Rectangle { anchors { left: parent.left; right: parent.right; bottom: parent.bottom } height: 2; color: "#45CFC9"; visible: tb.on }
                    MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: ml.tab = tb.modelData.k }
                }
            }
        }
        Item {
            anchors { left: parent.left; right: parent.right; top: tabs.bottom; bottom: parent.bottom; margins: ml.s * 32; topMargin: ml.s * 14 }
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
                    spacing: ml.s * 14
                    bottomPadding: ml.s * 12
                    Rectangle {      // actualización disponible
                        visible: !!page.g && !!page.g.updateAvailable && !page.g.portAvailable
                        width: parent.width; height: updNote.implicitHeight + ml.s * 24; radius: ml.s * 12; color: "#2F2A1B"; border.color: "#8A6D2F"
                        Text { id: updNote; anchors { left: parent.left; right: updBtn.left; verticalCenter: parent.verticalCenter; margins: ml.s * 16 }
                            wrapMode: Text.WordWrap; color: manager.ink; font.family: ml.font; font.pixelSize: ml.s * 15
                            text: page.g && page.g.updateAvailable ? qsTr("Actualización disponible: %1 → %2. Se conservan tus partidas y los datos del juego.").arg(page.g.updateAvailable.current || "?").arg(page.g.updateAvailable.version) : "" }
                        Rectangle { id: updBtn; anchors { right: parent.right; rightMargin: ml.s * 16; verticalCenter: parent.verticalCenter }
                            width: ml.s * 130; height: ml.s * 38; radius: ml.s * 10; color: page.g && page.g.running ? manager.surface2 : "#B8862F"
                            Text { anchors.centerIn: parent; text: qsTr("Actualizar"); color: "white"; font.family: ml.font; font.pixelSize: ml.s * 15; font.weight: Font.DemiBold }
                            MouseArea { anchors.fill: parent; enabled: !!page.g && !page.g.running; cursorShape: Qt.PointingHandCursor; onClicked: manager.updateFor(page.g) } }
                    }
                    Rectangle {      // port disponible
                        visible: !!page.g && !!page.g.portAvailable
                        width: parent.width; height: portNote.implicitHeight + ml.s * 24; radius: ml.s * 12; color: "#1F2F44"; border.color: "#3B6A99"
                        Text { id: portNote; anchors { left: parent.left; right: parent.right; verticalCenter: parent.verticalCenter; margins: ml.s * 16 }
                            wrapMode: Text.WordWrap; color: manager.ink; font.family: ml.font; font.pixelSize: ml.s * 15
                            text: page.g && page.g.portAvailable ? qsTr("Port disponible: %1 · %2 · licencia %3. Detectamos tu copia del juego; pulsa «Instalar port» para descargarlo y verificarlo.").arg(page.g.portAvailable.title).arg(page.g.portAvailable.version).arg(page.g.portAvailable.licenseName) : "" }
                    }
                    GameFacts {
                        width: parent.width
                        api: ml.api; game: page.g; uiScale: ml.s; uiFont: ml.font
                        ink: manager.ink; muted: manager.muted
                    }
                    Row {
                        spacing: ml.s * 12
                        Repeater {
                            model: [
                                { l: qsTr("Fuente"), v: page.g ? (page.g.variant || page.g.src || "—") : "—" },
                                { l: qsTr("Consola"), v: page.g ? ml.platName(page.g) : "—" },
                                { l: qsTr("Carpeta"), v: page.g && page.g.folder ? page.g.folder : "—" }
                            ]
                            delegate: Rectangle {
                                id: card
                                required property var modelData
                                width: Math.min(ml.s * 330, (page.width - ml.s * 64 - ml.s * 24) / 3); height: ml.s * 70; radius: ml.s * 12; color: manager.surface
                                Column { anchors { left: parent.left; right: parent.right; verticalCenter: parent.verticalCenter; margins: ml.s * 16 } spacing: ml.s * 4
                                    Text { text: card.modelData.l; color: manager.muted; font.family: ml.font; font.pixelSize: ml.s * 12 }
                                    Text { width: parent.width; text: card.modelData.v; elide: Text.ElideMiddle; color: manager.ink; font.family: ml.font; font.pixelSize: ml.s * 15; font.weight: Font.DemiBold } }
                            }
                        }
                    }
                    Text {      // tu copia del juego (volcado .nup o carpeta exefs+romfs que Omnia unió con este port)
                        visible: !!page.g && !!page.g.romCopy
                        width: parent.width; wrapMode: Text.WrapAnywhere; color: manager.muted; font.family: ml.font; font.pixelSize: ml.s * 13
                        text: page.g && page.g.romCopy ? qsTr("Tu copia del juego: %1").arg(page.g.romCopy.path) + (page.g.romCopy.buildId ? "  ·  build " + page.g.romCopy.buildId.substring(0, 12) : "") : ""
                    }
                    Text {      // ¿la copia es la versión que acepta el port? (build ID del exefs/main contra el descriptor del port)
                        visible: !!page.g && !!page.g.romCopy && !!page.g.romCopy.compat
                        width: parent.width; wrapMode: Text.WordWrap; font.family: ml.font; font.pixelSize: ml.s * 13
                        readonly property string st: page.g && page.g.romCopy && page.g.romCopy.compat ? page.g.romCopy.compat.state : ""
                        color: st === "ok" ? "#7fd69f" : (st === "mismatch" ? "#e8a24b" : manager.muted)
                        text: st === "ok" ? qsTr("Es la versión que acepta este port.")
                            : (st === "mismatch" ? qsTr("Esta copia es de otra versión (build %1); el port espera %2.").arg((page.g.romCopy.compat.found || "").substring(0, 8)).arg(page.g.romCopy.compat.expected.join(", "))
                            : qsTr("No se pudo comprobar la versión de esta copia (un archivo .nup no se lee todavía); el port espera el build %1.").arg(page.g && page.g.romCopy && page.g.romCopy.compat ? page.g.romCopy.compat.expected.join(", ") : ""))
                    }
                    Rectangle {      // el port cerró con un código que él mismo explica (exit_codes de su descriptor)
                        visible: !!page.g && !!page.g.lastExit
                        width: parent.width; height: exitNote.implicitHeight + ml.s * 20; radius: ml.s * 10; color: "#3A2A1E"; border.color: "#8A5A2F"
                        Text { id: exitNote; anchors { left: parent.left; right: parent.right; verticalCenter: parent.verticalCenter; margins: ml.s * 14 }
                            wrapMode: Text.WordWrap; color: manager.ink; font.family: ml.font; font.pixelSize: ml.s * 14
                            text: page.g && page.g.lastExit ? qsTr("La última vez, el juego se cerró con este aviso: %1").arg(page.g.lastExit.message) : "" }
                    }
                    Text {      // requisitos que declara el port (glibc, Vulkan…) y si este PC los cumple
                        visible: !!page.g && !!page.g.requirements && page.g.requirements.length > 0
                        width: parent.width; wrapMode: Text.WordWrap; font.family: ml.font; font.pixelSize: ml.s * 13
                        readonly property var bad: page.g && page.g.requirements ? page.g.requirements.filter(function(r) { return r.ok === false }) : []
                        color: bad.length > 0 ? "#e8a24b" : manager.muted
                        text: page.g && page.g.requirements
                              ? qsTr("Requisitos: %1").arg(page.g.requirements.map(function(r) { return r.label + " " + r.need + (r.ok === false ? " ✗ (este PC: " + r.have + ")" : (r.ok === true ? " ✓" : "")) }).join("  ·  "))
                                + (bad.length > 0 ? "  " + qsTr("El juego puede no arrancar.") : "") : ""
                    }
                    Text {
                        text: qsTr("Juegos instalados")
                        color: manager.ink; font.family: ml.font
                        font.pixelSize: ml.s * 21; font.weight: Font.DemiBold
                        visible: ml.installedIds.length > 0
                    }
                    Grid {
                        id: installedGrid
                        x: ml.s * 10
                        width: parent.width - 2 * x
                        readonly property real gap: ml.s * 17
                        readonly property real cardWidth: (width - gap * (columns - 1)) / columns
                        columns: Math.max(1, Math.floor((width + gap) / (ml.s * 185 + gap)))
                        spacing: gap
                        Repeater {
                            model: ml.installedIds
                            delegate: ManagerPosterCard {
                                id: installedCard
                                viewport: summaryScroll.contentItem
                                required property string modelData
                                readonly property var game: ml.gameById.get(modelData)
                                readonly property var origin: game ? manager.sourceForGame(game) : null
                                width: installedGrid.cardWidth; height: width * 1.42
                                scaleFactor: ml.s
                                title: game?.name || ""
                                artwork: game?.portada || game?.fondo || ""
                                store: origin?.label || ""
                                sourceLogo: origin?.logo || ""
                                platform: game ? ml.platName(game) : ""
                                installed: true
                                onContextRequested: manager.openGameMenu(game)
                                onActivated: ml.selectGame(modelData)
                            }
                        }
                    }
                }
            }
            // Partidas
            Column {
                visible: ml.tab === "saves"
                width: parent.width; spacing: ml.s * 12
                Text { width: parent.width; text: qsTr("Respalda las partidas guardadas o abre su carpeta."); color: manager.muted; wrapMode: Text.WordWrap; font.family: ml.font; font.pixelSize: ml.s * 15 }
                Row {
                    spacing: ml.s * 10
                    Repeater {
                        model: [{ l: qsTr("Respaldar partidas"), k: "backup" }, { l: qsTr("Abrir carpeta de partidas"), k: "open" }]
                        delegate: Rectangle {
                            id: sb
                            required property var modelData
                            width: sbText.implicitWidth + ml.s * 40; height: ml.s * 42; radius: ml.s * 10; color: manager.surface2
                            Text { id: sbText; anchors.centerIn: parent; text: sb.modelData.l; color: manager.ink; font.family: ml.font; font.pixelSize: ml.s * 14 }
                            MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    if (sb.modelData.k === "backup") api.savesBackup(page.g, function(st, b) { api.notify(st === 200 ? qsTr("Respaldo creado.") : ((b && b.error) || qsTr("No se pudo respaldar."))) })
                                    else api.savesOpen(page.g, function() { })
                                } }
                        }
                    }
                }
                Row {       // carpetas que declara el port (partidas, logs, carpeta del juego…)
                    visible: !!page.g && !!page.g.folderActions && page.g.folderActions.length > 0
                    spacing: ml.s * 10
                    Repeater {
                        model: page.g && page.g.folderActions ? page.g.folderActions : []
                        delegate: Rectangle {
                            id: fb
                            required property var modelData
                            width: fbText.implicitWidth + ml.s * 40; height: ml.s * 42; radius: ml.s * 10; color: manager.surface2
                            Text { id: fbText; anchors.centerIn: parent; text: fb.modelData.label; color: manager.ink; font.family: ml.font; font.pixelSize: ml.s * 14 }
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
                width: parent.width; spacing: ml.s * 10
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
                        width: mbText.implicitWidth + ml.s * 40; height: ml.s * 42; radius: ml.s * 10
                        color: modelData.danger ? "#50343A" : manager.surface2
                        Text { id: mbText; anchors.centerIn: parent; text: mb.modelData.l; color: manager.ink; font.family: ml.font; font.pixelSize: ml.s * 14 }
                        MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: manager.gameAction(mb.modelData.k, page.g) }
                    }
                }
            }
        }
    }
    Text { visible: ml.current === null; anchors { left: left.right; right: parent.right; verticalCenter: parent.verticalCenter }
        horizontalAlignment: Text.AlignHCenter; text: qsTr("Elige un juego de la lista."); color: manager.muted; font.family: ml.font; font.pixelSize: ml.s * 18 }
}

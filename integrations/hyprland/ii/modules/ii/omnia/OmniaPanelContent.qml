pragma ComponentBehavior: Bound

import qs.services
import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import Qt5Compat.GraphicalEffects as Effects
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell

/**
 * Panel rápido de Omnia, en dos columnas: a la izquierda la lista de juegos (con scroll); a la derecha el juego
 * seleccionado con «Jugar» y el menú «⋯», los recientes (hasta 3) y el acceso a BigMode.
 *   seleccionar → clic en un juego de la lista o en un reciente (solo cambia la selección)
 *   jugar       → botón «Jugar» (cierra el panel)
 *   BigMode     → «Big Mode» o «Ver detalles en Big Mode» del menú ⋯
 * Teclado y mando: ↑↓ lista · ←→ entre zonas · Enter/A acepta · M/Y menú · Tab cambia de zona · Esc/B atrás.
 */
Item {
    id: root
    signal closeRequested()

    readonly property bool blur: OmniaSettings.blur
    readonly property var game: OmniaApi.selectedGame
    property string searchText: ""
    readonly property var games: {
        const query = searchText.trim().toLocaleLowerCase();
        return query ? OmniaApi.library.filter(g =>
            [g.name, g.variant, g.src].some(value => (value || "").toLocaleLowerCase().includes(query))) : OmniaApi.library;
    }
    property date dateReference: new Date()
    onActiveChanged: if (active) dateReference = new Date()
    function playedDate(seconds) {
        const date = new Date(seconds * 1000);
        const day = Date.UTC(date.getFullYear(), date.getMonth(), date.getDate());
        const today = Date.UTC(dateReference.getFullYear(), dateReference.getMonth(), dateReference.getDate());
        const elapsed = (today - day) / 86400000;
        if (elapsed <= 0) return "Hoy";
        if (elapsed === 1) return "Ayer";
        if (elapsed < 7) return "Hace " + elapsed + " días";
        return date.toLocaleDateString(Qt.locale("es_CO"), "d MMM yyyy");
    }
    property string screenName: ""
    readonly property bool active: OmniaPanelState.shown && OmniaPanelState.screenName === screenName
    property string view: "main"                  // main | settings
    property string zone: "list"                  // list | play | more | recent
    property int recentIdx: 0
    property bool menuOpen: false
    property int menuIdx: 0
    property real menuX: 0
    property real menuY: 0

    focus: true
    implicitWidth: 840
    implicitHeight: view === "main" ? 580 : 580

    // ---------------- menú ⋯ ----------------
    readonly property var menuItems: {
        const g = root.game, out = [];
        if (!g) return out;
        if (g.portAvailable) out.push({ id: "port", label: "Instalar port en la app de escritorio", icon: "download" });
        if (g.updateAvailable && !g.running) out.push({ id: "update", label: "Actualizar en la app de escritorio (" + (g.updateAvailable.version || "nueva versión") + ")", icon: "download" });
        out.push({ id: "details", label: "Ver detalles en Big Mode", icon: "layout-grid" });
        out.push({ id: "fav", label: g.fav ? "Quitar de favoritos" : "Añadir a favoritos", icon: "star" });
        if (OmniaWallpaper.canPin(g)) out.push({ id: "pin", label: "Usar su fondo en el escritorio", icon: "image" });
        if (OmniaWallpaper.pinned) out.push({ id: "unpin", label: "Quitar fondo fijado", icon: "eye-off" });
        if (g.folder) out.push({ id: "folder", label: "Abrir carpeta del juego", icon: "folder-open" });
        return out;
    }
    function openMenu() {
        if (!game || menuItems.length === 0) return;
        const p = moreBtn.mapToItem(root, moreBtn.width, moreBtn.height + 8);
        menuX = Math.max(8, Math.min(root.width - 280, p.x - 270));
        menuY = p.y;
        menuIdx = 0;                              // el foco empieza en la primera opción
        menuOpen = true;
    }
    function closeMenu() { menuOpen = false; zone = "more"; root.forceActiveFocus(); }
    function runMenu(i) {
        const it = menuItems[i];
        if (!it || !game) return;
        if (it.id === "port") { OmniaApi.openDesktop(game.id, "install"); menuOpen = false; root.closeRequested(); return; }
        if (it.id === "update") { OmniaApi.openDesktop(game.id, "update"); menuOpen = false; root.closeRequested(); return; }
        if (it.id === "details") { OmniaApi.openBigMode(game.id, true); menuOpen = false; root.closeRequested(); return; }
        if (it.id === "fav") OmniaApi.toggleFav(game.id);
        else if (it.id === "pin") OmniaWallpaper.pin(game);
        else if (it.id === "unpin") OmniaWallpaper.unpin();
        else if (it.id === "folder") Quickshell.execDetached(["xdg-open", game.folder]);
        closeMenu();                              // ninguna acción del menú inicia el juego
    }

    // ---------------- selección y navegación ----------------
    readonly property int selIndex: {
        const id = OmniaApi.selected.id;
        return id ? games.findIndex(g => g.id === id) : -1;
    }
    function step(d) {
        if (games.length === 0) return;
        const i = selIndex < 0 ? (d > 0 ? 0 : games.length - 1) : Math.max(0, Math.min(games.length - 1, selIndex + d));
        OmniaApi.select(games[i].id);
        list.positionViewAtIndex(i, ListView.Contain);    // la selección siempre queda visible
    }
    function playGame() {
        if (!game) return;
        if (game.portAvailable) { OmniaApi.openDesktop(game.id, "install"); closeRequested(); return; }     // un volcado con port disponible: «Jugar» ofrece instalarlo
        if (OmniaApi.play(game.id)) closeRequested();
    }

    function nav(k) {
        if (view === "settings") { if (k === "back") view = "main"; return; }
        if (menuOpen) {
            const n = menuItems.length;
            if (k === "up") menuIdx = (menuIdx - 1 + n) % n;
            else if (k === "down") menuIdx = (menuIdx + 1) % n;
            else if (k === "accept") runMenu(menuIdx);
            else if (k === "back" || k === "menu") closeMenu();
            return;
        }
        const rc = OmniaApi.recent.length;
        if (k === "back") closeRequested();
        else if (k === "menu") openMenu();
        else if (k === "up") { if (zone === "list") step(-1); else if (zone === "recent") zone = "play"; else if (zone === "big") zone = rc > 0 ? "recent" : "play"; }
        else if (k === "down") {
            if (zone === "list") step(1);
            else if ((zone === "play" || zone === "more") && rc > 0) { zone = "recent"; recentIdx = Math.min(recentIdx, rc - 1); }
            else if (zone !== "big") zone = "big";
        }
        else if (k === "left") {
            if (zone === "play") zone = "list";
            else if (zone === "more") zone = "play";
            else if (zone === "recent") { if (recentIdx > 0) recentIdx--; else zone = "list"; }
        }
        else if (k === "right") {
            if (zone === "list") zone = "play";
            else if (zone === "play") zone = "more";
            else if (zone === "recent") recentIdx = Math.min(rc - 1, recentIdx + 1);
        }
        else if (k === "accept") {
            if (zone === "more") openMenu();
            else if (zone === "big") bigModeButton.clicked();
            else if (zone === "recent") { if (OmniaApi.recent[recentIdx]) { OmniaApi.select(OmniaApi.recent[recentIdx].id); zone = "play"; } }
            else playGame();
        }
        else if (k === "tab") {
            const order = rc > 0 ? ["list", "play", "more", "recent", "big"] : ["list", "play", "more", "big"];
            zone = order[(order.indexOf(zone) + 1) % order.length];
        }
    }
    Keys.onPressed: e => {
        OmniaPanelState.touch();
        const map = {};
        map[Qt.Key_Up] = "up"; map[Qt.Key_Down] = "down"; map[Qt.Key_Left] = "left"; map[Qt.Key_Right] = "right";
        map[Qt.Key_Return] = "accept"; map[Qt.Key_Enter] = "accept"; map[Qt.Key_Escape] = "back"; map[Qt.Key_Menu] = "menu";
        map[Qt.Key_M] = "menu"; map[Qt.Key_Tab] = "tab";
        const k = map[e.key];
        if (k === undefined) return;
        e.accepted = true;
        nav(k);
    }
    Connections {
        target: OmniaApi
        enabled: root.active
        function onPadKey(k) {
            const map = { l: "left", r: "right", u: "up", d: "down", A: "accept", B: "back", Y: "menu", X: "menu" };
            if (map[k]) root.nav(map[k]);
        }
    }
    Binding { target: OmniaPanelState; property: "keepOpen"; value: root.menuOpen || root.view === "settings"; when: root.active }
    Binding { target: OmniaApi; property: "padPolling"; value: OmniaPanelState.shown; when: root.active }
    Connections {
        target: OmniaPanelState
        function onNavRequested(k) { if (root.active) root.nav(k); }
        function onViewRequested(v) {
            if (!root.active) return;
            if (v === "settings") root.openSettings();
            else if (v === "menu") { root.view = "main"; root.openMenu(); }
        }
        function onModeChanged() {
            if (OmniaPanelState.mode === "closed") { root.view = "main"; root.menuOpen = false; root.zone = "list"; root.searchText = ""; }
            else if (OmniaPanelState.mode === "pinned") root.forceActiveFocus();
        }
    }
    function openSettings() {
        OmniaPanelState.pin();
        view = "settings";
    }
    onSelIndexChanged: if (selIndex >= 0 && view === "main") list.positionViewAtIndex(selIndex, ListView.Contain)

    // ---------------- diseño ----------------
    ColumnLayout {
        anchors { fill: parent; margins: 16 }
        spacing: 12

        // cabecera
        RowLayout {
            Layout.fillWidth: true
            spacing: 10
            OmniaIconAction { visible: root.view !== "main"; icon: "arrow-left"; onClicked: root.view = "main" }
            Image {
                visible: root.view === "main"
                Layout.preferredWidth: 40
                Layout.preferredHeight: 40
                fillMode: Image.PreserveAspectFit
                source: "images/omnia-logo.svg"
            }
            ColumnLayout {
                spacing: 0
                StyledText { text: root.view === "main" ? "Omnia" : "Ajustes"; font.pixelSize: Appearance.font.pixelSize.huge; color: OmniaTheme.ink }
                StyledText {
                    visible: root.view === "main" && OmniaApi.status !== "ok"
                    text: OmniaApi.status === "error" ? "Sin conexión" : OmniaApi.status === "empty" ? "Biblioteca vacía" : "Conectando…"
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    color: OmniaApi.status === "error" ? OmniaTheme.danger : OmniaTheme.inkDim
                }
            }
            Item { Layout.fillWidth: true }
            OmniaPadChip { visible: root.view === "main"; Layout.alignment: Qt.AlignVCenter }
            OmniaIconAction { visible: root.view === "main"; icon: "settings"; onClicked: root.openSettings() }
            OmniaIconAction { visible: root.view === "main"; icon: "refresh-cw"; onClicked: { OmniaApi.refresh(); OmniaApi.pollSelection(); } }
            OmniaIconAction { icon: "x"; onClicked: root.closeRequested() }
        }

        // ---------- ajustes ----------
        OmniaSettingsView {
            visible: root.view === "settings"
            Layout.fillWidth: true
            Layout.fillHeight: true
        }

        // ---------- error / vacío ----------
        Rectangle {
            visible: root.view === "main" && (OmniaApi.status === "error" || OmniaApi.status === "empty" || OmniaApi.status === "loading")
            Layout.fillWidth: true
            Layout.fillHeight: true
            radius: 16
            color: OmniaTheme.card(root.blur)
            border.width: 1
            border.color: OmniaTheme.line
            ColumnLayout {
                anchors.centerIn: parent
                width: Math.min(parent.width - 60, 460)
                spacing: 10
                OmniaLucide {
                    Layout.alignment: Qt.AlignHCenter
                    name: OmniaApi.status === "error" ? "circle-alert" : OmniaApi.status === "empty" ? "plus" : "clock"
                    width: 40; height: 40
                    color: OmniaApi.status === "error" ? OmniaTheme.danger : OmniaTheme.inkDim
                }
                StyledText {
                    Layout.alignment: Qt.AlignHCenter
                    text: OmniaApi.status === "error" ? "No se pudo cargar la biblioteca" : OmniaApi.status === "empty" ? "Tu biblioteca está vacía" : "Conectando con Omnia…"
                    font.pixelSize: Appearance.font.pixelSize.larger
                    color: OmniaApi.status === "error" ? OmniaTheme.danger : OmniaTheme.ink
                }
                StyledText {
                    Layout.fillWidth: true
                    horizontalAlignment: Text.AlignHCenter
                    wrapMode: Text.Wrap
                    visible: OmniaApi.status !== "loading"
                    text: OmniaApi.status === "error" ? OmniaApi.errorText + ". El fondo del escritorio no se modifica." : "Aún no hay juegos detectados. Abre BigMode para importarlos."
                    color: OmniaTheme.inkDim
                }
                RowLayout {
                    Layout.alignment: Qt.AlignHCenter
                    spacing: 8
                    OmniaPill { visible: OmniaApi.status === "error"; label: "Reintentar"; icon: "refresh-cw"; primary: true; onClicked: { OmniaApi.refresh(); OmniaApi.pollSelection(); } }
                    OmniaPill { visible: OmniaApi.status === "error"; label: "Ver registro"; icon: "circle-alert"; onClicked: Quickshell.execDetached(["bash", "-c", Config.options.apps.terminal + " journalctl --user -u omnia -n 60 --no-pager -f"]) }
                    OmniaPill { visible: OmniaApi.status === "empty"; label: "Big Mode"; icon: "layout-grid"; primary: true; onClicked: { OmniaApi.openBigMode("", false); root.closeRequested(); } }
                }
            }
        }

        // ---------- dos columnas ----------
        RowLayout {
            visible: root.view === "main" && OmniaApi.status === "ok"
            Layout.fillWidth: true
            Layout.fillHeight: true
            spacing: 14

            // ===== izquierda: lista de juegos =====
            Rectangle {
                Layout.preferredWidth: 300
                Layout.fillHeight: true
                radius: 20
                color: OmniaTheme.card(root.blur)
                border.width: 1
                border.color: OmniaTheme.line

                Rectangle {
                    id: searchBox
                    anchors { left: parent.left; right: parent.right; top: parent.top; margins: 8 }
                    height: 36
                    radius: 18
                    color: OmniaTheme.surface
                    border.width: searchField.activeFocus ? 1 : 0
                    border.color: OmniaTheme.ring
                    OmniaLucide {
                        id: searchIcon
                        anchors { left: parent.left; leftMargin: 10; verticalCenter: parent.verticalCenter }
                        width: 17; height: 17
                        name: "search"
                        color: OmniaTheme.inkDim
                    }
                    TextField {
                        id: searchField
                        anchors { left: searchIcon.right; right: parent.right; verticalCenter: parent.verticalCenter; leftMargin: 6; rightMargin: 6 }
                        height: parent.height
                        text: root.searchText
                        placeholderText: "Buscar juegos…"
                        color: OmniaTheme.ink
                        placeholderTextColor: OmniaTheme.inkDim
                        background: Item {}
                        Accessible.name: "Buscar juegos"
                        onTextEdited: root.searchText = text
                        onAccepted: {
                            if (root.games.length) OmniaApi.select(root.games[0].id);
                            root.forceActiveFocus();
                        }
                        Keys.onEscapePressed: {
                            root.searchText = "";
                            root.forceActiveFocus();
                        }
                        Keys.onDownPressed: {
                            root.forceActiveFocus();
                            if (root.games.length) OmniaApi.select(root.games[0].id);
                        }
                    }
                }
                StyledText {
                    anchors.centerIn: list
                    visible: root.games.length === 0
                    text: "Ningún juego coincide"
                    color: OmniaTheme.inkDim
                }
                ListView {
                    id: list
                    anchors { left: parent.left; right: parent.right; bottom: parent.bottom; top: searchBox.bottom; margins: 8 }
                    clip: true
                    spacing: 4
                    model: root.games
                    boundsBehavior: Flickable.StopAtBounds
                    flickableDirection: Flickable.VerticalFlick
                    ScrollBar.vertical: ScrollBar {
                        id: sbar
                        policy: ScrollBar.AsNeeded
                        visible: list.contentHeight > list.height + 1      // solo si la lista no cabe
                        interactive: true                    // se puede arrastrar
                        width: 10
                        contentItem: Rectangle {
                            implicitWidth: 6
                            radius: 3
                            color: OmniaTheme.ink
                            opacity: sbar.pressed ? 0.6 : (sbar.hovered || list.moving ? 0.4 : 0.22)
                        }
                        background: Item {}
                    }
                    delegate: Rectangle {
                        id: row
                        required property var modelData
                        required property int index
                        readonly property bool sel: OmniaApi.selected.id === modelData.id
                        width: list.width - 12
                        height: 72
                        radius: 12
                        color: sel ? OmniaTheme.rowSelected() : (rowMa.containsMouse ? Qt.rgba(1, 1, 1, 0.07) : "transparent")
                        border.width: sel && root.zone === "list" && root.activeFocus ? 2 : 0
                        border.color: OmniaTheme.ring
                        Behavior on color { ColorAnimation { duration: 110 } }
                        RowLayout {
                            anchors { fill: parent; leftMargin: 10; rightMargin: 10 }
                            spacing: 12
                            OmniaRoundedImage {
                                Layout.preferredWidth: 54; Layout.preferredHeight: 54
                                radius: 10
                                source: row.modelData.portada ?? ""
                                Rectangle {
                                    anchors.fill: parent; radius: 10; z: -1; color: OmniaTheme.surface
                                    StyledText { anchors.centerIn: parent; text: (row.modelData.name || "?").charAt(0).toUpperCase(); font.pixelSize: 22; color: OmniaTheme.inkDim }
                                }
                            }
                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: 1
                                StyledText {
                                    Layout.fillWidth: true
                                    text: row.modelData.name
                                    font.pixelSize: Appearance.font.pixelSize.normal
                                    color: OmniaTheme.ink
                                    elide: Text.ElideRight
                                    maximumLineCount: 2
                                    wrapMode: Text.Wrap
                                }
                                OmniaPlatformLine { Layout.fillWidth: true; game: row.modelData }
                            }
                        }
                        MouseArea {
                            id: rowMa
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: { root.zone = "list"; OmniaApi.select(row.modelData.id); }
                        }
                    }
                }
            }

            // ===== derecha =====
            ColumnLayout {
                Layout.fillWidth: true
                Layout.fillHeight: true
                spacing: 12

                // juego seleccionado
                Item {
                    id: hero
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    Layout.minimumHeight: 170

                    readonly property real corner: 20
                    Rectangle { anchors.fill: parent; radius: hero.corner; color: OmniaTheme.card(root.blur) }
                    OmniaRoundedImage {
                        anchors.fill: parent
                        radius: hero.corner
                        source: root.game ? (root.game.fondo || root.game.portada || "") : ""
                    }
                    Effects.LinearGradient {
                        id: bannerFade
                        anchors.fill: parent
                        start: Qt.point(0, height)
                        end: Qt.point(width * 0.83, height * 0.12)
                        visible: false
                        gradient: Gradient {
                            GradientStop { position: 0.0; color: "#fa0b0f14" }
                            GradientStop { position: 0.38; color: "#b80b0f14" }
                            GradientStop { position: 0.72; color: "#300b0f14" }
                            GradientStop { position: 1.0; color: "transparent" }
                        }
                    }
                    Rectangle { id: bannerMask; anchors.fill: parent; radius: hero.corner; visible: false }
                    Effects.OpacityMask { anchors.fill: parent; source: bannerFade; maskSource: bannerMask }
                    Rectangle { anchors.fill: parent; radius: hero.corner; color: "transparent"; border.color: OmniaTheme.line }

                    StyledText {
                        visible: !root.game
                        anchors.centerIn: parent
                        text: "Elige un juego de la lista"
                        color: OmniaTheme.inkDim
                        font.pixelSize: Appearance.font.pixelSize.larger
                    }
                    ColumnLayout {
                        visible: !!root.game
                        anchors { left: parent.left; right: parent.right; bottom: parent.bottom; margins: 16 }
                        spacing: 4
                        Item {      // logo del juego; si no tiene, su nombre
                            Layout.fillWidth: true
                            Layout.preferredHeight: 72
                            Image {
                                id: heroLogo
                                anchors.fill: parent
                                source: root.game && root.game.logo ? root.game.logo : ""
                                fillMode: Image.PreserveAspectFit
                                horizontalAlignment: Image.AlignLeft
                                verticalAlignment: Image.AlignBottom
                                asynchronous: true
                                smooth: true
                                mipmap: true
                                sourceSize.height: 216
                                visible: status === Image.Ready
                            }
                            StyledText {
                                visible: heroLogo.status !== Image.Ready
                                anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
                                text: root.game ? root.game.name : ""
                                font.pixelSize: 28
                                font.weight: Font.DemiBold
                                color: OmniaTheme.ink
                                elide: Text.ElideRight
                            }
                        }
                        OmniaPlatformLine { Layout.fillWidth: true; game: root.game }
                        StyledText {
                            Layout.fillWidth: true
                            visible: text.length > 0
                            text: root.game?.description || ""
                            color: OmniaTheme.ink
                            font.pixelSize: Appearance.font.pixelSize.smaller
                            wrapMode: Text.WordWrap
                            maximumLineCount: 2
                            elide: Text.ElideRight
                        }
                        RowLayout {
                            Layout.topMargin: 6
                            spacing: 10
                            OmniaPill {
                                id: playBtn
                                label: root.game && root.game.running ? "En ejecución" : (root.game && root.game.portAvailable ? "Instalar port" : "Jugar")
                                icon: root.game && root.game.portAvailable ? "download" : "play"
                                primary: true
                                implicitHeight: 44
                                implicitWidth: 170
                                enabled2: !(root.game && root.game.running)
                                ringed: root.zone === "play" && root.activeFocus
                                onClicked: { root.zone = "play"; root.playGame(); }
                            }
                            Rectangle {
                                id: moreBtn
                                implicitWidth: 44; implicitHeight: 44; radius: 22
                                color: moreMa.containsMouse || root.menuOpen ? Qt.rgba(1, 1, 1, 0.22) : Qt.rgba(1, 1, 1, 0.12)
                                border.width: root.zone === "more" && root.activeFocus ? 2 : 0
                                border.color: OmniaTheme.ring
                                OmniaLucide { anchors.centerIn: parent; name: "ellipsis"; width: 26; height: 26; color: OmniaTheme.ink }
                                MouseArea { id: moreMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: { root.zone = "more"; root.menuOpen ? root.closeMenu() : root.openMenu(); } }
                            }
                        }
                    }
                }

                // recientes (hasta tres, una sola fila)
                ColumnLayout {
                    visible: OmniaApi.recent.length > 0
                    Layout.fillWidth: true
                    spacing: 6
                    StyledText { text: "Jugado recientemente"; font.weight: Font.DemiBold; font.pixelSize: Appearance.font.pixelSize.normal; color: OmniaTheme.ink }
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 10
                        Repeater {
                            model: OmniaApi.recent
                            delegate: Rectangle {
                                id: rc
                                required property var modelData
                                required property int index
                                readonly property bool sel: OmniaApi.selected.id === modelData.id
                                Layout.fillWidth: true
                                Layout.minimumWidth: 60
                                Layout.preferredWidth: 150
                                Layout.maximumWidth: 170
                                Layout.preferredHeight: 122
                                radius: 16
                                color: rc.sel ? OmniaTheme.rowSelected() : OmniaTheme.card(root.blur)
                                border.color: OmniaTheme.line
                                OmniaRoundedImage {
                                    id: thumb
                                    anchors { left: parent.left; right: parent.right; top: parent.top }
                                    height: 78
                                    radius: 16
                                    source: rc.modelData.fondo || rc.modelData.portada || ""
                                    Rectangle {
                                        anchors.fill: parent; radius: 12; z: -1; color: OmniaTheme.surface
                                        StyledText { anchors.centerIn: parent; text: (rc.modelData.name || "?").charAt(0).toUpperCase(); font.pixelSize: 28; color: OmniaTheme.inkDim }
                                    }
                                }
                                Rectangle {
                                    anchors.fill: thumb
                                    radius: thumb.radius
                                    color: recentLogo.status === Image.Ready ? "#65000000" : "transparent"
                                }
                                Image {
                                    id: recentLogo
                                    anchors.fill: thumb
                                    anchors.leftMargin: 20
                                    anchors.rightMargin: 20
                                    anchors.topMargin: 10
                                    anchors.bottomMargin: 10
                                    source: rc.modelData.logo || ""
                                    fillMode: Image.PreserveAspectFit
                                    asynchronous: true
                                    visible: status === Image.Ready
                                }
                                Rectangle {
                                    anchors.fill: parent
                                    radius: rc.radius
                                    color: "transparent"
                                    border.width: rc.sel || (root.zone === "recent" && root.recentIdx === rc.index && root.activeFocus) ? 2 : 0
                                    border.color: rc.sel ? OmniaTheme.ring : OmniaTheme.ink
                                }
                                StyledText {
                                    id: recentTitle
                                    anchors { left: parent.left; right: parent.right; top: thumb.bottom; topMargin: 5; leftMargin: 9; rightMargin: 9 }
                                    text: rc.modelData.name
                                    font.pixelSize: Appearance.font.pixelSize.smaller
                                    color: rc.sel ? OmniaTheme.ring : OmniaTheme.ink
                                    elide: Text.ElideRight
                                }
                                StyledText {
                                    anchors { left: recentTitle.left; right: recentTitle.right; top: recentTitle.bottom; topMargin: 1 }
                                    text: root.playedDate(rc.modelData.lastPlayed)
                                    color: OmniaTheme.inkDim
                                    font.pixelSize: Appearance.font.pixelSize.smaller
                                    elide: Text.ElideRight
                                }
                                MouseArea {
                                    anchors.fill: parent
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: { root.zone = "recent"; root.recentIdx = rc.index; OmniaApi.select(rc.modelData.id); }
                                }
                            }
                        }
                        Item { Layout.fillWidth: true; Layout.preferredWidth: 0 }
                    }
                }

                StyledText {
                    Layout.fillWidth: true
                    visible: OmniaApi.actionError.length > 0
                    text: OmniaApi.actionError
                    color: OmniaTheme.danger
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    wrapMode: Text.Wrap
                }

            }
        }

        OmniaPill {
            id: bigModeButton
            visible: root.view === "main" && OmniaApi.status === "ok"
            Layout.fillWidth: true
            label: "Big Mode"
            icon: "layout-grid"
            primary: true
            ringed: root.zone === "big" && root.activeFocus
            implicitHeight: 44
            onClicked: { OmniaApi.openBigMode("", false); root.closeRequested(); }
        }
    }

    // ---------------- menú ⋯ (junto al botón) ----------------
    Item {
        visible: root.menuOpen
        anchors.fill: parent
        z: 50
        MouseArea { anchors.fill: parent; onClicked: root.closeMenu() }
        Rectangle {
            x: root.menuX
            y: root.menuY
            width: 280
            height: menuCol.implicitHeight + 12
            radius: 14
            color: Qt.rgba(0.082, 0.114, 0.153, 0.97)
            border.width: 1
            border.color: OmniaTheme.line
            Column {
                id: menuCol
                anchors { left: parent.left; right: parent.right; top: parent.top; margins: 6 }
                spacing: 2
                Repeater {
                    model: root.menuItems
                    delegate: Rectangle {
                        id: mi
                        required property var modelData
                        required property int index
                        width: parent.width
                        height: 42
                        radius: 9
                        color: root.menuIdx === index ? OmniaTheme.rowSelected() : (miMa.containsMouse ? Qt.rgba(1, 1, 1, 0.08) : "transparent")
                        RowLayout {
                            anchors { fill: parent; leftMargin: 12; rightMargin: 12 }
                            spacing: 10
                            OmniaLucide { name: mi.modelData.icon; width: 20; height: 20; color: OmniaTheme.ink }
                            StyledText { Layout.fillWidth: true; text: mi.modelData.label; color: OmniaTheme.ink; elide: Text.ElideRight }
                        }
                        MouseArea {
                            id: miMa
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onEntered: root.menuIdx = mi.index
                            onClicked: root.runMenu(mi.index)
                        }
                    }
                }
            }
        }
    }
}

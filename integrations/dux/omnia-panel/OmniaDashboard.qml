import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs.Common
import qs.Widgets
import qs.DCommon.Widgets
import qs.Modules.Plugins
import qs.Modules.DDash
import qs.Modules.DDash.Overview

// Panel rápido de Omnia como pestaña del dashboard de Dux (igual que «ASUS TUF»): se abre desde el botón de la barra, usa el
// estilo, los colores y la animación de Dux y habla con el núcleo de Omnia (HTTP local con el token de sesión). No depende de ii.
DashTabComponent {
    id: root

    implicitHeight: 560

    readonly property string base: "http://127.0.0.1:47831"
    property string token: ""
    property string status: "loading"          // loading | ok | empty | error
    property string errorText: ""
    property string actionError: ""
    property var games: []
    property string selectedId: ""
    property string search: ""
    property bool padOn: false
    property string padName: ""
    property int padLevel: -1
    property bool padCharging: false

    readonly property var library: games.filter(g => !g.hidden)
    readonly property var shown: {
        const q = search.trim().toLocaleLowerCase();
        return q ? library.filter(g => [g.name, g.variant, g.src].some(v => (v || "").toLocaleLowerCase().includes(q))) : library;
    }
    readonly property var game: library.find(g => g.id === selectedId) ?? (library.length ? library[0] : null)
    readonly property var recent: {
        const seen = {}, out = [];
        const played = library.filter(g => (g.lastPlayed || 0) > 0).sort((a, b) => b.lastPlayed - a.lastPlayed);
        for (const g of played) { if (!seen[g.id]) { seen[g.id] = true; out.push(g); } if (out.length === 3) break; }
        return out;
    }
    readonly property bool padKnown: padOn && padLevel >= 0
    readonly property color padTone: padOn && !padCharging && padLevel >= 0 && padLevel <= 10 ? "#E86D6D"
        : padOn && !padCharging && padLevel >= 0 && padLevel <= 30 ? "#E8B86D" : padCharging ? "#7FD69F" : Theme.surfaceVariantText
    readonly property string padShort: {
        const n = padName.toLowerCase();
        if (n.indexOf("dualsense") >= 0) return "DualSense";
        if (n.indexOf("dualshock") >= 0) return "DualShock 4";
        if (n.indexOf("pro controller") >= 0) return "Pro Controller";
        if (n.indexOf("joy-con") >= 0) return "Joy-Con";
        if (n.indexOf("steam") >= 0 || n.indexOf("deck") >= 0) return "Steam Deck";
        if (n.indexOf("xbox") >= 0) return "Xbox";
        const words = padName.split(/\s+/).filter(w => w);
        return words.length ? words.slice(0, 2).join(" ") : "Mando";
    }

    // ---------------- cliente del núcleo ----------------
    function request(method, path, body, cb) {
        const xhr = new XMLHttpRequest();
        xhr.onreadystatechange = () => {
            if (xhr.readyState !== XMLHttpRequest.DONE) return;
            let data = null;
            try { data = JSON.parse(xhr.responseText); } catch (e) {}
            if (cb) cb(xhr.status, data);
        };
        xhr.open(method, root.base + path);
        xhr.setRequestHeader("Authorization", "Bearer " + root.token);
        if (body) xhr.setRequestHeader("Content-Type", "application/json");
        xhr.send(body ? JSON.stringify(body) : undefined);
    }
    function refresh() {
        if (token === "") { status = "error"; errorText = "omnia-core no está en marcha (falta el token de sesión)."; return; }
        request("GET", "/library", null, (st, d) => {
            if (st === 200 && d && d.games !== undefined) {
                games = d.games;
                status = d.games.length ? "ok" : "empty";
                errorText = "";
            } else {
                status = "error";
                errorText = st === 0 ? "omnia-core no responde." : ((d && d.error) || ("Error HTTP " + st));
            }
        });
        request("GET", "/pad", null, (st, d) => {
            if (st !== 200 || !d) { padOn = false; return; }
            padOn = d.connected === true;
            padName = padOn ? String(d.name || "") : "";
            const bat = padOn && d.battery ? d.battery : null;
            padLevel = bat && bat.level !== undefined && bat.level !== null ? Math.max(0, Math.min(100, Number(bat.level))) : -1;
            padCharging = !!(bat && bat.charging);
        });
    }
    function select(id) {
        selectedId = id;
        actionError = "";
        request("POST", "/selection/set", { id: id, filterKey: "all" }, null);
    }
    function closeDash() { popoutService?.closeDankDash(); }
    function openApp(id, flag) {
        const cmd = ["omnia-ui", "--manager"];
        if (id) cmd.push("--game", id);
        if (flag) cmd.push(flag);
        Quickshell.execDetached(cmd);
        closeDash();
    }
    function play() {
        const g = game;
        if (!g) return;
        if (g.portAvailable) { openApp(g.id, "--install-port"); return; }      // sin port instalado se ofrece instalarlo en la app de escritorio
        const port = g.ports ? g.ports.find(p => p.canLaunch && !p.running) : null;
        if (!port) { actionError = "El juego ya está en ejecución o no tiene un lanzador disponible."; return; }
        request("POST", "/launch", { id: g.id, port: port.id }, (st, d) => {
            if (st !== 200) actionError = (d && d.error) || "No se pudo lanzar el juego.";
            else closeDash();
        });
    }
    function toggleFav() {
        if (game) request("POST", "/game/fav?id=" + encodeURIComponent(game.id), {}, () => root.refresh());
    }
    function playedDate(seconds) {
        const date = new Date(seconds * 1000);
        const now = new Date();
        const day = Date.UTC(date.getFullYear(), date.getMonth(), date.getDate());
        const today = Date.UTC(now.getFullYear(), now.getMonth(), now.getDate());
        const elapsed = Math.round((today - day) / 86400000);
        if (elapsed <= 0) return "Hoy";
        if (elapsed === 1) return "Ayer";
        if (elapsed < 7) return "Hace " + elapsed + " días";
        return date.toLocaleDateString(Qt.locale("es_CO"), "d MMM yyyy");
    }

    onLiveChanged: if (live) refresh()
    Timer { interval: 30000; running: root.live && root.token !== ""; repeat: true; onTriggered: root.refresh() }
    FileView {
        id: tokenFile
        path: (Quickshell.env("XDG_RUNTIME_DIR") || "/run/user/1000") + "/omnia/token"
        watchChanges: true
        printErrors: false
        onFileChanged: reload()
        onLoaded: { root.token = text().trim(); root.refresh(); }
        onLoadFailed: { root.status = "error"; root.errorText = "omnia-core no está en marcha (falta el token de sesión)."; }
    }

    // ---------------- interfaz ----------------
    ColumnLayout {
        anchors.fill: parent
        spacing: Theme.spacingM

        RowLayout {
            Layout.fillWidth: true
            spacing: Theme.spacingM
            StyledText {
                text: "Omnia"
                color: Theme.surfaceText
                font.pixelSize: Theme.fontSizeLarge
                font.weight: Font.Bold
            }
            Rectangle {
                id: padChip
                visible: root.padOn
                Layout.preferredHeight: 30
                implicitWidth: chipRow.implicitWidth + Theme.spacingM * 2
                radius: height / 2
                color: Theme.surfaceContainerHigh
                Row {
                    id: chipRow
                    anchors.centerIn: parent
                    spacing: Theme.spacingXS
                    DIcon { name: "sports_esports"; size: 18; color: root.padTone; anchors.verticalCenter: parent.verticalCenter }
                    StyledText { text: root.padShort; color: Theme.surfaceText; font.pixelSize: Theme.fontSizeSmall; anchors.verticalCenter: parent.verticalCenter }
                    StyledText { visible: root.padKnown; text: root.padLevel + " %" + (root.padCharging ? " ⚡" : ""); color: root.padTone; font.pixelSize: Theme.fontSizeSmall; anchors.verticalCenter: parent.verticalCenter }
                }
            }
            Item { Layout.fillWidth: true }
            DButton { text: "Actualizar"; iconName: "refresh"; onClicked: root.refresh() }
            DButton { text: "App"; iconName: "open_in_new"; variant: "tonal"; onClicked: root.openApp("", "") }
        }

        StyledText {
            visible: root.status === "error" || root.status === "empty"
            Layout.fillWidth: true
            wrapMode: Text.WordWrap
            text: root.status === "empty" ? "Aún no hay juegos en tu biblioteca de Omnia." : root.errorText
            color: Theme.surfaceVariantText
            font.pixelSize: Theme.fontSizeMedium
        }

        RowLayout {
            visible: root.status === "ok"
            Layout.fillWidth: true
            Layout.fillHeight: true
            spacing: Theme.spacingM

            Card {
                Layout.preferredWidth: 290
                Layout.fillHeight: true
                ColumnLayout {
                    anchors.fill: parent
                    anchors.margins: Theme.spacingS
                    spacing: Theme.spacingS
                    DTextField {
                        Layout.fillWidth: true
                        placeholderText: "Buscar juegos…"
                        leftIconName: "search"
                        showClearButton: true
                        onTextChanged: root.search = text
                    }
                    ListView {
                        id: list
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        clip: true
                        spacing: 2
                        model: root.shown
                        boundsBehavior: Flickable.StopAtBounds
                        delegate: Rectangle {
                            id: row
                            required property var modelData
                            readonly property bool current: root.game && root.game.id === modelData.id
                            width: list.width
                            height: 54
                            radius: Theme.cornerRadius
                            color: current ? Theme.primaryContainer : (hover.hovered ? Theme.surfaceContainerHigh : "transparent")
                            Row {
                                anchors.fill: parent
                                anchors.margins: 6
                                spacing: Theme.spacingS
                                Rectangle {
                                    width: 42; height: 42; radius: 8
                                    color: Theme.surfaceContainerHighest
                                    clip: true
                                    Image { anchors.fill: parent; source: row.modelData.portada || ""; fillMode: Image.PreserveAspectCrop; asynchronous: true; sourceSize.width: 96; sourceSize.height: 96 }
                                }
                                Column {
                                    anchors.verticalCenter: parent.verticalCenter
                                    width: parent.width - 42 - Theme.spacingS
                                    StyledText { width: parent.width; text: row.modelData.name; elide: Text.ElideRight; font.pixelSize: Theme.fontSizeMedium; color: row.current ? Theme.onPrimaryContainer : Theme.surfaceText }
                                    StyledText { width: parent.width; text: row.modelData.src || ""; elide: Text.ElideRight; font.pixelSize: Theme.fontSizeSmall; color: row.current ? Theme.onPrimaryContainer : Theme.surfaceVariantText; opacity: 0.8 }
                                }
                            }
                            HoverHandler { id: hover }
                            TapHandler { onTapped: root.select(row.modelData.id) }
                        }
                    }
                }
            }

            ColumnLayout {
                Layout.fillWidth: true
                Layout.fillHeight: true
                spacing: Theme.spacingM

                Card {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 250
                    clip: true
                    Image {
                        anchors.fill: parent
                        source: root.game ? (root.game.fondo || root.game.portada || "") : ""
                        fillMode: Image.PreserveAspectCrop
                        asynchronous: true
                    }
                    Rectangle {
                        anchors.fill: parent
                        gradient: Gradient {
                            GradientStop { position: 0.35; color: "transparent" }
                            GradientStop { position: 1.0; color: "#E6000000" }
                        }
                    }
                    Column {
                        anchors { left: parent.left; right: parent.right; bottom: parent.bottom; margins: Theme.spacingM }
                        spacing: Theme.spacingXS
                        StyledText { width: parent.width; text: root.game ? root.game.name : ""; elide: Text.ElideRight; color: "white"; font.pixelSize: Theme.fontSizeXLarge; font.weight: Font.Bold }
                        StyledText { width: parent.width; text: root.game ? (root.game.sub || root.game.src || "") : ""; elide: Text.ElideRight; color: "#CCFFFFFF"; font.pixelSize: Theme.fontSizeSmall }
                        Row {
                            spacing: Theme.spacingS
                            DButton { text: root.game && root.game.portAvailable ? "Instalar" : "Jugar"; iconName: root.game && root.game.portAvailable ? "download" : "play_arrow"; enabled: !!root.game; onClicked: root.play() }
                            DButton { text: ""; iconName: root.game && root.game.fav ? "star" : "star_border"; variant: "tonal"; enabled: !!root.game; tooltipText: "Favorito"; onClicked: root.toggleFav() }
                            DButton { text: ""; iconName: "grid_view"; variant: "tonal"; enabled: !!root.game; tooltipText: "Ver detalles en la app"; onClicked: root.openApp(root.game.id, "") }
                            DButton { text: ""; iconName: "folder_open"; variant: "tonal"; enabled: !!(root.game && root.game.folder); tooltipText: "Abrir carpeta"; onClicked: { Quickshell.execDetached(["xdg-open", root.game.folder]); root.closeDash(); } }
                        }
                    }
                }

                StyledText {
                    visible: root.actionError !== ""
                    Layout.fillWidth: true
                    text: root.actionError
                    wrapMode: Text.WordWrap
                    color: "#E8B86D"
                    font.pixelSize: Theme.fontSizeSmall
                }

                StyledText {
                    visible: root.recent.length > 0
                    text: "Jugado recientemente"
                    color: Theme.surfaceText
                    font.pixelSize: Theme.fontSizeMedium
                    font.weight: Font.Medium
                }
                RowLayout {
                    visible: root.recent.length > 0
                    Layout.fillWidth: true
                    spacing: Theme.spacingS
                    Repeater {
                        model: root.recent
                        delegate: Card {
                            id: rc
                            required property var modelData
                            Layout.fillWidth: true
                            Layout.preferredHeight: 96
                            Layout.preferredWidth: 1
                            clip: true
                            clickable: true
                            onClicked: root.select(rc.modelData.id)
                            Image { anchors.fill: parent; source: rc.modelData.fondo || rc.modelData.portada || ""; fillMode: Image.PreserveAspectCrop; asynchronous: true; sourceSize.width: 400 }
                            Rectangle { anchors.fill: parent; gradient: Gradient { GradientStop { position: 0.3; color: "transparent" } GradientStop { position: 1.0; color: "#E6000000" } } }
                            Column {
                                anchors { left: parent.left; right: parent.right; bottom: parent.bottom; margins: Theme.spacingS }
                                StyledText { width: parent.width; text: rc.modelData.name; elide: Text.ElideRight; color: "white"; font.pixelSize: Theme.fontSizeSmall; font.weight: Font.Medium }
                                StyledText { width: parent.width; text: root.playedDate(rc.modelData.lastPlayed); color: "#CCFFFFFF"; font.pixelSize: Theme.fontSizeSmall - 1 }
                            }
                        }
                    }
                }
                Item { Layout.fillHeight: true }
            }
        }
    }
}

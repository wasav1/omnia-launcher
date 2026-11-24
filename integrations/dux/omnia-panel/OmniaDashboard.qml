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

    implicitHeight: 540

    readonly property string base: "http://127.0.0.1:47831"
    property string token: ""
    property string status: "loading"          // loading | ok | empty | error
    property string errorText: ""
    property string actionError: ""
    property var games: []
    property string search: ""
    property bool padOn: false
    property string padName: ""
    property int padLevel: -1
    property bool padCharging: false

    readonly property int maxShown: 10
    readonly property var library: games.filter(g => !g.hidden)
    function byRecent(a, b) { return (b.lastPlayed || 0) - (a.lastPlayed || 0) || String(a.name).localeCompare(String(b.name)); }
    // Anclado: lo último que jugaste (si nunca jugaste nada, el primer favorito o el primer juego).
    readonly property var pinned: {
        const played = library.filter(g => (g.lastPlayed || 0) > 0).sort(byRecent);
        if (played.length) return played[0];
        return library.find(g => g.fav) ?? (library.length ? library[0] : null);
    }
    readonly property bool searching: search.trim() !== ""
    readonly property var matches: {
        const q = search.trim().toLocaleLowerCase();
        return q ? library.filter(g => [g.name, g.variant, g.src].some(v => (v || "").toLocaleLowerCase().includes(q))) : [];
    }
    // Lista: con búsqueda, coincidencias de TODA la biblioteca; sin ella, favoritos (por último juego) y después jugados; nunca el anclado.
    readonly property var queue: {
        if (searching) return matches.slice(0, maxShown);
        const rest = library.filter(g => !pinned || g.id !== pinned.id);
        const favs = rest.filter(g => g.fav).sort(byRecent);
        const played = rest.filter(g => !g.fav && (g.lastPlayed || 0) > 0).sort(byRecent);
        const out = favs.concat(played);
        return (out.length ? out : rest.sort((a, b) => String(a.name).localeCompare(String(b.name)))).slice(0, maxShown);
    }
    readonly property int hiddenCount: Math.max(0, (searching ? matches.length : library.length - (pinned ? 1 : 0)) - queue.length)
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
    function closeDash() { popoutService?.closeDankDash(); }
    function openApp(id, flag) {
        const cmd = ["omnia-ui", "--manager"];
        if (id) cmd.push("--game", id);
        if (flag) cmd.push(flag);
        Quickshell.execDetached(cmd);
        closeDash();
    }
    function play(g) {
        if (!g) return;
        if (g.portAvailable) { openApp(g.id, "--install-port"); return; }      // sin port instalado se ofrece instalarlo en la app de escritorio
        const port = g.ports ? g.ports.find(p => p.canLaunch && !p.running) : null;
        if (!port) { actionError = "El juego ya está en ejecución o no tiene un lanzador disponible."; return; }
        request("POST", "/launch", { id: g.id, port: port.id }, (st, d) => {
            if (st !== 200) actionError = (d && d.error) || "No se pudo lanzar el juego.";
            else closeDash();
        });
    }
    function toggleFav(g) {
        if (g) request("POST", "/game/fav?id=" + encodeURIComponent(g.id), {}, () => root.refresh());
    }
    function playTime(seconds) {
        const total = Math.floor(Number(seconds) || 0);
        if (total < 60) return "Sin tiempo registrado";
        const h = Math.floor(total / 3600), m = Math.floor((total % 3600) / 60);
        return h > 0 ? h + " h " + m + " min" : m + " min";
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
            StyledText { text: "Omnia"; color: Theme.surfaceText; font.pixelSize: Theme.fontSizeLarge; font.weight: Font.Bold }
            Rectangle {
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

            // ---- anclado: lo último que jugaste ----
            Card {
                Layout.preferredWidth: 330
                Layout.fillHeight: true
                clip: true
                ColumnLayout {
                    anchors.fill: parent
                    anchors.margins: Theme.spacingM
                    spacing: Theme.spacingS
                    StyledText {
                        text: root.pinned && (root.pinned.lastPlayed || 0) > 0 ? "Continuar jugando" : "Para empezar"
                        color: Theme.surfaceVariantText
                        font.pixelSize: Theme.fontSizeSmall
                    }
                    Rectangle {
                        Layout.fillWidth: true
                        Layout.fillHeight: true             // el banner absorbe el espacio libre de la tarjeta
                        Layout.minimumHeight: 150
                        Layout.maximumHeight: 320
                        radius: Theme.cornerRadius
                        color: Theme.surfaceContainerHighest
                        clip: true
                        Image {
                            anchors.fill: parent
                            source: root.pinned ? (root.pinned.fondo || root.pinned.portada || "") : ""
                            fillMode: Image.PreserveAspectCrop
                            asynchronous: true
                        }
                        Rectangle {
                            visible: !!(root.pinned && root.pinned.running)
                            anchors { left: parent.left; top: parent.top; margins: Theme.spacingS }
                            height: 22
                            width: runLabel.implicitWidth + Theme.spacingM
                            radius: 11
                            color: "#7FD69F"
                            StyledText { id: runLabel; anchors.centerIn: parent; text: "En ejecución"; color: "#0b2a18"; font.pixelSize: Theme.fontSizeSmall }
                        }
                    }
                    StyledText {
                        Layout.fillWidth: true
                        text: root.pinned ? root.pinned.name : ""
                        elide: Text.ElideRight
                        color: Theme.surfaceText
                        font.pixelSize: Theme.fontSizeLarge
                        font.weight: Font.Bold
                    }
                    StyledText {
                        Layout.fillWidth: true
                        text: root.pinned ? (root.pinned.sub || root.pinned.src || "") : ""
                        elide: Text.ElideRight
                        color: Theme.surfaceVariantText
                        font.pixelSize: Theme.fontSizeSmall
                    }
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: Theme.spacingS
                        Repeater {
                            model: [
                                { label: "Tiempo jugado", value: root.pinned ? root.playTime(root.pinned.totalSecs) : "" },
                                { label: "Última vez", value: root.pinned && (root.pinned.lastPlayed || 0) > 0 ? root.playedDate(root.pinned.lastPlayed) : "Nunca" }
                            ]
                            delegate: Rectangle {
                                required property var modelData
                                Layout.fillWidth: true
                                Layout.preferredWidth: 1
                                implicitHeight: statCol.implicitHeight + Theme.spacingS * 2
                                radius: Theme.cornerRadius
                                color: Theme.surfaceContainerHigh
                                Column {
                                    id: statCol
                                    anchors.fill: parent
                                    anchors.margins: Theme.spacingS
                                    StyledText { text: modelData.label; color: Theme.surfaceVariantText; font.pixelSize: Theme.fontSizeSmall }
                                    StyledText { width: parent.width; text: modelData.value; elide: Text.ElideRight; color: Theme.surfaceText; font.pixelSize: Theme.fontSizeMedium; font.weight: Font.Medium }
                                }
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
                    DButton {
                        Layout.fillWidth: true
                        text: root.pinned && root.pinned.portAvailable ? "Instalar" : "Jugar"
                        iconName: root.pinned && root.pinned.portAvailable ? "download" : "play_arrow"
                        enabled: !!root.pinned
                        onClicked: root.play(root.pinned)
                    }
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: Theme.spacingS
                        DButton { Layout.fillWidth: true; Layout.preferredWidth: 1; text: "Favorito"; iconName: root.pinned && root.pinned.fav ? "star" : "star_border"; variant: "tonal"; enabled: !!root.pinned; onClicked: root.toggleFav(root.pinned) }
                        DButton { Layout.fillWidth: true; Layout.preferredWidth: 1; text: "Detalles"; iconName: "grid_view"; variant: "tonal"; enabled: !!root.pinned; onClicked: root.openApp(root.pinned.id, "") }
                        DButton { Layout.fillWidth: true; Layout.preferredWidth: 1; text: "Carpeta"; iconName: "folder_open"; variant: "tonal"; enabled: !!(root.pinned && root.pinned.folder); onClicked: { Quickshell.execDetached(["xdg-open", root.pinned.folder]); root.closeDash(); } }
                    }
                }
            }

            // ---- lista con scroll: máximo 10, favoritos > últimos jugados ----
            Card {
                Layout.fillWidth: true
                Layout.fillHeight: true
                ColumnLayout {
                    anchors.fill: parent
                    anchors.margins: Theme.spacingS
                    spacing: Theme.spacingS
                    DTextField {
                        Layout.fillWidth: true
                        placeholderText: "Buscar en toda tu biblioteca…"
                        leftIconName: "search"
                        showClearButton: true
                        onTextChanged: root.search = text
                    }
                    StyledText {
                        Layout.leftMargin: Theme.spacingXS
                        text: root.searching ? (root.matches.length + (root.matches.length === 1 ? " resultado" : " resultados")) : "Favoritos y jugados recientemente"
                        color: Theme.surfaceVariantText
                        font.pixelSize: Theme.fontSizeSmall
                    }
                    StyledText {
                        visible: root.searching && root.matches.length === 0
                        Layout.fillWidth: true
                        Layout.margins: Theme.spacingM
                        text: "Ningún juego coincide."
                        color: Theme.surfaceVariantText
                        font.pixelSize: Theme.fontSizeMedium
                    }
                    ListView {
                        id: list
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        clip: true
                        spacing: 2
                        model: root.queue
                        boundsBehavior: Flickable.StopAtBounds
                        delegate: Rectangle {
                            id: row
                            required property var modelData
                            width: list.width
                            height: 54
                            radius: Theme.cornerRadius
                            color: hover.hovered ? Theme.surfaceContainerHigh : "transparent"
                            HoverHandler { id: hover }
                            Item {
                                id: info
                                anchors { left: parent.left; top: parent.top; bottom: parent.bottom; right: actions.left }
                                TapHandler { onTapped: root.openApp(row.modelData.id, "") }
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
                                        StyledText { width: parent.width; text: row.modelData.name; elide: Text.ElideRight; font.pixelSize: Theme.fontSizeMedium; color: Theme.surfaceText }
                                        StyledText {
                                            width: parent.width
                                            text: (row.modelData.src || "") + " · " + ((row.modelData.lastPlayed || 0) > 0 ? root.playedDate(row.modelData.lastPlayed) : "Sin jugar")
                                            elide: Text.ElideRight
                                            font.pixelSize: Theme.fontSizeSmall
                                            color: Theme.surfaceVariantText
                                        }
                                    }
                                }
                            }
                            Row {
                                id: actions
                                anchors { right: parent.right; rightMargin: 6; verticalCenter: parent.verticalCenter }
                                spacing: Theme.spacingXS
                                DButton { text: ""; iconName: row.modelData.fav ? "star" : "star_border"; variant: "text"; tooltipText: "Favorito"; onClicked: root.toggleFav(row.modelData) }
                                DButton { text: ""; iconName: row.modelData.portAvailable ? "download" : "play_arrow"; variant: "tonal"; tooltipText: row.modelData.portAvailable ? "Instalar" : "Jugar"; onClicked: root.play(row.modelData) }
                            }
                        }
                    }
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: Theme.spacingS
                        StyledText {
                            Layout.fillWidth: true
                            text: root.hiddenCount > 0 ? ("y " + root.hiddenCount + " más en tu biblioteca") : ""
                            color: Theme.surfaceVariantText
                            font.pixelSize: Theme.fontSizeSmall
                        }
                        DButton { text: "Big Mode"; iconName: "grid_view"; variant: "tonal"; onClicked: { Quickshell.execDetached(["omnia-ui", "--window"]); root.closeDash(); } }
                        DButton { text: "App"; iconName: "open_in_new"; variant: "tonal"; onClicked: root.openApp("", "") }
                    }
                }
            }
        }
    }
}

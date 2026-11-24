import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs.Common
import qs.Widgets
import qs.DCommon.Widgets
import qs.Modules.Plugins
import qs.Modules.DDash.Overview

// Panel rápido de Omnia, compacto, como popout del botón de la barra de Dux: usa el estilo, los colores y la animación de Dux y
// habla con el núcleo de Omnia (HTTP local con el token de sesión). No depende de ii.
Item {
    id: root

    signal closeRequested()
    property bool live: visible
    implicitWidth: 400
    implicitHeight: 590

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
    function closeDash() { closeRequested(); }
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

    // ---------------- interfaz (compacto, una columna) ----------------
    ColumnLayout {
        anchors.fill: parent
        spacing: Theme.spacingS

        RowLayout {
            Layout.fillWidth: true
            spacing: Theme.spacingS
            DTextField {
                Layout.fillWidth: true
                placeholderText: "Buscar en toda tu biblioteca…"
                leftIconName: "search"
                showClearButton: true
                onTextChanged: root.search = text
            }
            Rectangle {
                visible: root.padOn
                Layout.preferredHeight: 28
                implicitWidth: chipRow.implicitWidth + Theme.spacingM * 2
                radius: height / 2
                color: Theme.surfaceContainerHigh
                Row {
                    id: chipRow
                    anchors.centerIn: parent
                    spacing: Theme.spacingXS
                    DIcon { name: "sports_esports"; size: 16; color: root.padTone; anchors.verticalCenter: parent.verticalCenter }
                    StyledText { visible: root.padKnown; text: root.padLevel + " %" + (root.padCharging ? " ⚡" : ""); color: root.padTone; font.pixelSize: Theme.fontSizeSmall; anchors.verticalCenter: parent.verticalCenter }
                    StyledText { visible: !root.padKnown; text: root.padShort; color: Theme.surfaceText; font.pixelSize: Theme.fontSizeSmall; anchors.verticalCenter: parent.verticalCenter }
                }
            }
        }

        StyledText {
            visible: root.status === "error" || root.status === "empty"
            Layout.fillWidth: true
            wrapMode: Text.WordWrap
            text: root.status === "empty" ? "Aún no hay juegos en tu biblioteca de Omnia." : root.errorText
            color: Theme.surfaceVariantText
            font.pixelSize: Theme.fontSizeMedium
        }

        // ---- anclado: lo último que jugaste ----
        Card {
            visible: root.status === "ok" && !root.searching
            Layout.fillWidth: true
            implicitHeight: pinCol.implicitHeight + Theme.spacingM * 2
            border.width: 1.5
            border.color: Theme.withAlpha(Theme.primary, 0.55)
            ColumnLayout {
                id: pinCol
                anchors { left: parent.left; right: parent.right; top: parent.top; margins: Theme.spacingM }
                spacing: Theme.spacingS
                Rectangle {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 92
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
                        anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
                        height: 24
                        color: "#99000000"
                        StyledText {
                            anchors { left: parent.left; leftMargin: Theme.spacingS; verticalCenter: parent.verticalCenter }
                            text: root.pinned ? ((root.pinned.running ? "En ejecución · " : "") + (root.pinned.sub || root.pinned.src || "") + ((root.pinned.lastPlayed || 0) > 0 ? " · " + root.playedDate(root.pinned.lastPlayed) + " · " + root.playTime(root.pinned.totalSecs) : "")) : ""
                            color: "white"
                            font.pixelSize: Theme.fontSizeSmall
                        }
                    }
                }
                StyledText {
                    Layout.fillWidth: true
                    Layout.leftMargin: Theme.spacingXS
                    text: root.pinned ? root.pinned.name : ""
                    elide: Text.ElideRight
                    color: Theme.surfaceText
                    font.pixelSize: Theme.fontSizeLarge
                    font.weight: Font.Bold
                }
                StyledText {
                    visible: root.actionError !== ""
                    Layout.fillWidth: true
                    text: root.actionError
                    wrapMode: Text.WordWrap
                    color: "#E8B86D"
                    font.pixelSize: Theme.fontSizeSmall
                }
                RowLayout {
                    Layout.fillWidth: true
                    spacing: Theme.spacingS
                    DButton {
                        text: root.pinned && root.pinned.portAvailable ? "Instalar" : "Jugar"
                        iconName: root.pinned && root.pinned.portAvailable ? "download" : "play_arrow"
                        enabled: !!root.pinned
                        onClicked: root.play(root.pinned)
                    }
                    DButton { text: ""; iconName: root.pinned && root.pinned.fav ? "star" : "star_border"; variant: "tonal"; tooltipText: "Favorito"; enabled: !!root.pinned; onClicked: root.toggleFav(root.pinned) }
                    DButton { text: ""; iconName: "grid_view"; variant: "tonal"; tooltipText: "Ver detalles"; enabled: !!root.pinned; onClicked: root.openApp(root.pinned.id, "") }
                    DButton { text: ""; iconName: "folder_open"; variant: "tonal"; tooltipText: "Abrir carpeta"; enabled: !!(root.pinned && root.pinned.folder); onClicked: { Quickshell.execDetached(["xdg-open", root.pinned.folder]); root.closeDash(); } }
                    Item { Layout.fillWidth: true }
                }
            }
        }

        StyledText {
            visible: root.status === "ok" && root.searching
            Layout.leftMargin: Theme.spacingXS
            text: root.matches.length + (root.matches.length === 1 ? " resultado" : " resultados")
            color: Theme.surfaceVariantText
            font.pixelSize: Theme.fontSizeSmall
        }
        StyledText {
            visible: root.searching && root.matches.length === 0
            Layout.margins: Theme.spacingM
            text: "Ningún juego coincide."
            color: Theme.surfaceVariantText
            font.pixelSize: Theme.fontSizeMedium
        }

        // ---- lista con scroll: máximo 10, favoritos > últimos jugados ----
        ListView {
            id: list
            visible: root.status === "ok"
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
                height: 52
                radius: Theme.cornerRadius
                color: hover.hovered ? Theme.surfaceContainerHigh : "transparent"
                HoverHandler { id: hover }
                Item {
                    anchors { left: parent.left; top: parent.top; bottom: parent.bottom; right: actions.left }
                    TapHandler { onTapped: root.openApp(row.modelData.id, "") }
                    Row {
                        anchors.fill: parent
                        anchors.margins: 6
                        spacing: Theme.spacingS
                        Rectangle {
                            width: 38; height: 38; radius: 8
                            color: Theme.surfaceContainerHighest
                            clip: true
                            Image { anchors.fill: parent; source: row.modelData.portada || ""; fillMode: Image.PreserveAspectCrop; asynchronous: true; sourceSize.width: 96; sourceSize.height: 96 }
                        }
                        Column {
                            anchors.verticalCenter: parent.verticalCenter
                            width: parent.width - 38 - Theme.spacingS
                            StyledText { width: parent.width; text: row.modelData.name; elide: Text.ElideRight; font.pixelSize: Theme.fontSizeMedium; color: Theme.surfaceText }
                            StyledText { width: parent.width; text: row.modelData.src || ""; elide: Text.ElideRight; font.pixelSize: Theme.fontSizeSmall; color: Theme.surfaceVariantText }
                        }
                    }
                }
                Row {
                    id: actions
                    anchors { right: parent.right; rightMargin: 6; verticalCenter: parent.verticalCenter }
                    spacing: Theme.spacingXS
                    DIcon { visible: !!row.modelData.fav; name: "star"; size: 16; color: Theme.primary; anchors.verticalCenter: parent.verticalCenter }
                    DButton { text: ""; iconName: row.modelData.portAvailable ? "download" : "play_arrow"; variant: "tonal"; tooltipText: row.modelData.portAvailable ? "Instalar" : "Jugar"; onClicked: root.play(row.modelData) }
                }
            }
        }

        StyledText {
            visible: root.status === "ok" && root.hiddenCount > 0
            Layout.leftMargin: Theme.spacingXS
            text: "y " + root.hiddenCount + " más en tu biblioteca"
            color: Theme.surfaceVariantText
            font.pixelSize: Theme.fontSizeSmall
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: Theme.spacingS
            DButton { Layout.fillWidth: true; Layout.preferredWidth: 1; text: "Big Mode"; iconName: "grid_view"; variant: "tonal"; onClicked: { Quickshell.execDetached(["omnia-ui", "--window"]); root.closeDash(); } }
            DButton { Layout.fillWidth: true; Layout.preferredWidth: 1; text: "Descargas"; iconName: "download"; variant: "tonal"; onClicked: root.openApp("", "--downloads") }
        }
    }
}

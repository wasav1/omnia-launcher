import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Widgets
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
    implicitHeight: 620

    readonly property string base: "http://127.0.0.1:47831"
    property string token: ""
    property string language: Qt.locale().name.startsWith("en") ? "en" : "es"
    function tr(es, en) { return root.language === "en" ? en : es }
    property string status: "loading"          // loading | ok | empty | error
    property string errorText: ""
    property string actionError: ""
    property var updateStatus: ({phase: "idle", available: "", progress: 0})
    property string seenUpdate: ""
    property bool confirmUpdate: false
    function pollUpdate() {
        if (token === "") return
        request("GET", "/suite-update?surface=dux&visible=" + (live ? "1" : "0"), null, (status, body) => {
            if (status !== 200 || !body) return
            updateStatus = body
            if (live && body.phase === "ready" && body.available !== seenUpdate) {
                seenUpdate = body.available
                confirmUpdate = true
            }
        })
    }
    function updateAction(action) {
        request("POST", "/suite-update/" + action, {}, (status, body) => {
            if (status !== 200) actionError = body?.error || tr("No se pudo actualizar Omnia.", "Could not update Omnia.")
            else pollUpdate()
        })
    }
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
        if (token !== "") request("GET", "/settings", null, (st, data) => {
            if (st === 200 && data) root.language = data.language === "en" ? "en" : "es";
        });
        if (token === "") { status = "error"; errorText = root.tr("omnia-core no está en marcha (falta el token de sesión).", "omnia-core is stopped (session token missing)."); return; }
        request("GET", "/library", null, (st, d) => {
            if (st === 200 && d && d.games !== undefined) {
                games = d.games;
                status = d.games.length ? "ok" : "empty";
                errorText = "";
            } else {
                status = "error";
                errorText = st === 0 ? root.tr("omnia-core no responde.", "omnia-core is not responding.") : ((d && d.error) || (root.tr("Error HTTP ", "HTTP error ") + st));
            }
        });
    }
    function refreshPad() {
        request("GET", "/pad", null, (st, d) => {
            padOn = st === 200 && !!d && d.connected === true;
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
        if (!port) { actionError = root.tr("El juego ya está en ejecución o no tiene un lanzador disponible.", "The game is already running or has no available launcher."); return; }
        request("POST", "/launch", { id: g.id, port: port.id }, (st, d) => {
            if (st !== 200) actionError = root.language === "en" ? "Could not launch the game." : ((d && d.error) || "No se pudo lanzar el juego.");
            else closeDash();
        });
    }
    function toggleFav(g) {
        if (g) request("POST", "/game/fav?id=" + encodeURIComponent(g.id), {}, () => root.refresh());
    }
    function playTime(seconds) {
        const total = Math.floor(Number(seconds) || 0);
        if (total < 60) return root.tr("Sin tiempo registrado", "No playtime recorded");
        const h = Math.floor(total / 3600), m = Math.floor((total % 3600) / 60);
        return h > 0 ? h + " h " + m + " min" : m + " min";
    }
    function playedDate(seconds) {
        const date = new Date(seconds * 1000);
        const now = new Date();
        const day = Date.UTC(date.getFullYear(), date.getMonth(), date.getDate());
        const today = Date.UTC(now.getFullYear(), now.getMonth(), now.getDate());
        const elapsed = Math.round((today - day) / 86400000);
        if (elapsed <= 0) return root.tr("Hoy", "Today");
        if (elapsed === 1) return root.tr("Ayer", "Yesterday");
        if (elapsed < 7) return root.tr("Hace %1 días", "%1 days ago").arg(elapsed);
        return date.toLocaleDateString(Qt.locale(root.language === "en" ? "en_US" : "es_CO"), "d MMM yyyy");
    }

    onLiveChanged: { if (live) refresh(); pollUpdate(); }
    Timer {
        running: root.live && root.token !== ""; repeat: true; triggeredOnStart: true
        interval: root.updateStatus.phase === "downloading" || root.updateStatus.phase === "applying" ? 900 : 8000
        onTriggered: root.pollUpdate()
    }
    Timer { interval: 30000; running: root.live && root.token !== ""; repeat: true; onTriggered: root.refresh() }
    Timer {
        interval: 5000
        running: root.live && root.token !== ""
        repeat: true
        triggeredOnStart: true
        onTriggered: root.refreshPad()
    }
    FileView {
        id: tokenFile
        path: (Quickshell.env("XDG_RUNTIME_DIR") || "/run/user/1000") + "/omnia/token"
        watchChanges: true
        printErrors: false
        onFileChanged: reload()
        onLoaded: { root.token = text().trim(); root.refresh(); }
        onLoadFailed: { root.token = ""; root.padOn = false; root.status = "error"; root.errorText = root.tr("omnia-core no está en marcha (falta el token de sesión).", "omnia-core is stopped (session token missing)."); }
    }

    // ---------------- interfaz (compacto, una columna) ----------------
    ColumnLayout {
        anchors.fill: parent
        spacing: Theme.spacingS

        RowLayout {
            Layout.fillWidth: true
            spacing: Theme.spacingS
            Image {
                Layout.preferredWidth: 28
                Layout.preferredHeight: 28
                source: Qt.resolvedUrl("omnia-mark.svg")
                sourceSize: Qt.size(56, 56)
                fillMode: Image.PreserveAspectFit
            }
            StyledText {
                text: root.tr("Panel rápido de Omnia", "Omnia quick panel")
                color: Theme.surfaceText
                font.weight: Font.DemiBold
                Layout.fillWidth: true
            }
        }

        Rectangle {
            Layout.fillWidth: true
            implicitHeight: controllerRow.implicitHeight + Theme.spacingS * 2
            radius: 10
            color: Theme.surfaceContainerHigh

            RowLayout {
                id: controllerRow
                anchors.fill: parent
                anchors.margins: Theme.spacingS
                spacing: Theme.spacingS
                DIcon {
                    name: "sports_esports"
                    size: 18
                    color: root.padTone
                }
                StyledText {
                    Layout.fillWidth: true
                    text: root.padOn ? (root.padName || root.tr("Mando conectado", "Controller connected"))
                                     : root.tr("Sin mando conectado", "No controller connected")
                    color: Theme.surfaceText
                    font.pixelSize: Theme.fontSizeSmall
                    elide: Text.ElideRight
                }
                StyledText {
                    visible: root.padOn
                    text: root.padKnown ? root.padLevel + " %" + (root.padCharging ? " ⚡" : "")
                                        : root.tr("Batería no disponible", "Battery unavailable")
                    color: root.padTone
                    font.pixelSize: Theme.fontSizeSmall
                }
            }
        }

        DTextField {
            Layout.fillWidth: true
            placeholderText: root.tr("Buscar en toda tu biblioteca…", "Search your entire library…")
            leftIconName: "search"
            showClearButton: true
            onTextChanged: root.search = text
        }

        Rectangle {
            visible: !!root.updateStatus.available
            Layout.fillWidth: true
            Layout.preferredHeight: updateContents.implicitHeight + 18
            color: Theme.surfaceContainerHigh
            radius: 10
            ColumnLayout {
                id: updateContents
                anchors { left: parent.left; right: parent.right; top: parent.top; margins: 9 }
                StyledText {
                    Layout.fillWidth: true
                    wrapMode: Text.Wrap
                    text: root.updateStatus.phase === "downloading"
                        ? root.tr("Descargando Omnia · %1 %", "Downloading Omnia · %1%").arg(root.updateStatus.progress)
                        : root.updateStatus.phase === "applying" ? root.tr("Aplicando actualización…", "Applying update…")
                        : root.updateStatus.phase === "ready" && root.confirmUpdate
                          ? root.tr("Actualización lista. ¿Reiniciar Omnia?", "Update ready. Restart Omnia?")
                          : root.tr("Omnia %1", "Omnia %1").arg(root.updateStatus.available)
                    color: Theme.surfaceText
                }
                RowLayout {
                    visible: !["downloading", "applying"].includes(root.updateStatus.phase)
                    Rectangle {
                        implicitWidth: updateButton.implicitWidth + 20; implicitHeight: 30
                        radius: height / 2; color: Theme.surfaceContainerHigh
                        StyledText {
                            id: updateButton
                            anchors.centerIn: parent; color: Theme.surfaceText
                            text: root.updateStatus.phase === "ready"
                                ? (root.confirmUpdate ? root.tr("Reiniciar ahora", "Restart now") : root.tr("Reiniciar Omnia", "Restart Omnia"))
                                : root.tr("Actualizar", "Update")
                        }
                        MouseArea {
                            anchors.fill: parent; cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                if (root.updateStatus.phase !== "ready") root.updateAction("start")
                                else if (!root.confirmUpdate) root.confirmUpdate = true
                                else root.updateAction("apply")
                            }
                        }
                    }
                    StyledText {
                        visible: root.confirmUpdate && root.updateStatus.phase === "ready"
                        text: root.tr("Más tarde", "Later"); color: Theme.surfaceText
                        MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: root.confirmUpdate = false }
                    }
                }
            }
        }

        StyledText {
            visible: root.status === "error" || root.status === "empty"
            Layout.fillWidth: true
            wrapMode: Text.WordWrap
            text: root.status === "empty" ? root.tr("Aún no hay juegos en tu biblioteca de Omnia.", "Your Omnia library is empty.") : root.errorText
            color: Theme.surfaceVariantText
            font.pixelSize: Theme.fontSizeMedium
        }

        // ---- anclado: lo último que jugaste ----
        Rectangle {
            visible: root.status === "ok" && !root.searching
            Layout.fillWidth: true
            Layout.preferredHeight: pinCol.implicitHeight + Theme.spacingM * 2
            radius: 20
            color: Theme.surfaceContainerHigh
            border.width: 1.5
            border.color: Theme.withAlpha(Theme.primary, 0.55)
            ColumnLayout {
                id: pinCol
                anchors { left: parent.left; right: parent.right; top: parent.top; margins: Theme.spacingM }
                spacing: Theme.spacingS
                ClippingRectangle {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 104
                    radius: 14
                    color: Theme.surfaceContainerHighest
                    Image {
                        anchors.fill: parent
                        source: root.pinned ? (root.pinned.fondo || root.pinned.portada || "") : ""
                        fillMode: Image.PreserveAspectCrop
                        asynchronous: true
                    }
                    Rectangle {
                        anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
                        height: 26
                        color: "#99000000"
                        StyledText {
                            anchors { left: parent.left; leftMargin: Theme.spacingM; right: parent.right; rightMargin: Theme.spacingM; verticalCenter: parent.verticalCenter }
                            elide: Text.ElideRight
                            text: root.pinned ? ((root.pinned.running ? root.tr("En ejecución · ", "Running · ") : "") + (root.pinned.sub || root.pinned.src || "") + ((root.pinned.lastPlayed || 0) > 0 ? " · " + root.playedDate(root.pinned.lastPlayed) + " · " + root.playTime(root.pinned.totalSecs) : "")) : ""
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
                    Layout.bottomMargin: Theme.spacingXS
                    spacing: Theme.spacingS
                    DButton {
                        text: root.pinned && root.pinned.portAvailable ? root.tr("Instalar", "Install") : root.tr("Jugar", "Play")
                        iconName: root.pinned && root.pinned.portAvailable ? "download" : "play_arrow"
                        enabled: !!root.pinned
                        onClicked: root.play(root.pinned)
                    }
                    DButton { text: ""; iconName: root.pinned && root.pinned.fav ? "star" : "star_border"; variant: "tonal"; tooltipText: root.tr("Favorito", "Favorite"); enabled: !!root.pinned; onClicked: root.toggleFav(root.pinned) }
                    DButton { text: ""; iconName: "grid_view"; variant: "tonal"; tooltipText: root.tr("Ver detalles", "View details"); enabled: !!root.pinned; onClicked: root.openApp(root.pinned.id, "") }
                    DButton { text: ""; iconName: "folder_open"; variant: "tonal"; tooltipText: root.tr("Abrir carpeta", "Open folder"); enabled: !!(root.pinned && root.pinned.folder); onClicked: { Quickshell.execDetached(["xdg-open", root.pinned.folder]); root.closeDash(); } }
                    Item { Layout.fillWidth: true }
                }
            }
        }

        StyledText {
            visible: root.status === "ok" && root.searching
            Layout.leftMargin: Theme.spacingXS
            text: root.matches.length + (root.matches.length === 1 ? root.tr(" resultado", " result") : root.tr(" resultados", " results"))
            color: Theme.surfaceVariantText
            font.pixelSize: Theme.fontSizeSmall
        }
        StyledText {
            visible: root.searching && root.matches.length === 0
            Layout.margins: Theme.spacingM
            text: root.tr("Ningún juego coincide.", "No matching games.")
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
                height: 68
                radius: 18
                color: hover.hovered ? Theme.surfaceContainerHigh : "transparent"
                HoverHandler { id: hover }
                Item {
                    anchors { left: parent.left; top: parent.top; bottom: parent.bottom; right: actions.left }
                    TapHandler { onTapped: root.openApp(row.modelData.id, "") }
                    Row {
                        anchors.fill: parent
                        anchors.margins: 6
                        spacing: Theme.spacingM
                        ClippingRectangle {
                            width: 56; height: 56; radius: 14
                            color: Theme.surfaceContainerHighest
                            Image { anchors.fill: parent; source: row.modelData.portada || ""; fillMode: Image.PreserveAspectCrop; asynchronous: true; sourceSize.width: 160; sourceSize.height: 160 }
                        }
                        Column {
                            anchors.verticalCenter: parent.verticalCenter
                            width: parent.width - 56 - Theme.spacingM
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
                    DButton { text: ""; iconName: row.modelData.portAvailable ? "download" : "play_arrow"; variant: "tonal"; tooltipText: row.modelData.portAvailable ? root.tr("Instalar", "Install") : root.tr("Jugar", "Play"); onClicked: root.play(row.modelData) }
                }
            }
        }

        StyledText {
            visible: root.status === "ok" && root.hiddenCount > 0
            Layout.leftMargin: Theme.spacingXS
            text: root.tr("y %1 más en tu biblioteca", "and %1 more in your library").arg(root.hiddenCount)
            color: Theme.surfaceVariantText
            font.pixelSize: Theme.fontSizeSmall
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: Theme.spacingS
            DButton { Layout.fillWidth: true; Layout.preferredWidth: 1; text: "Big Mode"; iconName: "grid_view"; variant: "tonal"; onClicked: { Quickshell.execDetached(["omnia-ui", "--window"]); root.closeDash(); } }
            DButton { Layout.fillWidth: true; Layout.preferredWidth: 1; text: root.tr("Descargas", "Downloads"); iconName: "download"; variant: "tonal"; onClicked: root.openApp("", "--downloads") }
        }
    }
}

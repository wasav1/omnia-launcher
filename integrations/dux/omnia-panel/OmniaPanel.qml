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

// Panel rápido de Omnia como popout del botón de la barra de Dux (rediseño D, fase 6): juego seleccionado arriba,
// pestañas Recientes / Favoritos / Novedades, búsqueda en toda la biblioteca, descarga activa, Big Mode y Abrir Omnia.
// Superficie de cristal con los colores de Omnia (no los de Dux), para verse igual que Desktop y Big Mode.
// Habla con el núcleo de Omnia (HTTP local con el token de sesión). No depende de ii.
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
    // Colores de Omnia (los mismos de ui/qml/Theme.js; el plugin vive fuera de esa carpeta).
    readonly property QtObject ink: QtObject {
        readonly property color text: "#EEF4FB"
        readonly property color muted: "#A9BDD3"
        readonly property color soft: "#C9D6E4"
        readonly property color accent: "#4DA3FF"
        readonly property color accentInk: "#06121F"
        readonly property color accentLight: "#9CD0FF"
        readonly property color glass: "#14FFFFFF"
        readonly property color glassSoft: "#0DFFFFFF"
        readonly property color border: "#29FFFFFF"
        readonly property color borderSoft: "#1FFFFFFF"
        readonly property color inset: "#47000000"
        readonly property color warning: "#E8B86D"
        readonly property color favorite: "#FFD34D"
    }
    property string tab: "recent"                 // recent | fav | news
    property string selectedId: ""                // juego elegido en la lista (si no, el anclado)
    readonly property var featured: library.find(g => g.id === selectedId) ?? pinned
    readonly property string featuredLabel: !featured ? ""
        : featured.running ? root.tr("Jugando ahora", "Playing now")
        : selectedId && featured.id === selectedId && (!pinned || pinned.id !== selectedId) ? root.tr("Seleccionado", "Selected")
        : (featured.lastPlayed || 0) > 0 ? root.tr("Seguir jugando", "Continue playing")
        : featured.fav ? root.tr("Favorito", "Favorite") : root.tr("En tu biblioteca", "In your library")
    property var news: []
    property var downloads: []
    readonly property var activeDownload: downloads.find(j => ["downloading", "verifying", "extracting", "finalizing", "paused", "queued"].includes(j.status)) ?? null
    readonly property int queuedCount: downloads.filter(j => ["downloading", "verifying", "extracting", "finalizing", "paused", "queued"].includes(j.status)).length
    // Filas de la pestaña (o de la búsqueda): {kind: "game", game} o {kind: "news", item}
    readonly property var rows: {
        if (searching) return matches.slice(0, maxShown).map(g => ({ kind: "game", game: g }));
        if (tab === "news") return news.slice(0, maxShown).map(n => ({ kind: "news", item: n }));
        if (tab === "fav") return library.filter(g => g.fav).sort(byRecent).slice(0, maxShown).map(g => ({ kind: "game", game: g }));
        const played = library.filter(g => (g.lastPlayed || 0) > 0).sort(byRecent);
        const list = played.length ? played : library.slice().sort((a, b) => String(a.name).localeCompare(String(b.name)));
        return list.slice(0, maxShown).map(g => ({ kind: "game", game: g }));
    }
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
    readonly property int hiddenCount: searching ? Math.max(0, matches.length - maxShown) : 0
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
    function refreshNews() {
        request("GET", "/stores/news?lang=" + root.language, null, (st, d) => {
            if (st === 200 && d && Array.isArray(d.items)) root.news = d.items;
        });
    }
    function refreshDownloads() {
        request("GET", "/installations", null, (st, d) => {
            if (st === 200 && d && Array.isArray(d.jobs)) root.downloads = d.jobs;
        });
    }
    function storeName(key) {
        return ({ omnia: "Omnia", steam: "Steam", gog: "GOG", epic: "Epic", amazon: "Amazon", ubisoft: "Ubisoft", ea: "EA" })[String(key || "")] || String(key || "");
    }
    function openNews(item) {
        if (item && item.url) Qt.openUrlExternally(item.url);
        closeDash();
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

    onLiveChanged: { if (live) { refresh(); refreshNews(); refreshDownloads(); selectedId = ""; } pollUpdate(); }
    Timer {
        running: root.live && root.token !== ""; repeat: true; triggeredOnStart: true
        interval: root.updateStatus.phase === "downloading" || root.updateStatus.phase === "applying" ? 900 : 8000
        onTriggered: root.pollUpdate()
    }
    Timer { interval: 30000; running: root.live && root.token !== ""; repeat: true; onTriggered: root.refresh() }
    Timer { interval: root.activeDownload ? 1500 : 10000; running: root.live && root.token !== ""; repeat: true; onTriggered: root.refreshDownloads() }
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
        onLoaded: { root.token = text().trim(); root.refresh(); root.refreshNews(); root.refreshDownloads(); }
        onLoadFailed: { root.token = ""; root.padOn = false; root.status = "error"; root.errorText = root.tr("omnia-core no está en marcha (falta el token de sesión).", "omnia-core is stopped (session token missing)."); }
    }

    // ---------------- interfaz ----------------
    component IconButton: Rectangle {
        id: ib
        property string icon: ""
        property string tip: ""
        property color iconColor: root.ink.text
        signal clicked()
        width: 32; height: 32; radius: 10
        color: ibHover.hovered ? "#26FFFFFF" : "#73050910"
        border.color: "#33FFFFFF"
        opacity: enabled ? 1 : 0.45
        DIcon { anchors.centerIn: parent; name: ib.icon; size: 17; color: ib.iconColor }
        HoverHandler { id: ibHover; cursorShape: Qt.PointingHandCursor }
        TapHandler { onTapped: ib.clicked() }
        Accessible.name: ib.tip
        Accessible.role: Accessible.Button
    }

    // fondo: cristal oscuro con dos manchas de color (la del juego arriba y el azul de Omnia abajo)
    ClippingRectangle {
        id: surface
        anchors.fill: parent
        radius: 22
        color: "#0A0F17"
        Rectangle {
            width: 420; height: 420; radius: 210
            x: parent.width - 260; y: -180
            opacity: 0.45
            gradient: Gradient {
                GradientStop { position: 0.0; color: root.featured && root.featured.pal ? (root.featured.pal[1] || "#4DA3FF") : "#4DA3FF" }
                GradientStop { position: 1.0; color: "transparent" }
            }
        }
        Rectangle {
            width: 340; height: 340; radius: 170
            x: -160; y: parent.height - 200
            opacity: 0.35
            gradient: Gradient {
                GradientStop { position: 0.0; color: "transparent" }
                GradientStop { position: 1.0; color: "#1C4E8A" }
            }
        }
        Rectangle { anchors.fill: parent; color: "#8C0A0F17" }       // velo para que el texto se lea
    }
    Rectangle { anchors.fill: parent; radius: 22; color: "transparent"; border.color: root.ink.border }
    Rectangle { anchors { left: parent.left; right: parent.right; top: parent.top; leftMargin: 22; rightMargin: 22 } height: 1; color: "#1FFFFFFF" }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 16
        spacing: 12

        // ---- marca y mando
        RowLayout {
            Layout.fillWidth: true
            spacing: 10
            Image {
                Layout.preferredWidth: 24; Layout.preferredHeight: 24
                source: Qt.resolvedUrl("omnia-mark.svg")
                sourceSize: Qt.size(48, 48)
                fillMode: Image.PreserveAspectFit
            }
            Text { text: "Omnia"; color: root.ink.text; font.pixelSize: 18; font.weight: Font.Bold; Layout.fillWidth: true }
            Rectangle {
                implicitHeight: 28; implicitWidth: padRow.implicitWidth + 20; radius: 14
                color: root.ink.glass; border.color: root.ink.borderSoft
                Row {
                    id: padRow
                    anchors.centerIn: parent; spacing: 6
                    DIcon { name: "sports_esports"; size: 15; color: root.padTone; anchors.verticalCenter: parent.verticalCenter }
                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: !root.padOn ? root.tr("Sin mando", "No controller")
                            : root.padKnown ? root.padLevel + " %" + (root.padCharging ? " ⚡" : "")
                            : (root.padName || root.tr("Mando", "Controller"))
                        color: root.padOn ? root.padTone : root.ink.soft; font.pixelSize: 12
                    }
                }
            }
        }

        // ---- buscador
        Rectangle {
            Layout.fillWidth: true
            implicitHeight: 38; radius: 12
            color: root.ink.inset
            border.color: searchInput.activeFocus ? root.ink.accent : root.ink.borderSoft
            DIcon { x: 12; anchors.verticalCenter: parent.verticalCenter; name: "search"; size: 16; color: root.ink.muted }
            TextInput {
                id: searchInput
                anchors { left: parent.left; leftMargin: 36; right: clearSearch.left; rightMargin: 6; verticalCenter: parent.verticalCenter }
                color: root.ink.text; font.pixelSize: 13
                selectionColor: root.ink.accent
                clip: true
                onTextChanged: root.search = text
                Keys.onEscapePressed: text = ""
                Text { visible: !searchInput.text; text: root.tr("Buscar en tu biblioteca", "Search your library"); color: root.ink.muted; font.pixelSize: 13; anchors.verticalCenter: parent.verticalCenter }
            }
            DIcon {
                id: clearSearch
                visible: searchInput.text !== ""
                anchors { right: parent.right; rightMargin: 10; verticalCenter: parent.verticalCenter }
                name: "close"; size: 16; color: root.ink.muted
                TapHandler { onTapped: searchInput.text = "" }
            }
        }

        // ---- aviso de actualización de Omnia
        Rectangle {
            visible: !!root.updateStatus.available
            Layout.fillWidth: true
            Layout.preferredHeight: updateContents.implicitHeight + 16
            color: root.ink.glass; border.color: root.ink.borderSoft
            radius: 12
            RowLayout {
                id: updateContents
                anchors { left: parent.left; right: parent.right; verticalCenter: parent.verticalCenter; margins: 10 }
                spacing: 8
                Text {
                    Layout.fillWidth: true
                    wrapMode: Text.Wrap
                    text: root.updateStatus.phase === "downloading"
                        ? root.tr("Descargando Omnia · %1 %", "Downloading Omnia · %1%").arg(root.updateStatus.progress)
                        : root.updateStatus.phase === "applying" ? root.tr("Aplicando actualización…", "Applying update…")
                        : root.updateStatus.phase === "ready" && root.confirmUpdate
                          ? root.tr("Actualización lista. ¿Reiniciar Omnia?", "Update ready. Restart Omnia?")
                          : root.tr("Omnia %1 disponible", "Omnia %1 available").arg(root.updateStatus.available)
                    color: root.ink.text; font.pixelSize: 12
                }
                Text {
                    visible: root.confirmUpdate && root.updateStatus.phase === "ready"
                    text: root.tr("Más tarde", "Later"); color: root.ink.muted; font.pixelSize: 12
                    TapHandler { onTapped: root.confirmUpdate = false }
                }
                Rectangle {
                    visible: !["downloading", "applying"].includes(root.updateStatus.phase)
                    implicitWidth: updateButton.implicitWidth + 20; implicitHeight: 28; radius: 9
                    color: root.ink.accent
                    Text {
                        id: updateButton
                        anchors.centerIn: parent; color: root.ink.accentInk; font.pixelSize: 12; font.weight: Font.Bold
                        text: root.updateStatus.phase === "ready"
                            ? (root.confirmUpdate ? root.tr("Reiniciar ahora", "Restart now") : root.tr("Reiniciar", "Restart"))
                            : root.tr("Actualizar", "Update")
                    }
                    HoverHandler { cursorShape: Qt.PointingHandCursor }
                    TapHandler {
                        onTapped: {
                            if (root.updateStatus.phase !== "ready") root.updateAction("start")
                            else if (!root.confirmUpdate) root.confirmUpdate = true
                            else root.updateAction("apply")
                        }
                    }
                }
            }
        }

        Text {
            visible: root.status === "error" || root.status === "empty"
            Layout.fillWidth: true
            wrapMode: Text.WordWrap
            text: root.status === "empty" ? root.tr("Aún no hay juegos en tu biblioteca de Omnia.", "Your Omnia library is empty.") : root.errorText
            color: root.ink.muted; font.pixelSize: 13
        }

        // ---- juego seleccionado
        ClippingRectangle {
            visible: root.status === "ok" && !!root.featured
            Layout.fillWidth: true
            Layout.preferredHeight: 150
            radius: 18
            color: "#111A26"
            border.color: root.ink.border
            Image {
                anchors.fill: parent
                source: root.featured ? (root.featured.fondo || root.featured.portada || "") : ""
                fillMode: Image.PreserveAspectCrop
                asynchronous: true
            }
            Rectangle {
                anchors.fill: parent
                gradient: Gradient {
                    orientation: Gradient.Horizontal
                    GradientStop { position: 0.0; color: "#E6060A10" }
                    GradientStop { position: 0.8; color: "#33060A10" }
                }
            }
            ColumnLayout {
                anchors { fill: parent; margins: 14 }
                spacing: 4
                Text { text: root.featuredLabel.toUpperCase(); color: root.ink.accentLight; font.pixelSize: 11; font.weight: Font.Bold; font.letterSpacing: 1.3 }
                Item { Layout.fillHeight: true }
                Text {
                    Layout.fillWidth: true
                    text: root.featured ? root.featured.name : ""
                    elide: Text.ElideRight; color: root.ink.text; font.pixelSize: 19; font.weight: Font.Bold
                }
                Text {
                    Layout.fillWidth: true
                    elide: Text.ElideRight; color: root.ink.soft; font.pixelSize: 12
                    text: root.featured ? [root.featured.sub || root.featured.src || "",
                                           (root.featured.lastPlayed || 0) > 0 ? root.playedDate(root.featured.lastPlayed) : "",
                                           (root.featured.totalSecs || 0) >= 60 ? root.playTime(root.featured.totalSecs) : ""].filter(x => x).join(" · ") : ""
                }
                Text {
                    visible: root.actionError !== ""
                    Layout.fillWidth: true
                    text: root.actionError; elide: Text.ElideRight
                    color: root.ink.warning; font.pixelSize: 11
                }
                RowLayout {
                    Layout.topMargin: 4
                    spacing: 6
                    Rectangle {
                        implicitHeight: 32; implicitWidth: playRow.implicitWidth + 28; radius: 10
                        readonly property bool busy: !!root.featured && !!root.featured.running
                        color: playHover.hovered ? root.ink.accentLight : root.ink.accent
                        opacity: busy ? 0.6 : 1
                        Row {
                            id: playRow
                            anchors.centerIn: parent; spacing: 4
                            DIcon { name: root.featured && root.featured.portAvailable ? "download" : "play_arrow"; size: 17; color: root.ink.accentInk; anchors.verticalCenter: parent.verticalCenter }
                            Text {
                                anchors.verticalCenter: parent.verticalCenter
                                text: root.featured && root.featured.running ? root.tr("Jugando", "Playing")
                                    : root.featured && root.featured.portAvailable ? root.tr("Instalar", "Install") : root.tr("Jugar", "Play")
                                color: root.ink.accentInk; font.pixelSize: 13; font.weight: Font.Bold
                            }
                        }
                        HoverHandler { id: playHover; cursorShape: Qt.PointingHandCursor }
                        TapHandler { onTapped: root.play(root.featured) }
                    }
                    IconButton { icon: "star"; tip: root.tr("Favorito", "Favorite"); iconColor: root.featured && root.featured.fav ? root.ink.favorite : root.ink.text; onClicked: root.toggleFav(root.featured) }
                    IconButton { icon: "info"; tip: root.tr("Ver ficha", "View details"); onClicked: root.openApp(root.featured.id, "") }
                    IconButton { icon: "folder_open"; tip: root.tr("Abrir carpeta", "Open folder"); enabled: !!(root.featured && root.featured.folder)
                        onClicked: { Quickshell.execDetached(["xdg-open", root.featured.folder]); root.closeDash(); } }
                }
            }
        }

        // ---- pestañas (o el conteo de la búsqueda)
        Rectangle {
            visible: root.status === "ok" && !root.searching
            Layout.fillWidth: true
            implicitHeight: 36; radius: 12
            color: "#40000000"; border.color: root.ink.borderSoft
            Row {
                anchors { fill: parent; margins: 3 }
                spacing: 4
                Repeater {
                    model: [{ k: "recent", l: root.tr("Recientes", "Recent") }, { k: "fav", l: root.tr("Favoritos", "Favorites") }, { k: "news", l: root.tr("Novedades", "News") }]
                    delegate: Rectangle {
                        id: tabItem
                        required property var modelData
                        readonly property bool on: root.tab === modelData.k
                        width: (parent.width - 8) / 3; height: parent.height; radius: 9
                        color: on ? "#384DA3FF" : (tabHover.hovered ? root.ink.glassSoft : "transparent")
                        border.color: on ? "#804DA3FF" : "transparent"
                        Text { anchors.centerIn: parent; text: tabItem.modelData.l; color: tabItem.on ? root.ink.accentLight : root.ink.soft; font.pixelSize: 12; font.weight: tabItem.on ? Font.Bold : Font.Medium }
                        HoverHandler { id: tabHover; cursorShape: Qt.PointingHandCursor }
                        TapHandler { onTapped: { root.tab = tabItem.modelData.k; if (tabItem.modelData.k === "news" && !root.news.length) root.refreshNews(); } }
                    }
                }
            }
        }
        Text {
            visible: root.status === "ok" && root.searching
            text: root.matches.length === 0 ? root.tr("Ningún juego coincide.", "No matching games.")
                : root.matches.length + (root.matches.length === 1 ? root.tr(" resultado", " result") : root.tr(" resultados", " results"))
                  + (root.hiddenCount > 0 ? root.tr(" · se muestran %1", " · showing %1").arg(root.maxShown) : "")
            color: root.ink.muted; font.pixelSize: 12
        }

        // ---- lista
        ListView {
            id: list
            visible: root.status === "ok"
            Layout.fillWidth: true
            Layout.fillHeight: true
            clip: true
            spacing: 2
            model: root.rows
            boundsBehavior: Flickable.StopAtBounds
            delegate: Rectangle {
                id: row
                required property var modelData
                readonly property bool isGame: modelData.kind === "game"
                readonly property var g: isGame ? modelData.game : null
                readonly property var n: isGame ? null : modelData.item
                readonly property bool chosen: isGame && root.featured && root.featured.id === g.id
                width: list.width
                height: 50
                radius: 12
                color: chosen ? "#264DA3FF" : (rowHover.hovered ? root.ink.glassSoft : "transparent")
                border.color: chosen ? "#664DA3FF" : "transparent"
                HoverHandler { id: rowHover; cursorShape: Qt.PointingHandCursor }
                TapHandler {
                    onTapped: {
                        if (row.isGame) { root.selectedId = row.g.id; root.actionError = ""; }
                        else root.openNews(row.n);
                    }
                }
                Row {
                    anchors { left: parent.left; leftMargin: 7; right: rowAction.left; rightMargin: 8; verticalCenter: parent.verticalCenter }
                    spacing: 10
                    ClippingRectangle {
                        width: 36; height: 36; radius: 9
                        color: "#1A2535"
                        Image {
                            anchors.fill: parent
                            source: row.isGame ? (row.g.portada || row.g.fondo || "") : (row.n.artwork || row.n.image || "")
                            fillMode: Image.PreserveAspectCrop; asynchronous: true
                            sourceSize.width: 96; sourceSize.height: 96
                        }
                    }
                    Column {
                        anchors.verticalCenter: parent.verticalCenter
                        width: parent.width - 46
                        spacing: 1
                        Text { width: parent.width; text: row.isGame ? row.g.name : row.n.title; elide: Text.ElideRight; color: root.ink.text; font.pixelSize: 13; font.weight: Font.DemiBold }
                        Text {
                            width: parent.width; elide: Text.ElideRight; color: root.ink.muted; font.pixelSize: 11
                            text: row.isGame ? [row.g.sub || row.g.src || "", (row.g.lastPlayed || 0) > 0 ? root.playedDate(row.g.lastPlayed) : ""].filter(x => x).join(" · ")
                                             : root.storeName(row.n.source)
                        }
                    }
                }
                Rectangle {
                    id: rowAction
                    anchors { right: parent.right; rightMargin: 7; verticalCenter: parent.verticalCenter }
                    width: 32; height: 32; radius: 9
                    color: actionHover.hovered ? "#264DA3FF" : root.ink.glassSoft
                    border.color: root.ink.borderSoft
                    DIcon {
                        anchors.centerIn: parent; size: 17; color: root.ink.accentLight
                        name: !row.isGame ? "open_in_new" : row.g.portAvailable ? "download" : "play_arrow"
                    }
                    HoverHandler { id: actionHover; cursorShape: Qt.PointingHandCursor }
                    TapHandler { onTapped: row.isGame ? root.play(row.g) : root.openNews(row.n) }
                }
            }
            Text {
                visible: list.count === 0 && !root.searching
                anchors.centerIn: parent
                width: parent.width - 30
                horizontalAlignment: Text.AlignHCenter; wrapMode: Text.WordWrap
                color: root.ink.muted; font.pixelSize: 13
                text: root.tab === "fav" ? root.tr("Aún no tienes favoritos.", "No favorites yet.")
                    : root.tab === "news" ? root.tr("Cargando novedades…", "Loading news…")
                    : root.tr("Aún no has jugado nada.", "Nothing played yet.")
            }
        }

        // ---- descarga activa
        Rectangle {
            visible: !!root.activeDownload
            Layout.fillWidth: true
            implicitHeight: 50; radius: 12
            color: root.ink.glassSoft; border.color: root.ink.borderSoft
            HoverHandler { cursorShape: Qt.PointingHandCursor }
            TapHandler { onTapped: root.openApp("", "--downloads") }
            Column {
                anchors { left: parent.left; right: parent.right; verticalCenter: parent.verticalCenter; margins: 12 }
                spacing: 6
                Item {
                    width: parent.width; height: 16
                    Text {
                        anchors { left: parent.left; right: dlPct.left; rightMargin: 8 }
                        text: root.activeDownload ? root.activeDownload.name + (root.queuedCount > 1 ? root.tr("  ·  +%1 en cola", "  ·  +%1 queued").arg(root.queuedCount - 1) : "") : ""
                        elide: Text.ElideRight; color: root.ink.text; font.pixelSize: 12; font.weight: Font.DemiBold
                    }
                    Text { id: dlPct; anchors.right: parent.right; text: root.activeDownload ? Math.round(Number(root.activeDownload.progress || 0)) + " %" : ""; color: root.ink.muted; font.pixelSize: 12 }
                }
                Rectangle {
                    width: parent.width; height: 4; radius: 2; color: "#1FFFFFFF"
                    Rectangle { width: parent.width * Math.max(0, Math.min(1, Number(root.activeDownload ? root.activeDownload.progress || 0 : 0) / 100)); height: parent.height; radius: 2; color: root.ink.accent }
                }
            }
        }

        // ---- Big Mode y Abrir Omnia
        RowLayout {
            Layout.fillWidth: true
            spacing: 8
            Rectangle {
                Layout.fillWidth: true; Layout.preferredWidth: 1
                implicitHeight: 40; radius: 12
                color: bmHover.hovered ? root.ink.accentLight : root.ink.accent
                Row { anchors.centerIn: parent; spacing: 6
                    DIcon { name: "sports_esports"; size: 17; color: root.ink.accentInk; anchors.verticalCenter: parent.verticalCenter }
                    Text { text: "Big Mode"; color: root.ink.accentInk; font.pixelSize: 13; font.weight: Font.Bold; anchors.verticalCenter: parent.verticalCenter } }
                HoverHandler { id: bmHover; cursorShape: Qt.PointingHandCursor }
                TapHandler { onTapped: { Quickshell.execDetached(["omnia-ui", "--window"]); root.closeDash(); } }
            }
            Rectangle {
                Layout.fillWidth: true; Layout.preferredWidth: 1
                implicitHeight: 40; radius: 12
                color: appHover.hovered ? "#24FFFFFF" : root.ink.glass
                border.color: root.ink.border
                Row { anchors.centerIn: parent; spacing: 6
                    DIcon { name: "open_in_new"; size: 17; color: root.ink.text; anchors.verticalCenter: parent.verticalCenter }
                    Text { text: root.tr("Abrir Omnia", "Open Omnia"); color: root.ink.text; font.pixelSize: 13; font.weight: Font.DemiBold; anchors.verticalCenter: parent.verticalCenter } }
                HoverHandler { id: appHover; cursorShape: Qt.PointingHandCursor }
                TapHandler { onTapped: root.openApp("", "") }
            }
        }
    }
}

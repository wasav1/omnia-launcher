pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io

/**
 * Cliente de omnia-core (HTTP en 127.0.0.1). Lee el token de $XDG_RUNTIME_DIR/omnia/token.
 * status: "loading" | "ok" | "empty" | "error"
 */
Singleton {
    id: root

    readonly property string base: "http://127.0.0.1:" + OmniaSettings.port
    property string token: ""
    property string language: Qt.locale().name.startsWith("en") ? "en" : "es"
    function tr(es, en) { return root.language === "en" ? en : es }
    property string status: "loading"
    property string errorText: ""
    property string actionError: ""
    property var games: []
    property int libraryRevision: -1
    property var selected: ({ id: "", name: "", fondo: "", revision: -1, filterKey: "all" })
    readonly property var library: games.filter(g => !g.hidden)
    // Recientes: hasta tres, por última vez jugados (más nuevo primero), sin repetir y solo los que se han jugado.
    readonly property var recent: {
        const seen = {}, out = [];
        const played = library.filter(g => (g.lastPlayed || 0) > 0).sort((a, b) => b.lastPlayed - a.lastPlayed);
        for (const g of played) { if (!seen[g.id]) { seen[g.id] = true; out.push(g); } if (out.length === 3) break; }
        return out;
    }
    readonly property var selectedGame: selected.id ? (games.find(g => g.id === selected.id) ?? null) : null
    readonly property bool loaded: status === "ok" || status === "empty"

    // Mando: el panel lo activa solo mientras está abierto (petición larga a /events, como BigMode).
    property bool padPolling: false                // el panel abierto lo activa
    property bool padWatching: false               // el aviso «mando conectado» lo mantiene activo mientras el ajuste esté encendido
    readonly property bool padActive: padPolling || padWatching
    property bool padBaseline: false               // ya se leyó el estado inicial: solo las conexiones posteriores avisan
    property int padSeq: -1
    property int padGameRev: -1
    property bool padOn: false
    property string padName: ""
    property string padFamily: ""
    property var padBattery: null          // {level, charging} si el sistema expone la batería del mando
    signal padKey(string key)
    signal padConnected(string name, var battery, string family)

    function pollPad() {
        if (!root.padActive) return;
        if (root.token === "") { padRetry.restart(); return; }        // el token aún no cargó (o el núcleo no está): reintenta, no se queda sin escuchar
        const gen = ++root.padGen;
        request("GET", `/events?since=${root.padSeq}&gameSince=${root.padGameRev}&wait=20`, null, (st, d) => {
            if (gen !== root.padGen || !root.padActive) return;
            if (st === 200 && d) {
                const first = root.padSeq < 0;
                root.padSeq = d.seq;
                if (d.gameRevision !== undefined) root.padGameRev = d.gameRevision;
                const wasOn = root.padOn;
                root.padOn = d.padOn === true;
                root.padName = d.padName || "";
                root.padFamily = d.padFamily || d.padLayout || "";
                root.padBattery = d.padBattery || null;
                if (root.padBaseline && !wasOn && root.padOn) root.padConnected(root.padName, root.padBattery, root.padFamily);
                root.padBaseline = true;
                if (!first && d.events) for (const e of d.events) root.padKey(e.key);
                Qt.callLater(root.pollPad);
            } else {
                padRetry.restart();
            }
        });
    }
    property int padGen: 0
    onTokenChanged: if (padActive && token !== "") { padSeq = -1; pollPad(); }    // token nuevo (p. ej. tras reiniciar omnia-core)
    onPadActiveChanged: { if (padActive) { padSeq = -1; padBaseline = false; pollPad(); } else padGen++; }
    Timer { id: padRetry; interval: 2000; onTriggered: { root.padSeq = -1; root.pollPad(); } }

    function toggleFav(id) {
        request("POST", "/game/fav?id=" + encodeURIComponent(id), {}, (st, d) => { root.refresh(); });
    }
    function activity(id, cb) { request("GET", "/game/activity?id=" + encodeURIComponent(id), null, (st, d) => cb(st === 200 ? d : null)); }
    function saves(game, cb) {
        const port = game.ports && game.ports.length ? game.ports[0].id : "";
        request("GET", `/saves?id=${encodeURIComponent(game.id)}&port=${encodeURIComponent(port)}`, null, (st, d) => cb(st === 200 ? d : null));
    }

    signal selectionChanged()

    function request(method, path, body, cb) {
        const xhr = new XMLHttpRequest();
        xhr.onreadystatechange = () => {
            if (xhr.readyState !== XMLHttpRequest.DONE) return;
            let data = null;
            try { data = JSON.parse(xhr.responseText); } catch (e) {}
            cb(xhr.status, data);
        };
        xhr.open(method, root.base + path);
        xhr.setRequestHeader("Authorization", "Bearer " + root.token);
        if (body) xhr.setRequestHeader("Content-Type", "application/json");
        xhr.send(body ? JSON.stringify(body) : undefined);
    }

    function fail(text) {
        root.status = "error";
        root.errorText = text;
    }

    function refresh() {
        if (root.token === "") { fail(root.tr("omnia-core no está en marcha (falta el token de sesión)", "omnia-core is stopped (session token missing)")); return; }
        request("GET", "/settings", null, (st, data) => {
            if (st === 200 && data) root.language = data.language === "en" ? "en" : "es";
        });
        request("GET", "/library", null, (st, d) => {
            if (st === 200 && d && d.games !== undefined) {
                root.games = d.games;
                root.libraryRevision = d.revision;
                root.status = d.games.length ? "ok" : "empty";
                root.errorText = "";
            } else if (st === 0) {
                fail(root.tr("omnia-core no responde en 127.0.0.1:", "omnia-core is not responding at 127.0.0.1:") + OmniaSettings.port);
            } else {
                fail((d && d.error) || ("error HTTP " + st));
            }
        });
    }

    property int pollSerial: 0
    function pollSelection() {
        if (root.token === "") return;
        const serial = ++root.pollSerial;
        const since = root.selected.revision >= 0 ? `?since=${root.selected.revision}&wait=25` : "";
        request("GET", "/selection" + since, null, (st, d) => {
            if (serial !== root.pollSerial) return;      // llegó una petición más nueva
            if (st === 200 && d && d.revision !== undefined) {
                const changed = d.revision !== root.selected.revision;
                root.selected = d;
                if (changed) { root.selectionChanged(); root.refresh(); }
                if (root.status === "error") root.refresh();
                root.pollSelection();
            } else {
                if (st === 0 || st >= 500) root.fail(root.tr("omnia-core no responde en 127.0.0.1:", "omnia-core is not responding at 127.0.0.1:") + OmniaSettings.port);
                retry.restart();
            }
        });
    }

    function select(id) {
        const g = games.find(x => x.id === id);
        root.actionError = "";
        root.selected = Object.assign({}, root.selected, { id: id, name: g ? g.name : "", fondo: g ? (g.fondo || "") : "" });
        root.selectionChanged();
        request("POST", "/selection/set", { id: id, filterKey: root.selected.filterKey || "all" }, (st, d) => {
            if (st !== 200) root.actionError = (d && d.error) || root.tr("No se pudo cambiar la selección.", "Could not change the selection.");
        });
    }

    function play(id) {
        const g = games.find(x => x.id === id);
        if (g && g.portAvailable) { openDesktop(id, "install"); return true; }          // sin port instalado no se puede jugar: se ofrece instalarlo en la app de escritorio
        const port = g && g.ports ? g.ports.find(p => p.canLaunch && !p.running) : null;
        if (!g || !port) { root.actionError = root.tr("El juego ya está en ejecución o no tiene un lanzador disponible.", "The game is already running or has no available launcher."); return false; }
        root.actionError = "";
        request("POST", "/launch", { id: id, port: port.id }, (st, d) => {
            if (st !== 200) root.actionError = (d && d.error) || root.tr("No se pudo lanzar el juego.", "Could not launch the game.");
        });
        return true;
    }

    // BigMode (biblioteca completa). Con id y details=true abre directamente la ficha de ese juego.
    function openBigMode(id, details, installPort, updatePort) {
        const cmd = Array.from(OmniaSettings.libraryCommand);
        if (id) cmd.push("--game", id);
        if (id && details) cmd.push("--details");
        if (id && installPort) cmd.push("--install-port");      // abre el diálogo «Instalar port» del juego
        if (id && updatePort) cmd.push("--update-port");        // abre el diálogo «Actualizar» del juego
        console.log("[Omnia] abrir BigMode:", JSON.stringify(cmd));
        Quickshell.execDetached(cmd);
    }
    // App de escritorio (Omnia Desktop Suite). Instalar, actualizar y ver descargas se hacen siempre aquí, nunca en Big Mode:
    // action = "install" | "update" | "downloads" | "" (solo abrirla en la ficha del juego, si se da id).
    function openDesktop(id, action) {
        const cmd = Array.from(OmniaSettings.desktopCommand);
        if (action === "downloads") cmd.push("--downloads");
        else if (id) {
            cmd.push("--game", id);
            if (action === "install") cmd.push("--install-port");
            else if (action === "update") cmd.push("--update-port");
        }
        console.log("[Omnia] abrir app de escritorio:", JSON.stringify(cmd));
        Quickshell.execDetached(cmd);
    }
    function openLibrary() { openBigMode("", false); }
    function openLibraryLegacy() {
        console.log("[Omnia] abrir BigMode:", JSON.stringify(OmniaSettings.libraryCommand));
        Quickshell.execDetached(OmniaSettings.libraryCommand);
    }

    Timer { id: retry; interval: 3000; onTriggered: { root.refresh(); root.pollSelection(); } }
    Timer { interval: 60000; running: root.token !== ""; repeat: true; onTriggered: root.refresh() }

    FileView {
        id: tokenFile
        path: OmniaSettings.tokenFile
        watchChanges: true
        printErrors: false
        onFileChanged: reload()
        onLoaded: {
            root.token = text().trim();
            root.refresh();
            root.pollSelection();
        }
        onLoadFailed: root.fail(root.tr("omnia-core no está en marcha (falta el token de sesión)", "omnia-core is stopped (session token missing)"))
    }
}

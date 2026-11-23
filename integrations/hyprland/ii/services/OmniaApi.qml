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
    property bool padPolling: false
    property int padSeq: -1
    property int padGameRev: -1
    property bool padOn: false
    property string padName: ""
    property string padFamily: ""
    property var padBattery: null          // {level, charging} si el sistema expone la batería del mando
    signal padKey(string key)

    function pollPad() {
        if (!root.padPolling || root.token === "") return;
        const gen = ++root.padGen;
        request("GET", `/events?since=${root.padSeq}&gameSince=${root.padGameRev}&wait=20`, null, (st, d) => {
            if (gen !== root.padGen || !root.padPolling) return;
            if (st === 200 && d) {
                const first = root.padSeq < 0;
                root.padSeq = d.seq;
                if (d.gameRevision !== undefined) root.padGameRev = d.gameRevision;
                root.padOn = d.padOn === true;
                root.padName = d.padName || "";
                root.padFamily = d.padFamily || d.padLayout || "";
                root.padBattery = d.padBattery || null;
                if (!first && d.events) for (const e of d.events) root.padKey(e.key);
                Qt.callLater(root.pollPad);
            } else {
                padRetry.restart();
            }
        });
    }
    property int padGen: 0
    onPadPollingChanged: { if (padPolling) { padSeq = -1; pollPad(); } else padGen++; }
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
        if (root.token === "") { fail("omnia-core no está en marcha (falta el token de sesión)"); return; }
        request("GET", "/library", null, (st, d) => {
            if (st === 200 && d && d.games !== undefined) {
                root.games = d.games;
                root.libraryRevision = d.revision;
                root.status = d.games.length ? "ok" : "empty";
                root.errorText = "";
            } else if (st === 0) {
                fail("omnia-core no responde en 127.0.0.1:" + OmniaSettings.port);
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
                if (st === 0 || st >= 500) root.fail("omnia-core no responde en 127.0.0.1:" + OmniaSettings.port);
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
            if (st !== 200) root.actionError = (d && d.error) || "No se pudo cambiar la selección.";
        });
    }

    function play(id) {
        const g = games.find(x => x.id === id);
        const port = g && g.ports ? g.ports.find(p => p.canLaunch && !p.running) : null;
        if (!g || !port) { root.actionError = "El juego ya está en ejecución o no tiene un lanzador disponible."; return false; }
        root.actionError = "";
        request("POST", "/launch", { id: id, port: port.id }, (st, d) => {
            if (st !== 200) root.actionError = (d && d.error) || "No se pudo lanzar el juego.";
        });
        return true;
    }

    // BigMode (biblioteca completa). Con id y details=true abre directamente la ficha de ese juego.
    function openBigMode(id, details, installPort) {
        const cmd = Array.from(OmniaSettings.libraryCommand);
        if (id) cmd.push("--game", id);
        if (id && details) cmd.push("--details");
        if (id && installPort) cmd.push("--install-port");      // abre el diálogo «Instalar port» del juego
        console.log("[Omnia] abrir BigMode:", JSON.stringify(cmd));
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
        onLoadFailed: root.fail("omnia-core no está en marcha (falta el token de sesión)")
    }
}

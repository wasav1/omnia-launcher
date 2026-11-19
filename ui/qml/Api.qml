import QtQuick

// Cliente de omnia-core: HTTP en loopback con el token de sesión (se lee del archivo, nunca va en el código).
QtObject {
    id: api

    property int port: 47831
    property string tokenPath: ""
    property string token: ""
    // Plasma wallpaper plugins run inside plasmashell and cannot read the bearer token through QML XHR.
    // A native QML singleton may provide it; the standalone UI keeps using its private token file.
    property string providedToken: ""
    property bool controlsEnabled: true
    property bool systemEnabled: false
    property bool ok: false
    property string error: ""
    property var games: []
    property string toast: ""
    property string notificationPosition: "bottom-right"
    property string theme: "blue"
    property color themeAccent: "#336599"
    property real toastLevel: 0           // opacidad del aviso: 1 al mostrarlo, 3 s después se desvanece en 2 s
    function notify(text) { toast = ""; toast = text }
    onToastChanged: {
        toastFade.stop()
        if (toast === "") { toastLevel = 0; return }
        toastLevel = 1
        toastHold.restart()
    }
    property Timer toastHold: Timer { interval: 3000; onTriggered: toastFade.start() }
    property NumberAnimation toastFade: NumberAnimation { target: api; property: "toastLevel"; to: 0; duration: 2000; easing.type: Easing.InOutQuad
        onFinished: api.toast = "" }
    property bool covered: false          // una ventana maximizada o a pantalla completa tapa el escritorio
    property bool shelfActive: true       // el mando es de la estantería (ninguna ventana normal tiene el foco)
    property var apps: []
    property var appGroups: []
    property bool gameMode: false         // modo juego activo (descargas congeladas y perfil de energía alto)
    readonly property bool gameRunning: {
        for (let i = 0; i < api.games.length; i++) if (api.games[i].running) return true
        return false
    }                                      // estado inmediato para la interfaz; el modo de energía usa su propia histéresis
    property bool padOn: false
    property bool menuOpen: false         // Big Menu abierto (la UI lo informa; pausa el sondeo del espectro)
    property string padName: ""
    property int padSeq: -1
    property int gameRevision: -1
    property int revision: -1
    property bool audioActive: false
    property bool audioAvailable: false
    property var audioBands: []
    property var system: ({})             // /system: procesador, discos, batería, perfil energético y ventiladores
    signal padKey(string key)
    property string _last: ""

    function arg(name, fallback) {
        let a = Qt.application.arguments, i = a.indexOf(name)
        return (i >= 0 && i + 1 < a.length) ? a[i + 1] : fallback
    }

    function readToken() {
        if (providedToken) return providedToken
        if (!tokenPath) return ""
        try {
            let x = new XMLHttpRequest()
            x.open("GET", "file://" + tokenPath, false)       // archivo local pequeño: síncrono
            x.send()
            return x.responseText.trim()
        } catch (e) { return "" }
    }

    function call(method, path, done, body) {
        if (!api.token) api.token = api.readToken()
        let x = new XMLHttpRequest()
        x.onreadystatechange = function () {
            if (x.readyState !== 4) return
            let body = {}
            try { body = JSON.parse(x.responseText) } catch (e) { }
            if (x.status === 401) api.token = ""                  // el servicio se reinició: token nuevo
            done(x.status, body)
        }
        x.open(method, "http://127.0.0.1:" + api.port + path)
        x.setRequestHeader("Authorization", "Bearer " + api.token)
        if (method === "POST") x.setRequestHeader("Content-Type", "application/json")
        x.send(method === "POST" ? (body ? JSON.stringify(body) : "{}") : null)
    }

    function loadPreferences() {
        call("GET", "/settings", function(status, body) {
            if (status === 200) {
                api.notificationPosition = body.notification_position || "bottom-right"
                api.theme = body.theme || "blue"
                api.themeAccent = body.theme_accent || "#336599"
            }
        })
    }

    function refresh() {
        call("GET", "/library?since=" + api.revision, function (status, body) {
            if (status === 200) {
                api.ok = true; api.error = ""
                if (body.revision !== undefined && body.revision !== api.revision && body.games)
                    api.games = body.games
                if (body.revision !== undefined) api.revision = body.revision
            }
            else {
                api.ok = false
                api.error = status === 0 ? "omnia-core no responde (¿está en marcha el servicio?)"
                      : status === 401 ? "token no válido: reiniciando conexión" : "error " + status
            }
        })
    }

    function selectGame(id, done, filterKey) {
        call("POST", "/selection/set", function (status, body) {
            if (status !== 200) console.warn("Omnia: no se pudo sincronizar el juego seleccionado", status)
            if (done) done(status, body)
        }, { id: id || "", filterKey: filterKey || "all" })
    }
    function setView(filterKey, searchText, done) {
        call("POST", "/view/set", function (status, body) {
            if (status !== 200) console.warn("Omnia: no se pudo sincronizar la vista", status)
            if (done) done(status, body)
        },
             { filterKey: filterKey || "all", searchText: searchText || "" })
    }

    // Al cerrar/minimizar un juego a pantalla completa, KWin libera el escritorio. Refresca la biblioteca
    // enseguida para retirar la capa «EN EJECUCIÓN» sin esperar al siguiente sondeo periódico.
    onCoveredChanged: if (!covered) Qt.callLater(refresh)

    function pollSystem() {
        call("GET", "/system", function (status, body) { if (status === 200 && body) api.system = body })
    }

    function pollAudio() {
        call("GET", "/audio", function (status, body) {
            if (status === 200 && body) {
                api.audioAvailable = body.available === true
                api.audioActive = body.active === true
                api.audioBands = body.bands || []
            }
        })
    }

    function launch(g, portId) {
        if (!g || !g.ports.length) return
        api.toast = "Lanzando " + g.name + "…"
        call("POST", "/launch?id=" + encodeURIComponent(g.id) + "&port=" + encodeURIComponent(portId || g.ports[0].id), function (status, body) {
            api.toast = status === 200 ? "" : (body.error || "error " + status)
            api.refresh()
        })
    }

    // --- aplicaciones (Big Menu)
    function loadApps() {
        call("GET", "/apps", function (status, body) {
            if (status === 200) { api.apps = body.apps; api.appGroups = body.groups }
        })
    }
    // --- salida de audio (botón del altavoz)
    function loadAudioOutputs(done) {
        call("GET", "/audio/outputs", function (status, body) {
            if (status !== 200 || !body || !body.ok || !body.items.length) { done([], (body && body.error) || ""); return }
            done(body.items, "")
        })
    }
    function setAudioOutput(item, done) {
        call("POST", "/audio/set?sink=" + encodeURIComponent(item.sink) + "&port=" + encodeURIComponent(item.port || ""),
             function (status) { if (done) done(status === 200) })
    }
    function launchApp(a, done) {
        call("POST", "/app/launch?id=" + encodeURIComponent(a.id), function (status, body) {
            if (status !== 200) api.toast = body.error || "error " + status
            if (done) done(status === 200)
        })
    }
    // --- partidas, explorador de carpetas y juegos manuales (cada función avisa con done(status, cuerpo))
    function fsList(path, files, exts, done) {
        call("GET", "/fs/list?path=" + encodeURIComponent(path || "") + "&files=" + (files ? "1" : "0") + "&ext=" + encodeURIComponent((exts || []).join(",")), done)
    }
    function _q(g, portId) { return "id=" + encodeURIComponent(g.id) + "&port=" + encodeURIComponent(portId || (g.ports && g.ports.length ? g.ports[0].id : "")) }
    function savesInfo(g, done, portId) { call("GET", "/saves?" + _q(g, portId), done) }
    function savesSuggest(g, done, portId) { call("GET", "/saves/suggest?" + _q(g, portId), done) }
    function savesConfig(g, body, done, portId) { call("POST", "/saves/config?" + _q(g, portId), done, body) }
    function savesBackup(g, done, portId) { call("POST", "/saves/backup?" + _q(g, portId), done) }
    function savesRestore(g, file, done, portId) { call("POST", "/saves/restore?" + _q(g, portId) + "&file=" + encodeURIComponent(file), done) }
    function savesOpen(g, done, portId) { call("POST", "/saves/open?" + _q(g, portId), done) }
    function artBrowse(g, kind, page, sgid, done) {
        call("GET", "/art/browse?id=" + encodeURIComponent(g.id) + "&kind=" + encodeURIComponent(kind) + "&page=" + page + "&sgid=" + sgid, done)
    }
    function artPick(g, kind, page, sgid, index, done) {
        call("POST", "/art/pick?id=" + encodeURIComponent(g.id) + "&kind=" + encodeURIComponent(kind) + "&page=" + page + "&sgid=" + sgid + "&index=" + index, done)
    }
    function artCycle(g, kind, direction, done) {
        call("POST", "/art/cycle?id=" + encodeURIComponent(g.id) + "&kind=" + encodeURIComponent(kind) + "&dir=" + direction, done)
    }
    function importFind(done) { call("GET", "/import/find", done) }
    function importPreview(path, done) { call("GET", "/import/preview?path=" + encodeURIComponent(path), done) }
    function importApply(path, done) { call("POST", "/import/apply?path=" + encodeURIComponent(path), function (st, b) { if (st === 200) api.refresh(); done(st, b) }) }
    function templates(done) { call("GET", "/templates", done) }
    function addGame(body, done) { call("POST", "/game/add", function (st, b) { if (st === 200) api.refresh(); done(st, b) }, body) }
    function suggestGame(path, done) { call("GET", "/game/suggest?path=" + encodeURIComponent(path), done) }
    function removeGame(g, done) { call("POST", "/game/remove?id=" + encodeURIComponent(g.id), function (st, b) { if (st === 200) api.refresh(); done(st, b) }) }

    function reportMenu(open) { api.menuOpen = open; call("POST", "/menu/state?open=" + (open ? "1" : "0"), function () { }) }
    function power(action) {
        call("POST", "/power?a=" + encodeURIComponent(action), function (status, body) {
            if (status !== 200) api.toast = (body && body.error) || "No se pudo ejecutar la acción"
        })
    }
    function toggleAppFav(a) {
        call("POST", "/app/fav?id=" + encodeURIComponent(a.id), function () { api.loadApps() })
    }

    function toggleFav(g) {
        if (!g) return
        call("POST", "/game/fav?id=" + encodeURIComponent(g.id), function () { api.refresh() })
    }

    // Mando: petición larga a /events (el servidor responde en cuanto hay un botón nuevo o a los 20 s)
    function pollPad() {
        call("GET", "/events?since=" + padSeq + "&gameSince=" + gameRevision + "&wait=20", function (status, body) {
            if (status === 200) {
                const first = api.padSeq < 0
                api.padSeq = body.seq
                if (!first && api.gameRevision >= 0 && body.gameRevision !== api.gameRevision) api.refresh()
                api.gameRevision = body.gameRevision === undefined ? api.gameRevision : body.gameRevision
                api.padOn = body.padOn
                api.padName = body.padName
                api.covered = body.covered === true
                api.gameMode = body.gameMode ? body.gameMode.active === true : false
                api.shelfActive = body.shelfActive !== false
                if (!first) for (let i = 0; i < body.events.length; i++) api.padKey(body.events[i].key)
                Qt.callLater(function() { api.pollPad() })
            } else {
                retry.start()            // omnia-core no responde o el token cambió: reintenta sin saturar
            }
        })
    }
    property Timer retry: Timer { interval: 2000; onTriggered: { api.padSeq = -1; api.pollPad() } }
    property Timer audioPoll: Timer { interval: api.audioActive ? 42 : 1000; repeat: true; running: api.controlsEnabled && api.ok && !api.covered && !api.gameRunning && !api.menuOpen; triggeredOnStart: true; onTriggered: api.pollAudio() }

    property Timer systemPoll: Timer { interval: 3000; repeat: true; running: api.systemEnabled && api.ok && !api.gameRunning; triggeredOnStart: true; onTriggered: api.pollSystem() }
    property Timer preferencesPoll: Timer { interval: 5000; repeat: true; running: api.controlsEnabled && api.ok; triggeredOnStart: true; onTriggered: api.loadPreferences() }

    Component.onCompleted: {
        port = parseInt(arg("--port", "47831"))
        tokenPath = arg("--token", "")
        loadPreferences()
        refresh()
        if (controlsEnabled) pollPad()
    }
}

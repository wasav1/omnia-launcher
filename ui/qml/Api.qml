import QtQuick

// Cliente de omnia-core: HTTP en loopback con el token de sesión (se lee del archivo, nunca va en el código).
QtObject {
    id: api

    property int port: 47831
    property string tokenPath: ""
    property string token: ""
    property bool ok: false
    property string error: ""
    property var games: []
    property string toast: ""
    property bool covered: false          // una ventana maximizada o a pantalla completa tapa el escritorio
    property bool shelfActive: true       // el mando es de la estantería (ninguna ventana normal tiene el foco)
    property var apps: []
    property var appGroups: []
    property bool gameMode: false         // modo juego activo (descargas congeladas y perfil de energía alto)
    property bool padOn: false
    property bool menuOpen: false         // Big Menu abierto (la UI lo informa; pausa el sondeo del espectro)
    property string padName: ""
    property int padSeq: -1
    property bool audioActive: false
    property bool audioAvailable: false
    property var audioBands: []
    property var system: ({})             // /system: modelo y GHz de la CPU, disco de los juegos, batería
    signal padKey(string key)
    property string _last: ""

    function arg(name, fallback) {
        let a = Qt.application.arguments, i = a.indexOf(name)
        return (i >= 0 && i + 1 < a.length) ? a[i + 1] : fallback
    }

    function readToken() {
        if (!tokenPath) return ""
        try {
            let x = new XMLHttpRequest()
            x.open("GET", "file://" + tokenPath, false)       // archivo local pequeño: síncrono
            x.send()
            return x.responseText.trim()
        } catch (e) { return "" }
    }

    function call(method, path, done, body) {
        if (!token) token = readToken()
        let x = new XMLHttpRequest()
        x.onreadystatechange = function () {
            if (x.readyState !== 4) return
            let body = {}
            try { body = JSON.parse(x.responseText) } catch (e) { }
            if (x.status === 401) token = ""                  // el servicio se reinició: token nuevo
            done(x.status, body)
        }
        x.open(method, "http://127.0.0.1:" + port + path)
        x.setRequestHeader("Authorization", "Bearer " + token)
        x.send(method === "POST" ? (body ? JSON.stringify(body) : "{}") : null)
    }

    function refresh() {
        call("GET", "/library", function (status, body) {
            if (status === 200) {
                ok = true; error = ""
                let sig = JSON.stringify(body.games)
                if (sig !== _last) { _last = sig; games = body.games }      // solo si cambió: la lista no se reconstruye en cada sondeo
            }
            else {
                ok = false
                error = status === 0 ? "omnia-core no responde (¿está en marcha el servicio?)"
                      : status === 401 ? "token no válido: reiniciando conexión" : "error " + status
            }
        })
    }

    function pollSystem() {
        call("GET", "/system", function (status, body) { if (status === 200 && body) system = body })
    }

    function pollAudio() {
        call("GET", "/audio", function (status, body) {
            if (status === 200) {
                audioAvailable = body.available === true
                audioActive = body.active === true
                audioBands = body.bands || []
            }
        })
    }

    function launch(g, portId) {
        if (!g || !g.ports.length) return
        toast = "Lanzando " + g.name + "…"
        call("POST", "/launch?id=" + encodeURIComponent(g.id) + "&port=" + encodeURIComponent(portId || g.ports[0].id), function (status, body) {
            toast = status === 200 ? "" : (body.error || "error " + status)
            refresh()
        })
    }

    // --- aplicaciones (Big Menu)
    function loadApps() {
        call("GET", "/apps", function (status, body) {
            if (status === 200) { apps = body.apps; appGroups = body.groups }
        })
    }
    function launchApp(a, done) {
        call("POST", "/app/launch?id=" + encodeURIComponent(a.id), function (status, body) {
            if (status !== 200) toast = body.error || "error " + status
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
    function importApply(path, done) { call("POST", "/import/apply?path=" + encodeURIComponent(path), function (st, b) { if (st === 200) refresh(); done(st, b) }) }
    function templates(done) { call("GET", "/templates", done) }
    function addGame(body, done) { call("POST", "/game/add", function (st, b) { if (st === 200) refresh(); done(st, b) }, body) }
    function removeGame(g, done) { call("POST", "/game/remove?id=" + encodeURIComponent(g.id), function (st, b) { if (st === 200) refresh(); done(st, b) }) }

    function reportMenu(open) { menuOpen = open; call("POST", "/menu/state?open=" + (open ? "1" : "0"), function () { }) }
    function power(action) {
        call("POST", "/power?a=" + encodeURIComponent(action), function (status, body) {
            if (status !== 200) toast = (body && body.error) || "No se pudo ejecutar la acción"
        })
    }
    function toggleAppFav(a) {
        call("POST", "/app/fav?id=" + encodeURIComponent(a.id), function () { loadApps() })
    }

    function toggleFav(g) {
        if (!g) return
        call("POST", "/game/fav?id=" + encodeURIComponent(g.id), function () { refresh() })
    }

    // Mando: petición larga a /events (el servidor responde en cuanto hay un botón nuevo o a los 20 s)
    function pollPad() {
        call("GET", "/events?since=" + padSeq + "&wait=20", function (status, body) {
            if (status === 200) {
                const first = padSeq < 0
                padSeq = body.seq
                padOn = body.padOn
                padName = body.padName
                covered = body.covered === true
                gameMode = body.gameMode ? body.gameMode.active === true : false
                shelfActive = body.shelfActive !== false
                if (!first) for (let i = 0; i < body.events.length; i++) padKey(body.events[i].key)
                Qt.callLater(pollPad)
            } else {
                retry.start()            // omnia-core no responde o el token cambió: reintenta sin saturar
            }
        })
    }
    property Timer retry: Timer { interval: 2000; onTriggered: { api.padSeq = -1; api.pollPad() } }
    property Timer audioPoll: Timer { interval: 42; repeat: true; running: api.ok && !api.covered && !api.gameMode && !api.menuOpen; triggeredOnStart: true; onTriggered: api.pollAudio() }

    property Timer systemPoll: Timer { interval: 3000; repeat: true; running: api.ok && !api.gameMode; triggeredOnStart: true; onTriggered: api.pollSystem() }

    Component.onCompleted: {
        port = parseInt(arg("--port", "47831"))
        tokenPath = arg("--token", "")
        refresh()
        pollPad()
    }
}

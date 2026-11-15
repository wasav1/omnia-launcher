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

    function call(method, path, done) {
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
        x.send(method === "POST" ? "{}" : null)
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

    function launch(g) {
        if (!g || !g.ports.length) return
        toast = "Lanzando " + g.name + "…"
        call("POST", "/launch?id=" + encodeURIComponent(g.id) + "&port=" + encodeURIComponent(g.ports[0].id), function (status, body) {
            toast = status === 200 ? "" : (body.error || "error " + status)
            refresh()
        })
    }

    function toggleFav(g) {
        if (!g) return
        call("POST", "/game/fav?id=" + encodeURIComponent(g.id), function () { refresh() })
    }

    Component.onCompleted: {
        port = parseInt(arg("--port", "47831"))
        tokenPath = arg("--token", "")
        refresh()
    }
}

import QtQuick
import QtQuick.Window
import org.kde.layershell as LayerShell
import org.kde.kirigami as Kirigami
import QtQuick.Controls as QQC2
import Qt5Compat.GraphicalEffects
import org.kde.plasma.plasmoid
import org.kde.plasma.core as PlasmaCore

// Estantería de juegos: escritorio de juegos para Plasma 6.
// Lienzo de referencia 1920x1080 escalado al tamaño del widget.
PlasmoidItem {
    id: root
    readonly property bool inShell: Qt.application.name === "plasmashell"
    preferredRepresentation: inShell ? compactRepresentation : fullRepresentation
    property bool shown: true
    Plasmoid.backgroundHints: PlasmaCore.Types.NoBackground

    // ------------------------------------------------------------------ configuración y datos
    readonly property string base: Plasmoid.configuration.helperUrl
    readonly property int clearance: Plasmoid.configuration.clearance
    readonly property real film: Plasmoid.configuration.film / 100
    readonly property int blurPx: Plasmoid.configuration.blur
    property var games: []
    property var view: []
    property string plat: "all"
    property int cur: 0
    readonly property var curGame: (view.length > 0 && cur >= 0 && cur < view.length) ? view[cur] : null
    property bool helperOk: false
    readonly property string tintHex: curGame && curGame.pal && curGame.pal.length > 0 ? "#ff" + String(curGame.pal[0]).replace("#", "") : ""
    onTintHexChanged: if (tintHex !== "" && helperOk) api("/tint?c=" + encodeURIComponent(tintHex), function() {})
    property string lastJson: ""
    property bool padConnected: false
    property bool busy: false
    property string launchName: ""
    property string toastText: ""
    property real clockMs: Date.now()
    property var stats: ({})
    property var tempHist: []
    property var levels: [0, 0, 0, 0]
    property var bands: []
    property bool soundOn: false
    property real lastLoud: 0
    function noteSound(l) {
        var m = Math.max(l[0], l[1], l[2], l[3])
        if (m > 0.12) { lastLoud = Date.now(); if (!soundOn) soundOn = true }
        else if (soundOn && Date.now() - lastLoud > 3500) soundOn = false
    }
    property bool levelsReal: false
    property int evSeq: -1
    property bool hasFocus: false
    // Big Menu
    property bool bmOpen: false
    property bool bmPanelOn: false
    property string bmMode: "apps"     // "apps" | "power"
    property int pwIdx: 0
    property string pwConfirm: ""
    property int pwCI: 0               // 0 = Cancelar, 1 = Confirmar
    property bool searchOpen: false
    readonly property var pwItems: [
        { id: "lock",     t: "Bloquear",      icon: "system-lock-screen", c: false },
        { id: "suspend",  t: "Suspender",     icon: "system-suspend",     c: false },
        { id: "logout",   t: "Cerrar sesión", icon: "system-log-out",     c: true, q: "¿Cerrar la sesión?" },
        { id: "reboot",   t: "Reiniciar",     icon: "system-reboot",      c: true, q: "¿Reiniciar el equipo?" },
        { id: "shutdown", t: "Apagar",        icon: "system-shutdown",    c: true, q: "¿Apagar el equipo?" }
    ]
    property bool bmVis: false     // diálogos visibles (se mantienen mientras dura el fundido de salida)
    property bool bmShow: false    // objetivo de las animaciones
    property string gq: ""         // búsqueda de juegos (barra superior)
    property string padName: ""
    // salida de audio (solo con mando)
    // estantería deshabilitada mientras corre un juego lanzado desde ella (GeForce NOW no cuenta: su app queda abierta)
    property string runningId: ""
    property string runningName: ""
    property string runningLogo: ""
    property string ignoredRun: ""
    readonly property bool gameRunning: runningId !== "" && ignoredRun !== runningId
    onGameRunningChanged: { if (gameRunning) { ctxOpen = false; audOpen = false; artOpen = false; gsClose(false) } syncPad() }
    property bool refreshing: false
    function refreshLibrary() {
        if (refreshing) return
        refreshing = true
        toast("Buscando juegos instalados…")
        api("/library/refresh", function(r) {
            refreshing = false
            if (!r || !r.ok) { toast("No se pudo actualizar la biblioteca"); return }
            reload(true)
            var t = []
            if (r.new > 0) t.push("+" + r.new + (r.new === 1 ? " juego nuevo" : " juegos nuevos"))
            if (r.gone > 0) t.push("−" + r.gone + (r.gone === 1 ? " quitado" : " quitados"))
            toast(t.length ? "Biblioteca actualizada: " + t.join(" · ") : "Biblioteca al día: no hay juegos nuevos")
        })
    }
    // ---------------- selección manual de arte (SteamGridDB)
    property bool artOpen: false
    property string artGid: ""
    property string artGName: ""
    property string artKind: "portada"
    property var artItems: []
    property var artGames: []
    property int artSgid: 0
    property int artPage: 0
    property bool artMore: false
    property bool artBusy: false
    property bool artFail: false
    property int artIdx: 0
    readonly property var artKinds: ["portada", "fondo", "logo"]
    readonly property int artCols: artKind === "portada" ? 6 : (artKind === "fondo" ? 3 : 4)
    function artShow() {
        if (!curGame || busy) return
        artGid = curGame.id; artGName = curGame.name; artKind = "portada"; artSgid = 0
        artItems = []; artGames = []; artIdx = 0; artOpen = true
        artLoad(0)
    }
    function artLoad(page) {
        artBusy = true; artFail = false
        var kind = artKind, gid = artGid
        api("/art/browse?id=" + encodeURIComponent(gid) + "&kind=" + kind + "&page=" + page + "&sgid=" + artSgid, function(r) {
            if (kind !== artKind || gid !== artGid) return
            artBusy = false
            if (!r || !r.ok) { artFail = true; if (page === 0) artItems = []; return }
            artGames = r.games; artSgid = r.sgid; artMore = r.more; artPage = page
            artItems = page === 0 ? r.items : artItems.concat(r.items)
            if (page === 0) artIdx = 0
        })
    }
    function artTab(d) {
        var i = (artKinds.indexOf(artKind) + d + artKinds.length) % artKinds.length
        artKind = artKinds[i]; artItems = []; artIdx = 0; artLoad(0)
    }
    function artGame(d) {
        if (artGames.length < 2) return
        var ci = 0
        for (var i = 0; i < artGames.length; i++) if (artGames[i].id === artSgid) ci = i
        artSgid = artGames[(ci + d + artGames.length) % artGames.length].id
        artItems = []; artIdx = 0; artLoad(0)
    }
    function artPick(i) {
        var it = artItems[i]
        if (!it || artBusy) return
        artBusy = true
        api("/art/pick?id=" + encodeURIComponent(artGid) + "&kind=" + artKind + "&sgid=" + artSgid + "&url=" + encodeURIComponent(it.url), function(r) {
            artBusy = false
            toast(r && r.ok ? "Arte aplicado: " + artKind : "No se pudo descargar el arte")
            if (r && r.ok) {
                var na = []
                for (var j = 0; j < artItems.length; j++) { var o = {}; for (var kk in artItems[j]) o[kk] = artItems[j][kk]; o.cur = (j === i); if (j === i) na.unshift(o); else na.push(o) }
                artItems = na; artIdx = 0
                reload(true)
            }
        })
    }
    function artMove(dx, dy) {
        var n = artItems.length
        if (n === 0) return
        var i = artIdx + dx + dy * artCols
        if (i < 0 || i >= n) { if (dy > 0 && artMore && !artBusy) artLoad(artPage + 1); return }
        artIdx = i
        if (artMore && !artBusy && i > n - artCols * 2) artLoad(artPage + 1)
    }
    function artKey(k) {
        if (k === "l") artMove(-1, 0); else if (k === "r") artMove(1, 0)
        else if (k === "u") artMove(0, -1); else if (k === "d") artMove(0, 1)
        else if (k === "A") artPick(artIdx)
        else if (k === "LB") artTab(-1); else if (k === "RB") artTab(1)
        else if (k === "LT") artGame(-1); else if (k === "RT") artGame(1)
        else if (k === "B" || k === "CTX" || k === "PADSTART" || k === "MENU") artOpen = false
    }
    property bool audOpen: false
    property int audIdx: 0
    property var audItems: []
    function audShow() {
        api("/audio/outputs", function(r) {
            if (!r || !r.ok || !r.items.length) { toast("No se pudo leer los dispositivos de audio"); return }
            audItems = r.items
            audIdx = Math.max(0, r.items.findIndex(function(x) { return x.current }))
            audOpen = true
        })
    }
    function audActivate(i) {
        var it = audItems[i]
        audOpen = false
        if (!it) return
        api("/audio/set?sink=" + encodeURIComponent(it.sink) + "&port=" + encodeURIComponent(it.port), function(r) {
            toast(r && r.ok ? "Audio: " + it.label : "No se pudo cambiar la salida de audio")
        })
    }
    function audKey(k) {
        var n = audItems.length
        if (k === "u") audIdx = (audIdx - 1 + n) % n
        else if (k === "d") audIdx = (audIdx + 1) % n
        else if (k === "A") audActivate(audIdx)
        else if (k === "B" || k === "CTX" || k === "PADSTART" || k === "MENU") audOpen = false
    }
    property bool ctxOpen: false
    property int ctxIdx: 0
    property real ctxX: -1
    property real ctxY: -1
    property string pendingKeep: ""
    readonly property var ctxItems: {
        var g = curGame
        if (!g) return []
        var l = [
            { t: "Jugar", ic: "media-playback-start", a: 0 },
            { t: "Respaldar partidas", ic: "document-save", a: 1 },
            { t: "Abrir carpeta", ic: "folder-open", a: 2 },
            { t: "Cambiar arte", ic: "view-refresh", a: 3 },
            { t: "Elegir arte (SteamGridDB)…", ic: "images-flickr", a: 7 },
            { t: g.fav ? "Quitar de favoritos" : "Añadir a favoritos", ic: "starred-symbolic", a: 4 },
            { t: g.hidden ? "Mostrar juego" : "Ocultar juego", ic: g.hidden ? "view-visible" : "view-hidden", a: 5 }
        ]
        if (gq !== "") l.push({ t: "Borrar filtro de búsqueda", ic: "edit-clear", a: 6 })
        return l
    }
    function ctxShow(x, y) { if (!curGame || busy) return; ctxX = x; ctxY = y; ctxIdx = 0; ctxOpen = true }
    function ctxActivate(i) {
        var it = ctxItems[i]; ctxOpen = false
        if (!it) return
        if (it.a === 0) launch()
        else if (it.a === 1) doBackup()
        else if (it.a === 2) doOpen()
        else if (it.a === 3) cycleArt()
        else if (it.a === 7) artShow()
        else if (it.a === 4) toggleFav()
        else if (it.a === 5) toggleHide()
        else gsClose(true)
    }
    function ctxKey(k) {
        var n = ctxItems.length
        if (k === "u") ctxIdx = (ctxIdx - 1 + n) % n
        else if (k === "d") ctxIdx = (ctxIdx + 1) % n
        else if (k === "A") ctxActivate(ctxIdx)
        else if (k === "B" || k === "CTX" || k === "PADSTART" || k === "MENU") ctxOpen = false
    }
    function startSearch() {
        if (gsOpen) { gsClose(false); fz = "shelf" }
        else if (gq !== "") { gsPad = true; gsOpen = true; oskR = 1; oskC = 0 }
    }
    property bool gsOpen: false    // campo de búsqueda de juegos integrado en la estantería
    property bool gsPad: false     // abierta con el mando -> teclado virtual (con ratón/teclado NO aparece)
    function gsApply(t) { gq = t; updateView(""); cur = 0 }
    // teclado virtual para el mando
    property int oskR: 1
    property int oskC: 0
    property bool oskShift: false
    readonly property var oskRows: {
        var base = ["1234567890", "qwertyuiop", "asdfghjklñ", "zxcvbnm-'."], out = []
        for (var i = 0; i < base.length; i++) {
            var r = []
            for (var j = 0; j < base[i].length; j++) { var ch = base[i][j]; r.push({ t: oskShift ? ch.toUpperCase() : ch, k: "ch", w: 1 }) }
            out.push(r)
        }
        out.push([{ t: "⇧", k: "shift", w: 1.6 }, { t: "ESPACIO", k: "space", w: 4.4 }, { t: "⌫", k: "back", w: 1.6 }, { t: "BUSCAR", k: "done", w: 2.2 }])
        return out
    }
    function oskMove(d) {
        var R = oskRows
        if (d === "u" || d === "d") {
            var x = (oskC + 0.5) / R[oskR].length
            oskR = (oskR + (d === "d" ? 1 : -1) + R.length) % R.length
            oskC = Math.min(R[oskR].length - 1, Math.floor(x * R[oskR].length))
        } else oskC = (oskC + (d === "r" ? 1 : -1) + R[oskR].length) % R[oskR].length
    }
    function oskPress() {
        var key = oskRows[oskR][oskC]
        if (key.k === "shift") oskShift = !oskShift
        else if (key.k === "space") gsApply(gq + " ")
        else if (key.k === "back") gsApply(gq.slice(0, -1))
        else if (key.k === "done") { gsClose(false); fz = "shelf" }
        else { gsApply(gq + key.t); if (oskShift) oskShift = false }
    }
    function oskKey(k) {
        if (k === "l" || k === "r" || k === "u" || k === "d") oskMove(k)
        else if (k === "A") oskPress()
        else if (k === "B") { if (gq.length) gsApply(gq.slice(0, -1)); else gsClose(true) }     // B borra; con el campo vacío cierra la búsqueda
        else if (k === "X") oskShift = !oskShift
        else if (k === "Y") gsApply(gq + " ")
    }
    function gsToggle() { if (gsOpen) gsClose(true); else { gsPad = false; gsOpen = true } }
    function gsClose(clear) { gsOpen = false; gsPad = false; if (clear && gq !== "") gsApply("") }
    property var apps: []
    property var bmTop: []
    property var bmList: []
    property var bmRows: []
    property string bmCat: "Todas"
    property string bmQuery: ""
    property string bmZone: "grid"   // "q" | "cats" | "grid"
    property int bmIdx: 0
    readonly property var bmCats: ["Todas", "Favoritos", "Juegos", "Multimedia", "Desarrollo", "Internet", "Oficina", "Utilidades", "Sistema", "Configuración"]
    readonly property int bmCols: 6
    readonly property real bmU: (deskWin.screen ? deskWin.screen.width : 1920) / 100 * 0.84     // 1 unidad = 1 % del ancho (igual que el prototipo)
    readonly property var bmPal: ["#5865f2","#4d4de8","#1fa0e8","#6b7280","#e8923a","#7b6cf0","#c9965a","#f05a5a","#f0b84a","#3a8fd8","#e0572c","#41c460","#7a8794","#6c63e8","#2f9e6e","#d6492f","#8a5cf0","#2aa7c9","#e6b422"]
    function bmColor(n) { var h = 0; for (var i = 0; i < n.length; i++) h = (h * 31 + n.charCodeAt(i)) >>> 0; return bmPal[h % bmPal.length] }
    function bmInitials(n) { var w = n.replace(/[^A-Za-zÁÉÍÓÚÑáéíóúñ0-9 ]/g, " ").trim().split(/\s+/); return w.length > 1 ? (w[0][0] + w[1][0]).toUpperCase() : n.substring(0, 2) }
    readonly property bool panOn: Plasmoid.configuration.pan && !covered && !bmOpen && !gameRunning
    property var portSel: ({})
    readonly property int portIdx: curGame ? (portSel[curGame.id] !== undefined ? Math.min(portSel[curGame.id], curGame.ports.length - 1) : curGame.lastPort) : 0
    readonly property var curPort: (curGame && curGame.ports.length > 0) ? curGame.ports[portIdx] : null
    readonly property int pn: (curGame && curGame.ports.length > 1) ? curGame.ports.length : 0
    // zonas de foco: "shelf" | "act" | "pl" | "head" (cabecera: filtros, lupa, energía)
    property string fz: "shelf"
    property int fi: 0

    readonly property var plats: ({
        n64:    { nom: "Nintendo 64",       cor: "N64",         col: "#d9a441" },
        sw1:    { nom: "Nintendo Switch",   cor: "Switch",      col: "#e8604f" },
        sw2:    { nom: "Nintendo Switch 2", cor: "Switch 2",    col: "#58a6f0" },
        steam:  { nom: "PC · Steam",        cor: "Steam",       col: "#8fb0d0" },
        gfn:    { nom: "PC · GeForce NOW",  cor: "GeForce NOW", col: "#8cc63f" },
        heroic: { nom: "PC · Heroic",       cor: "Heroic",      col: "#a58ae6" },
        pc:     { nom: "PC",                cor: "PC",          col: "#6fc3c9" },
        fav:    { nom: "Favoritos",         cor: "★ Favoritos", col: "#e6d9a0" },
        hidden: { nom: "Ocultos",           cor: "Ocultos",     col: "#a59f8f" }
    })
    // claves de los filtros de la cabecera: Todos, Favoritos (si hay), consolas, Ocultos (si hay)
    readonly property var chipKeys: {
        var ks = ["all"], hasF = false, hasH = false
        for (var i = 0; i < games.length; i++) { if (games[i].fav) hasF = true; if (games[i].hidden) hasH = true }
        if (hasF) ks.push("fav")
        for (var j = 0; j < games.length; j++) if (ks.indexOf(games[j].platform) < 0) ks.push(games[j].platform)
        if (hasH) ks.push("hidden")
        return ks
    }
    readonly property int headCount: chipKeys.length + 3 + (padConnected ? 1 : 0)          // filtros + lupa + energía
    // Icono de la tarjeta/ficha: en PC se usa el logo del origen (Steam, Hydra, Heroic, Lutris, GeForce NOW)
    function iconKey(g) {
        if (!g) return "pc"
        if (g.platform !== "pc" || !g.src) return g.platform
        var k = { "Steam": "steam", "Hydra": "hydra", "Heroic": "heroic", "Lutris": "lutris", "GeForce NOW": "gfn" }[g.src]
        return k || "pc"
    }
    function platOf(k) { return plats[k] || { nom: k, cor: k, col: "#cccccc" } }

    // módulos opcionales: si alguno falla, el resto del widget sigue funcionando
    Loader { id: sensLoader; source: "SensorsSource.qml" }
    Loader { id: musicLoader; source: "MusicSource.qml" }
    Loader { id: winLoader; source: "WindowsWatcher.qml" }
    readonly property var sens: sensLoader.item
    readonly property var mus: musicLoader.item
    readonly property bool hasMusic: mus ? mus.available : false
    readonly property bool musicPlaying: mus ? mus.playing : false
    // el launcher queda tapado solo por ventanas maximizadas o en pantalla completa (las normales no lo ocultan)
    readonly property bool covered: winLoader.item ? winLoader.item.coveringWindows > 0 : false
    readonly property bool deskVisible: winLoader.item ? winLoader.item.visibleWindows === 0 : true

    // ------------------------------------------------------------------ utilidades
    function api(path, cb) {
        var x = new XMLHttpRequest()
        x.open("GET", base + path)
        x.onreadystatechange = function() {
            if (x.readyState !== XMLHttpRequest.DONE) return
            var r = null
            if (x.status === 200) { try { r = JSON.parse(x.responseText) } catch (e) { r = null } }
            if (cb) cb(r)
        }
        x.send()
    }
    function toast(t) { toastText = t; toastTimer.restart() }
    readonly property var meses: ["ene", "feb", "mar", "abr", "may", "jun", "jul", "ago", "sep", "oct", "nov", "dic"]
    function two(n) { return (n < 10 ? "0" : "") + n }
    function relTime(ts) {
        if (!ts || ts <= 0) return "nunca"
        var d = new Date(ts * 1000), n = new Date(clockMs)
        var hm = two(d.getHours()) + ":" + two(d.getMinutes())
        var sd = new Date(n.getFullYear(), n.getMonth(), n.getDate()).getTime()
        if (d.getTime() >= sd) return "hoy " + hm
        if (d.getTime() >= sd - 86400000) return "ayer " + hm
        return d.getDate() + " " + meses[d.getMonth()]
    }
    function durText(s) {
        if (!s || s <= 0) return ""
        var h = Math.floor(s / 3600), m = Math.floor((s % 3600) / 60)
        return h > 0 ? h + " h " + m + " min" : Math.max(1, m) + " min"
    }
    function mmss(s) { s = Math.max(0, Math.floor(s)); return Math.floor(s / 60) + ":" + two(s % 60) }
    function gb(b) { return (b / 1073741824).toFixed(1) }
    function ajustesText(list) {
        if (!list || list.length === 0) return "por defecto"
        var out = []
        for (var i = 0; i < Math.min(2, list.length); i++) {
            var k = list[i].k, v = list[i].v
            if (k === "output_res") out.push(v.replace("x", "×"))
            else if (k === "game_res") out.push(v + "p")
            else if (k === "fps_limit") out.push(v + " fps")
            else if (k === "anisotropic_filtering" || k === "aniso") out.push("aniso " + v)
            else if (k === "frame_generation") out.push(v === "0" ? "sin FG" : "FG")
            else if (k === "dlss") out.push(v === "0" ? "sin DLSS" : "DLSS " + v)
            else out.push(k + " " + v)
        }
        return out.join(" · ")
    }
    function sessionText(g) {
        if (!g) return ""
        var d = durText(g.lastSessionSecs)
        return d !== "" ? d : relTime(g.lastPlayed)
    }

    // ------------------------------------------------------------------ biblioteca
    function updateView(keepId) {
        var v = []
        var q = gq.trim().toLowerCase()
        for (var i = 0; i < games.length; i++) {
            var g = games[i]
            if (plat === "fav") { if (!g.fav || g.hidden) continue }
            else if (plat === "hidden") { if (!g.hidden) continue }
            else {
                if (g.hidden) continue
                if (plat !== "all" && g.platform !== plat) continue
            }
            if (q) {
                var hay = (g.name + " " + g.sub).toLowerCase()
                for (var pj = 0; pj < g.ports.length; pj++) hay += " " + g.ports[pj].name.toLowerCase()
                if (hay.indexOf(q) < 0) continue
            }
            v.push(g)
        }
        if (plat === "all" || plat === "fav") {        // los favoritos van primero (orden estable)
            // orden: último jugado, favoritos, luego juegos NUEVOS (añadidos hace <14 días y aún sin jugar), luego el resto
            var f = [], nw = [], n = [], lim = Date.now() / 1000 - 14 * 86400
            for (var ii = 0; ii < v.length; ii++) {
                var gv = v[ii]
                if (gv.fav) f.push(gv)
                else if (gv.added > lim && !(gv.lastPlayed > 0)) nw.push(gv)
                else n.push(gv)
            }
            nw.sort(function(a, b) { return b.added - a.added })
            v = f.concat(nw, n)
            if (plat === "all") {                       // el ÚLTIMO JUGADO (solo uno) va antes de los favoritos
                var bi = -1, bl = 0
                for (var li = 0; li < v.length; li++) if (v[li].lastPlayed > bl) { bl = v[li].lastPlayed; bi = li }
                if (bi > 0) v.unshift(v.splice(bi, 1)[0])
            }
        }
        var idx = 0
        if (keepId) for (var j = 0; j < v.length; j++) if (v[j].id === keepId) idx = j
        view = v
        cur = Math.min(idx, Math.max(0, v.length - 1))
    }
    function reload(force) {
        api("/library", function(r) {
            if (!r) { helperOk = false; return }
            helperOk = true
            var rid = "", rnm = "", rlg = ""
            for (var gi = 0; gi < r.games.length && rid === ""; gi++) {
                var gg = r.games[gi]
                if (gg.src === "GeForce NOW") continue
                for (var pi = 0; pi < gg.ports.length; pi++) if (gg.ports[pi].running) { rid = gg.id; rnm = gg.name; rlg = gg.logo || ""; break }
            }
            runningId = rid; runningName = rnm; runningLogo = rlg
            padConnected = r.pad
            var j = JSON.stringify(r.games)
            if (j === lastJson && !force) return
            lastJson = j
            var keep = pendingKeep !== "" ? pendingKeep : (curGame ? curGame.id : "")
            pendingKeep = ""
            games = r.games
            updateView(keep)
        })
    }
    function setPlat(k) {
        if (busy) return
        plat = k
        api("/ui?plat=" + k, function() {})
        updateView("")
        fz = "shelf"; fi = 0
    }
    function cyc(d) {
        var ks = chipKeys
        var i0 = ks.indexOf(plat)
        if (i0 < 0) i0 = 0
        setPlat(ks[(i0 + d + ks.length) % ks.length])
    }
    function sel(x) {
        if (busy || view.length === 0) return
        cur = Math.max(0, Math.min(view.length - 1, x))
    }
    function selectPort(i) {
        if (!curGame) return
        var m = JSON.parse(JSON.stringify(portSel))
        m[curGame.id] = i
        portSel = m
    }
    function cycPort(d) {
        if (!curGame || curGame.ports.length < 2 || busy) return
        var n = curGame.ports.length
        var i = (portIdx + d + n) % n
        selectPort(i)
        toast("Port: " + curGame.ports[i].name)
    }
    function bmUpdate() {
        var q = bmQuery.trim().toLowerCase(), l = []
        for (var i = 0; i < apps.length; i++) {
            var a = apps[i]
            if (q) { if ((a.name + " " + a.generic + " " + a.keywords + " " + a.base).toLowerCase().indexOf(q) >= 0) l.push(a) }
            else if (bmCat === "Todas" || (bmCat === "Favoritos" && a.fav) || a.group === bmCat) l.push(a)
        }
        var t = []
        if (!q && bmCat === "Todas") {
            for (var j = 0; j < apps.length; j++) if (apps[j].fav) t.push(apps[j])
            if (t.length === 0) { var m = apps.slice().sort(function(x, y) { return y.used - x.used }); t = m.slice(0, 5).filter(function(x) { return x.used > 0 }) }
            t = t.slice(0, bmCols)
            var ids = {}; for (var k = 0; k < t.length; k++) ids[t[k].id] = 1
            l = l.filter(function(x) { return !ids[x.id] })      // sin repetir los favoritos de arriba
        }
        bmTop = t; bmList = l
        // filas para la lista virtualizada: etiquetas + filas de bmCols apps (con su índice base)
        var rows = [], c = bmCols, off = 0
        function chunk(arr, base) { for (var i = 0; i < arr.length; i += c) rows.push({ k: "row", items: arr.slice(i, i + c), base: base + i }) }
        if (t.length) rows.push({ k: "label", t: "FAVORITOS", first: true })
        chunk(t, 0)
        if (t.length) rows.push({ k: "label", t: "TODAS LAS APLICACIONES", first: false })
        chunk(l, t.length)
        if (!t.length && !l.length) rows.push({ k: "empty" })
        bmRows = rows
        bmIdx = Math.max(0, Math.min(bmIdx, t.length + l.length - 1))
    }
    function bmAll() { return bmTop.concat(bmList) }
    function bmCatStep(d) {
        var i = Math.max(0, Math.min(bmCats.length - 1, bmCats.indexOf(bmCat) + d))
        bmCat = bmCats[i]; bmQuery = ""; bmIdx = 0; bmUpdate()
    }
    function pwActivate() {
        var it = pwItems[pwIdx]
        if (pwConfirm !== "") {
            if (pwCI === 1) { api("/power?a=" + pwConfirm, function() {}); bmClose() }
            else pwConfirm = ""
            return
        }
        if (it.c) { pwConfirm = it.id; pwCI = 0 }
        else { api("/power?a=" + it.id, function() {}); bmClose() }
    }
    function pwBack() { if (pwConfirm !== "") pwConfirm = ""; else bmMode = "apps" }
    function pwQuestion() { for (var i = 0; i < pwItems.length; i++) if (pwItems[i].id === pwConfirm) return pwItems[i].q; return "" }
    function bmOpenMenu(mode) {
        api("/apps", function(r) {
            if (!r) { toast("El ayudante no responde"); return }
            apps = r.apps; bmCat = "Todas"; bmQuery = ""; bmZone = "cats"; bmIdx = 0
            bmMode = mode === "power" ? "power" : "apps"; pwIdx = 0; pwConfirm = ""; pwCI = 0
            bmUpdate(); bmOpen = true
        })
    }
    function bmClose() { bmOpen = false }
    function bmToggle() { if (bmOpen) bmClose(); else bmOpenMenu("apps") }
    function bmLaunch(a) {
        if (!a) return
        api("/app/launch?id=" + encodeURIComponent(a.id), function(r) { if (!r || !r.ok) toast(r && r.error ? r.error : "No se pudo abrir " + a.name) })
        bmClose()
    }
    function bmFav(a) {
        if (!a) return
        api("/app/fav?id=" + encodeURIComponent(a.id), function() {
            api("/apps", function(r) { if (r) { apps = r.apps; bmUpdate() } })
        })
    }
    function bmNav(d) {
        if (bmMode === "power") {
            if (pwConfirm !== "") { if (d === "l") pwCI = 0; else if (d === "r") pwCI = 1 }
            else if (d === "l") pwIdx = Math.max(0, pwIdx - 1)
            else if (d === "r") pwIdx = Math.min(pwItems.length - 1, pwIdx + 1)
            return
        }
        var n = bmTop.length + bmList.length, cols = bmCols
        if (bmZone === "grid") {
            if (d === "r") bmIdx = Math.min(n - 1, bmIdx + 1)
            else if (d === "l") bmIdx = Math.max(0, bmIdx - 1)
            else if (d === "d") {
                if (bmTop.length && bmIdx < bmTop.length) bmIdx = Math.min(n - 1, bmTop.length + Math.min(bmIdx, Math.max(0, bmList.length - 1)))
                else bmIdx = Math.min(n - 1, bmIdx + cols)
            } else if (d === "u") {
                if (bmTop.length && bmIdx >= bmTop.length && bmIdx - cols < bmTop.length) bmIdx = Math.min(bmTop.length - 1, Math.max(0, bmIdx - bmTop.length))
                else if (bmIdx < cols && (!bmTop.length || bmIdx < bmTop.length)) bmZone = "cats"
                else bmIdx = bmIdx - cols
            }
        } else if (bmZone === "cats") {
            if (d === "r") bmCatStep(1)
            else if (d === "l") bmCatStep(-1)
            else if (d === "d") { bmZone = "grid"; bmIdx = 0 }
            else if (d === "u") bmZone = "q"
        } else {
            if (d === "d") bmZone = "cats"
        }
    }
    function bmEnter() {
        if (bmMode === "power") { pwActivate(); return }
        if (bmZone === "grid") bmLaunch(bmAll()[bmIdx])
        else if (bmZone === "cats") { bmZone = "grid"; bmIdx = 0 }
        else { var a = bmAll(); if (a.length) bmLaunch(a[0]) }
    }
    function launch() {
        var g = curGame, p = curPort
        if (!g || !p || busy) return
        if (!p.canLaunch) { toast("Aún no está listo: " + p.s); return }
        busy = true
        launchName = g.name + (g.ports.length > 1 ? " · " + p.name : "")
        api("/launch?id=" + g.id + "&port=" + p.id, function(r) {
            if (!r || !r.ok) { busy = false; toast(r && r.error ? r.error : "No se pudo lanzar"); return }
            launchTimer.restart()
        })
    }
    function doBackup() {
        var g = curGame, p = curPort
        if (!g || !p) return
        if (!p.canBackup) { toast("No hay partidas que respaldar"); return }
        api("/backup?id=" + g.id + "&port=" + p.id, function(r) {
            if (r && r.ok) { toast("Respaldo de " + p.name + " creado"); reload(true) }
            else toast(r && r.error ? r.error : "No se pudo respaldar")
        })
    }
    function doOpen() { var g = curGame, p = curPort; if (g && p) api("/open?id=" + g.id + "&port=" + p.id, function() {}) }
    function cycleArt() {
        var g = curGame
        if (!g) return
        api("/art/cycle?id=" + g.id + "&kind=portada&dir=1", function() {
            api("/art/cycle?id=" + g.id + "&kind=fondo&dir=1", function() { reload(true) })
        })
        toast("Arte cambiado")
    }

    // ------------------------------------------------------------------ navegación (teclado y mando)
    function actsCount() { return pn + 1 }
    function toggleFav() {
        var g = curGame; if (!g) return
        api("/game/fav?id=" + g.id, function(r) { toast(r && r.on ? "★ " + g.name + " añadido a favoritos" : g.name + " ya no es favorito"); reload(true) })
    }
    function toggleHide() {
        var g = curGame; if (!g) return
        var leaves = (plat !== "hidden") !== !!g.hidden            // al ocultar (o mostrar desde «Ocultos») el juego sale de la lista
        if (leaves) { var nb = view[cur + 1] || view[cur - 1]; pendingKeep = nb ? nb.id : "" }
        api("/game/hide?id=" + g.id, function(r) { toast(r && r.on ? g.name + " oculto (filtro «Ocultos»)" : g.name + " visible de nuevo"); reload(true) })
    }
    function activateAct(i) {
        if (i < pn) { selectPort(i); return }
        var j = i - pn
        if (j === 0) launch()
        else if (j === 1) doBackup()
        else if (j === 2) doOpen()
        else if (j === 3) cycleArt()
        else if (j === 4) toggleFav()
        else toggleHide()
    }
    function activatePl(i) {
        if (!mus) return
        if (i === 0) mus.previous()
        else if (i === 1) mus.playPause()
        else mus.next()
    }
    function nav(d) {
        if (busy) return
        if (fz === "shelf") {
            if (d === "l") sel(cur - 1)
            else if (d === "r") sel(cur + 1)
            else if (d === "u") { fz = "act"; fi = pn }
        } else if (fz === "act") {
            if (d === "l") fi = Math.max(0, fi - 1)
            else if (d === "r") fi = Math.min(actsCount() - 1, fi + 1)
            else if (d === "d") { fz = "shelf"; fi = 0 }
            else if (d === "u") { if (hasMusic) { fz = "pl"; fi = 1 } else { fz = "head"; fi = Math.max(0, chipKeys.indexOf(plat)) } }
        } else if (fz === "pl") {
            if (d === "l") fi = Math.max(0, fi - 1)
            else if (d === "r") fi = Math.min(2, fi + 1)
            else if (d === "d") { fz = "act"; fi = pn }
            else if (d === "u") { fz = "head"; fi = Math.max(0, chipKeys.indexOf(plat)) }
        } else {   // cabecera: filtros · lupa · energía
            if (d === "l") fi = Math.max(0, fi - 1)
            else if (d === "r") fi = Math.min(headCount - 1, fi + 1)
            else if (d === "d") { fz = hasMusic ? "pl" : "act"; fi = hasMusic ? 1 : pn }
        }
    }
    function enter() {
        if (busy) return
        if (fz === "shelf") launch()
        else if (fz === "act") activateAct(fi)
        else if (fz === "pl") activatePl(fi)
        else activateHead(fi)
    }
    function activateHead(i) {
        var n = chipKeys.length
        if (i < n) setPlat(chipKeys[i])
        else if (i === n) { gsPad = true; gsOpen = true; oskR = 1; oskC = 0 }          // lupa con mando: se abre con el teclado virtual
        else if (i === n + 1) bmOpenMenu("power")
        else if (i === n + 2) refreshLibrary()
        else audShow()
    }
    function back() {
        if (busy) { launchTimer.stop(); busy = false; return }
        if (fz !== "shelf") { fz = "shelf"; fi = 0 }
    }
    function handleKey(k) {
        if (k === "GAMEEND" || k === "GAMESTART") { reload(true); syncPad(); return }       // el juego se abrió/cerró: estado y mando al instante
        if (gameRunning && !bmOpen) {                       // estantería deshabilitada: solo el Big Menú (Start / tecla Windows)
            if (k === "PADSTART" || k === "MENU") bmToggle()
            return
        }
        if (audOpen) { audKey(k); return }
        if (artOpen) { artKey(k); return }
        if (k === "CTX" && !bmOpen) { if (gsOpen && gsPad) return; if (ctxOpen) ctxOpen = false; else ctxShow(-1, -1); return }
        if (ctxOpen) { ctxKey(k); return }
        if (k === "PADSTART") {
            if (bmOpen) { bmClose(); return }
            if (gsOpen || gq !== "") { startSearch(); return }       // en modo filtro Start lanza la búsqueda (no el Big Menu)
            bmToggle(); return
        }
        if (k === "CTX") { bmMode = bmMode === "power" ? "apps" : "power"; pwConfirm = ""; return }
        if (k === "MENU") { bmToggle(); return }
        if (k === "SEARCH") { if (!bmOpen) searchOpen = true; return }
        if (k === "POWER") { if (!bmOpen) bmOpenMenu("power"); else { bmMode = bmMode === "power" ? "apps" : "power"; pwConfirm = "" } return }
        if (k.indexOf("PLAT:") === 0) { setPlat(k.substring(5)); return }
        if (k.indexOf("Q:") === 0) { gq = k.substring(2); var kp = curGame ? curGame.id : ""; updateView(kp); cur = 0; return }
        if (bmOpen) {
            if (k === "l" || k === "r" || k === "u" || k === "d") bmNav(k)
            else if (k === "A") bmEnter()
            else if (k === "B") { if (bmMode === "power") pwBack(); else bmClose() }
            else if (k === "Y") { if (bmMode === "apps") bmZone = "q" }
            else if (k === "X") { var al = bmAll(); if (al[bmIdx]) bmFav(al[bmIdx]) }
            else if (k === "LB" || k === "RB") {
                bmCatStep(k === "RB" ? 1 : -1)
            }
            return
        }
        if (gsOpen && gsPad) { oskKey(k); return }
        if (k === "l" || k === "r" || k === "u" || k === "d") nav(k)
        else if (k === "A") enter()
        else if (k === "B") back()
        else if (k === "X") doBackup()
        else if (k === "Y") { if (mus) mus.playPause() }
        else if (k === "LB") cyc(-1)
        else if (k === "RB") cyc(1)
        else if (k === "LT") cycPort(-1)
        else if (k === "RT") cycPort(1)
    }
    // eventos del mando (long-poll al ayudante)
    function pollEvents() {
        var x = new XMLHttpRequest()
        x.open("GET", base + "/events?since=" + evSeq + "&wait=20")
        x.onreadystatechange = function() {
            if (x.readyState !== XMLHttpRequest.DONE) return
            if (x.status === 200) {
                try {
                    var r = JSON.parse(x.responseText)
                    evSeq = r.seq
                    padConnected = r.padOn; if (r.padName !== undefined) padName = r.padName
                    for (var i = 0; i < r.events.length; i++) handleKey(r.events[i].k)
                } catch (e) {}
                pollTimer.restart()
            } else retryTimer.restart()
        }
        x.send()
    }
    function syncPad() { api("/pad?on=" + ((deskVisible || hasFocus || bmOpen) && !busy ? "1" : "0"), function() {}) }
    onFzChanged: api("/log?m=" + encodeURIComponent("zona: " + fz + " fi=" + fi + (busy ? " (ocupado)" : "") + (ctxOpen ? " (menú)" : "") + (gsOpen ? " (búsqueda)" : "")), function() {})
    onCoveredChanged: api("/log?m=" + encodeURIComponent("tapado por ventana maximizada/pantalla completa: " + covered), function() {})
    onDeskVisibleChanged: { syncPad(); api("/log?m=" + encodeURIComponent("escritorio a la vista: " + deskVisible), function() {}) }
    onHasFocusChanged: syncPad()
    onBmOpenChanged: {
        if (bmOpen) { bmHideTimer.stop(); bmShowTimer.stop(); bmPanelTimer.restart()
               api("/menu/prep?open=1", function() { if (root.bmOpen) { bmPanelTimer.stop(); root.bmReveal() } }) }
        else { bmPanelTimer.stop(); bmShowTimer.stop(); bmShow = false; bmHideTimer.restart()
               bmQuery = ""; bmCat = "Todas"; bmUpdate() }          // al cerrar: sin texto de búsqueda ni categoría residual
        syncPad(); api("/ui?menu=" + (bmOpen ? 1 : 0), function() {}) }

    // ------------------------------------------------------------------ temporizadores
    Timer { id: toastTimer; interval: 2400; onTriggered: root.toastText = "" }
    Timer { id: launchTimer; interval: 4500; onTriggered: { root.busy = false; root.reload(true) } }
    Timer { id: pollTimer; interval: 10; onTriggered: root.pollEvents() }
    Timer { id: retryTimer; interval: 2000; onTriggered: root.pollEvents() }
    Timer { interval: 1000; repeat: true; running: true; onTriggered: root.clockMs = Date.now() }
    Timer { interval: root.runningId !== "" ? 2500 : 6000; repeat: true; running: true; onTriggered: { root.reload(false); root.syncPad() } }
    Timer {
        interval: 3000; repeat: true; running: true; triggeredOnStart: true
        onTriggered: root.api("/stats", function(r) { if (r) root.stats = r })
    }
    Timer {
        interval: 1000; repeat: true; running: true
        onTriggered: {
            var h = root.tempHist.slice()
            h.push(root.sens ? root.sens.cpuTemp : 0)
            if (h.length > 60) h.shift()
            root.tempHist = h
        }
    }
    Timer {
        interval: 80; repeat: true; running: !root.covered && !root.bmOpen && !root.busy
        onTriggered: root.api("/levels", function(r) { if (r) { root.levels = r.levels; root.bands = r.bands || []; root.levelsReal = r.ok; root.noteSound(r.levels) } })
    }
    Component.onCompleted: { reload(true); pollEvents(); syncPad() }

    // ------------------------------------------------------------------ pantalla
    // capa de pantalla (layer-shell): cubre todo el monitor, por debajo de las ventanas y los paneles
    Window {
        id: deskWin
        visible: root.inShell && root.shown
        color: "#000000"
        flags: Qt.FramelessWindowHint
        LayerShell.Window.scope: "estanteria"
        LayerShell.Window.layer: LayerShell.Window.LayerBackground
        LayerShell.Window.anchors: LayerShell.Window.AnchorTop | LayerShell.Window.AnchorBottom | LayerShell.Window.AnchorLeft | LayerShell.Window.AnchorRight
        LayerShell.Window.exclusionZone: -1
        LayerShell.Window.keyboardInteractivity: LayerShell.Window.KeyboardInteractivityOnDemand
        Loader { anchors.fill: parent; sourceComponent: shelfComp; active: deskWin.visible }
    }
    // precarga del arte (comparte caché con el telón y el panel: el menú abre sin tirones de decodificación)
    Image { visible: false; asynchronous: true; source: root.curGame ? root.curGame.fondo : ""; sourceSize.width: 1920; cache: true }
    Image { visible: false; asynchronous: true; source: root.curGame ? root.curGame.fondo : ""; sourceSize.width: 960; cache: true }
    PlasmaCore.Dialog {
        id: searchDialog
        visible: root.searchOpen
        location: PlasmaCore.Types.Floating
        type: PlasmaCore.Dialog.Normal
        flags: Qt.WindowStaysOnTopHint
        backgroundHints: PlasmaCore.Dialog.NoBackground
        hideOnWindowDeactivate: false
        property bool wasActive: false
        readonly property var scr: deskWin.screen
        x: (scr ? scr.virtualX : 0) + ((scr ? scr.width : 1920) - 460) / 2
        y: (scr ? scr.virtualY : 0) + 50
        onActiveChanged: { if (active) wasActive = true; else if (wasActive && root.searchOpen) { wasActive = false; root.searchOpen = false } }
        onVisibleChanged: { if (visible) { sf.text = root.gq; sf.forceActiveFocus(); sf.selectAll() } else wasActive = false }
        mainItem: FocusScope {
            width: 460; height: 56
            Rectangle { anchors.fill: parent; radius: 28; color: "#f01a3326"; border.width: 1; border.color: "#59e6d9a0" }
            Kirigami.Icon { x: 18; anchors.verticalCenter: parent.verticalCenter; width: 20; height: 20; source: "search"; opacity: 0.85 }
            QQC2.TextField {
                id: sf
                x: 46; width: parent.width - 100; height: parent.height
                placeholderText: "Buscar juego del catálogo…"
                font.pixelSize: 20; font.family: "Hanken Grotesk"
                color: "#f3efe3"
                background: Item {}
                verticalAlignment: TextInput.AlignVCenter
                onTextChanged: root.api("/search?q=" + encodeURIComponent(text), function() {})
                Keys.onEscapePressed: { text = ""; root.searchOpen = false }
                Keys.onReturnPressed: root.searchOpen = false
                Keys.onEnterPressed: root.searchOpen = false
            }
            Text { visible: sf.text !== ""; anchors.right: parent.right; anchors.rightMargin: 20; anchors.verticalCenter: parent.verticalCenter; text: "✕"; color: "#a59f8f"; font.pixelSize: 16
                MouseArea { anchors.fill: parent; anchors.margins: -8; onClicked: sf.text = "" } }
        }
    }
    // Apertura: 1) el ayudante prepara Glass y el panel; 2) se muestra la ventana; 3) un fotograma después arranca la animación.
    function bmReveal() { if (!bmOpen || bmVis) return; bmVis = true; bmShowTimer.restart() }
    Timer { id: bmPanelTimer; interval: 800; onTriggered: root.bmReveal() }                 // respaldo si el ayudante no responde
    Timer { id: bmShowTimer; interval: 70; onTriggered: root.bmShow = root.bmOpen }
    Timer { id: bmHideTimer; interval: 360; onTriggered: { root.bmVis = false; if (!root.bmOpen) api("/menu/prep?open=0", function() {}) } }
    Window {
        id: bmDialog
        visible: root.bmVis
        color: "transparent"
        flags: Qt.FramelessWindowHint
        screen: deskWin.screen
        LayerShell.Window.scope: "estanteria-menu"
        LayerShell.Window.layer: LayerShell.Window.LayerOverlay
        LayerShell.Window.anchors: LayerShell.Window.AnchorTop | LayerShell.Window.AnchorBottom | LayerShell.Window.AnchorLeft | LayerShell.Window.AnchorRight
        LayerShell.Window.exclusionZone: -1
        LayerShell.Window.keyboardInteractivity: LayerShell.Window.KeyboardInteractivityExclusive
        property bool wasActive: false
        onActiveChanged: {
            if (active) wasActive = true
            else if (wasActive && root.bmOpen) { wasActive = false; root.bmClose() }
        }
        readonly property real u: root.bmU
        readonly property int sw: width > 0 ? width : (screen ? screen.width : 1920)
        readonly property int sh: height > 0 ? height : (screen ? screen.height : 1080)
        readonly property real pw: 56 * u
        readonly property real ph: 43 * u
        readonly property real px: (sw - pw) / 2
        readonly property real py: 0.53 * sh - ph / 2
        onVisibleChanged: { if (!visible) { root.bmOpen = false; wasActive = false } else bmBody.forceActiveFocus() }
        Item {
          anchors.fill: parent
          Item {
            id: bdRoot
            anchors.fill: parent
            opacity: root.bmShow ? 1 : 0
            Behavior on opacity { NumberAnimation { duration: 300; easing.type: Easing.InOutCubic } }
            // sin telón: detrás del panel se ve lo que haya en pantalla
            // sombra del panel
            RectangularGlow {
                x: (bdRoot.width - 56 * bmDialog.u) / 2; y: 0.53 * bdRoot.height - 21.5 * bmDialog.u + 2 * bmDialog.u
                width: 56 * bmDialog.u; height: 43 * bmDialog.u
                glowRadius: bmDialog.u * 3.5; spread: 0; color: "#99000000"; cornerRadius: 2 * bmDialog.u + glowRadius; cached: true
            }
            MouseArea { anchors.fill: parent; onClicked: root.bmClose() }
          }
          FocusScope {
            id: bmBody
            x: bmDialog.px; y: bmDialog.py
            readonly property real u: bmDialog.u
            width: bmDialog.pw
            height: bmDialog.ph
            focus: true
            Keys.onPressed: function(e) {
                var k = e.key, h = true
                if (k === Qt.Key_Escape) { if (root.bmMode === "power") root.pwBack(); else if (root.bmQuery !== "") { root.bmQuery = ""; root.bmUpdate() } else root.bmClose() }
                else if (k === Qt.Key_P && (e.modifiers & Qt.ControlModifier)) { root.bmMode = root.bmMode === "power" ? "apps" : "power"; root.pwConfirm = "" }
                else if (k === Qt.Key_Right) root.bmNav("r")
                else if (k === Qt.Key_Left) root.bmNav("l")
                else if (k === Qt.Key_Down) root.bmNav("d")
                else if (k === Qt.Key_Up) root.bmNav("u")
                else if (k === Qt.Key_Return || k === Qt.Key_Enter) root.bmEnter()
                else if (k === Qt.Key_Tab) { root.bmZone = root.bmZone === "q" ? "cats" : (root.bmZone === "cats" ? "grid" : "q") }
                else if (k === Qt.Key_Backtab) { root.bmZone = root.bmZone === "grid" ? "cats" : (root.bmZone === "cats" ? "q" : "grid") }
                else if (k === Qt.Key_F && (e.modifiers & Qt.ControlModifier)) { var al = root.bmAll(); if (al[root.bmIdx]) root.bmFav(al[root.bmIdx]) }
                else if (root.bmMode === "apps" && e.text.length > 0 && !(e.modifiers & Qt.ControlModifier) && !(e.modifiers & Qt.MetaModifier)) { root.bmZone = "q"; searchField.forceActiveFocus(); searchField.text += e.text }
                else h = false
                e.accepted = h
            }
            Connections { target: root; function onBmZoneChanged() { if (root.bmZone === "q") searchField.forceActiveFocus(); else bmBody.forceActiveFocus() } }
            Item {
                id: bmPanel
                anchors.fill: parent
                opacity: root.bmShow ? 1 : 0
                transformOrigin: Item.Center
                scale: root.bmShow ? 1 : 0.97
                y: root.bmShow ? 0 : bmBody.u * 1.2
                Behavior on opacity { NumberAnimation { duration: 300; easing.type: Easing.InOutCubic } }
                Behavior on scale { NumberAnimation { duration: 300; easing.type: Easing.InOutCubic } }
                Behavior on y { NumberAnimation { duration: 300; easing.type: Easing.InOutCubic } }
                MouseArea { anchors.fill: parent }

                // ================= CRISTAL (igual que el boceto): arte desenfocado + tinte + brillo + facetas =================
                Rectangle { id: glassMask; anchors.fill: parent; radius: bmBody.u * 2; visible: false }
                Item {
                    id: glassBody
                    anchors.fill: parent
                    layer.enabled: true
                    layer.effect: OpacityMask { maskSource: glassMask }
                    // sin imagen de fondo: solo oscurecido; el desenfoque lo pone Glass sobre lo que haya detrás
                    Rectangle { anchors.fill: parent; color: "#030a07"; opacity: 0.40 }
                    // tinte 30
                    LinearGradient {
                        anchors.fill: parent; start: Qt.point(0, 0); end: Qt.point(width, height)
                        gradient: Gradient {
                            GradientStop { position: 0.0; color: "#0ed2f5e8" }
                            GradientStop { position: 0.45; color: "#6b0e221a" }
                            GradientStop { position: 1.0; color: "#9406120d" }
                        }
                    }
                    Rectangle { anchors.fill: parent; radius: bmBody.u * 2; color: "transparent"; border.width: 1; border.color: "#14ffffff" }
                    Rectangle { x: bmBody.u * 2; width: parent.width - bmBody.u * 4; height: 1; color: "#38fff6c8" }      // brillo superior
                }
                Rectangle { anchors.fill: parent; radius: bmBody.u * 2; color: "transparent"; border.width: 1; border.color: "#33e6d9a0" }  // borde dorado 20

                Column {
                    anchors.fill: parent; spacing: 0
                    // ---- cabecera ----
                    Item {
                        width: parent.width; height: bmBody.u * 5.3
                        Row {
                            x: bmBody.u * 1.8; y: bmBody.u * 1.3; width: parent.width - bmBody.u * 3.6; spacing: bmBody.u * 1.2
                            Rectangle {
                                width: parent.width - bmBody.u * 4.2; height: bmBody.u * 3.0; radius: height / 2
                                color: "#73040c09"; border.width: 1; border.color: searchField.activeFocus || root.bmZone === "q" ? "#e6d9a0" : "#33e6d9a0"
                                Kirigami.Icon { x: bmBody.u * 1.2; anchors.verticalCenter: parent.verticalCenter; width: bmBody.u * 1.3; height: width; source: "search"; color: "#e6d9a0" }
                                QQC2.TextField {
                                    id: searchField
                                    x: bmBody.u * 3.1; width: parent.width - bmBody.u * 3.8; height: parent.height
                                    placeholderText: "Buscar aplicaciones…"; placeholderTextColor: "#73e9e6d6"
                                    font.pixelSize: bmBody.u * 1.2; font.family: "Noto Sans"; color: "#e9e6d6"
                                    background: Item {}
                                    verticalAlignment: TextInput.AlignVCenter
                                    text: root.bmQuery
                                    onTextChanged: if (text !== root.bmQuery) { root.bmQuery = text; root.bmIdx = 0; root.bmUpdate() }
                                    Connections { target: root; function onBmQueryChanged() { if (searchField.text !== root.bmQuery) searchField.text = root.bmQuery } }
                                    Keys.onPressed: function(e) {
                                        if (e.key === Qt.Key_Down || e.key === Qt.Key_Tab) { root.bmZone = "cats"; e.accepted = true }
                                        else if (e.key === Qt.Key_Return || e.key === Qt.Key_Enter) { root.bmEnter(); e.accepted = true }
                                        else if (e.key === Qt.Key_Escape) { if (text !== "") { text = ""; } else root.bmClose(); e.accepted = true }
                                    }
                                }
                            }
                            Rectangle {
                                width: bmBody.u * 3.0; height: width; radius: width / 2
                                color: root.bmMode === "power" ? "#33e6d9a0" : "transparent"; border.width: 1; border.color: "#59e6d9a0"
                                Kirigami.Icon { anchors.centerIn: parent; width: bmBody.u * 1.45; height: width; source: "system-shutdown-symbolic"; color: "#e6d9a0" }
                                MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: { root.bmMode = root.bmMode === "power" ? "apps" : "power"; root.pwConfirm = "" } }
                            }
                        }
                    }
                    // ---- categorías: PÍLDORAS en carrusel ----
                    // Empieza alineado a la izquierda; el seleccionado avanza hasta el centro; ahí el carrusel se desplaza manteniéndolo al medio;
                    // cuando ya no hay más a la derecha el carrusel se queda pegado al borde y el seleccionado sigue hasta el final.
                    Item {
                        id: catVp
                        visible: root.bmMode === "apps"
                        width: parent.width; height: root.bmMode === "apps" ? bmBody.u * 3.7 : 0; clip: true
                        readonly property real pad: bmBody.u * 1.8
                        readonly property real viewW: width - 2 * pad
                        property real scrollX: 0
                        function recalc() {
                            var it = catRep.itemAt(root.bmCats.indexOf(root.bmCat))
                            if (!it) return
                            var mx = Math.max(0, catRow.width - viewW)
                            scrollX = Math.max(0, Math.min(it.x + it.width / 2 - viewW / 2, mx))
                        }
                        Behavior on scrollX { NumberAnimation { duration: 300; easing.type: Easing.OutCubic } }
                        Connections { target: root; function onBmCatChanged() { catVp.recalc() } }
                        onViewWChanged: recalc()
                        Component.onCompleted: recalc()
                        Row {
                            id: catRow
                            x: catVp.pad - catVp.scrollX; y: 0; height: bmBody.u * 2.5; spacing: bmBody.u * 0.6
                            onWidthChanged: catVp.recalc()
                            Repeater {
                                id: catRep
                                model: root.bmCats
                                delegate: Rectangle {
                                    id: pill
                                    required property string modelData
                                    readonly property bool on: root.bmCat === modelData
                                    readonly property real cx: x + width / 2 - catVp.scrollX + catVp.pad       // posición en el visor
                                    readonly property real edge: bmBody.u * 5
                                    readonly property bool moreL: catVp.scrollX > 1
                                    readonly property bool moreR: catVp.scrollX < catRow.width - catVp.viewW - 1
                                    height: catRow.height; radius: height / 2; width: pt.implicitWidth + bmBody.u * 2.3
                                    // se desvanece solo en el borde que tiene más píldoras detrás
                                    opacity: Math.max(0.1, Math.min(moreL ? Math.min(1, (cx - catVp.pad * 0.3) / edge) : 1, moreR ? Math.min(1, (catVp.width - cx - catVp.pad * 0.3) / edge) : 1))
                                    color: on ? "#e6d9a0" : "#12e9e6d6"
                                    Behavior on color { ColorAnimation { duration: 180 } }
                                    border.width: root.bmZone === "cats" && on ? 2 : 0; border.color: "#ffffff"
                                    Text { id: pt; anchors.centerIn: parent; text: pill.modelData.toUpperCase()
                                        font.pixelSize: bmBody.u * 1.0; font.family: "Rajdhani"; font.weight: Font.DemiBold; font.letterSpacing: bmBody.u * 0.09
                                        color: pill.on ? "#14211a" : "#bfe9e6d6" }
                                    MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: { root.bmZone = "cats"; root.bmCat = pill.modelData; root.bmQuery = ""; root.bmIdx = 0; root.bmUpdate() } }
                                }
                            }
                        }
                        MouseArea { anchors.fill: parent; acceptedButtons: Qt.NoButton; onWheel: function(w) { root.bmZone = "cats"; root.bmCatStep((w.angleDelta.y > 0 || w.angleDelta.x > 0) ? -1 : 1) } }
                    }
                    // ---- mosaico (lista virtualizada: solo se crean las filas visibles) ----
                    Item {
                        id: area
                        width: parent.width; height: parent.height - bmBody.u * 5.3 - catVp.height - bmBody.u * 2.8
                        ListView {
                            id: gridList
                            visible: root.bmMode === "apps"
                            x: bmBody.u * 1.8; y: bmBody.u * 0.4; width: parent.width - bmBody.u * 3.6; height: parent.height - bmBody.u * 0.4
                            clip: true; model: root.bmRows; cacheBuffer: Math.max(0, height)
                            boundsBehavior: Flickable.StopAtBounds
                            reuseItems: true
                            readonly property real rowH: bmBody.u * (0.78 * 2 + 5.6 + 0.6 + 2.0)
                            readonly property real tileW: width / root.bmCols
                            NumberAnimation { id: scrollAnim; target: gridList; property: "contentY"; duration: 220; easing.type: Easing.OutCubic }
                            delegate: Item {
                                id: rowD
                                required property var modelData
                                required property int index
                                width: gridList.width
                                height: modelData.k === "row" ? gridList.rowH : (modelData.k === "label" ? bmBody.u * (modelData.first ? 3.0 : 3.6) : bmBody.u * 14)
                                Item { visible: rowD.modelData.k === "label"; anchors.fill: parent
                                    Text { id: lb; y: bmBody.u * (rowD.modelData.first ? 0.9 : 1.5); text: rowD.modelData.t || ""; color: "#e6d9a0"
                                        font.pixelSize: bmBody.u; font.family: "Rajdhani"; font.weight: Font.DemiBold; font.letterSpacing: bmBody.u * 0.22 }
                                    Rectangle { x: lb.implicitWidth + bmBody.u; y: lb.y + lb.implicitHeight / 2; width: parent.width - x; height: 1; color: "#38e6d9a0" } }
                                Row { visible: rowD.modelData.k === "row"; property int gbase: rowD.modelData.base || 0
                                    Repeater { model: rowD.modelData.k === "row" ? rowD.modelData.items : []; delegate: tileComp } }
                                Text { visible: rowD.modelData.k === "empty"; anchors.centerIn: parent; text: "Sin resultados para «" + root.bmQuery + "»"; color: "#99e9e6d6"; font.pixelSize: bmBody.u * 1.4; font.family: "Noto Sans" }
                            }
                            // mantiene visible la selección con desplazamiento suave
                            Connections { target: root; function onBmIdxChanged() { gridList.follow() } }
                            function follow() {
                                var idx = root.bmIdx, ri = -1
                                for (var r = 0; r < root.bmRows.length; r++) { var q = root.bmRows[r]; if (q.k === "row" && idx >= q.base && idx < q.base + q.items.length) { ri = r; break } }
                                if (ri < 0) return
                                var y = 0, u = bmBody.u
                                for (var k = 0; k < ri; k++) { var m = root.bmRows[k]; y += m.k === "row" ? rowH : (m.k === "label" ? u * (m.first ? 3.0 : 3.6) : u * 14) }
                                var target = contentY
                                if (ri > 0 && root.bmRows[ri - 1].k === "label") y -= u * (root.bmRows[ri - 1].first ? 3.0 : 3.6)    // que se vea también su etiqueta
                                if (y < contentY) target = Math.max(0, y)
                                else if (y + rowH > contentY + height) target = y + rowH - height + u * 0.4
                                if (target !== contentY) { scrollAnim.stop(); scrollAnim.to = target; scrollAnim.start() }
                            }
                        }
                        Item {
                            id: pwView
                            visible: root.bmMode === "power"
                            anchors.fill: parent
                            opacity: visible ? 1 : 0
                            Behavior on opacity { NumberAnimation { duration: 200 } }
                            Column {
                                anchors.centerIn: parent; spacing: bmBody.u * 1.8
                                Text {
                                    anchors.horizontalCenter: parent.horizontalCenter
                                    text: root.pwConfirm === "" ? "Energía y sesión" : root.pwQuestion()
                                    color: "#ffffff"; font.pixelSize: bmBody.u * 2.2; font.family: "Noto Sans"; font.weight: Font.Light
                                }
                                Row {
                                    visible: root.pwConfirm === ""
                                    anchors.horizontalCenter: parent.horizontalCenter; spacing: bmBody.u * 0.6
                                    Repeater {
                                        model: root.pwItems
                                        delegate: Item {
                                            id: pwi
                                            required property var modelData
                                            required property int index
                                            readonly property bool sel: root.pwIdx === index
                                            width: bmBody.u * 8.4; height: bmBody.u * 9.2
                                            scale: sel ? 1.06 : 1
                                            Behavior on scale { NumberAnimation { duration: 140; easing.type: Easing.OutCubic } }
                                            Rectangle { anchors.fill: parent; radius: bmBody.u * 1.4; color: pwi.sel ? "#33e6d9a0" : (pm.containsMouse ? "#1affffff" : "transparent"); border.width: pwi.sel ? 2 : 0; border.color: "#e6d9a0" }
                                            Kirigami.Icon { source: pwi.modelData.icon; width: bmBody.u * 4; height: width; anchors.horizontalCenter: parent.horizontalCenter; y: bmBody.u * 1.4 }
                                            Text { y: bmBody.u * 6.6; width: parent.width; horizontalAlignment: Text.AlignHCenter; text: pwi.modelData.t; color: "#e9e6d6"; font.pixelSize: bmBody.u * 1.1; font.family: "Noto Sans" }
                                            MouseArea { id: pm; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: { root.pwIdx = pwi.index; root.pwActivate() } }
                                        }
                                    }
                                }
                                Row {
                                    visible: root.pwConfirm !== ""
                                    anchors.horizontalCenter: parent.horizontalCenter; spacing: bmBody.u * 1.4
                                    Repeater {
                                        model: ["Cancelar", "Confirmar"]
                                        delegate: Rectangle {
                                            id: cb
                                            required property string modelData
                                            required property int index
                                            readonly property bool sel: root.pwCI === index
                                            width: bmBody.u * 12; height: bmBody.u * 3.8; radius: height / 2
                                            color: sel ? (index === 1 ? "#e6c25a4a" : "#e6e6d9a0") : "#1fffffff"
                                            border.width: sel ? 2 : 0; border.color: "#e6d9a0"
                                            Text { anchors.centerIn: parent; text: cb.modelData; color: cb.sel && index === 0 ? "#14211a" : "#f3efe3"; font.pixelSize: bmBody.u * 1.3; font.family: "Noto Sans"; font.weight: Font.DemiBold }
                                            MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: { root.pwCI = cb.index; root.pwActivate() } }
                                        }
                                    }
                                }
                                Text {
                                    anchors.horizontalCenter: parent.horizontalCenter
                                    text: root.pwConfirm === "" ? "← →  elegir · A / Intro  aceptar · B / Esc  volver" : "← →  elegir · A / Intro  aceptar · B / Esc  cancelar"
                                    color: "#99e9e6d6"; font.pixelSize: bmBody.u * 0.95; font.family: "Noto Sans"
                                }
                            }
                        }
                    }
                    // ---- pie ----
                    Item {
                        width: parent.width; height: bmBody.u * 2.8
                        Text { visible: root.bmMode === "apps"; x: bmBody.u * 1.8; anchors.verticalCenter: parent.verticalCenter
                            text: root.bmTop.length + root.bmList.length + " apps"; color: "#8ce9e6d6"; font.pixelSize: bmBody.u * 0.95; font.family: "Noto Sans" }
                        PadGuide {
                            visible: root.bmMode === "apps" && root.padConnected
                            anchors.right: parent.right; anchors.rightMargin: bmBody.u * 1.8; anchors.verticalCenter: parent.verticalCenter
                            width: bmBody.u * 40
                            padName: root.padName
                            iconSize: bmBody.u * 1.5; fontPx: bmBody.u * 0.85; spacing: bmBody.u * 0.8
                            textColor: "#b3e9e6d6"; fontFamily: "Noto Sans"
                            hints: [{ k: "A", t: "Abrir" }, { k: "B", t: "Cerrar" }, { k: "X", t: "Favorito" }, { k: "Y", t: "Buscar" }, { k: "LB+RB", t: "Categoría" }, { k: "SELECT", t: "Energía" }]
                        }
                        Text { visible: root.bmMode === "apps" && !root.padConnected; anchors.right: parent.right; anchors.rightMargin: bmBody.u * 1.8; anchors.verticalCenter: parent.verticalCenter
                            text: "Intro abre · Ctrl+F favorito · Tab cambia de zona · Esc cierra"; color: "#8ce9e6d6"; font.pixelSize: bmBody.u * 0.95; font.family: "Noto Sans" }
                    }
                }
            }
        }
        }
    }
    Component {
        id: tileComp
        Item {
            id: tile
            required property var modelData
            required property int index
            readonly property real u: root.bmU
            readonly property int gi: (parent && parent.gbase !== undefined ? parent.gbase : 0) + index
            readonly property bool sel: root.bmZone === "grid" && root.bmIdx === gi
            readonly property real isz: u * 5.6                       // "Tamaño" de icono = 56
            readonly property color col: root.bmColor(modelData.name)
            width: gridList.tileW; height: gridList.rowH
            // selección / hover
            Rectangle { anchors.fill: parent; anchors.margins: u * 0.25; radius: u * 1.3
                color: tile.sel ? "#29e6d9a0" : (tm.containsMouse ? "#17e9e6d6" : "transparent"); border.width: tile.sel ? 1 : 0; border.color: "#8ce6d9a0" }
            Item {
                id: icBox
                width: tile.isz; height: tile.isz; x: (parent.width - width) / 2; y: u * 0.78
                scale: tm.containsMouse || tile.sel ? 1.06 : 1
                Behavior on scale { NumberAnimation { duration: 140; easing.type: Easing.OutCubic } }
                // icono del prototipo: círculo (redondeo 50 %) con la identidad de color de cada app y su icono real encima
                Rectangle {
                    anchors.fill: parent; radius: width * 0.24
                    gradient: Gradient {
                        GradientStop { position: 0.0; color: Qt.rgba(tile.col.r, tile.col.g, tile.col.b, 0.50) }
                        GradientStop { position: 1.0; color: Qt.rgba(tile.col.r * 0.4, tile.col.g * 0.4, tile.col.b * 0.4, 0.62) }
                    }
                    border.width: 1; border.color: "#4dffffff"
                    // brillo de cristal en la mitad superior
                    Rectangle { x: 1; y: 1; width: parent.width - 2; height: parent.height * 0.48; radius: parent.radius - 1
                        gradient: Gradient { GradientStop { position: 0; color: "#38ffffff" } GradientStop { position: 1; color: "#00ffffff" } } }
                }
                Text { anchors.centerIn: parent; visible: !realIcon.valid; text: root.bmInitials(tile.modelData.name); color: "#ffffff"
                    font.pixelSize: tile.isz * 0.4; font.family: "Rajdhani"; font.weight: Font.Bold }
                Kirigami.Icon { id: realIcon; anchors.centerIn: parent; width: parent.width * 0.66; height: width; source: tile.modelData.icon; visible: valid }
            }
            Text { y: icBox.y + icBox.height + u * 0.6; width: parent.width - u * 0.6; x: u * 0.3; horizontalAlignment: Text.AlignHCenter; elide: Text.ElideRight
                text: tile.modelData.name; color: "#e9e6d6"; font.pixelSize: u * 1.1; font.family: "Noto Sans"; font.weight: Font.Medium }
            Text { visible: tile.modelData.fav || tm.containsMouse; anchors.right: parent.right; anchors.top: parent.top; anchors.margins: u * 0.5
                text: "★"; font.pixelSize: u * 1.2; color: tile.modelData.fav ? "#e6d9a0" : "#a6e9e6d6" }
            MouseArea { id: tm; anchors.fill: parent; z: 1; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; acceptedButtons: Qt.LeftButton
                onClicked: { root.api("/log?m=" + encodeURIComponent("menu: clic en " + tile.modelData.name), function() {}); root.bmLaunch(tile.modelData) } }
            MouseArea { z: 2; width: u * 2.6; height: u * 2.6; anchors.right: parent.right; anchors.top: parent.top; cursorShape: Qt.PointingHandCursor
                onClicked: { root.api("/log?m=" + encodeURIComponent("menu: favorito " + tile.modelData.name), function() {}); root.bmFav(tile.modelData) } }
        }
    }
    compactRepresentation: Item {
        id: mini
        Rectangle { anchors.fill: parent; radius: width / 2; color: "#33000000"; border.width: 1; border.color: "#66ffffff" }
        Kirigami.Icon { anchors.centerIn: parent; width: Math.min(parent.width, parent.height) * 0.6; height: width; source: "applications-games" }
        MouseArea { anchors.fill: parent; onClicked: root.shown = !root.shown }
        Component.onCompleted: { if (Window.window && Window.window.screen) deskWin.screen = Window.window.screen }
    }
    fullRepresentation: Item {
        implicitWidth: 1280
        implicitHeight: 720
        Loader { anchors.fill: parent; sourceComponent: shelfComp }
    }
    Plasmoid.onActivated: root.shown = !root.shown

    Component {
        id: shelfComp
    Item {
        id: full
        implicitWidth: 1280
        implicitHeight: 720
        focus: true
        clip: true
        readonly property real s: width / 1920
        readonly property real ch: height / s
        property bool winActive: Window.active
        onWinActiveChanged: root.hasFocus = winActive

        Keys.onPressed: function(e) {
            var k = e.key, h = true
            if (root.gameRunning) { if (k === Qt.Key_Escape) root.ignoredRun = root.runningId; e.accepted = true; return }
            if (root.artOpen) {
                if (k === Qt.Key_Up) root.artKey("u"); else if (k === Qt.Key_Down) root.artKey("d")
                else if (k === Qt.Key_Left) root.artKey("l"); else if (k === Qt.Key_Right) root.artKey("r")
                else if (k === Qt.Key_Return || k === Qt.Key_Enter) root.artKey("A")
                else if (k === Qt.Key_Tab) root.artTab(1); else if (k === Qt.Key_Backtab) root.artTab(-1)
                else if (k === Qt.Key_PageUp) root.artGame(-1); else if (k === Qt.Key_PageDown) root.artGame(1)
                else if (k === Qt.Key_Escape) root.artOpen = false
                e.accepted = true; return
            }
            if (root.ctxOpen) {
                if (k === Qt.Key_Up) root.ctxKey("u"); else if (k === Qt.Key_Down) root.ctxKey("d")
                else if (k === Qt.Key_Return || k === Qt.Key_Enter) root.ctxKey("A")
                else root.ctxOpen = false
                e.accepted = true; return
            }
            if (k === Qt.Key_Menu) { root.ctxShow(-1, -1); e.accepted = true; return }
            if (k === Qt.Key_F5) { root.refreshLibrary(); e.accepted = true; return }
            if (k === Qt.Key_Right) root.nav("r")
            else if (k === Qt.Key_Left) root.nav("l")
            else if (k === Qt.Key_Up) root.nav("u")
            else if (k === Qt.Key_Down) root.nav("d")
            else if (k === Qt.Key_Return || k === Qt.Key_Enter) root.enter()
            else if (k === Qt.Key_Escape) { if (root.gq !== "" || root.gsOpen) root.gsClose(true); else root.back() }
            else if (k === Qt.Key_Slash || (k === Qt.Key_F && (e.modifiers & Qt.ControlModifier))) root.gsToggle()
            else if (k === Qt.Key_F) root.toggleFav()
            else if (k === Qt.Key_H) root.toggleHide()
            else if (k === Qt.Key_Tab) root.cyc((e.modifiers & Qt.ControlModifier) ? -1 : 1)
            else if (k === Qt.Key_Backtab) root.cyc(-1)
            else if (k === Qt.Key_F10) root.shown = false
            else if (k === Qt.Key_PageUp) root.cycPort(-1)
            else if (k === Qt.Key_PageDown) root.cycPort(1)
            else if (k === Qt.Key_Space) { if (root.mus) root.mus.playPause() }
            else h = false
            e.accepted = h
        }
        MouseArea { anchors.fill: parent; z: -10; acceptedButtons: Qt.LeftButton | Qt.RightButton
            onPressed: function(m) { full.forceActiveFocus(); if (m.button === Qt.RightButton) { var pt = mapToItem(canvas, m.x, m.y); root.ctxShow(pt.x, pt.y) } m.accepted = false } }

        Rectangle { anchors.fill: parent; color: "#0b0d0c" }

        Item {
            id: canvas
            width: 1920
            height: full.ch
            scale: full.s
            transformOrigin: Item.TopLeft
            clip: true

            readonly property color acc: root.curGame ? root.curGame.acc : "#e6d9a0"
            readonly property string gfont: root.curGame ? root.curGame.font : "Marcellus SC"
            readonly property string hud: "Rajdhani"
            readonly property string body: "Hanken Grotesk"
            readonly property color ink: "#f3efe3"
            readonly property color ink2: "#d6d0bf"
            readonly property color ink3: "#a59f8f"

            // ---------------------------------------------------------- fondos (uno por juego, fundido)
            Repeater {
                model: root.games
                delegate: Item {
                    id: wp
                    required property var modelData
                    required property int index
                    anchors.fill: parent
                    readonly property bool isCur: root.curGame && root.curGame.id === modelData.id
                    property bool wasCur: false
                    onIsCurChanged: if (isCur) wasCur = true
                    opacity: isCur ? 1 : 0
                    visible: opacity > 0.01
                    Behavior on opacity { NumberAnimation { duration: 900; easing.type: Easing.InOutQuad } }
                    // solo se materializa el fondo del juego actual (y el que se está fundiendo): con cientos de juegos cada fondo
                    // eager costaba ~8 MB (escena + imagen + desenfoque + filtros)
                    Loader {
                        anchors.fill: parent
                        active: wp.isCur || wp.opacity > 0.01
                        sourceComponent: Component {
                            Item {
                                anchors.fill: parent
                    Scene { anchors.fill: parent; pal: wp.modelData.pal; visible: img.status !== Image.Ready }
                    // la imagen ocupa TODA la altura de la pantalla; si es más ancha que ella, se desplaza de ida y vuelta (60 s por trayecto)
                    Image {
                        id: img
                        readonly property real asp: implicitHeight > 0 ? implicitWidth / implicitHeight : 16 / 9
                        width: Math.max(wp.width, wp.height * asp); height: width / asp
                        source: (wp.isCur || wp.opacity > 0.01) ? wp.modelData.fondo : ""
                        fillMode: Image.Stretch
                        asynchronous: true
                        sourceSize.height: 1080
                        visible: false
                    }
                    FastBlur {
                        id: blurred
                        width: img.width; height: img.height
                        source: img
                        radius: root.blurPx
                        visible: false
                    }
                    Item {
                        id: pan
                        width: img.width; height: img.height
                        y: -(height - wp.height) / 2
                        readonly property real excess: Math.max(0, width - wp.width)
                        property real off: 0
                        x: -off
                        SequentialAnimation on off {
                            id: panAnim
                            running: wp.isCur && Plasmoid.configuration.pan && pan.excess > 1
                            paused: !root.panOn
                            loops: Animation.Infinite
                            NumberAnimation { to: pan.excess; duration: 60000; easing.type: Easing.InOutSine }
                            NumberAnimation { to: 0; duration: 60000; easing.type: Easing.InOutSine }
                        }
                        HueSaturation {
                            anchors.fill: parent
                            source: root.blurPx > 0 ? blurred : img
                            saturation: -0.30 * Math.min(1, root.film * 2)
                            lightness: -0.04 * Math.min(1, root.film * 2)
                            visible: img.status === Image.Ready
                        }
                    }
                            }
                        }
                    }
                }
            }
            // cristal esmerilado: velo claro + brillos diagonales casi imperceptibles que se desplazan
            Rectangle { anchors.fill: parent; color: "#1affffff"; opacity: root.blurPx > 0 ? 0.55 : 0 }
            // legibilidad: oscurece la izquierda y la zona de la estantería
            // película: velo del color del juego que apaga el fondo
            Rectangle {
                anchors.fill: parent
                color: root.curGame && root.curGame.pal.length > 0 ? root.curGame.pal[0] : "#000000"
                opacity: root.film
                Behavior on color { ColorAnimation { duration: 900 } }
            }
            Rectangle { anchors.fill: parent; color: "#000000"; opacity: 0.18 + root.film * 0.28 }
            Rectangle {
                anchors.left: parent.left; anchors.top: parent.top; anchors.bottom: parent.bottom
                width: 1500
                gradient: Gradient {
                    orientation: Gradient.Horizontal
                    GradientStop { position: 0.0; color: "#a6000000" }
                    GradientStop { position: 1.0; color: "#00000000" }
                }
            }
            Rectangle {
                anchors.left: parent.left; anchors.right: parent.right; anchors.bottom: parent.bottom
                height: 560
                gradient: Gradient {
                    GradientStop { position: 0.0; color: "#00000000" }
                    GradientStop { position: 1.0; color: "#b3000000" }
                }
            }

            // ---------------------------------------------------------- ondas
            Waves {
                anchors.left: parent.left; anchors.bottom: parent.bottom
                active: root.hasMusic || root.soundOn
                playing: root.musicPlaying || root.soundOn
                real: root.levelsReal
                levels: root.levels
                bands: root.bands
                color: canvas.acc
                visibleOnScreen: !root.covered && !root.bmOpen && !root.busy
            }

            // ---------------------------------------------------------- filtro por consola / catálogo
            Row {
                x: 84; y: 54; spacing: 10
                Repeater {
                    model: root.chipKeys
                    delegate: Rectangle {
                        id: chipBtn
                        required property int index
                        readonly property bool padFocus: root.fz === "head" && root.fi === index
                        opacity: root.gsOpen ? 0 : 1
                        enabled: !root.gsOpen
                        Behavior on opacity { NumberAnimation { duration: 180 } }
                        required property string modelData
                        readonly property bool on: root.plat === modelData
                        readonly property var pd: root.platOf(modelData)
                        height: 34; radius: 17
                        width: chipRow.implicitWidth + 28
                        color: on ? "#ebffffff" : "#59000000"
                        border.width: on ? 0 : 1
                        border.color: "#47f3efe3"
                        Row {
                            id: chipRow
                            anchors.centerIn: parent
                            spacing: 7
                            PlatIcon {
                                visible: chipBtn.modelData !== "all" && chipBtn.modelData !== "fav" && chipBtn.modelData !== "hidden"
                                key: chipBtn.modelData; size: 18
                                color: chipBtn.on ? "#10150f" : chipBtn.pd.col
                                anchors.verticalCenter: parent.verticalCenter
                            }
                            Text {
                                text: chipBtn.modelData === "all" ? "Todos" : chipBtn.pd.cor
                                font.family: canvas.hud; font.pixelSize: 17; font.weight: Font.DemiBold; font.letterSpacing: 1
                                color: chipBtn.on ? "#10150f" : (chipBtn.modelData === "all" ? canvas.ink : chipBtn.pd.col)
                                anchors.verticalCenter: parent.verticalCenter
                            }
                        }
                        Rectangle { visible: chipBtn.padFocus; anchors.fill: parent; anchors.margins: -4; radius: height / 2; color: "transparent"; border.width: 3; border.color: canvas.acc }
                        MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: root.setPlat(chipBtn.modelData) }
                    }
                }
                // buscar juego (integrado en el launcher)
                Rectangle {
                    id: gsBtn
                    width: 34; height: 34; radius: 17
                    color: (root.gsOpen || root.gq !== "") ? "#ebffffff" : (gsHover.containsMouse ? "#33ffffff" : "#59000000")
                    border.width: (root.gsOpen || root.gq !== "") ? 0 : 1; border.color: "#47f3efe3"
                    Behavior on color { ColorAnimation { duration: 180 } }
                    Kirigami.Icon { anchors.centerIn: parent; width: 18; height: 18; source: "search"; color: (root.gsOpen || root.gq !== "") ? "#10150f" : "#f3efe3" }
                    Rectangle { visible: root.fz === "head" && root.fi === root.chipKeys.length; anchors.fill: parent; anchors.margins: -4; radius: height / 2; color: "transparent"; border.width: 3; border.color: canvas.acc }
                    MouseArea { id: gsHover; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: root.gsToggle() }
                }
                // energía y sesión
                Rectangle {
                    width: 34; height: 34; radius: 17
                    color: pwHover.containsMouse ? "#33ffffff" : "#59000000"
                    border.width: 1; border.color: "#47f3efe3"
                    Behavior on color { ColorAnimation { duration: 180 } }
                    Kirigami.Icon { anchors.centerIn: parent; width: 18; height: 18; source: "system-shutdown-symbolic"; color: "#f3efe3" }
                    Rectangle { visible: root.fz === "head" && root.fi === root.chipKeys.length + 1; anchors.fill: parent; anchors.margins: -4; radius: height / 2; color: "transparent"; border.width: 3; border.color: canvas.acc }
                    MouseArea { id: pwHover; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: root.bmOpenMenu("power") }
                }
                // actualizar biblioteca: vuelve a detectar los juegos instalados (Steam, Hydra, GeForce NOW)
                Rectangle {
                    width: 34; height: 34; radius: 17
                    color: root.refreshing ? "#ebffffff" : (rfHover.containsMouse ? "#33ffffff" : "#59000000")
                    border.width: root.refreshing ? 0 : 1; border.color: "#47f3efe3"
                    Behavior on color { ColorAnimation { duration: 180 } }
                    Kirigami.Icon { id: rfIcon; anchors.centerIn: parent; width: 18; height: 18; source: "view-refresh"; isMask: true; color: root.refreshing ? "#10150f" : "#f3efe3"
                        RotationAnimator on rotation { running: root.refreshing; from: 0; to: 360; duration: 900; loops: Animation.Infinite }
                        onVisibleChanged: if (!root.refreshing) rotation = 0 }
                    Rectangle { visible: root.fz === "head" && root.fi === root.chipKeys.length + 2; anchors.fill: parent; anchors.margins: -4; radius: height / 2; color: "transparent"; border.width: 3; border.color: canvas.acc }
                    MouseArea { id: rfHover; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: root.refreshLibrary() }
                }
                // salida de audio: solo se muestra en modo mando
                Rectangle {
                    id: audBtn
                    visible: root.padConnected
                    width: 34; height: 34; radius: 17
                    color: root.audOpen ? "#ebffffff" : (audHover.containsMouse ? "#33ffffff" : "#59000000")
                    border.width: root.audOpen ? 0 : 1; border.color: "#47f3efe3"
                    Behavior on color { ColorAnimation { duration: 180 } }
                    Kirigami.Icon { anchors.centerIn: parent; width: 18; height: 18; source: "audio-speakers-symbolic"; color: root.audOpen ? "#10150f" : "#f3efe3" }
                    Rectangle { visible: root.fz === "head" && root.fi === root.chipKeys.length + 3; anchors.fill: parent; anchors.margins: -4; radius: height / 2; color: "transparent"; border.width: 3; border.color: canvas.acc }
                    MouseArea { id: audHover; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: root.audShow() }
                }
            }

            // campo de búsqueda de juegos (sustituye a las consolas mientras se busca)
            Rectangle {
                id: gsBox
                    x: 84; y: 54; z: 3
                    visible: opacity > 0.01; opacity: root.gsOpen ? 1 : 0
                    width: gsBtn.x - 10; height: 34; radius: 17; clip: true
                    Behavior on opacity { NumberAnimation { duration: 180 } }
                    color: "#99000000"; border.width: 1; border.color: root.gsOpen ? "#e6d9a0" : "#47f3efe3"
                    Timer { id: gsFocus; interval: 90; onTriggered: { if (!root.gsPad) gsField.forceActiveFocus() } }
                    Connections { target: root; function onGqChanged() { if (gsField.text !== root.gq) gsField.text = root.gq } }
                    Connections { target: root
                        function onGsOpenChanged() { if (root.gsOpen) { gsField.text = root.gq; gsFocus.restart() } else gsField.text = "" } }
                    QQC2.TextField {
                        id: gsField
                        x: 16; width: parent.width - 150; height: parent.height
                        placeholderText: "Buscar juego…"; placeholderTextColor: "#80f3efe3"
                        font.pixelSize: 17; font.family: "Rajdhani"; font.weight: Font.DemiBold; color: "#f3efe3"
                        background: Item {}
                        verticalAlignment: TextInput.AlignVCenter
                        onTextChanged: if (root.gsOpen && text !== root.gq) root.gsApply(text)
                        onActiveFocusChanged: if (!activeFocus && root.gsOpen && !root.gsPad) root.gsClose(false)
                        Keys.onEscapePressed: root.gsClose(true)
                        Keys.onReturnPressed: { full.forceActiveFocus() }
                        Keys.onEnterPressed: { full.forceActiveFocus() }
                        Keys.onDownPressed: { full.forceActiveFocus() }
                        Keys.onLeftPressed: function(e) { if (cursorPosition === 0) { full.forceActiveFocus(); root.sel(root.cur - 1) } else e.accepted = false }
                        Keys.onRightPressed: function(e) { if (cursorPosition === length) { full.forceActiveFocus(); root.sel(root.cur + 1) } else e.accepted = false }
                    }
                    Text { anchors.right: parent.right; anchors.rightMargin: 44; anchors.verticalCenter: parent.verticalCenter
                        text: root.gq !== "" ? root.view.length + (root.view.length === 1 ? " juego" : " juegos") : ""
                        color: "#c9f3efe3"; font.family: canvas.hud; font.pixelSize: 14; font.letterSpacing: 0.6 }
                    Text { visible: root.gq !== ""; anchors.right: parent.right; anchors.rightMargin: 14; anchors.verticalCenter: parent.verticalCenter; text: "✕"; color: "#f3efe3"; font.pixelSize: 16
                        MouseArea { anchors.fill: parent; anchors.margins: -10; cursorShape: Qt.PointingHandCursor; onPressed: root.gsClose(true) } }
                }
                // botón «borrar filtro» visible cuando hay un filtro activo y el campo está oculto
                Rectangle {
                    visible: root.gq !== "" && !root.gsOpen
                    x: 84 + gsBtn.x + 88; y: 54; width: 34; height: 34; radius: 17; z: 3
                    color: clrM.containsMouse ? "#40ffffff" : "#59000000"; border.width: 1; border.color: "#80e6d9a0"
                    Text { anchors.centerIn: parent; text: "✕"; color: "#f3efe3"; font.pixelSize: 16 }
                    MouseArea { id: clrM; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: root.gsClose(true) }
                }

            // estantería deshabilitada mientras el juego está abierto (se reactiva sola al cerrarlo)
            Item {
                anchors.fill: parent; z: 40
                visible: opacity > 0.01; opacity: root.gameRunning ? 1 : 0
                Behavior on opacity { NumberAnimation { duration: 400 } }
                Rectangle { anchors.fill: parent; color: "#fa050806" }
                MouseArea { anchors.fill: parent; acceptedButtons: Qt.AllButtons; hoverEnabled: true }
                Column {
                    anchors.centerIn: parent; spacing: 14
                    Text { anchors.horizontalCenter: parent.horizontalCenter; text: "EN EJECUCIÓN"; color: canvas.acc; font.family: canvas.hud; font.pixelSize: 20; font.letterSpacing: 6; font.weight: Font.DemiBold }
                    Image {
                        id: runLogo
                        anchors.horizontalCenter: parent.horizontalCenter
                        visible: status === Image.Ready
                        source: root.runningLogo
                        width: 900; height: 260; fillMode: Image.PreserveAspectFit
                        asynchronous: true; smooth: true; mipmap: true; sourceSize.height: 520
                    }
                    Text { visible: runLogo.status !== Image.Ready; anchors.horizontalCenter: parent.horizontalCenter; text: root.runningName; color: canvas.ink; font.family: canvas.hud; font.pixelSize: 64; font.weight: Font.DemiBold
                        width: Math.min(implicitWidth, 1500); elide: Text.ElideRight; horizontalAlignment: Text.AlignHCenter }
                    Text { anchors.horizontalCenter: parent.horizontalCenter; text: "La estantería se reactiva sola cuando cierres el juego"; color: canvas.ink2; font.family: canvas.body; font.pixelSize: 22 }
                    Text { anchors.horizontalCenter: parent.horizontalCenter; text: "Big Menú: botón Start del mando o tecla Windows"; color: canvas.ink3; font.family: canvas.body; font.pixelSize: 18 }
                    Item { width: 1; height: 18 }
                    Text { anchors.horizontalCenter: parent.horizontalCenter; text: "El juego ya no está abierto · reactivar ahora (Esc)"; color: fgM.containsMouse ? canvas.acc : canvas.ink3
                        font.family: canvas.body; font.pixelSize: 15; font.underline: true
                        MouseArea { id: fgM; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: root.ignoredRun = root.runningId } }
                }
            }

            // salida de audio (modo mando): lista de dispositivos, A elige, B cierra
            Item {
                anchors.fill: parent; z: 31
                visible: opacity > 0.01; opacity: root.audOpen ? 1 : 0
                Behavior on opacity { NumberAnimation { duration: 140 } }
                MouseArea { anchors.fill: parent; acceptedButtons: Qt.AllButtons; onClicked: root.audOpen = false }
                Rectangle {
                    x: Math.min(1920 - width - 20, 84 + audBtn.x + audBtn.width + 10 - width / 2 + 40); y: 100
                    width: 520; height: root.audItems.length * 54 + 70; radius: 20
                    color: "#ff0d1510"; border.width: 1; border.color: "#73e6d9a0"
                    scale: root.audOpen ? 1 : 0.94; transformOrigin: Item.TopRight
                    Behavior on scale { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }
                    MouseArea { anchors.fill: parent; acceptedButtons: Qt.AllButtons }
                    Text { x: 24; y: 16; text: "SALIDA DE AUDIO"; color: canvas.acc; font.family: canvas.hud; font.pixelSize: 15; font.letterSpacing: 3; font.weight: Font.DemiBold }
                    Column {
                        x: 12; y: 50; width: parent.width - 24
                        Repeater {
                            model: root.audItems
                            delegate: Rectangle {
                                id: ait
                                required property var modelData
                                required property int index
                                readonly property bool foc: root.audIdx === index
                                width: parent.width; height: 54; radius: 14
                                color: foc ? canvas.acc : (am.containsMouse ? "#1fffffff" : "transparent")
                                Kirigami.Icon { x: 16; anchors.verticalCenter: parent.verticalCenter; width: 24; height: 24; isMask: true
                                    source: ait.modelData.kind === "hdmi" ? "video-display-symbolic" : (ait.modelData.kind === "usb" ? "audio-headphones-symbolic" : (ait.modelData.kind === "bt" ? "bluetooth-symbolic" : "audio-speakers-symbolic"))
                                    color: ait.foc ? "#10150f" : "#f3efe3" }
                                Text { x: 58; width: parent.width - 120; elide: Text.ElideRight; anchors.verticalCenter: parent.verticalCenter; text: ait.modelData.label
                                    color: ait.foc ? "#10150f" : "#f3efe3"; font.family: canvas.body; font.pixelSize: 19; font.weight: Font.Medium }
                                Text { visible: ait.modelData.current; anchors.right: parent.right; anchors.rightMargin: 18; anchors.verticalCenter: parent.verticalCenter; text: "✓ ACTIVO"
                                    color: ait.foc ? "#10150f" : canvas.acc; font.family: canvas.hud; font.pixelSize: 14; font.letterSpacing: 1.6; font.weight: Font.DemiBold }
                                MouseArea { id: am; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                                    onEntered: root.audIdx = ait.index; onClicked: root.audActivate(ait.index) }
                            }
                        }
                    }
                }
            }

            // selector manual de arte (SteamGridDB): pestañas Portada/Fondo/Logo, cuadrícula de miniaturas
            Item {
                id: artWin
                anchors.fill: parent; z: 32
                visible: opacity > 0.01; opacity: root.artOpen ? 1 : 0
                Behavior on opacity { NumberAnimation { duration: 160 } }
                Rectangle { anchors.fill: parent; color: "#eb050806" }
                MouseArea { anchors.fill: parent; acceptedButtons: Qt.AllButtons; onClicked: root.artOpen = false }
                Rectangle {
                    x: 240; y: 110; width: 1440; height: 860; radius: 26
                    color: "#ff0d1510"; border.width: 1; border.color: "#73e6d9a0"
                    scale: root.artOpen ? 1 : 0.96; transformOrigin: Item.Center
                    Behavior on scale { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }
                    MouseArea { anchors.fill: parent; acceptedButtons: Qt.AllButtons }
                    Text { x: 36; y: 26; text: "ELEGIR ARTE · " + root.artGName.toUpperCase(); color: canvas.acc; font.family: canvas.hud; font.pixelSize: 20; font.letterSpacing: 3; font.weight: Font.DemiBold }
                    Row {
                        x: 36; y: 70; spacing: 12
                        PadGuide { visible: root.padConnected; anchors.verticalCenter: undefined; height: 42; padName: root.padName; iconSize: 38; hints: [{ k: "LB", t: "" }] }
                        Repeater {
                            model: root.artKinds
                            delegate: Rectangle {
                                required property string modelData
                                readonly property bool on: root.artKind === modelData
                                height: 42; width: tl.implicitWidth + 40; radius: 21
                                color: on ? canvas.acc : (tm.containsMouse ? "#26ffffff" : "#14ffffff")
                                Text { id: tl; anchors.centerIn: parent; text: parent.modelData === "portada" ? "Portada" : (parent.modelData === "fondo" ? "Fondo" : "Logo")
                                    color: parent.on ? "#10150f" : "#f3efe3"; font.family: canvas.body; font.pixelSize: 19; font.weight: Font.DemiBold }
                                MouseArea { id: tm; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                                    onClicked: { root.artKind = parent.modelData; root.artItems = []; root.artIdx = 0; root.artLoad(0) } }
                            }
                        }
                        PadGuide { visible: root.padConnected; height: 42; padName: root.padName; iconSize: 38; hints: [{ k: "RB", t: "" }] }
                    }
                    // juego de SteamGridDB (por si la búsqueda eligió otra edición)
                    Row {
                        anchors.right: parent.right; anchors.rightMargin: 36; y: 70; spacing: 10; height: 42
                        Rectangle { width: 42; height: 42; radius: 21; color: gl.containsMouse ? "#26ffffff" : "#14ffffff"; visible: root.artGames.length > 1
                            Text { anchors.centerIn: parent; text: "‹"; color: "#f3efe3"; font.pixelSize: 26 }
                            MouseArea { id: gl; anchors.fill: parent; hoverEnabled: true; onClicked: root.artGame(-1) } }
                        Text { anchors.verticalCenter: parent.verticalCenter; color: "#d6d0bf"; font.family: canvas.body; font.pixelSize: 18
                            width: 520; elide: Text.ElideMiddle; horizontalAlignment: Text.AlignRight
                            text: { for (var i = 0; i < root.artGames.length; i++) if (root.artGames[i].id === root.artSgid) return root.artGames[i].name + (root.artGames[i].year ? " (" + root.artGames[i].year + ")" : "") + "   ·   " + (i + 1) + "/" + root.artGames.length; return "" } }
                        Rectangle { width: 42; height: 42; radius: 21; color: gr.containsMouse ? "#26ffffff" : "#14ffffff"; visible: root.artGames.length > 1
                            Text { anchors.centerIn: parent; text: "›"; color: "#f3efe3"; font.pixelSize: 26 }
                            MouseArea { id: gr; anchors.fill: parent; hoverEnabled: true; onClicked: root.artGame(1) } }
                    }
                    GridView {
                        id: artGrid
                        x: 24; y: 130; width: parent.width - 48; height: parent.height - 130 - 64
                        clip: true; boundsBehavior: Flickable.StopAtBounds
                        cellWidth: Math.floor(width / root.artCols); cellHeight: root.artKind === "portada" ? cellWidth * 1.45 : (root.artKind === "fondo" ? cellWidth * 0.42 + 12 : cellWidth * 0.62)
                        model: root.artItems
                        currentIndex: root.artIdx
                        Connections { target: root; function onArtIdxChanged() { artGrid.positionViewAtIndex(root.artIdx, GridView.Contain) } }
                        delegate: Item {
                            id: ad
                            required property var modelData
                            required property int index
                            width: artGrid.cellWidth; height: artGrid.cellHeight
                            readonly property bool foc: root.artIdx === index
                            // resplandor de la posición actual
                            Rectangle { visible: ad.foc; anchors.fill: parent; anchors.margins: 3; radius: 19; color: "transparent"; border.width: 3; border.color: "#59e6d9a0" }
                            Rectangle {
                                anchors.fill: parent; anchors.margins: 8; radius: 14
                                color: "#1a211c"; clip: true
                                scale: ad.foc ? 1.0 : 0.985
                                Image {
                                    anchors.fill: parent; anchors.margins: root.artKind === "logo" ? 18 : 0
                                    source: ad.modelData.thumb; asynchronous: true; smooth: true
                                    fillMode: root.artKind === "logo" ? Image.PreserveAspectFit : Image.PreserveAspectCrop
                                    opacity: status === Image.Ready ? 1 : 0
                                    Behavior on opacity { NumberAnimation { duration: 150 } }
                                }
                                Rectangle { anchors.fill: parent; radius: 14; color: "transparent"; z: 5
                                    border.width: ad.foc ? 5 : (ad.modelData.cur ? 3 : 1)
                                    border.color: ad.foc ? canvas.acc : (ad.modelData.cur ? "#7fd99a" : "#33f3efe3") }
                                Rectangle { visible: ad.modelData.cur === true; z: 6; anchors.left: parent.left; anchors.top: parent.top; anchors.margins: 12
                                    height: 28; radius: 14; color: "#7fd99a"; width: cuT.implicitWidth + 22
                                    Text { id: cuT; anchors.centerIn: parent; text: "✓ EN USO"; color: "#0c1a10"; font.family: canvas.hud; font.pixelSize: 14; font.weight: Font.Bold; font.letterSpacing: 1.2 } }
                                Rectangle { z: 6; visible: ad.foc || am2.containsMouse; anchors.left: parent.left; anchors.bottom: parent.bottom; anchors.margins: 8
                                    height: 24; radius: 12; color: "#b3000000"; width: ml.implicitWidth + 16
                                    Text { id: ml; anchors.centerIn: parent; text: ad.modelData.w + "×" + ad.modelData.h + (ad.modelData.by ? " · " + ad.modelData.by : ""); color: "#f3efe3"; font.family: canvas.hud; font.pixelSize: 12 } }
                                MouseArea { id: am2; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                                    onEntered: root.artIdx = ad.index; onClicked: { root.artIdx = ad.index; root.artPick(ad.index) } }
                            }
                        }
                        onContentYChanged: if (atYEnd && root.artMore && !root.artBusy) root.artLoad(root.artPage + 1)
                    }
                    Text { anchors.centerIn: parent; visible: root.artItems.length === 0
                        text: root.artBusy ? "Buscando en SteamGridDB…" : (root.artFail ? "No se pudo consultar SteamGridDB" : "Sin resultados para este juego"); color: "#d6d0bf"; font.family: canvas.body; font.pixelSize: 24 }
                    PadGuide {
                        visible: root.padConnected
                        x: 36; anchors.bottom: parent.bottom; anchors.bottomMargin: 16; width: parent.width - 72
                        padName: root.padName; iconSize: 36; fontPx: 17; spacing: 22; textColor: "#d6d0bf"; fontFamily: canvas.body
                        hints: [{ k: "DPAD", t: "Mover" }, { k: "A", t: "Aplicar" }, { k: "LB+RB", t: "Portada · Fondo · Logo" }, { k: "LT+RT", t: "Otra edición" }, { k: "B", t: "Cerrar" }]
                    }
                    Text { visible: !root.padConnected; x: 36; anchors.bottom: parent.bottom; anchors.bottomMargin: 22; color: "#a8a395"; font.family: canvas.body; font.pixelSize: 17
                        text: (root.artBusy && root.artItems.length > 0 ? "Descargando…   " : "") + "Intro: aplicar   ·   Tab: Portada/Fondo/Logo   ·   Re Pág/Av Pág: otra edición del juego   ·   Esc: cerrar" }
                }
            }

            // menú contextual del juego (clic derecho / Select / tecla Menú)
            Item {
                id: ctxMenu
                anchors.fill: parent; z: 30
                visible: opacity > 0.01; opacity: root.ctxOpen ? 1 : 0
                Behavior on opacity { NumberAnimation { duration: 140 } }
                MouseArea { anchors.fill: parent; acceptedButtons: Qt.LeftButton | Qt.RightButton; onClicked: root.ctxOpen = false }
                Rectangle {
                    id: ctxBox
                    width: 360; height: root.ctxItems.length * 50 + 28; radius: 20
                    x: root.ctxX < 0 ? 560 : Math.max(20, Math.min(1920 - width - 20, root.ctxX))
                    y: root.ctxY < 0 ? 470 : Math.max(100, Math.min(canvas.height - height - 130, root.ctxY))
                    color: "#ff0d1510"; border.width: 1; border.color: "#73e6d9a0"
                    scale: root.ctxOpen ? 1 : 0.94; transformOrigin: Item.TopLeft
                    Behavior on scale { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }
                    Text { x: 22; y: 10; text: root.curGame ? root.curGame.name.toUpperCase() : ""; width: parent.width - 44; elide: Text.ElideRight
                        color: canvas.acc; font.family: canvas.hud; font.pixelSize: 14; font.letterSpacing: 2.4; font.weight: Font.DemiBold; opacity: 0 }
                    MouseArea { anchors.fill: parent; acceptedButtons: Qt.AllButtons }
                    Column {
                        x: 12; y: 14; width: parent.width - 24
                        Repeater {
                            model: root.ctxItems
                            delegate: Rectangle {
                                id: cit
                                required property var modelData
                                required property int index
                                readonly property bool foc: root.ctxIdx === index
                                width: parent.width; height: 50; radius: 14
                                color: foc ? canvas.acc : (cm.containsMouse ? "#1fffffff" : "transparent")
                                Kirigami.Icon { x: 16; anchors.verticalCenter: parent.verticalCenter; width: 22; height: 22; source: cit.modelData.ic; isMask: true; color: cit.foc ? "#10150f" : "#f3efe3" }
                                Text { x: 54; anchors.verticalCenter: parent.verticalCenter; text: cit.modelData.t
                                    color: cit.foc ? "#10150f" : "#f3efe3"; font.family: canvas.body; font.pixelSize: 19; font.weight: Font.Medium }
                                MouseArea { id: cm; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                                    onEntered: root.ctxIdx = cit.index; onClicked: root.ctxActivate(cit.index) }
                            }
                        }
                    }
                }
            }

            // teclado virtual: SOLO cuando la búsqueda se abre con el mando
            Rectangle {
                id: padKb
                visible: opacity > 0.01; opacity: root.gsOpen && root.gsPad ? 1 : 0
                Behavior on opacity { NumberAnimation { duration: 180 } }
                x: (1920 - width) / 2; y: 104; z: 8; width: 1040; height: kbCol.implicitHeight + 40; radius: 28
                color: "#fa0b120e"; border.width: 1; border.color: "#59e6d9a0"
                Column {
                    id: kbCol
                    anchors { top: parent.top; topMargin: 20; horizontalCenter: parent.horizontalCenter }
                    width: parent.width - 48; spacing: 8
                    Repeater {
                        model: root.oskRows
                        delegate: Row {
                            id: kbRow
                            required property var modelData
                            required property int index
                            anchors.horizontalCenter: parent.horizontalCenter
                            spacing: 8
                            readonly property real tot: { var t = 0; for (var q = 0; q < modelData.length; q++) t += modelData[q].w; return t }
                            readonly property real unit: (kbCol.width - spacing * (modelData.length - 1)) / tot
                            Repeater {
                                model: kbRow.modelData
                                delegate: Rectangle {
                                    id: kk
                                    required property var modelData
                                    required property int index
                                    readonly property bool foc: root.oskR === kbRow.index && root.oskC === index
                                    width: kbRow.unit * modelData.w; height: 58; radius: 14
                                    color: foc ? canvas.acc : (modelData.k === "shift" && root.oskShift ? "#59e6d9a0" : "#1affffff")
                                    border.width: foc ? 0 : 1; border.color: "#33e6d9a0"
                                    scale: foc ? 1.06 : 1
                                    Behavior on scale { NumberAnimation { duration: 100 } }
                                    Text { anchors.centerIn: parent; text: kk.modelData.t; color: kk.foc ? "#14211a" : "#f3efe3"; font.family: canvas.hud; font.weight: Font.DemiBold; font.pixelSize: kk.modelData.k === "ch" ? 28 : 22; font.letterSpacing: kk.modelData.k === "ch" ? 0 : 1.5 }
                                    MouseArea { anchors.fill: parent; onClicked: { root.oskR = kbRow.index; root.oskC = kk.index; root.oskPress() } }
                                }
                            }
                        }
                    }
                    Row {
                        anchors.horizontalCenter: parent.horizontalCenter; spacing: 28
                        Repeater {
                            model: [["A", "Escribir"], ["B", "Borrar"], ["X", "Mayús"], ["Y", "Espacio"]]
                            delegate: Row {
                                required property var modelData
                                spacing: 8
                                Rectangle { width: 32; height: 32; radius: 16; color: "transparent"; border.width: 1; border.color: "#80e6d9a0"
                                    Text { anchors.centerIn: parent; text: parent.parent.modelData[0]; color: "#e6d9a0"; font.family: canvas.hud; font.bold: true; font.pixelSize: 14 } }
                                Text { anchors.verticalCenter: parent.verticalCenter; text: modelData[1].toUpperCase(); color: "#b3f3efe3"; font.family: canvas.hud; font.weight: Font.DemiBold; font.pixelSize: 15; font.letterSpacing: 2 }
                            }
                        }
                    }
                }
            }

            // ---------------------------------------------------------- información del juego
            Item {
                id: info
                x: 84; y: 112; width: 600; height: 330
                opacity: root.busy ? 0.15 : 1
                Behavior on opacity { NumberAnimation { duration: 400 } }
                property var g: root.curGame
                property var gp: g ? root.platOf(g.platform) : root.platOf("")
                Column {
                    spacing: 0
                    Row {
                        spacing: 10; height: 30
                        PlatIcon { key: info.g ? root.iconKey(info.g) : "n64"; size: 24; color: info.gp.col; anchors.verticalCenter: parent.verticalCenter }
                        Text { text: info.gp.nom; color: info.gp.col; font.family: canvas.hud; font.pixelSize: 19; font.weight: Font.DemiBold; font.letterSpacing: 1.5; anchors.verticalCenter: parent.verticalCenter }
                    }
                    Item { width: 1; height: 8 }
                    Text {
                        text: (info.g ? info.g.sub : "").toUpperCase() + ((info.g && !(info.g.lastPlayed > 0)) ? " · SIN JUGAR" : "") + ((root.view.length > 0 && root.games.length > 0 && info.g && root.games[0].id === info.g.id) ? " · ÚLTIMO JUGADO" : "")
                        color: canvas.acc; font.family: canvas.body; font.pixelSize: 16; font.letterSpacing: 3
                    }
                    Item {
                        id: titleBox
                        width: 600; height: titleLogo.ok ? 150 : titleTxt.implicitHeight
                        Image {
                            id: titleLogo
                            readonly property bool ok: status === Image.Ready
                            anchors.left: parent.left; anchors.verticalCenter: parent.verticalCenter
                            width: 600; height: 140
                            source: (info.g && info.g.logo) ? info.g.logo : ""
                            fillMode: Image.PreserveAspectFit; horizontalAlignment: Image.AlignLeft
                            asynchronous: true; smooth: true; mipmap: true; sourceSize.height: 280
                            visible: ok
                        }
                        Text {
                            id: titleTxt
                            visible: !titleLogo.ok
                            width: 600
                            text: info.g ? info.g.name : (root.helperOk ? "Sin juegos" : "Iniciando…")
                            color: canvas.ink
                            font.family: canvas.gfont; font.pixelSize: 68
                            fontSizeMode: Text.HorizontalFit; minimumPixelSize: 38
                            maximumLineCount: 1
                            topPadding: 6; bottomPadding: 8
                        }
                    }
                    Text { text: info.g ? (root.curPort ? root.curPort.s : info.g.s) : (root.helperOk ? "" : "Esperando al ayudante (estanteria-helper)"); color: canvas.ink2; font.family: canvas.body; font.pixelSize: 22 }
                    Item { width: 1; height: 14 }
                    Flow {
                        width: 600; spacing: 18
                        Repeater {
                            model: {
                                var c = []
                                if (info.g) {
                                    if (root.curPort && root.curPort.running) c.push("En ejecución")
                                    if (root.curPort) for (var i = 0; i < root.curPort.chips.length; i++) c.push(root.curPort.chips[i])
                                    for (var k = 0; k < info.g.chips.length; k++) c.push(info.g.chips[k])
                                }
                                return c
                            }
                            delegate: Row {
                                id: chipItem
                                required property string modelData
                                spacing: 10
                                Rectangle { width: 8; height: 8; radius: 4; color: canvas.acc; anchors.verticalCenter: parent.verticalCenter }
                                Text { text: chipItem.modelData; color: canvas.ink; font.family: canvas.body; font.pixelSize: 18 }
                            }
                        }
                    }
                    // selector de port (solo si el juego tiene varios)
                    Item { visible: root.pn > 0; width: 1; height: root.pn > 0 ? 16 : 0 }
                    Row {
                        visible: root.pn > 0
                        spacing: 10; height: root.pn > 0 ? 36 : 0
                        Text { text: "PORT"; color: canvas.ink3; font.family: canvas.hud; font.pixelSize: 15; font.letterSpacing: 3; anchors.verticalCenter: parent.verticalCenter }
                        Repeater {
                            model: info.g ? info.g.ports : []
                            delegate: Rectangle {
                                id: portChip
                                required property var modelData
                                required property int index
                                readonly property bool on: index === root.portIdx
                                readonly property bool ring: root.fz === "act" && root.fi === index
                                height: 34; radius: 17
                                width: pcRow.implicitWidth + 28
                                color: on ? canvas.acc : "#59000000"
                                border.width: on ? 0 : 1; border.color: "#47f3efe3"
                                Row {
                                    id: pcRow
                                    anchors.centerIn: parent; spacing: 7
                                    Rectangle { visible: portChip.modelData.running; width: 8; height: 8; radius: 4; color: "#6fd66f"; anchors.verticalCenter: parent.verticalCenter }
                                    Text { text: portChip.modelData.name; color: portChip.on ? "#10150f" : canvas.ink; font.family: canvas.hud; font.pixelSize: 18; font.weight: Font.DemiBold; font.letterSpacing: 0.8; anchors.verticalCenter: parent.verticalCenter }
                                }
                                Rectangle { visible: portChip.ring; anchors.fill: parent; anchors.margins: -5; radius: 22; color: "transparent"; border.width: 3; border.color: canvas.acc }
                                MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: root.selectPort(portChip.index) }
                            }
                        }
                    }
                    Item { width: 1; height: 18 }
                    Rectangle {
                        id: playBtn
                        readonly property bool ring: root.fz === "act" && root.fi === root.pn
                        height: 48; radius: 24; width: playRow.implicitWidth + 52
                        color: root.curPort && root.curPort.canLaunch ? canvas.acc : "#66ffffff"
                        Row {
                            id: playRow
                            anchors.centerIn: parent; spacing: 10
                            Canvas {
                                width: 17; height: 17; anchors.verticalCenter: parent.verticalCenter
                                onPaint: { var c = getContext("2d"); c.reset(); c.fillStyle = "#10150f"; c.beginPath(); c.moveTo(3, 1); c.lineTo(16, 8.5); c.lineTo(3, 16); c.closePath(); c.fill() }
                            }
                            Text {
                                text: !root.curPort ? "Jugar" : (root.curPort.running ? "En ejecución" : (root.curPort.canLaunch ? (root.pn > 0 ? "Jugar con " + root.curPort.name : "Jugar") : "Por preparar"))
                                color: "#10150f"; font.family: canvas.body; font.pixelSize: 21; font.weight: Font.DemiBold
                            }
                        }
                        Rectangle { visible: playBtn.ring; anchors.fill: parent; anchors.margins: -6; radius: 30; color: "transparent"; border.width: 3; border.color: canvas.acc }
                        MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: root.launch() }
                    }
                    // esquema del mando conectado (iconos reales según el tipo de mando)
                    Item { visible: root.padConnected; width: 1; height: root.padConnected ? 16 : 0 }
                    PadGuide {
                        visible: root.padConnected
                        width: 664
                        padName: root.padName
                        iconSize: 26; fontPx: 15; spacing: 11
                        textColor: canvas.ink2; fontFamily: canvas.hud
                        hints: {
                            var h = [{ k: "A", t: "Jugar" }, { k: "X", t: "Respaldar" }]
                            if (root.pn === 0) h.push({ k: "Y", t: "Música" })
                            h.push({ k: "LB+RB", t: "Consola" })
                            if (root.pn > 0) h.push({ k: "LT+RT", t: "Port" })
                            h.push({ k: "SELECT", t: "Opciones" }, { k: "START", t: "Big Menú" })
                            return h
                        }
                    }
                }
            }

            // ---------------------------------------------------------- reloj
            Item {
                x: 760; y: 80; width: 700; height: 150
                opacity: root.busy ? 0.15 : 1
                Behavior on opacity { NumberAnimation { duration: 500 } }
                readonly property date now: new Date(root.clockMs)
                Item {
                    Text { id: hh; text: ((parent.parent.now.getHours() % 12) || 12); color: canvas.ink; font.family: canvas.hud; font.pixelSize: 104; font.weight: Font.DemiBold }
                    Text {
                        id: cc; x: hh.width + 4; text: ":"; color: canvas.ink; font.family: canvas.hud; font.pixelSize: 104; font.weight: Font.DemiBold
                        opacity: (parent.parent.now.getSeconds() % 2) ? 0.2 : 0.85
                    }
                    Text { id: mm; x: cc.x + cc.width + 4; text: root.two(parent.parent.now.getMinutes()); color: canvas.ink; font.family: canvas.hud; font.pixelSize: 104; font.weight: Font.DemiBold }
                    Text { x: mm.x + mm.width + 14; anchors.baseline: hh.baseline; text: parent.parent.now.getHours() < 12 ? "AM" : "PM"; color: canvas.acc; font.family: canvas.hud; font.pixelSize: 32; font.weight: Font.DemiBold; font.letterSpacing: 4 }
                }
                Text {
                    y: 112
                    text: parent.now.toLocaleDateString(Qt.locale("es_MX"), "dddd d 'de' MMMM").toUpperCase()
                    color: canvas.ink2; font.family: canvas.hud; font.pixelSize: 22; font.letterSpacing: 3
                }
            }

            // mando detectado (junto al reloj)
            Rectangle {
                x: 1130; y: 118; height: 36; radius: 18; z: 2
                width: padRow.implicitWidth + 28
                color: "#59000000"; border.width: 1; border.color: root.padConnected ? "#80e6d9a0" : "#33f3efe3"
                opacity: root.busy ? 0.15 : 1
                Row {
                    id: padRow; anchors.centerIn: parent; spacing: 8
                    Kirigami.Icon { width: 20; height: 20; source: "input-gamepad-symbolic"; color: root.padConnected ? canvas.acc : "#80f3efe3"; anchors.verticalCenter: parent.verticalCenter }
                    Text { anchors.verticalCenter: parent.verticalCenter; text: root.padConnected ? (root.padName !== "" ? root.padName : "Mando conectado") : "Sin mando"
                        color: root.padConnected ? "#f3efe3" : "#80f3efe3"; font.family: canvas.hud; font.pixelSize: 16; font.weight: Font.DemiBold; font.letterSpacing: 1 }
                }
            }

            // ---------------------------------------------------------- partidas y ficha
            Item {
                id: mid
                x: 760; y: 236; width: 640; height: 260
                opacity: root.busy ? 0.15 : 1
                Behavior on opacity { NumberAnimation { duration: 400 } }
                property var g: root.curPort
                Column {
                    width: parent.width; spacing: 0
                    Row {
                        width: parent.width; spacing: 14; height: 22
                        Text { id: l1; text: "PARTIDAS · " + (mid.g && mid.g.saves.length > 0 ? mid.g.saves.length + " RANURAS" : "NINGUNA"); color: canvas.acc; font.family: canvas.hud; font.pixelSize: 16; font.weight: Font.DemiBold; font.letterSpacing: 3.2 }
                        Rectangle { width: parent.width - l1.implicitWidth - 14; height: 1; color: "#47f3efe3"; anchors.verticalCenter: parent.verticalCenter }
                    }
                    Item { width: 1; height: 8 }
                    Item {
                        width: parent.width; height: 70
                        Row {
                            visible: mid.g && mid.g.saves.length > 0
                            width: parent.width
                            Repeater {
                                model: mid.g ? mid.g.saves : []
                                delegate: Item {
                                    id: slot
                                    required property var modelData
                                    required property int index
                                    readonly property bool latest: mid.g && modelData.mtime > 0 && modelData.mtime >= Math.max.apply(null, mid.g.saves.map(function(x) { return x.mtime }))
                                    width: parent.width / Math.max(1, mid.g.saves.length); height: 70
                                    Rectangle { visible: slot.index > 0; x: 0; width: 1; height: 56; color: "#47f3efe3" }
                                    Column {
                                        x: slot.index > 0 ? 14 : 0; spacing: 2
                                        Rectangle {
                                            width: 13; height: 13; radius: 7
                                            color: slot.latest ? canvas.acc : (slot.modelData.used ? canvas.ink : "transparent")
                                            border.width: 2; border.color: slot.modelData.used ? (slot.latest ? canvas.acc : canvas.ink) : canvas.ink3
                                        }
                                        Item { width: 1; height: 4 }
                                        Text { text: slot.modelData.name; color: slot.modelData.used ? canvas.ink : canvas.ink3; font.family: canvas.hud; font.pixelSize: 17; font.weight: Font.DemiBold; font.letterSpacing: 0.7 }
                                        Text { text: slot.modelData.used ? root.relTime(slot.modelData.mtime) : "vacía"; color: slot.latest ? canvas.acc : canvas.ink2; font.family: canvas.body; font.pixelSize: 14; font.weight: slot.latest ? Font.DemiBold : Font.Normal }
                                    }
                                }
                            }
                        }
                        Text {
                            visible: !(mid.g && mid.g.saves.length > 0)
                            width: 560; wrapMode: Text.WordWrap
                            text: "Aún no hay partidas. Aparecerán aquí cuando juegues."
                            color: canvas.ink2; font.family: canvas.body; font.pixelSize: 19
                        }
                    }
                    Row {
                        spacing: 10; height: 30
                        Kirigami.Icon { source: "application-menu"; width: 18; height: 18; opacity: 0.7; anchors.verticalCenter: parent.verticalCenter }
                        Text { anchors.verticalCenter: parent.verticalCenter; text: "Más opciones: clic derecho · botón Select del mando"; color: canvas.ink3; font.family: canvas.body; font.pixelSize: 16 }
                    }
                    Item { width: 1; height: 14 }
                    Row {
                        width: parent.width; spacing: 14; height: 22
                        Text { id: l2; text: "FICHA"; color: canvas.acc; font.family: canvas.hud; font.pixelSize: 16; font.weight: Font.DemiBold; font.letterSpacing: 3.2 }
                        Rectangle { width: parent.width - l2.implicitWidth - 14; height: 1; color: "#47f3efe3"; anchors.verticalCenter: parent.verticalCenter }
                    }
                    Item { width: 1; height: 10 }
                    Row {
                        width: parent.width
                        Repeater {
                            model: mid.g ? [
                                { v: root.sessionText(mid.g), l: "ÚLTIMA SESIÓN", w: 150 },
                                { v: mid.g.disk !== "" ? mid.g.disk : "—", l: "EN DISCO", w: 120 },
                                { v: root.ajustesText(mid.g.ajustes), l: "AJUSTES", w: 220 },
                                { v: root.relTime(mid.g.lastBackup), l: "ÚLTIMO RESPALDO", w: 150 }
                            ] : []
                            delegate: Column {
                                id: stc
                                required property var modelData
                                width: modelData.w; spacing: 3
                                Text { width: parent.width - 10; text: stc.modelData.v; color: canvas.ink; font.family: canvas.hud; font.pixelSize: 22; font.weight: Font.DemiBold; elide: Text.ElideRight }
                                Text { text: stc.modelData.l; color: canvas.ink3; font.family: canvas.hud; font.pixelSize: 14; font.letterSpacing: 2.5; font.weight: Font.Medium }
                            }
                        }
                    }
                }
            }

            // ---------------------------------------------------------- reproductor (MPRIS)
            Item {
                id: player
                x: 1530; y: 48; width: 320; height: 156
                opacity: root.hasMusic ? (root.busy ? 0.15 : 1) : 0
                visible: opacity > 0.01
                Behavior on opacity { NumberAnimation { duration: 600 } }
                // difuminado radial sin bordes
                Canvas {
                    x: -60; y: -44; width: parent.width + 120; height: parent.height + 88
                    onPaint: {
                        var c = getContext("2d"); c.reset()
                        c.translate(width / 2, height / 2); c.scale(width / 2, height / 2)
                        var g = c.createRadialGradient(0, 0, 0, 0, 0, 1)
                        g.addColorStop(0, "rgba(0,0,0,0.58)"); g.addColorStop(0.4, "rgba(0,0,0,0.36)")
                        g.addColorStop(0.62, "rgba(0,0,0,0.12)"); g.addColorStop(0.78, "rgba(0,0,0,0)")
                        c.fillStyle = g; c.fillRect(-1, -1, 2, 2)
                    }
                }
                Column {
                    anchors.horizontalCenter: parent.horizontalCenter
                    width: parent.width; spacing: 4
                    Text { width: parent.width; horizontalAlignment: Text.AlignHCenter; elide: Text.ElideRight; text: root.mus ? root.mus.track : ""; color: canvas.ink; font.family: canvas.hud; font.pixelSize: 21; font.weight: Font.DemiBold; font.letterSpacing: 0.6 }
                    Text { width: parent.width; horizontalAlignment: Text.AlignHCenter; elide: Text.ElideRight; text: root.mus ? root.mus.artist : ""; color: canvas.ink2; font.family: canvas.hud; font.pixelSize: 17; font.letterSpacing: 0.7 }
                    Item { width: 1; height: 2 }
                    Row {
                        anchors.horizontalCenter: parent.horizontalCenter; spacing: 6
                        Repeater {
                            model: 3
                            delegate: Item {
                                id: pb
                                required property int index
                                readonly property bool main: index === 1
                                readonly property bool ring: root.fz === "pl" && root.fi === index
                                width: main ? 46 : 38; height: width
                                anchors.verticalCenter: parent.verticalCenter
                                Rectangle { anchors.fill: parent; radius: width / 2; color: pb.main ? canvas.acc : (pbm.containsMouse ? "#29ffffff" : "transparent") }
                                Canvas {
                                    anchors.centerIn: parent; width: 24; height: 24
                                    property bool playing: root.musicPlaying
                                    onPlayingChanged: requestPaint()
                                    Component.onCompleted: requestPaint()
                                    onPaint: {
                                        var c = getContext("2d"); c.reset()
                                        c.fillStyle = pb.main ? "#10150f" : "#f3efe3"
                                        if (pb.index === 0) { c.fillRect(6, 5, 2, 14); c.beginPath(); c.moveTo(20, 5); c.lineTo(20, 19); c.lineTo(9, 12); c.closePath(); c.fill() }
                                        else if (pb.index === 2) { c.fillRect(16, 5, 2, 14); c.beginPath(); c.moveTo(4, 5); c.lineTo(4, 19); c.lineTo(15, 12); c.closePath(); c.fill() }
                                        else if (playing) { c.fillRect(6, 4, 4, 16); c.fillRect(14, 4, 4, 16) }
                                        else { c.beginPath(); c.moveTo(7, 4); c.lineTo(20, 12); c.lineTo(7, 20); c.closePath(); c.fill() }
                                    }
                                }
                                Rectangle { visible: pb.ring; anchors.fill: parent; anchors.margins: -5; radius: width / 2; color: "transparent"; border.width: 3; border.color: canvas.acc }
                                MouseArea { id: pbm; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: root.activatePl(pb.index) }
                            }
                        }
                    }
                    Item { width: 1; height: 4 }
                    Row {
                        width: parent.width; spacing: 10; height: 20
                        Text { text: root.mus ? root.mmss(root.mus.position) : "0:00"; color: canvas.ink3; font.family: canvas.hud; font.pixelSize: 14; anchors.verticalCenter: parent.verticalCenter }
                        Rectangle {
                            width: parent.width - 2 * 44 - 20; height: 4; radius: 2; color: "#2effffff"; anchors.verticalCenter: parent.verticalCenter
                            Rectangle { height: parent.height; radius: 2; color: canvas.acc; width: (root.mus && root.mus.length > 0) ? parent.width * Math.min(1, root.mus.position / root.mus.length) : 0 }
                        }
                        Text { text: root.mus ? root.mmss(root.mus.length) : "0:00"; color: canvas.ink3; font.family: canvas.hud; font.pixelSize: 14; anchors.verticalCenter: parent.verticalCenter }
                    }
                }
            }

            // ---------------------------------------------------------- broche
            Clasp { x: 1530; y: 212; color: canvas.acc; opacity: root.busy ? 0.15 : 0.9 }

            // ---------------------------------------------------------- monitor del PC
            Item {
                id: hud
                x: 1530; y: 246; width: 320; height: 440
                opacity: root.busy ? 0.15 : 1
                Behavior on opacity { NumberAnimation { duration: 500 } }
                function tcol(t) { return t >= 88 ? "#e2604f" : (t >= 75 ? "#e6a850" : "#d6d0bf") }
                Column {
                    width: parent.width; spacing: 0
                    Row {
                        width: parent.width; spacing: 14; height: 24
                        Text { id: l3; text: "SISTEMA"; color: canvas.acc; font.family: canvas.hud; font.pixelSize: 16; font.weight: Font.DemiBold; font.letterSpacing: 3.2 }
                        Rectangle { width: parent.width - l3.implicitWidth - 14; height: 1; color: "#47f3efe3"; anchors.verticalCenter: parent.verticalCenter }
                    }
                    HudRow {
                        acc: canvas.acc; ink: canvas.ink; ink2: canvas.ink2; ink3: canvas.ink3
                        label: "CPU"; sub: "i5-10300H"
                        pct: root.sens ? root.sens.cpu : 0
                        vtext: Math.round(root.sens ? root.sens.cpu : 0) + " %"
                        extra: (root.sens ? Math.round(root.sens.cpuTemp) : 0) + " °C" + (root.stats.ghz ? "  " + root.stats.ghz.toFixed(1) + " GHz" : "")
                        extraColor: hud.tcol(root.sens ? root.sens.cpuTemp : 0)
                    }
                    HudRow {
                        acc: canvas.acc; ink: canvas.ink; ink2: canvas.ink2; ink3: canvas.ink3
                        label: "GPU"; sub: "GTX 1650 Ti"
                        pct: root.sens ? root.sens.gpu : 0
                        vtext: Math.round(root.sens ? root.sens.gpu : 0) + " %"
                        extra: (root.sens ? Math.round(root.sens.gpuTemp) : 0) + " °C"
                        extraColor: hud.tcol(root.sens ? root.sens.gpuTemp : 0)
                    }
                    HudRow {
                        acc: canvas.acc; ink: canvas.ink; ink2: canvas.ink2; ink3: canvas.ink3
                        label: "RAM"; sub: root.sens && root.sens.ramTotal > 0 ? Math.round(root.sens.ramTotal / 1073741824) + " GB" : ""
                        pct: root.sens && root.sens.ramTotal > 0 ? root.sens.ramUsed / root.sens.ramTotal * 100 : 0
                        vtext: root.sens ? root.gb(root.sens.ramUsed) : "0.0"
                        extra: "/ " + (root.sens ? root.gb(root.sens.ramTotal) : "0") + " GB"
                    }
                    HudRow {
                        acc: canvas.acc; ink: canvas.ink; ink2: canvas.ink2; ink3: canvas.ink3
                        label: "VRAM"; sub: root.sens && root.sens.vramTotal > 0 ? Math.round(root.sens.vramTotal / 1073741824) + " GB" : ""
                        pct: root.sens && root.sens.vramTotal > 0 ? root.sens.vramUsed / root.sens.vramTotal * 100 : 0
                        vtext: root.sens ? root.gb(root.sens.vramUsed) : "0.0"
                        extra: "/ " + (root.sens ? root.gb(root.sens.vramTotal) : "0") + " GB"
                    }
                    HudRow {
                        acc: canvas.acc; ink: canvas.ink; ink2: canvas.ink2; ink3: canvas.ink3
                        label: "JUEGOS"; sub: "Btrfs"
                        pct: root.stats.disk ? root.stats.disk.used / root.stats.disk.total * 100 : 0
                        vtext: root.stats.disk ? Math.round(root.stats.disk.used / 1073741824) + "" : "—"
                        extra: root.stats.disk ? "/ " + Math.round(root.stats.disk.total / 1073741824) + " GB" : ""
                    }
                    HudRow {
                        acc: canvas.acc; ink: canvas.ink; ink2: canvas.ink2; ink3: canvas.ink3
                        label: "BATERÍA"; sub: root.stats.ac ? "enchufado" : "con batería"
                        pct: root.stats.bat ? root.stats.bat.pct : 0
                        vtext: root.stats.bat ? root.stats.bat.pct + " %" : "—"
                        extra: ""
                    }
                    Item {
                        width: parent.width; height: 62
                        Canvas {
                            id: spark
                            width: parent.width; height: 34
                            property var h: root.tempHist
                            onHChanged: requestPaint()
                            onPaint: {
                                var c = getContext("2d"); c.reset()
                                if (h.length < 2) return
                                var lo = h[0], hi = h[0]
                                for (var k = 1; k < h.length; k++) { lo = Math.min(lo, h[k]); hi = Math.max(hi, h[k]) }
                                var mid = (lo + hi) / 2, half = Math.max(6, (hi - lo) / 2 + 2)
                                c.strokeStyle = canvas.acc; c.lineWidth = 2; c.lineJoin = "round"
                                c.beginPath()
                                for (var i = 0; i < h.length; i++) {
                                    var x = (60 - h.length + i) * width / 59, y = 17 - (h[i] - mid) / half * 14
                                    if (i === 0) c.moveTo(x, y); else c.lineTo(x, y)
                                }
                                c.stroke()
                            }
                        }
                        Text { y: 38; text: "TEMP. CPU · 60 S"; color: canvas.ink3; font.family: canvas.hud; font.pixelSize: 15; font.letterSpacing: 2.5 }
                    }
                }
            }

            // ---------------------------------------------------------- estantería de portadas
            Item {
                id: shelfWrap
                x: 0; width: 1920; height: 640
                y: canvas.height - root.clearance - height
                Item {
                    id: track
                    x: 230 - root.cur * 210
                    Behavior on x { NumberAnimation { duration: 550; easing.type: Easing.OutCubic } }
                    height: parent.height
                    Row {
                        id: cardsRow
                        spacing: 20
                        anchors.bottom: parent.bottom
                        Repeater {
                            model: root.view
                            delegate: Item {
                                id: slotWrap
                                required property var modelData
                                required property int index
                                readonly property bool on: index === root.cur
                                width: on ? 290 : 190
                                height: 435
                                z: on ? 5 : 0
                                Behavior on width { NumberAnimation { duration: 420; easing.type: Easing.OutBack; easing.overshoot: 0.8 } }
                                // difuminado de las tarjetas que se acercan a los bordes de la pantalla
                                readonly property real cx: x + track.x + width / 2
                                opacity: Math.max(0, Math.min(1, cx / 300, (1920 - cx) / 380))
                                // con cientos de juegos solo se crean las tarjetas cercanas a la seleccionada (cada una lleva capa y máscara)
                                Loader { anchors.fill: parent; active: Math.abs(slotWrap.index - root.cur) <= 9; sourceComponent: slotComp }
                                Component {
                                id: slotComp
                                Item {
                                id: slotItem
                                readonly property var modelData: slotWrap.modelData
                                readonly property int index: slotWrap.index
                                readonly property bool on: slotWrap.on
                                readonly property var pd: root.platOf(modelData.platform)
                                width: slotWrap.width; height: 435

                                Item {
                                    id: card
                                    anchors.bottom: parent.bottom
                                    width: parent.width
                                    height: slotItem.on ? 435 : 285
                                    Behavior on height { NumberAnimation { duration: 420; easing.type: Easing.OutBack; easing.overshoot: 0.8 } }
                                    opacity: root.busy && !slotItem.on ? 0 : 1
                                    Behavior on opacity { NumberAnimation { duration: 400 } }
                                    transform: Translate { y: root.busy && slotItem.on ? -70 : (cardHover.containsMouse && !slotItem.on ? -10 : 0); Behavior on y { NumberAnimation { duration: 280; easing.type: Easing.OutCubic } } }
                                    scale: root.busy && slotItem.on ? 1.3 : 1
                                    Behavior on scale { NumberAnimation { duration: 700; easing.type: Easing.OutCubic } }

                                    // contenido recortado con esquinas redondeadas
                                    Item {
                                        id: body
                                        anchors.fill: parent
                                        layer.enabled: true
                                        layer.effect: OpacityMask { maskSource: bodyMask }
                                        Rectangle { anchors.fill: parent; color: "#222222" }
                                        Scene { anchors.fill: parent; pal: slotItem.modelData.pal; big: false; visible: cimg.status !== Image.Ready }
                                        Image {
                                            id: cimg
                                            anchors.fill: parent
                                            source: slotItem.modelData.portada
                                            fillMode: Image.PreserveAspectCrop
                                            asynchronous: true
                                            sourceSize.width: 600
                                        }
                                        Rectangle {
                                            visible: cimg.status !== Image.Ready
                                            anchors.left: parent.left; anchors.right: parent.right; anchors.bottom: parent.bottom
                                            height: parent.height * 0.42
                                            gradient: Gradient {
                                                GradientStop { position: 0.0; color: "#00000000" }
                                                GradientStop { position: 1.0; color: "#d9000000" }
                                            }
                                        }
                                        Column {
                                            visible: cimg.status !== Image.Ready
                                            anchors.left: parent.left; anchors.right: parent.right; anchors.bottom: parent.bottom
                                            anchors.margins: 14
                                            Text { width: parent.width; text: slotItem.modelData.name; color: "#f3efe3"; font.family: slotItem.modelData.font; font.pixelSize: slotItem.on ? 35 : 24; wrapMode: Text.WordWrap; maximumLineCount: 2; lineHeight: 0.95 }
                                            Text { text: slotItem.modelData.sub; color: "#d6d0bf"; font.family: canvas.body; font.pixelSize: slotItem.on ? 20 : 17 }
                                        }
                                        // brillo al seleccionar
                                        Rectangle {
                                            width: 80; height: parent.height * 1.4; y: -parent.height * 0.2
                                            rotation: 18; color: "#2effffff"
                                            x: slotItem.on ? parent.width + 120 : -160
                                            Behavior on x { NumberAnimation { duration: 800; easing.type: Easing.OutCubic } }
                                        }
                                    }
                                    Rectangle { id: bodyMask; anchors.fill: parent; radius: 18; visible: false }
                                    // borde
                                    Rectangle {
                                        anchors.fill: parent; radius: 18; color: "transparent"
                                        border.width: 1; border.color: slotItem.on ? "#d9ffffff" : "#38ffffff"
                                    }
                                    // etiqueta de consola
                                    Rectangle {
                                        x: 12; y: 12; height: 26; radius: 13; color: "#8c000000"
                                        width: tagRow.implicitWidth + 17
                                        Row {
                                            id: tagRow
                                            anchors.centerIn: parent; spacing: 5
                                            PlatIcon { key: root.iconKey(slotItem.modelData); size: 17; color: slotItem.pd.col; anchors.verticalCenter: parent.verticalCenter }
                                            Text { text: (slotItem.modelData.platform === "pc" && slotItem.modelData.src) ? "PC · " + slotItem.modelData.src : slotItem.pd.cor; color: slotItem.pd.col; font.family: canvas.hud; font.pixelSize: 15; font.weight: Font.Bold; font.letterSpacing: 0.9; anchors.verticalCenter: parent.verticalCenter }
                                        }
                                    }
                                    // favorito
                                    Text { visible: slotItem.modelData.fav; anchors.right: parent.right; anchors.top: parent.top; anchors.margins: 10
                                        text: "★"; color: "#e6d9a0"; font.pixelSize: 22; style: Text.Outline; styleColor: "#99000000" }
                                    // juego sin iniciar nunca: punto verde; con la tarjeta seleccionada, "NUEVO"
                                    Rectangle {
                                        visible: !(slotItem.modelData.lastPlayed > 0)
                                        anchors.right: parent.right; anchors.top: parent.top
                                        anchors.topMargin: slotItem.on ? 12 : 16
                                        anchors.rightMargin: (slotItem.modelData.fav ? 40 : 12) + (slotItem.on ? 0 : 4)
                                        height: slotItem.on ? 26 : 14; radius: height / 2
                                        width: slotItem.on ? nuT.implicitWidth + 18 : 14
                                        color: "#6fd08c"; border.width: slotItem.on ? 0 : 2; border.color: "#cc0c1a10"
                                        Text { id: nuT; visible: slotItem.on; anchors.centerIn: parent; text: "NUEVO"; color: "#0c1a10"; font.family: canvas.hud; font.pixelSize: 14; font.weight: Font.Bold; font.letterSpacing: 1.2 }
                                    }
                                    // cuántos ports tiene el juego
                                    Rectangle {
                                        visible: slotItem.modelData.portCount > 1
                                        anchors.right: parent.right; anchors.bottom: parent.bottom; anchors.margins: 12
                                        height: 26; radius: 13; color: "#8c000000"; width: pcT.implicitWidth + 18
                                        Text { id: pcT; anchors.centerIn: parent; text: slotItem.modelData.portCount + " ports"; color: "#f3efe3"; font.family: canvas.hud; font.pixelSize: 15; font.weight: Font.Bold; font.letterSpacing: 0.9 }
                                    }
                                    MouseArea {
                                        id: cardHover
                                        anchors.fill: parent; cursorShape: Qt.PointingHandCursor; hoverEnabled: true
                                        acceptedButtons: Qt.LeftButton | Qt.RightButton
                                        onClicked: function(m) {
                                            full.forceActiveFocus()
                                            if (m.button === Qt.RightButton) {
                                                if (!slotItem.on) root.sel(slotItem.index)
                                                var pt = cardHover.mapToItem(canvas, m.x, m.y); root.ctxShow(pt.x, pt.y)
                                            } else if (slotItem.on) root.launch(); else root.sel(slotItem.index)
                                        }
                                    }
                                }
                            }
                                }
                                }
                        }
                    }
                }
            }
            MouseArea {
                x: 0; width: 1920; height: 520
                y: canvas.height - root.clearance - 520
                acceptedButtons: Qt.NoButton
                onWheel: function(w) {
                    if (w.angleDelta.y > 0 || w.angleDelta.x > 0) root.sel(root.cur - 1)
                    else if (w.angleDelta.y < 0 || w.angleDelta.x < 0) root.sel(root.cur + 1)
                }
            }

            // ---------------------------------------------------------- lanzamiento y avisos
            Rectangle {
                anchors.fill: parent; color: "#000000"
                opacity: root.busy ? 0.85 : 0
                visible: opacity > 0.01
                Behavior on opacity { NumberAnimation { duration: 600 } }
                z: 20
            }
            Text {
                z: 21
                anchors.horizontalCenter: parent.horizontalCenter
                y: canvas.height - 260
                text: "Iniciando " + root.launchName + "…"
                color: canvas.ink; font.family: canvas.gfont; font.pixelSize: 36; font.letterSpacing: 1.5
                opacity: root.busy ? 1 : 0
                Behavior on opacity { NumberAnimation { duration: 400 } }
            }
            Rectangle {
                z: 22
                anchors.horizontalCenter: parent.horizontalCenter
                y: 56
                height: 46; radius: 23; width: toastT.implicitWidth + 52
                color: "#c7000000"; border.width: 1; border.color: "#47f3efe3"
                opacity: root.toastText !== "" ? 1 : 0
                visible: opacity > 0.01
                Behavior on opacity { NumberAnimation { duration: 300 } }
                Text { id: toastT; anchors.centerIn: parent; text: root.toastText; color: canvas.ink; font.family: canvas.body; font.pixelSize: 21 }
            }
            // estado del mando
            Text {
                x: 1920 - width - 24; y: 8
                text: root.padConnected ? "Mando conectado" : ""
                color: canvas.ink3; font.family: canvas.hud; font.pixelSize: 15; font.letterSpacing: 2
                visible: false
            }
        }
    }
    }
}

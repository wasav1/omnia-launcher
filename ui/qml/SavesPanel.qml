import QtQuick

// Partidas de un juego: dónde están, respaldar, restaurar y elegir la carpeta. Teclado, ratón y mando.
FocusScope {
    id: sp
    property var api
    property var game
    property string portId: ""
    signal finished

    property var info: null
    property var suggestions: []
    property string note: ""
    property string stage: "main"          // main | restore | confirm
    property string pendingFile: ""
    readonly property bool isManual: !!game && game.id.indexOf("manual-") === 0

    function reload() {
        api.savesInfo(game, function (st, b) { if (st === 200) info = b }, portId)
        api.savesSuggest(game, function (st, b) { suggestions = st === 200 ? b.suggestions : [] }, portId)
    }
    function ago(ts) {
        if (!ts) return "nunca"
        const d = Date.now() / 1000 - ts
        if (d < 90) return "hace un momento"
        if (d < 3600) return "hace " + Math.floor(d / 60) + " min"
        if (d < 86400) return "hace " + Math.floor(d / 3600) + " h"
        return "hace " + Math.floor(d / 86400) + " días"
    }
    function mb(n) { return n < 1048576 ? Math.max(1, Math.round(n / 1024)) + " KB" : (n / 1048576).toFixed(1) + " MB" }

    readonly property var restorable: info ? info.backups.filter(function (b) { return b.restorable }) : []
    readonly property var rows: {
        if (!info) return [{ text: "Cargando…", disabled: true }]
        if (stage === "restore") {
            const r = restorable.map(function (b) { return { kind: "pick", file: b.name, text: b.name, sub: mb(b.size) + "  ·  " + ago(b.mtime) } })
            r.push({ kind: "back", text: "Volver" })
            return r
        }
        if (stage === "confirm") return [
            { kind: "yes", text: "Sí, restaurar", sub: "Antes se guarda lo que hay ahora, para poder volver atrás", accent: true },
            { kind: "back", text: "Cancelar" }]
        const out = [
            { kind: "backup", text: "Respaldar ahora", sub: "Se guarda un .tar.gz en " + info.backupDir, disabled: !info.configured },
            { kind: "restore", text: "Restaurar un respaldo…", sub: restorable.length + " con restauración automática", disabled: restorable.length === 0 },
            { kind: "browse", text: "Elegir la carpeta de partidas…", sub: "Se abre el explorador" }]
        for (let i = 0; i < suggestions.length; i++)
            out.push({ kind: "suggest", path: suggestions[i].path, text: "Usar: " + suggestions[i].label, sub: suggestions[i].path })
        out.push({ kind: "open", text: "Abrir la carpeta de partidas", disabled: !info.folder })
        if (isManual) out.push({ kind: "remove", text: "Quitar este juego de Omnia", sub: "Solo lo quita de la biblioteca; no borra archivos" })
        out.push({ kind: "close", text: "Cerrar" })
        return out
    }
    function statusText() {
        if (!info) return ""
        const n = info.slots.length
        return (info.configured ? "Carpeta: " + (info.folder || "(aún no existe)") : "Sin carpeta de partidas configurada")
             + "\n" + (info.configured ? n + (n === 1 ? " partida encontrada" : " partidas encontradas") : "Elige la carpeta o usa una sugerencia")
             + "   ·   " + info.backups.length + " respaldos (último " + ago(info.lastBackup) + ")"
    }
    function say(msg) { note = msg }

    function run(i) {
        const r = rows[i]
        if (!r) return
        if (r.kind === "backup") api.savesBackup(game, function (st, b) { say(st === 200 ? "Respaldo creado: " + b.file : (b.error || "error " + st)); reload() }, portId)
        else if (r.kind === "restore") { stage = "restore"; list.reset() }
        else if (r.kind === "pick") { pendingFile = r.file; note = ""; stage = "confirm"; list.reset() }
        else if (r.kind === "yes") api.savesRestore(game, pendingFile, function (st, b) {
            say(st === 200 ? "Restaurado (" + b.restored + " archivos)" + (b.safety ? ". Antes se guardó: " + b.safety : "") : (b.error || "error " + st))
            stage = "main"; reload() }, portId)
        else if (r.kind === "back") stage = stage === "confirm" ? "restore" : "main"
        else if (r.kind === "browse") browser.active = true
        else if (r.kind === "suggest") api.savesConfig(game, { dirs: [r.path] }, function (st, b) { say(st === 200 ? "Carpeta configurada" : (b.error || "error " + st)); reload() }, portId)
        else if (r.kind === "open") api.savesOpen(game, function (st, b) { if (st !== 200) say(b.error || "error " + st) }, portId)
        else if (r.kind === "remove") api.removeGame(game, function (st, b) { if (st === 200) sp.finished(); else say(b.error || "error " + st) })
        else if (r.kind === "close") sp.finished()
    }
    function back() { if (stage !== "main") stage = stage === "confirm" ? "restore" : "main"; else sp.finished() }

    Component.onCompleted: { reload(); forceActiveFocus() }
    focus: true
    Keys.onPressed: function (e) {
        if (browser.active) return
        if (e.key === Qt.Key_Down) { list.moveSelection(1); e.accepted = true }
        else if (e.key === Qt.Key_Up) { list.moveSelection(-1); e.accepted = true }
        else if (e.key === Qt.Key_Return || e.key === Qt.Key_Enter) { list.activate(); e.accepted = true }
        else if (e.key === Qt.Key_Escape) { back(); e.accepted = true }
    }
    Connections {
        target: sp.api
        function onPadKey(key) {
            if (browser.active) return
            if (key === "d") list.moveSelection(1); else if (key === "u") list.moveSelection(-1)
            else if (key === "A") list.activate(); else if (key === "B") sp.back()
        }
    }

    Modal {
        id: m
        anchors.fill: parent
        title: "Partidas · " + (sp.game ? sp.game.name : "")
        footer: "↑↓ elegir  ·  Enter/A aceptar  ·  Esc/B volver"
        onCloseRequested: sp.finished()
        Column {
            anchors.fill: parent
            spacing: 12
            Text { width: parent.width; wrapMode: Text.WordWrap; text: sp.stage === "confirm" ? "¿Restaurar «" + sp.pendingFile + "»?" : sp.statusText()
                   color: "#c9bf8a"; font.pixelSize: 16; lineHeight: 1.15 }
            Text { visible: sp.note !== ""; width: parent.width; wrapMode: Text.WordWrap; text: sp.note; color: "#7fd69f"; font.pixelSize: 16 }
            OptionList {
                id: list
                width: parent.width; height: parent.height - y
                items: sp.rows
                onActivated: function (i) { sp.run(i) }
            }
        }
    }
    Loader {
        id: browser
        anchors.fill: parent
        active: false
        sourceComponent: Browser {
            api: sp.api
            mode: "dir"
            heading: "Carpeta de partidas de " + (sp.game ? sp.game.name : "")
            startPath: sp.info && sp.info.folder ? sp.info.folder : ""
            onChosen: function (path) {
                browser.active = false
                sp.api.savesConfig(sp.game, { dirs: [path] }, function (st, b) { sp.say(st === 200 ? "Carpeta configurada: " + path : (b.error || "error " + st)); sp.reload() }, sp.portId)
                sp.forceActiveFocus()
            }
            onCancelled: { browser.active = false; sp.forceActiveFocus() }
        }
    }
}

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
        if (!ts) return qsTr("nunca")
        const d = Date.now() / 1000 - ts
        if (d < 90) return qsTr("hace un momento")
        if (d < 3600) return qsTr("hace %1 min").arg(Math.floor(d / 60))
        if (d < 86400) return qsTr("hace %1 h").arg(Math.floor(d / 3600))
        return qsTr("hace %1 días").arg(Math.floor(d / 86400))
    }
    function mb(n) { return n < 1048576 ? Math.max(1, Math.round(n / 1024)) + " KB" : (n / 1048576).toFixed(1) + " MB" }

    readonly property var restorable: info ? info.backups.filter(function (b) { return b.restorable }) : []
    readonly property var rows: {
        if (!info) return [{ text: qsTr("Cargando…"), disabled: true }]
        if (stage === "restore") {
            const r = restorable.map(function (b) { return { kind: "pick", file: b.name, text: b.name, sub: mb(b.size) + "  ·  " + ago(b.mtime) } })
            r.push({ kind: "back", text: qsTr("Volver") })
            return r
        }
        if (stage === "confirm") return [
            { kind: "yes", text: qsTr("Sí, restaurar"), sub: qsTr("Antes se guarda lo que hay ahora, para poder volver atrás"), accent: true },
            { kind: "back", text: qsTr("Cancelar") }]
        const out = [
            { kind: "backup", text: qsTr("Respaldar ahora"), sub: qsTr("Se guarda un .tar.gz en %1").arg(info.backupDir), disabled: !info.configured },
            { kind: "restore", text: qsTr("Restaurar un respaldo…"), sub: qsTr("%1 con restauración automática").arg(restorable.length), disabled: restorable.length === 0 },
            { kind: "browse", text: qsTr("Elegir la carpeta de partidas…"), sub: qsTr("Se abre el explorador") }]
        for (let i = 0; i < suggestions.length; i++)
            out.push({ kind: "suggest", path: suggestions[i].path, text: qsTr("Usar: %1").arg(suggestions[i].label), sub: suggestions[i].path })
        out.push({ kind: "open", text: qsTr("Abrir la carpeta de partidas"), disabled: !info.folder })
        if (isManual) out.push({ kind: "remove", text: qsTr("Quitar este juego de Omnia"), sub: qsTr("Solo lo quita de la biblioteca; no borra archivos") })
        out.push({ kind: "close", text: qsTr("Cerrar") })
        return out
    }
    function statusText() {
        if (!info) return ""
        const n = info.slots.length
        return (info.configured ? qsTr("Carpeta: %1").arg(info.folder || qsTr("(aún no existe)")) : qsTr("Sin carpeta de partidas configurada"))
             + "\n" + (info.configured ? qsTr("%1 partidas encontradas").arg(n) : qsTr("Elige la carpeta o usa una sugerencia"))
             + "   ·   " + qsTr("%1 respaldos (último %2)").arg(info.backups.length).arg(ago(info.lastBackup))
    }
    function say(msg) { note = msg }

    function run(i) {
        const r = rows[i]
        if (!r) return
        if (r.kind === "backup") api.savesBackup(game, function (st, b) { say(st === 200 ? qsTr("Respaldo creado: %1").arg(b.file) : (b.error || qsTr("Error %1").arg(st))); reload() }, portId)
        else if (r.kind === "restore") { stage = "restore"; list.reset() }
        else if (r.kind === "pick") { pendingFile = r.file; note = ""; stage = "confirm"; list.reset() }
        else if (r.kind === "yes") api.savesRestore(game, pendingFile, function (st, b) {
            say(st === 200 ? qsTr("Restaurado (%1 archivos)").arg(b.restored) + (b.safety ? qsTr(". Antes se guardó una copia en: %1").arg(b.safety) : "") : (b.error || qsTr("Error %1").arg(st)))
            stage = "main"; reload() }, portId)
        else if (r.kind === "back") stage = stage === "confirm" ? "restore" : "main"
        else if (r.kind === "browse") browser.active = true
        else if (r.kind === "suggest") api.savesConfig(game, { dirs: [r.path] }, function (st, b) { say(st === 200 ? qsTr("Carpeta configurada") : (b.error || qsTr("Error %1").arg(st))); reload() }, portId)
        else if (r.kind === "open") api.savesOpen(game, function (st, b) { if (st !== 200) say(b.error || qsTr("Error %1").arg(st)) }, portId)
        else if (r.kind === "remove") api.removeGame(game, function (st, b) { if (st === 200) sp.finished(); else say(b.error || qsTr("Error %1").arg(st)) })
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
        title: qsTr("Partidas · %1").arg(sp.game ? sp.game.name : "")
        footer: "↑↓ elegir  ·  Enter/A aceptar  ·  Esc/B volver"
        onCloseRequested: sp.finished()
        Column {
            anchors.fill: parent
            spacing: 12
            Text { width: parent.width; wrapMode: Text.WordWrap; text: sp.stage === "confirm" ? qsTr("¿Restaurar «%1»?").arg(sp.pendingFile) : sp.statusText()
                   color: "#C9D6E4"; font.pixelSize: 16; lineHeight: 1.15 }
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
            heading: qsTr("Carpeta de partidas de %1").arg(sp.game ? sp.game.name : "")
            startPath: sp.info && sp.info.folder ? sp.info.folder : ""
            onChosen: function (path) {
                browser.active = false
                sp.api.savesConfig(sp.game, { dirs: [path] }, function (st, b) { sp.say(st === 200 ? qsTr("Carpeta configurada: %1").arg(path) : (b.error || qsTr("Error %1").arg(st))); sp.reload() }, sp.portId)
                sp.forceActiveFocus()
            }
            onCancelled: { browser.active = false; sp.forceActiveFocus() }
        }
    }
}

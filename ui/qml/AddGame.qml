import QtQuick
import QtQuick.Dialogs

// Asistente para añadir un juego que Omnia no detecta: un port, un emulador, un juego de Windows u otro ejecutable.
FocusScope {
    id: ag
    property var api
    signal finished
    signal added(string id)
    signal importRequested(string path)
    signal nameEditRequested(string initial)

    property string stage: "kind"           // kind | name | done
    property var tpls: []
    property string legacyPath: ""          // biblioteca anterior encontrada (disco de Bazzite), si la hay
    property var sel: null                  // el tipo elegido
    property string file: ""
    property string name: ""
    property string note: ""
    property string newId: ""
    property string directPath: ""
    property bool directStart: false
    property string recognized: ""
    property string identity: ""
    property string existingId: ""
    property string catalogSlug: ""
    property string matchedTitle: ""
    property var matches: []
    property bool busy: false
    property bool valid: false
    property bool libraryFinish: false
    property bool nameKeyboard: false
    property bool editingName: false
    property int request: 0
    property var folderCandidates: []

    function finishNameEdit(value) {
        if (value !== undefined) name = value
        Qt.callLater(function() { ag.editingName = false; ag.forceActiveFocus() })
    }

    function templateName(id, fallback) {
        const names = {
            gopher64: qsTr("Emulador N64 (Gopher64)"),
            "bedrock-on-linux": qsTr("Minecraft Bedrock (BedrockOnLinux)"),
            longshot: qsTr("Longshot (port de The Legend of Zelda: Ocarina of Time)"),
            hookshot: qsTr("Hookshot (port de The Legend of Zelda: Ocarina of Time)"),
            nx2navi: qsTr("NX2navi (port de The Legend of Zelda: Ocarina of Time)"),
            savagewind: qsTr("Savage Wind (port de The Legend of Zelda: Breath of the Wild)"),
            totkrecomp: qsTr("TOTK Recomp (port de The Legend of Zelda: Tears of the Kingdom)")
        }
        return names[id] || fallback
    }

    function prepareDirect(path) {
        file = path; name = baseName(path); note = ""; recognized = ""; identity = ""; existingId = ""
        catalogSlug = ""; matchedTitle = ""; matches = []; valid = false
        stage = "name"; list.reset()
        if (sel?.needs === "rom") { valid = true; return }
        const sequence = ++request
        const requestedType = sel
        busy = true
        api.suggestGame(path, function(st, body) {
            if (ag.request !== sequence) return
            ag.busy = false
            if (st !== 200) { note = body.error || qsTr("No se pudo identificar este archivo"); return }
            sel = requestedType?.tpl && !body.template
                ? requestedType : { kind: body.kind, template: body.template || "", needs: "exe", platform: body.platform || "pc" }
            name = body.name || baseName(path)
            recognized = body.recognized || ""
            identity = api.identityLabel(body.identity)
            existingId = body.existingId || ""
            note = existingId ? qsTr("Este juego ya está en tu biblioteca.")
                : recognized ? qsTr("Reconocido como %1").arg(recognized) : qsTr("Revisa el nombre antes de añadirlo.")
            valid = true
            list.reset()
        })
    }

    function findMatches() {
        const sequence = ++request
        busy = true; matches = []; stage = "match"; list.reset()
        api.manualMatches(name, result => {
            if (ag.request !== sequence) return
            ag.matches = result || []
            ag.busy = false
            list.reset()
        })
    }

    readonly property var kinds: {
        const out = ag.tpls.map(function (t) {
            return { id: t.id, text: templateName(t.id, t.name), sub: t.needs === "rom" ? qsTr("Elige la ROM del juego") : qsTr("Elige el ejecutable del port"), needs: t.needs, ext: t.ext, tpl: t.id }
        })
        out.push({ id: "_win", text: qsTr("Juego de Windows (.exe) con Proton"), sub: qsTr("Elige el .exe; Omnia lo ejecuta con umu-launcher"), needs: "exe", ext: [".exe"], kind: "windows" })
        out.push({ id: "_nat", text: qsTr("Juego nativo u otro ejecutable"), sub: qsTr("Elige el archivo que lo inicia"), needs: "exe", ext: [], kind: "native" })
        out.push({ id: "_folder", text: qsTr("Buscar ejecutables en una carpeta"), sub: qsTr("Omnia detecta ejecutables sin iniciarlos"), needs: "", ext: [] })
        if (legacyPath !== "") out.unshift({ id: "_import", text: qsTr("Importar mi biblioteca anterior…"), sub: qsTr("Vista previa e importación de ports y emuladores de Bazzite"), needs: "", ext: [] })
        return out
    }
    readonly property var rows: {
        if (stage === "kind") return kinds.map(function (k) { return { text: k.text, sub: k.sub } }).concat([{ text: qsTr("Cancelar") }])
        if (stage === "match") return matches.map(item => ({text: item.name, sub: api.manualMatchLabel(item)}))
            .concat([{text: busy ? qsTr("Buscando juegos…") : qsTr("Añadir sin vincular"), disabled: busy}, {text: qsTr("Volver")}])
        if (stage === "folder") return folderCandidates.map(item => ({text: item.name, sub: item.path}))
            .concat([{text: busy ? qsTr("Buscando ejecutables…") : qsTr("Volver a elegir origen"), disabled: busy}])
        if (stage === "name") {
            const out = [{ key: "add", text: existingId ? qsTr("Ver en la biblioteca") : qsTr("Añadir «%1»").arg(name),
                           accent: true, disabled: busy || !valid || !name.trim() }]
            if (valid && !existingId && nameKeyboard) out.push({key: "edit", text: qsTr("Editar nombre")})
            if (valid && !existingId && sel?.needs === "exe")
                out.push({key: "match", text: qsTr("Buscar ficha"), sub: matchedTitle})
            return out.concat([{key: "back", text: qsTr("Volver")}])
        }
        return [{ text: libraryFinish ? qsTr("Ver en la biblioteca") : qsTr("Elegir su carpeta de partidas ahora"),
                  sub: libraryFinish ? "" : qsTr("Abre la gestión de partidas para este juego"), accent: true }, { text: qsTr("Cerrar") }]
    }
    function baseName(p) { const f = p.split("/").pop(); const i = f.lastIndexOf("."); return i > 0 ? f.substring(0, i) : f }
    function localPath(url) { return decodeURIComponent(url.toString().replace(/^file:\/\//, "")) }

    function scanFolder(path) {
        stage = "folder"; busy = true; folderCandidates = []; list.reset()
        api.setLibraryRoot("add", path, function(rootStatus, rootBody) {
            if (rootStatus !== 200) { ag.busy = false; ag.note = rootBody.error || qsTr("No se pudo añadir la carpeta."); stage = "kind"; return }
            api.scanGameFolder(path, function(status, body) {
                ag.busy = false
                ag.folderCandidates = status === 200 ? (body.candidates || []) : []
                if (status !== 200) ag.note = body.error || qsTr("No se pudieron revisar los ejecutables de la carpeta.")
                list.reset()
            })
        })
    }

    function run(i) {
        if (stage === "kind") {
            if (i >= kinds.length) { ag.finished(); return }
            sel = kinds[i]
            if (sel.id === "_import") { ag.importRequested(legacyPath); return }
            if (sel.id === "_folder") { folderDialog.open(); return }
            browser.active = true
        } else if (stage === "folder") {
            if (i < folderCandidates.length) {
                const candidate = folderCandidates[i]
                sel = {kind: candidate.kind, needs: "exe", ext: []}
                prepareDirect(candidate.path)
            } else if (!busy) { stage = "kind"; list.reset() }
        } else if (stage === "match") {
            if (i < matches.length) { catalogSlug = matches[i].slug; matchedTitle = matches[i].name }
            else if (i === matches.length && !busy) { catalogSlug = ""; matchedTitle = "" }
            back()
        } else if (stage === "name") {
            const key = rows[i]?.key
            if (key === "back") { back(); return }
            if (key === "match") { findMatches(); return }
            if (key === "edit") { editingName = true; nameEditRequested(name); return }
            if (key !== "add" || busy || !valid) return
            if (existingId) { ag.added(existingId); return }
            busy = true
            const body = { name: name.trim() }
            if (sel.tpl || sel.template) body.template = sel.tpl || sel.template; else body.kind = sel.kind
            if (sel.platform) body.platform = sel.platform
            body[sel.needs === "rom" ? "rom" : "exe"] = file
            body.inspectExecutable = sel.needs === "exe"
            if (body.inspectExecutable && catalogSlug) body.catalogSlug = catalogSlug
            api.addGame(body, function (st, b) {
                busy = false
                if (st === 200) { newId = b.id; note = qsTr("Añadido a la biblioteca"); stage = "done"; list.reset() }
                else note = b.error || ("error " + st)
            })
        } else {
            if (i === 0) ag.added(newId); else ag.finished()
        }
    }
    onNameChanged: { catalogSlug = ""; matchedTitle = "" }
    function back() {
        request++; busy = false
        if (stage === "match") stage = "name"
        else if (stage === "folder") stage = "kind"
        else if (stage === "name") { stage = "kind"; note = "" }
        else ag.finished()
        list.reset()
    }

    Component.onCompleted: {
        api.templates(function (st, b) { if (st === 200) tpls = b.templates })
        api.importFind(function (st, b) { if (st === 200 && b.candidates.length > 0) legacyPath = b.candidates[0].path })
        forceActiveFocus()
        if (directPath !== "") prepareDirect(directPath)
        else if (directStart) Qt.callLater(function() { directDialog.open() })
    }
    focus: true
    Keys.onPressed: function (e) {
        if (browser.active || editingName) return
        if (e.key === Qt.Key_Down) { list.moveSelection(1); e.accepted = true }
        else if (e.key === Qt.Key_Up) { list.moveSelection(-1); e.accepted = true }
        else if (e.key === Qt.Key_Return || e.key === Qt.Key_Enter) { list.activate(); e.accepted = true }
        else if (e.key === Qt.Key_Escape) { back(); e.accepted = true }
    }
    Connections {
        target: ag.api
        function onPadKey(key) {
            if (browser.active || ag.editingName) return
            if (key === "d") list.moveSelection(1); else if (key === "u") list.moveSelection(-1)
            else if (key === "A") list.activate(); else if (key === "B") ag.back()
        }
    }

    Modal {
        anchors.fill: parent
        title: ag.stage === "kind" ? qsTr("Añadir un juego") : ag.stage === "folder" ? qsTr("Ejecutables encontrados") : ag.stage === "name" ? qsTr("Nombre del juego")
            : ag.stage === "match" ? qsTr("Elegir ficha del catálogo") : qsTr("Listo")
        footer: qsTr("↑↓ elegir  ·  Enter/A aceptar  ·  Esc/B volver")
        onCloseRequested: ag.finished()
        Column {
            anchors.fill: parent
            spacing: 12
            Text { visible: ag.stage === "kind"; width: parent.width; wrapMode: Text.WordWrap; color: "#C9D6E4"; font.pixelSize: 16
                   text: qsTr("¿Qué tipo de juego quieres añadir? Omnia sabe dónde guardan sus partidas los ports y emuladores compatibles.") }
            Text { visible: ag.stage === "folder"; width: parent.width; wrapMode: Text.WordWrap; color: "#C9D6E4"; font.pixelSize: 16
                   text: ag.busy ? qsTr("Revisando archivos compatibles…") : (ag.folderCandidates.length ? qsTr("Elige qué ejecutable quieres añadir. Omnia no lo iniciará durante la detección.") : qsTr("No se encontraron ejecutables compatibles en la carpeta.")) }
            Text { visible: ag.stage === "name"; width: parent.width; elide: Text.ElideMiddle; color: "#C9D6E4"; font.pixelSize: 16; text: ag.file }
            Text { visible: ag.stage === "name"; width: parent.width; wrapMode: Text.WordWrap; color: ag.recognized ? "#7fd69f" : "#C9D6E4"; font.pixelSize: 15; text: ag.note }
            Text { visible: ag.stage === "name" && ag.identity !== ""; width: parent.width; color: "#C9D6E4"; font.pixelSize: 15; text: ag.identity }
            Rectangle {
                visible: ag.stage === "name"; width: parent.width; height: 52; radius: 26; color: Qt.rgba(1, 1, 1, 0.08)
                TextInput {
                    id: nameInput
                    anchors { fill: parent; leftMargin: 22; rightMargin: 22 }
                    verticalAlignment: TextInput.AlignVCenter; color: "#EEF4FB"; font.pixelSize: 22; clip: true
                    text: ag.name
                    onTextChanged: ag.name = text
                    Keys.onPressed: function (e) {
                        if (e.key === Qt.Key_Return || e.key === Qt.Key_Enter) { list.activate(); e.accepted = true }
                        else if (e.key === Qt.Key_Escape) { ag.back(); e.accepted = true }
                        else if (e.key === Qt.Key_Down) { list.moveSelection(1); e.accepted = true }
                        else if (e.key === Qt.Key_Up) { list.moveSelection(-1); e.accepted = true }
                    }
                }
            }
            Text { visible: ag.stage === "done" && ag.note !== ""; width: parent.width; wrapMode: Text.WordWrap; text: ag.note; color: "#7fd69f"; font.pixelSize: 16 }
            OptionList {
                id: list
                width: parent.width; height: parent.height - y
                items: ag.rows
                onActivated: function (i) { ag.run(i) }
            }
        }
    }
    Loader {
        id: browser
        anchors.fill: parent
        active: false
        sourceComponent: Browser {
            api: ag.api
            mode: "file"
            exts: ag.sel ? ag.sel.ext : []
            heading: ag.sel && ag.sel.needs === "rom" ? qsTr("Elige la ROM") : qsTr("Elige el ejecutable")
            onChosen: function (path) {
                browser.active = false
                ag.prepareDirect(path)
            }
            onCancelled: { browser.active = false; ag.forceActiveFocus() }
        }
    }
    FileDialog {
        id: directDialog
        title: qsTr("Selecciona el ejecutable del juego")
        fileMode: FileDialog.OpenFile
        nameFilters: [qsTr("Ejecutables y juegos (*)"), qsTr("Ejecutables de Linux (*)"), qsTr("Juegos de Windows (*.exe)")]
        onAccepted: {
            const url = selectedFile.toString()
            if (url.startsWith("file:///"))
                ag.prepareDirect(decodeURIComponent(url.slice(7)))
        }
        onRejected: if (ag.directStart) ag.finished()
    }
    FolderDialog {
        id: folderDialog
        title: qsTr("Elige la carpeta que quieres revisar")
        onAccepted: ag.scanFolder(ag.localPath(selectedFolder))
    }
}

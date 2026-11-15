import QtQuick

// Asistente para añadir un juego que Omnia no detecta: un port, un emulador, un juego de Windows u otro ejecutable.
FocusScope {
    id: ag
    property var api
    signal finished
    signal added(string id)

    property string stage: "kind"           // kind | name | done
    property var tpls: []
    property var sel: null                  // el tipo elegido
    property string file: ""
    property string name: ""
    property string note: ""
    property string newId: ""

    readonly property var kinds: {
        const out = ag.tpls.map(function (t) {
            return { id: t.id, text: t.name, sub: t.needs === "rom" ? "Elige la ROM del juego" : "Elige el ejecutable del port", needs: t.needs, ext: t.ext, tpl: t.id }
        })
        out.push({ id: "_win", text: "Juego de Windows (.exe) con Proton", sub: "Elige el .exe; se ejecuta con umu-launcher", needs: "exe", ext: [".exe"], kind: "windows" })
        out.push({ id: "_nat", text: "Juego nativo u otro ejecutable", sub: "Elige el archivo que lo arranca", needs: "exe", ext: [], kind: "native" })
        return out
    }
    readonly property var rows: {
        if (stage === "kind") return kinds.map(function (k) { return { text: k.text, sub: k.sub } }).concat([{ text: "Cancelar" }])
        if (stage === "name") return [{ text: "Añadir «" + name + "»", sub: "Teclea para cambiar el nombre", accent: true }, { text: "Volver" }]
        return [{ text: "Elegir su carpeta de partidas ahora", sub: "Abre el panel de partidas del juego nuevo", accent: true }, { text: "Cerrar" }]
    }
    function baseName(p) { const f = p.split("/").pop(); const i = f.lastIndexOf("."); return i > 0 ? f.substring(0, i) : f }

    function run(i) {
        if (stage === "kind") {
            if (i >= kinds.length) { ag.finished(); return }
            sel = kinds[i]
            browser.active = true
        } else if (stage === "name") {
            if (i === 1) { stage = "kind"; return }
            const body = { name: name.trim() }
            if (sel.tpl) body.template = sel.tpl; else body.kind = sel.kind
            body[sel.needs === "rom" ? "rom" : "exe"] = file
            api.addGame(body, function (st, b) {
                if (st === 200) { newId = b.id; note = "Añadido a la biblioteca"; stage = "done"; list.reset() }
                else note = b.error || ("error " + st)
            })
        } else {
            if (i === 0) ag.added(newId); else ag.finished()
        }
    }
    function back() { if (stage === "name") stage = "kind"; else ag.finished() }

    Component.onCompleted: { api.templates(function (st, b) { if (st === 200) tpls = b.templates }); forceActiveFocus() }
    focus: true
    Keys.onPressed: function (e) {
        if (browser.active) return
        if (e.key === Qt.Key_Down) { list.move(1); e.accepted = true }
        else if (e.key === Qt.Key_Up) { list.move(-1); e.accepted = true }
        else if (e.key === Qt.Key_Return || e.key === Qt.Key_Enter) { list.activate(); e.accepted = true }
        else if (e.key === Qt.Key_Escape) { back(); e.accepted = true }
    }
    Connections {
        target: ag.api
        function onPadKey(key) {
            if (browser.active) return
            if (key === "d") list.move(1); else if (key === "u") list.move(-1)
            else if (key === "A") list.activate(); else if (key === "B") ag.back()
        }
    }

    Modal {
        anchors.fill: parent
        title: stage === "kind" ? "Añadir un juego" : (stage === "name" ? "Nombre del juego" : "Listo")
        footer: "↑↓ elegir  ·  Enter/A aceptar  ·  Esc/B volver"
        onCloseRequested: ag.finished()
        Column {
            anchors.fill: parent
            spacing: 12
            Text { visible: ag.stage === "kind"; width: parent.width; wrapMode: Text.WordWrap; color: "#c9bf8a"; font.pixelSize: 16
                   text: "¿Qué tipo de juego quieres añadir? Omnia sabe dónde guardan sus partidas los ports y emuladores de la lista." }
            Text { visible: ag.stage === "name"; width: parent.width; elide: Text.ElideMiddle; color: "#c9bf8a"; font.pixelSize: 16; text: ag.file }
            Rectangle {
                visible: ag.stage === "name"; width: parent.width; height: 52; radius: 26; color: Qt.rgba(1, 1, 1, 0.08)
                TextInput {
                    id: nameInput
                    anchors { fill: parent; leftMargin: 22; rightMargin: 22 }
                    verticalAlignment: TextInput.AlignVCenter; color: "#f4efd8"; font.pixelSize: 22; clip: true
                    text: ag.name
                    onTextChanged: ag.name = text
                    Keys.onPressed: function (e) {
                        if (e.key === Qt.Key_Return || e.key === Qt.Key_Enter) { list.activate(); e.accepted = true }
                        else if (e.key === Qt.Key_Escape) { ag.back(); e.accepted = true }
                        else if (e.key === Qt.Key_Down) { list.move(1); e.accepted = true }
                        else if (e.key === Qt.Key_Up) { list.move(-1); e.accepted = true }
                    }
                }
            }
            Text { visible: ag.note !== ""; width: parent.width; wrapMode: Text.WordWrap; text: ag.note; color: ag.stage === "done" ? "#7fd69f" : "#e89a8a"; font.pixelSize: 16 }
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
            heading: ag.sel && ag.sel.needs === "rom" ? "Elige la ROM" : "Elige el ejecutable"
            onChosen: function (path) {
                browser.active = false
                ag.file = path
                ag.name = ag.baseName(path)
                ag.note = ""
                ag.stage = "name"
                ag.forceActiveFocus()
                nameInput.forceActiveFocus()
            }
            onCancelled: { browser.active = false; ag.forceActiveFocus() }
        }
    }
}

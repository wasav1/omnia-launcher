import QtQuick

// Explorador de carpetas (o de archivos) manejable con mando. El núcleo solo deja mirar dentro del home y los discos externos.
//   mode "dir":  elegir una carpeta («Usar esta carpeta» o Y)       mode "file": elegir un archivo (con filtro de extensiones)
Modal {
    id: br
    property var api
    property string mode: "dir"
    property var exts: []
    property string startPath: ""
    property string heading: "Elige una carpeta"
    signal chosen(string path)
    signal cancelled

    property var data: ({ path: "", parent: null, dirs: [], files: [], shortcuts: [] })
    property string error: ""
    property int shortcutIdx: 0

    title: heading
    footer: mode === "dir" ? "↑↓ elegir  ·  Enter/A entrar  ·  ← / B subir  ·  Y usar esta carpeta  ·  LB/RB atajos  ·  Esc cancelar"
                           : "↑↓ elegir  ·  Enter/A abrir o elegir  ·  ← / B subir  ·  LB/RB atajos  ·  Esc cancelar"
    onCloseRequested: br.cancelled()

    function go(path) {
        api.fsList(path, mode === "file", exts, function (status, body) {
            if (status === 200) { data = body; error = ""; list.reset() }
            else error = body.error || ("error " + status)
        })
    }
    function up() { if (data.parent) go(data.parent); else br.cancelled() }
    function useHere() { if (mode === "dir") br.chosen(data.path) }
    function step(d) {
        const n = data.shortcuts.length
        if (n === 0) return
        shortcutIdx = (shortcutIdx + d + n) % n
        go(data.shortcuts[shortcutIdx].path)
    }
    readonly property var rows: {
        const out = []
        if (mode === "dir") out.push({ kind: "use", text: "✔  Usar esta carpeta", sub: data.path, accent: true })
        if (data.parent) out.push({ kind: "up", text: "⬆  Subir", sub: data.parent })
        for (let i = 0; i < data.dirs.length; i++) out.push({ kind: "dir", text: "📁  " + data.dirs[i].name, path: data.dirs[i].path })
        for (let j = 0; j < data.files.length; j++) out.push({ kind: "file", text: "📄  " + data.files[j].name, path: data.files[j].path })
        return out
    }
    function activate(i) {
        const r = rows[i]
        if (!r) return
        if (r.kind === "use") br.chosen(data.path)
        else if (r.kind === "up") up()
        else if (r.kind === "dir") go(r.path)
        else if (r.kind === "file") br.chosen(r.path)
    }

    Component.onCompleted: { go(startPath); forceActiveFocus() }
    focus: true
    Keys.onPressed: function (e) {
        if (e.key === Qt.Key_Down) { list.move(1); e.accepted = true }
        else if (e.key === Qt.Key_Up) { list.move(-1); e.accepted = true }
        else if (e.key === Qt.Key_Return || e.key === Qt.Key_Enter || e.key === Qt.Key_Right) { list.activate(); e.accepted = true }
        else if (e.key === Qt.Key_Left || e.key === Qt.Key_Backspace) { up(); e.accepted = true }
        else if (e.key === Qt.Key_Escape) { br.cancelled(); e.accepted = true }
        else if (e.key === Qt.Key_Space) { useHere(); e.accepted = true }
    }
    Connections {
        target: br.api
        function onPadKey(key) {
            if (key === "d") list.move(1); else if (key === "u") list.move(-1)
            else if (key === "A") list.activate(); else if (key === "B") br.up()
            else if (key === "Y") br.useHere()
            else if (key === "RB") br.step(1); else if (key === "LB") br.step(-1)
        }
    }

    // ruta actual y atajos
    Column {
        anchors.fill: parent
        spacing: 10
        Text { width: parent.width; elide: Text.ElideMiddle; text: br.data.path; color: "#c9bf8a"; font.pixelSize: 16 }
        ListView {
            width: parent.width; height: 36; orientation: ListView.Horizontal; spacing: 8; clip: true
            model: br.data.shortcuts
            delegate: Rectangle {
                required property var modelData
                required property int index
                height: 34; width: sct.width + 28; radius: 17
                color: br.data.path === modelData.path ? "#2e8b57" : Qt.rgba(1, 1, 1, 0.08)
                Text { id: sct; anchors.centerIn: parent; text: parent.modelData.name; color: "#f4efd8"; font.pixelSize: 15 }
                MouseArea { cursorShape: Qt.PointingHandCursor; anchors.fill: parent; onClicked: { br.shortcutIdx = parent.index; br.go(parent.modelData.path) } }
            }
        }
        Text { visible: br.error !== ""; text: br.error; color: "#e89a8a"; font.pixelSize: 16 }
        OptionList {
            id: list
            width: parent.width; height: parent.height - 110
            items: br.rows
            onActivated: function (i) { br.activate(i) }
        }
    }
}

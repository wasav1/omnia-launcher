import QtQuick
import QtQuick.Controls
import QtQuick.Dialogs

/** Asistente «Añadir juego» de la app de escritorio, en tres pasos: 1 Origen · 2 Detección · 3 Confirmación.
 *  (BigMode conserva `AddGame.qml`, pensado para el mando.) */
FocusScope {
    id: wz
    property var manager: null
    property var api: null
    signal finished()
    signal added(string id)
    signal importRequested(string path)

    readonly property real s: manager ? manager.s : 1
    readonly property string font: "Hanken Grotesk"
    property int step: 1
    property bool templateList: false          // paso 1: lista de ports y emuladores compatibles
    property var tpls: []
    property string legacyPath: ""
    property var sel: null                      // lo elegido: { kind | template, needs, platform, ext }
    property string file: ""
    property string name: ""
    property string note: ""
    property bool recognized: false
    property bool busy: false
    property bool folderFlow: false
    property string newId: ""
    property bool done: false
    property string error: ""
    property string identity: ""
    property string existingId: ""
    property var matches: []
    property string matchedQuery: ""
    property string catalogSlug: ""
    property bool matching: false
    property string folderPath: ""
    property var folderCandidates: []
    property bool scanLimited: false

    function findMatches() {
        const query = name.trim()
        if (!query || existingId || sel?.needs !== "exe") return
        const selectedFile = file
        matchedQuery = query; matches = []; catalogSlug = ""; matching = true
        api.manualMatches(query, result => {
            if (wz.file !== selectedFile || wz.matchedQuery !== query) return
            wz.matches = result || []
            wz.matching = false
        })
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
    function baseName(p) { const f = p.split("/").pop(); const i = f.lastIndexOf("."); return i > 0 ? f.substring(0, i) : f }
    function localPath(url) { return decodeURIComponent(url.toString().replace(/^file:\/\//, "")) }

    // ---- paso 1 → 2
    function chooseFolder(path) {
        folderFlow = true; folderPath = path; folderCandidates = []; scanLimited = false; step = 2; busy = true; error = ""
        note = qsTr("Añadiendo la carpeta a tu biblioteca…")
        const before = api.games.length
        api.setLibraryRoot("add", path, function(st, body) {
            if (st !== 200) { busy = false; error = (body && body.error) || qsTr("No se pudo añadir la carpeta."); return }
            wz.manager.libraryRoots = body.roots || []
            note = qsTr("Buscando juegos…")
            api.call("POST", "/library/refresh", function() {
                api.refresh()
                countTimer.before = before
                countTimer.restart()
            })
        })
    }
    Timer {
        id: countTimer
        property int before: 0
        interval: 2200
        onTriggered: {
            const n = api.games.length - before
            wz.recognized = n > 0
            wz.note = qsTr("Buscando ejecutables en la carpeta…")
            wz.api.scanGameFolder(wz.folderPath, function(st, body) {
                if (wz.step !== 2 || !wz.folderFlow) return
                wz.busy = false
                if (st === 200) {
                    wz.folderCandidates = body.candidates || []
                    wz.scanLimited = !!body.limited
                } else {
                    wz.folderCandidates = []
                    wz.error = body.error || qsTr("No se pudieron revisar los ejecutables de la carpeta.")
                }
                const found = wz.folderCandidates.length
                wz.note = found ? qsTr("Se encontraron %n ejecutable(s). Elige uno para añadirlo.", "", found)
                    : (n > 0 ? qsTr("Se detectaron %n juego(s) nuevos. No hay ejecutables sueltos para importar.", "", n)
                             : qsTr("No se encontraron juegos ni ejecutables compatibles en esa carpeta."))
                wz.step = 3
            })
        }
    }
    function chooseFile(path) {
        folderFlow = false; file = path; step = 2; busy = true; error = ""; note = qsTr("Identificando el archivo…")
        identity = ""; existingId = ""; matches = []; matchedQuery = ""; catalogSlug = ""; matching = false
        if (sel?.needs === "rom") {
            busy = false; recognized = false; name = baseName(path)
            note = qsTr("Revisa el nombre antes de añadirlo.")
            return
        }
        const requestedType = sel
        api.suggestGame(path, function(st, body) {
            if (wz.step !== 2 || wz.file !== path) return
            wz.busy = false
            if (st !== 200) {
                wz.recognized = false
                wz.error = body.error || qsTr("No se pudo identificar el archivo.")
                return
            }
            wz.sel = requestedType?.tpl && !body.template
                ? requestedType : { kind: body.kind, template: body.template || "", needs: "exe", platform: body.platform || "pc" }
            wz.name = body.name || wz.baseName(path)
            wz.recognized = !!body.recognized
            wz.existingId = body.existingId || ""
            wz.identity = api.identityLabel(body.identity)
            wz.note = wz.existingId ? qsTr("Este juego ya está en tu biblioteca.")
                : body.recognized ? qsTr("Reconocido como %1").arg(body.recognized) : qsTr("Revisa el nombre antes de añadirlo.")
        })
    }
    function confirm() {
        if (!sel || !name.trim() || busy) return
        if (existingId) { added(existingId); return }
        busy = true; error = ""
        const body = { name: name.trim() }
        if (sel.tpl || sel.template) body.template = sel.tpl || sel.template; else body.kind = sel.kind
        if (sel.platform) body.platform = sel.platform
        body[sel.needs === "rom" ? "rom" : "exe"] = file
        body.inspectExecutable = sel.needs === "exe"
        if (body.inspectExecutable && catalogSlug && matchedQuery === name.trim()) body.catalogSlug = catalogSlug
        api.addGame(body, function(st, b) {
            wz.busy = false
            if (st === 200) { wz.newId = b.id; wz.done = true }
            else wz.error = (b && b.error) || ("error " + st)
        })
    }
    function next() {
        if (step === 2 && !busy && !error) { step = 3; if (!identity) findMatches() }
        else if (step === 3 && !folderFlow && !done) confirm()
        else if (step === 3 && (folderFlow || done)) { if (folderFlow) finished(); else added(newId) }
    }
    function back() {
        if (done || (step === 3 && folderFlow)) { finished(); return }
        if (step === 3) { step = 2; return }
        if (step === 2) { step = 1; templateList = false; error = ""; return }
        if (templateList) { templateList = false; return }
        finished()
    }

    readonly property var kinds: tpls.map(function(t) {
        return { id: t.id, text: templateName(t.id, t.name), sub: t.needs === "rom" ? qsTr("Elige la ROM del juego") : qsTr("Elige el ejecutable del port"), needs: t.needs, ext: t.ext || [], tpl: t.id }
    }).concat([
        { id: "_win", text: qsTr("Juego de Windows (.exe) con Proton"), sub: qsTr("Omnia lo ejecuta con umu-launcher"), needs: "exe", ext: [".exe"], kind: "windows" }
    ])

    property bool started: false
    function start() {          // se llama cuando el anfitrión ya fijó `manager` y `api` (ver el Loader de OmniaManager)
        if (started || !api || !manager) return
        started = true
        api.templates(function(st, b) { if (st === 200) tpls = b.templates })
        api.importFind(function(st, b) { if (st === 200 && b.candidates && b.candidates.length > 0) legacyPath = b.candidates[0].path })
        forceActiveFocus()
    }
    onApiChanged: start()
    onManagerChanged: start()
    focus: true
    Keys.onPressed: function(e) {
        if (e.key === Qt.Key_Escape) { back(); e.accepted = true }
        else if ((e.key === Qt.Key_Return || e.key === Qt.Key_Enter) && step > 1 && !nameField.activeFocus) { next(); e.accepted = true }
    }

    FolderDialog { id: folderDialog; title: qsTr("Elige la carpeta de juegos"); onAccepted: wz.chooseFolder(wz.localPath(selectedFolder)) }
    FileDialog {
        id: fileDialog
        property var exts: []
        title: qsTr("Elige el archivo del juego")
        nameFilters: exts.length ? [qsTr("Archivos compatibles (%1)").arg(exts.map(function(x) { return "*" + x }).join(" ")), qsTr("Todos los archivos (*)")] : [qsTr("Todos los archivos (*)")]
        onAccepted: wz.chooseFile(wz.localPath(selectedFile))
    }
    function openFile(item) { sel = item; fileDialog.exts = item.ext || []; fileDialog.open() }

    Rectangle {
        anchors.fill: parent
        color: "#B8000000"
        MouseArea { anchors.fill: parent; onClicked: wz.back() }
    }
    Rectangle {
        id: card
        anchors.centerIn: parent
        width: Math.min(parent.width - wz.s * 80, wz.s * 700)
        height: Math.min(parent.height - wz.s * 80, wz.s * 560)
        radius: wz.s * 22
        color: manager.surface
        border.color: "#2effffff"
        clip: true
        MouseArea { anchors.fill: parent }

        // cabecera: título y pasos
        Item {
            id: head
            anchors { left: parent.left; right: parent.right; top: parent.top }
            height: wz.s * 92
            Text { x: wz.s * 28; y: wz.s * 20; text: qsTr("Añadir juego"); color: manager.ink; font.family: wz.font; font.pixelSize: wz.s * 22; font.weight: Font.DemiBold }
            Rectangle {
                anchors { right: parent.right; rightMargin: wz.s * 18; top: parent.top; topMargin: wz.s * 16 }
                width: wz.s * 34; height: width; radius: width / 2; color: xMa.containsMouse ? "#26FFFFFF" : "transparent"
                LucideIcon { anchors.centerIn: parent; width: wz.s * 18; height: width; name: "x"; color: manager.muted }
                MouseArea { id: xMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: wz.finished() }
            }
            Row {
                x: wz.s * 28; y: wz.s * 58
                spacing: wz.s * 10
                Repeater {
                    model: [qsTr("Origen"), qsTr("Detección"), qsTr("Confirmación")]
                    delegate: Row {
                        id: stp
                        required property string modelData
                        required property int index
                        readonly property bool on: wz.step === index + 1
                        readonly property bool past: wz.step > index + 1
                        spacing: wz.s * 8
                        Rectangle {
                            width: wz.s * 22; height: width; radius: width / 2; anchors.verticalCenter: parent.verticalCenter
                            color: stp.on ? manager.accent : (stp.past ? "#2E8B57" : manager.surface2)
                            Text { anchors.centerIn: parent; text: stp.past ? "✓" : (stp.index + 1); color: manager.ink; font.family: wz.font; font.pixelSize: wz.s * 12; font.weight: Font.DemiBold }
                        }
                        Text { anchors.verticalCenter: parent.verticalCenter; text: stp.modelData; color: stp.on ? manager.ink : manager.muted; font.family: wz.font; font.pixelSize: wz.s * 14; font.weight: stp.on ? Font.DemiBold : Font.Normal }
                        Rectangle { visible: stp.index < 2; width: wz.s * 26; height: 1; color: "#334352"; anchors.verticalCenter: parent.verticalCenter }
                    }
                }
            }
            Rectangle { anchors { left: parent.left; right: parent.right; bottom: parent.bottom } height: 1; color: "#1c2733" }
        }

        // cuerpo
        Item {
            anchors { left: parent.left; right: parent.right; top: head.bottom; bottom: foot.top; margins: wz.s * 26 }
            // paso 1: origen
            Column {
                visible: wz.step === 1 && !wz.templateList
                width: parent.width; spacing: wz.s * 10
                Text { width: parent.width; wrapMode: Text.WordWrap; text: qsTr("¿Qué quieres añadir? Steam, Heroic y Lutris se detectan solos."); color: manager.muted; font.family: wz.font; font.pixelSize: wz.s * 15 }
                Repeater {
                    model: [
                        { icon: "folder-open", t: qsTr("Carpeta de juegos"), d: qsTr("Omnia detecta solo los juegos y ROMs que haya dentro"), a: "folder" },
                        { icon: "hard-drive", t: qsTr("ROM de consola"), d: qsTr("Busca ROMs en una carpeta y elige emulador"), a: "roms" },
                        { icon: "gamepad-2", t: qsTr("Ejecutable o AppImage"), d: qsTr("Juego nativo, AppImage o .exe de Windows"), a: "exe" },
                        { icon: "plus", t: qsTr("Port o emulador compatible"), d: qsTr("Longshot, Gopher64, BedrockOnLinux y más"), a: "templates" },
                        { icon: "download", t: qsTr("Importar mi biblioteca anterior"), d: qsTr("Vista previa e importación de ports y emuladores"), a: "import", only: wz.legacyPath !== "" }
                    ].filter(function(x) { return x.only === undefined || x.only })
                    delegate: Rectangle {
                        id: opt
                        required property var modelData
                        width: parent.width; height: wz.s * 62; radius: wz.s * 14
                        color: optMa.containsMouse ? "#26FFFFFF" : manager.surface2
                        border.color: optMa.containsMouse ? "#5B9BE0" : "transparent"
                        scale: optMa.pressed ? 0.99 : 1
                        Behavior on color { ColorAnimation { duration: 120 } }
                        Row { anchors { left: parent.left; leftMargin: wz.s * 18; verticalCenter: parent.verticalCenter } spacing: wz.s * 14
                            LucideIcon { anchors.verticalCenter: parent.verticalCenter; width: wz.s * 24; height: width; name: opt.modelData.icon; color: "#9CC8F4" }
                            Column { anchors.verticalCenter: parent.verticalCenter; spacing: wz.s * 2
                                Text { text: opt.modelData.t; color: manager.ink; font.family: wz.font; font.pixelSize: wz.s * 17; font.weight: Font.DemiBold }
                                Text { text: opt.modelData.d; color: manager.muted; font.family: wz.font; font.pixelSize: wz.s * 13 } } }
                        MouseArea {
                            id: optMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                const a = opt.modelData.a
                                if (a === "folder") folderDialog.open()
                                else if (a === "roms") { wz.finished(); wz.manager.libraryAction("roms") }
                                else if (a === "exe") wz.openFile({ kind: "native", needs: "exe", ext: [] })
                                else if (a === "templates") wz.templateList = true
                                else if (a === "import") wz.importRequested(wz.legacyPath)
                            }
                        }
                    }
                }
            }
            ListView {
                visible: wz.step === 1 && wz.templateList
                anchors.fill: parent; clip: true; spacing: wz.s * 8; model: wz.kinds
                header: Text { width: parent.width; height: wz.s * 34; text: qsTr("Elige el tipo de juego"); color: manager.muted; font.family: wz.font; font.pixelSize: wz.s * 15 }
                delegate: Rectangle {
                    id: kd
                    required property var modelData
                    width: ListView.view.width; height: wz.s * 58; radius: wz.s * 12
                    color: kdMa.containsMouse ? "#26FFFFFF" : manager.surface2
                    Column { anchors { left: parent.left; leftMargin: wz.s * 18; verticalCenter: parent.verticalCenter } spacing: wz.s * 2
                        Text { text: kd.modelData.text; color: manager.ink; font.family: wz.font; font.pixelSize: wz.s * 15; font.weight: Font.DemiBold }
                        Text { text: kd.modelData.sub; color: manager.muted; font.family: wz.font; font.pixelSize: wz.s * 12 } }
                    MouseArea { id: kdMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: wz.openFile(kd.modelData) }
                }
            }
            // paso 2: detección
            Column {
                visible: wz.step === 2
                anchors.centerIn: parent; width: parent.width; spacing: wz.s * 14
                BusyIndicator { anchors.horizontalCenter: parent.horizontalCenter; running: wz.busy; visible: wz.busy; width: wz.s * 44; height: width }
                Text { width: parent.width; horizontalAlignment: Text.AlignHCenter; text: wz.file; elide: Text.ElideMiddle; visible: wz.file !== "" && !wz.folderFlow; color: manager.muted; font.family: wz.font; font.pixelSize: wz.s * 13 }
                Text { width: parent.width; horizontalAlignment: Text.AlignHCenter; wrapMode: Text.WordWrap; text: wz.error || wz.note
                    color: wz.error ? "#E8B86D" : (wz.recognized ? "#7fd69f" : manager.ink); font.family: wz.font; font.pixelSize: wz.s * 17 }
            }
            // paso 3: confirmación
            Column {
                visible: wz.step === 3
                width: parent.width; spacing: wz.s * 14
                Text { visible: wz.folderFlow || wz.done; width: parent.width; wrapMode: Text.WordWrap; text: wz.done ? qsTr("Añadido a la biblioteca.") : wz.note
                    color: "#7fd69f"; font.family: wz.font; font.pixelSize: wz.s * 18; font.weight: Font.DemiBold }
                Text { visible: !wz.folderFlow && !wz.done; text: qsTr("Nombre del juego"); color: manager.muted; font.family: wz.font; font.pixelSize: wz.s * 13 }
                TextField {
                    id: nameField
                    visible: !wz.folderFlow && !wz.done
                    width: parent.width; height: wz.s * 48
                    text: wz.name; onTextChanged: wz.name = text
                    color: manager.ink; font.family: wz.font; font.pixelSize: wz.s * 18
                    onAccepted: wz.confirm()
                    background: Rectangle { radius: wz.s * 12; color: manager.surface2; border.color: nameField.activeFocus ? "#5B9BE0" : "#24FFFFFF" }
                }
                Text { visible: !wz.folderFlow && !wz.done; width: parent.width; wrapMode: Text.WordWrap; text: wz.note; color: wz.recognized ? "#7fd69f" : manager.muted; font.family: wz.font; font.pixelSize: wz.s * 14 }
                Text { visible: !wz.done && wz.identity !== ""; width: parent.width; text: wz.identity; color: manager.muted; font.family: wz.font; font.pixelSize: wz.s * 14 }
                Row {
                    visible: !wz.folderFlow && !wz.done && !wz.existingId && wz.sel?.needs === "exe"
                    width: parent.width; spacing: wz.s * 10
                    Button {
                        text: wz.matching ? qsTr("Buscando juegos…") : qsTr("Buscar ficha")
                        enabled: !wz.matching && !wz.busy && wz.name.trim() !== ""
                        onClicked: wz.findMatches()
                    }
                    ComboBox {
                        id: matchPicker
                        width: parent.width - x
                        visible: wz.matches.length > 0 && wz.matchedQuery === wz.name.trim()
                        model: [qsTr("Añadir sin vincular")].concat(wz.matches.map(item => [item.name, api.manualMatchLabel(item)].filter(Boolean).join(" · ")))
                        onActivated: index => wz.catalogSlug = index > 0 ? wz.matches[index - 1].slug : ""
                        Connections { target: wz; function onMatchesChanged() { matchPicker.currentIndex = 0 } }
                    }
                }
                Text { visible: !wz.folderFlow && !wz.done; width: parent.width; text: wz.file; elide: Text.ElideMiddle; color: "#8495A8"; font.family: wz.font; font.pixelSize: wz.s * 12 }
                Text { visible: wz.folderFlow && wz.scanLimited; width: parent.width; wrapMode: Text.WordWrap
                    text: qsTr("Se muestran los primeros 80 ejecutables. Elige una subcarpeta para revisar más."); color: manager.muted; font.family: wz.font; font.pixelSize: wz.s * 12 }
                ListView {
                    visible: wz.folderFlow && wz.folderCandidates.length > 0
                    width: parent.width; height: Math.min(contentHeight, wz.s * 210)
                    model: wz.folderCandidates; clip: true; spacing: wz.s * 5
                    delegate: Rectangle {
                        required property var modelData
                        width: ListView.view.width; height: wz.s * 44; radius: wz.s * 9
                        color: candidateMouse.containsMouse ? "#263E5268" : manager.surface2
                        border.color: candidateMouse.containsMouse ? manager.accent : "#202E3A"
                        Row {
                            anchors.fill: parent; anchors.leftMargin: wz.s * 12; anchors.rightMargin: wz.s * 12; spacing: wz.s * 8
                            LucideIcon { anchors.verticalCenter: parent.verticalCenter; width: wz.s * 18; height: width; name: "gamepad-2"; color: "#9CC8F4" }
                            Column { anchors.verticalCenter: parent.verticalCenter; width: parent.width - wz.s * 44; spacing: wz.s * 1
                                Text { width: parent.width; text: modelData.name; elide: Text.ElideRight; color: manager.ink; font.family: wz.font; font.pixelSize: wz.s * 13 }
                                Text { width: parent.width; text: modelData.path; elide: Text.ElideMiddle; color: manager.muted; font.family: wz.font; font.pixelSize: wz.s * 10 }
                            }
                        }
                        MouseArea { id: candidateMouse; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                            onClicked: { wz.sel = {kind: modelData.kind, needs: "exe", ext: []}; wz.chooseFile(modelData.path) } }
                    }
                }
                Text { visible: wz.error !== ""; width: parent.width; wrapMode: Text.WordWrap; text: wz.error; color: "#E8B86D"; font.family: wz.font; font.pixelSize: wz.s * 14 }
            }
        }

        // pie con botones
        Item {
            id: foot
            anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
            height: wz.s * 70
            Rectangle { anchors { left: parent.left; right: parent.right; top: parent.top } height: 1; color: "#1c2733" }
            Rectangle {
                anchors { left: parent.left; leftMargin: wz.s * 26; verticalCenter: parent.verticalCenter }
                width: wz.s * 110; height: wz.s * 42; radius: wz.s * 12; color: backMa.containsMouse ? "#26FFFFFF" : manager.surface2
                visible: !(wz.step === 3 && (wz.done || wz.folderFlow))
                Text { anchors.centerIn: parent; text: wz.step === 1 && !wz.templateList ? qsTr("Cancelar") : qsTr("Atrás"); color: manager.ink; font.family: wz.font; font.pixelSize: wz.s * 15 }
                MouseArea { id: backMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: wz.back() }
            }
            Rectangle {
                id: primary
                visible: wz.step > 1
                readonly property bool ready: wz.step === 2 ? (!wz.busy && !wz.error && (wz.folderFlow || wz.name !== "" || wz.recognized || wz.note !== "")) : (wz.step === 3 ? (wz.folderFlow || wz.done || (wz.name.trim() !== "" && !wz.busy)) : false)
                anchors { right: parent.right; rightMargin: wz.s * 26; verticalCenter: parent.verticalCenter }
                width: wz.s * 190; height: wz.s * 42; radius: wz.s * 12
                color: ready ? (priMa.containsMouse ? Qt.lighter(manager.accent, 1.15) : manager.accent) : manager.surface2
                opacity: ready ? 1 : 0.55
                Text { anchors.centerIn: parent; color: manager.ink; font.family: wz.font; font.pixelSize: wz.s * 15; font.weight: Font.DemiBold
                    text: wz.step === 2 ? qsTr("Siguiente") : (wz.folderFlow ? qsTr("Terminar") : (wz.done || wz.existingId ? qsTr("Ver en la biblioteca") : qsTr("Añadir a la biblioteca"))) }
                MouseArea { id: priMa; anchors.fill: parent; enabled: primary.ready; hoverEnabled: true; cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor; onClicked: wz.next() }
            }
        }
    }
}

pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls
import QtQuick.Dialogs
import "Theme.js" as Theme

/** Asistente «Añadir juego» de la app de escritorio (entrega 4).
 *  1 Origen: una carpeta (o un archivo suelto). 2 Omnia revisa todo lo que hay dentro con `/add/scan`: ports conocidos,
 *  juegos de PC, ROMs y volcados, cada uno con su tipo ya decidido (no hay que elegir el port a mano).
 *  3 Lista con casillas y búsqueda por texto → «Añadir N». 4 Resultado: lo añadido, lo que falló y, si se añadió una ROM o un
 *  volcado, el port de ese juego si está en otra carpeta (`portsFound`); si no hay, la biblioteca ofrece «Instalar port».
 *  Ventana de cristal de escritorio, tamaños fijos de Theme. (Big Mode usa `AddGame.qml`, pensado para el mando.) */
FocusScope {
    id: wz
    property var manager: null
    property var api: null
    signal finished()
    signal added(string id)
    signal addedMany(int count)
    signal importRequested(string path)

    property string step: "source"          // source | scan | pick | done
    property string legacyPath: ""
    property string root: ""
    property string onlyKey: ""             // archivo suelto: solo se marca ese
    property var items: []
    property bool limited: false
    property var checked: ({})
    property string query: ""
    property string filter: "all"           // all | port | game | rom
    property int current: 0
    property bool busy: false
    property string error: ""
    property var result: null               // respuesta de /add/batch

    readonly property var visibleItems: {
        const q = query.trim().toLowerCase()
        return items.filter(function(it) {
            if (filter !== "all" && it.type !== filter) return false
            if (!q) return true
            return [it.name, it.systemName || "", it.recognized || "", it.fileName || it.path.split("/").pop()]
                .join(" ").toLowerCase().indexOf(q) >= 0
        })
    }
    readonly property var chosen: items.filter(function(it) { return wz.checked[it.key] && !it.existingId })
    readonly property int newCount: items.filter(function(it) { return !it.existingId }).length
    readonly property bool allVisibleOn: {
        const free = visibleItems.filter(function(it) { return !it.existingId })
        return free.length > 0 && free.every(function(it) { return wz.checked[it.key] })
    }
    function count(type) { return items.filter(function(it) { return type === "all" || it.type === type }).length }
    function typeLabel(type) { return type === "port" ? qsTr("Port") : type === "rom" ? qsTr("ROM") : qsTr("PC") }

    function localPath(url) { return decodeURIComponent(url.toString().replace(/^file:\/\//, "")) }
    function parentOf(p) { return p.substring(0, p.lastIndexOf("/")) || "/" }

    // ---- escaneo
    function scan(path, only) {
        root = path; onlyKey = only || ""; step = "scan"; busy = true; error = ""; items = []; checked = {}; query = ""; filter = "all"
        api.addScan(path, function(st, body) {
            if (st === 403) {           // fuera de las bibliotecas: se añade la carpeta como biblioteca y se vuelve a intentar
                api.setLibraryRoot("add", path, function(st2, b2) {
                    if (st2 !== 200) { wz.fail((b2 && b2.error) || qsTr("No se pudo usar esa carpeta.")); return }
                    if (wz.manager) wz.manager.libraryRoots = b2.roots || []
                    api.addScan(path, wz.scanned)
                })
                return
            }
            wz.scanned(st, body)
        })
    }
    function scanned(st, body) {
        if (step !== "scan") return
        busy = false
        if (st !== 200) { fail((body && body.error) || qsTr("No se pudo revisar esa carpeta.")); return }
        let list = body.items || []
        if (onlyKey) list = list.filter(function(it) { return it.key === onlyKey })
        items = list
        limited = !!body.limited
        const on = {}
        list.forEach(function(it) { if (!it.existingId) on[it.key] = true })   // todo lo nuevo, marcado
        checked = on
        current = 0
        step = "pick"
        if (onlyKey && !list.length) error = qsTr("Omnia no reconoce ese archivo como juego, port o ROM.")
        else if (!list.length) error = qsTr("No se encontraron juegos, ports ni ROMs en esa carpeta.")
        search.forceActiveFocus()
    }
    function fail(msg) { busy = false; error = msg; step = "pick"; items = [] }

    function toggle(it) {
        if (!it || it.existingId) return
        const next = Object.assign({}, checked)
        next[it.key] = !next[it.key]
        checked = next
    }
    function setVisible(on) {
        const next = Object.assign({}, checked)
        visibleItems.forEach(function(it) { if (!it.existingId) next[it.key] = on })
        checked = next
    }

    // ---- añadir
    function addChosen() {
        if (!chosen.length || busy) return
        busy = true; error = ""
        api.addBatch(chosen, root, function(st, body) {
            wz.busy = false
            if (st !== 200) { wz.error = (body && body.error) || qsTr("No se pudo añadir."); return }
            wz.result = body
            wz.step = "done"
        })
    }
    function addPort(port) {
        api.addBatch([port], root, function(st, body) {
            if (st === 200 && body.added && body.added.length) {
                const r = Object.assign({}, wz.result)
                r.added = r.added.concat(body.added)
                r.portsFound = r.portsFound.filter(function(p) { return p.path !== port.path })
                wz.result = r
            } else wz.error = (body && body.failed && body.failed[0] && body.failed[0].error) || qsTr("No se pudo añadir el port.")
        })
    }
    function close() {
        const ok = result ? result.added.filter(function(a) { return !a.existing }) : []
        if (ok.length === 1) added(ok[0].id)
        else if (ok.length > 1) addedMany(ok.length)
        else finished()
    }
    function back() {
        if (step === "done") { close(); return }
        if (step === "pick" || step === "scan") { step = "source"; error = ""; items = []; return }
        finished()
    }

    property bool started: false
    function start() {          // se llama cuando el anfitrión ya fijó `manager` y `api` (ver el Loader de OmniaManager)
        if (started || !api || !manager) return
        started = true
        api.importFind(function(st, b) { if (st === 200 && b.candidates && b.candidates.length > 0) wz.legacyPath = b.candidates[0].path })
        forceActiveFocus()
    }
    onApiChanged: start()
    onManagerChanged: start()
    focus: true
    Keys.onPressed: function(e) {
        if (e.key === Qt.Key_Escape) { if (search.activeFocus && query) query = ""; else back(); e.accepted = true; return }
        if (step !== "pick") {
            if (step === "done" && (e.key === Qt.Key_Return || e.key === Qt.Key_Enter)) { close(); e.accepted = true }
            return
        }
        if ((e.modifiers & Qt.ControlModifier) && e.key === Qt.Key_F) { search.forceActiveFocus(); search.selectAll(); e.accepted = true }
        else if ((e.modifiers & Qt.ControlModifier) && e.key === Qt.Key_A) { setVisible(!allVisibleOn); e.accepted = true }
        else if (e.key === Qt.Key_Down) { current = Math.min(visibleItems.length - 1, current + 1); list.forceActiveFocus(); e.accepted = true }
        else if (e.key === Qt.Key_Up) { current = Math.max(0, current - 1); if (current === 0) search.forceActiveFocus(); e.accepted = true }
        else if (e.key === Qt.Key_Space && !search.activeFocus) { toggle(visibleItems[current]); e.accepted = true }
        else if (e.key === Qt.Key_Return || e.key === Qt.Key_Enter) { addChosen(); e.accepted = true }
    }

    FolderDialog { id: folderDialog; title: qsTr("Elige la carpeta de juegos"); onAccepted: wz.scan(wz.localPath(selectedFolder)) }
    FileDialog {
        id: fileDialog
        title: qsTr("Elige el archivo del juego")
        nameFilters: [qsTr("Todos los archivos (*)")]
        onAccepted: { const p = wz.localPath(selectedFile); wz.scan(wz.parentOf(p), p) }
    }

    Rectangle {
        anchors.fill: parent
        color: "#B8000000"
        MouseArea { anchors.fill: parent; onClicked: wz.back() }
    }

    // ---- ventana
    Rectangle {
        id: stage
        anchors.centerIn: parent
        width: Math.min(parent.width - 64, wz.step === "source" ? 640 : 860)
        height: Math.min(parent.height - 64, wz.step === "source" ? (wz.legacyPath ? 400 : 340) : 680)
        radius: Theme.radius.xl
        color: "#FA0E1622"
        border.color: Theme.color.glassBorderStrong
        clip: true
        Behavior on width { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }
        Behavior on height { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }
        MouseArea { anchors.fill: parent }
        Rectangle { anchors { left: parent.left; right: parent.right; top: parent.top; leftMargin: parent.radius; rightMargin: parent.radius } height: 1; color: Theme.color.glassHighlight }

        // cabecera
        Item {
            id: head
            anchors { left: parent.left; right: parent.right; top: parent.top; leftMargin: 24; rightMargin: 16 }
            height: 72
            Column {
                anchors { left: parent.left; right: closeBtn.left; rightMargin: 12; verticalCenter: parent.verticalCenter }
                spacing: 2
                Text { text: wz.step === "done" ? qsTr("Listo") : qsTr("Añadir juego"); color: Theme.color.ink; font.family: Theme.font.family; font.pixelSize: Theme.font.size.heading - 4; font.weight: Font.DemiBold }
                Text {
                    width: parent.width; elide: Text.ElideMiddle
                    color: Theme.color.muted; font.family: Theme.font.family; font.pixelSize: Theme.font.size.small
                    text: wz.step === "source" ? qsTr("Steam, Epic, GOG, Heroic y Lutris se detectan solos.")
                        : wz.step === "done" ? qsTr("Arte y ficha se buscan solos por el nombre del juego.")
                        : wz.root
                }
            }
            Rectangle {
                id: closeBtn
                anchors { right: parent.right; verticalCenter: parent.verticalCenter }
                width: 32; height: 32; radius: 16; color: xMa.containsMouse ? Theme.color.glassFillStrong : "transparent"
                LucideIcon { anchors.centerIn: parent; width: 16; height: 16; name: "x"; color: Theme.color.muted }
                MouseArea { id: xMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: wz.step === "done" ? wz.close() : wz.finished() }
            }
            Rectangle { anchors { left: parent.left; right: parent.right; bottom: parent.bottom; rightMargin: 8 } height: 1; color: Theme.color.glassBorder }
        }

        // ---- 1 origen
        Column {
            visible: wz.step === "source"
            anchors { left: parent.left; right: parent.right; top: head.bottom; margins: 24 }
            spacing: 12
            Rectangle {
                id: folderCard
                width: parent.width; height: 150; radius: Theme.radius.lg
                color: fcMa.containsMouse ? Theme.color.accentSoft : Theme.color.glassFillSoft
                border.color: fcMa.containsMouse ? Theme.color.accent : Theme.color.glassBorder
                Behavior on color { ColorAnimation { duration: 120 } }
                Column {
                    anchors.centerIn: parent; spacing: 8; width: parent.width - 48
                    LucideIcon { anchors.horizontalCenter: parent.horizontalCenter; width: 34; height: 34; name: "folder-open"; color: Theme.color.accentLight }
                    Text { anchors.horizontalCenter: parent.horizontalCenter; text: qsTr("Elegir una carpeta"); color: Theme.color.ink; font.family: Theme.font.family; font.pixelSize: Theme.font.size.title; font.weight: Font.DemiBold }
                    Text { width: parent.width; horizontalAlignment: Text.AlignHCenter; wrapMode: Text.WordWrap; color: Theme.color.muted; font.family: Theme.font.family; font.pixelSize: Theme.font.size.small
                        text: qsTr("Omnia revisa la carpeta y sus subcarpetas: ports, juegos de PC, ROMs y volcados (NUP, exefs + romfs). Luego eliges cuáles añadir.") }
                }
                MouseArea { id: fcMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: folderDialog.open() }
            }
            Repeater {
                model: [
                    { icon: "gamepad-2", t: qsTr("Un solo archivo"), d: qsTr("Un ejecutable, AppImage, .exe o ROM concreto"), a: "file" },
                    { icon: "download", t: qsTr("Importar mi biblioteca anterior"), d: qsTr("Vista previa e importación de ports y emuladores"), a: "import", only: wz.legacyPath !== "" }
                ].filter(function(x) { return x.only === undefined || x.only })
                delegate: Rectangle {
                    id: opt
                    required property var modelData
                    width: parent.width; height: 56; radius: Theme.radius.md
                    color: optMa.containsMouse ? Theme.color.glassFillStrong : Theme.color.glassFillSoft
                    border.color: optMa.containsMouse ? Theme.color.glassBorderStrong : "transparent"
                    Row {
                        anchors { left: parent.left; leftMargin: 16; verticalCenter: parent.verticalCenter }
                        spacing: 14
                        LucideIcon { anchors.verticalCenter: parent.verticalCenter; width: 20; height: 20; name: opt.modelData.icon; color: Theme.color.accentLight }
                        Column { anchors.verticalCenter: parent.verticalCenter; spacing: 1
                            Text { text: opt.modelData.t; color: Theme.color.ink; font.family: Theme.font.family; font.pixelSize: Theme.font.size.bodyLarge; font.weight: Font.DemiBold }
                            Text { text: opt.modelData.d; color: Theme.color.muted; font.family: Theme.font.family; font.pixelSize: Theme.font.size.small } }
                    }
                    MouseArea { id: optMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                        onClicked: opt.modelData.a === "file" ? fileDialog.open() : wz.importRequested(wz.legacyPath) }
                }
            }
        }

        // ---- 2 revisando
        Column {
            visible: wz.step === "scan"
            anchors.centerIn: parent
            spacing: 14
            BusyIndicator { anchors.horizontalCenter: parent.horizontalCenter; running: wz.step === "scan"; width: 44; height: 44 }
            Text { anchors.horizontalCenter: parent.horizontalCenter; text: qsTr("Buscando juegos, ports y ROMs…"); color: Theme.color.ink; font.family: Theme.font.family; font.pixelSize: Theme.font.size.title }
        }

        // ---- 3 elegir
        Item {
            id: pick
            visible: wz.step === "pick"
            anchors { left: parent.left; right: parent.right; top: head.bottom; bottom: foot.top; leftMargin: 24; rightMargin: 24; topMargin: 16 }
            Row {
                id: tools
                width: parent.width; spacing: 10
                TextField {
                    id: search
                    width: parent.width - chips.width - 10; height: Theme.size.control
                    placeholderText: qsTr("Buscar por nombre, consola o archivo")
                    text: wz.query; onTextChanged: { wz.query = text; wz.current = 0 }
                    color: Theme.color.ink; placeholderTextColor: Theme.color.muted
                    font.family: Theme.font.family; font.pixelSize: Theme.font.size.body
                    leftPadding: 36
                    background: Rectangle { radius: Theme.radius.sm; color: Theme.color.inset; border.color: search.activeFocus ? Theme.color.accent : Theme.color.glassBorder
                        LucideIcon { x: 12; anchors.verticalCenter: parent.verticalCenter; width: 15; height: 15; name: "search"; color: Theme.color.muted } }
                }
                Row {
                    id: chips
                    spacing: 6
                    Repeater {
                        model: [{ id: "all", t: qsTr("Todo") }, { id: "port", t: qsTr("Ports") }, { id: "game", t: qsTr("PC") }, { id: "rom", t: qsTr("ROMs") }]
                            .filter(function(c) { return c.id === "all" || wz.count(c.id) > 0 })
                        delegate: Rectangle {
                            id: chip
                            required property var modelData
                            readonly property bool on: wz.filter === modelData.id
                            width: chipText.implicitWidth + 24; height: Theme.size.control; radius: Theme.radius.sm
                            color: on ? Theme.color.accentSoft : (chipMa.containsMouse ? Theme.color.glassFillStrong : Theme.color.glassFillSoft)
                            border.color: on ? Theme.color.accent : Theme.color.glassBorder
                            Text { id: chipText; anchors.centerIn: parent; text: chip.modelData.t + "  " + wz.count(chip.modelData.id)
                                color: chip.on ? Theme.color.accentLight : Theme.color.soft; font.family: Theme.font.family; font.pixelSize: Theme.font.size.small; font.weight: Font.DemiBold }
                            MouseArea { id: chipMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: { wz.filter = chip.modelData.id; wz.current = 0 } }
                        }
                    }
                }
            }
            // seleccionar todo lo visible
            Item {
                id: allRow
                anchors { left: parent.left; right: parent.right; top: tools.bottom; topMargin: 10 }
                height: 30
                visible: wz.items.length > 0
                Row {
                    anchors.verticalCenter: parent.verticalCenter; spacing: 10
                    CheckMark { anchors.verticalCenter: parent.verticalCenter; on: wz.allVisibleOn }
                    Text { anchors.verticalCenter: parent.verticalCenter; text: wz.allVisibleOn ? qsTr("Quitar todos") : qsTr("Marcar todos")
                        color: Theme.color.soft; font.family: Theme.font.family; font.pixelSize: Theme.font.size.small }
                }
                MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: wz.setVisible(!wz.allVisibleOn) }
                Text { anchors { right: parent.right; verticalCenter: parent.verticalCenter }
                    color: Theme.color.muted; font.family: Theme.font.family; font.pixelSize: Theme.font.size.small
                    text: qsTr("%1 de %2 nuevos marcados").arg(wz.chosen.length).arg(wz.newCount) }
            }
            ListView {
                id: list
                anchors { left: parent.left; right: parent.right; top: allRow.bottom; bottom: parent.bottom; topMargin: 6 }
                clip: true; spacing: 4
                model: wz.visibleItems
                currentIndex: wz.current
                boundsBehavior: Flickable.StopAtBounds
                ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }
                section.property: "type"
                section.delegate: Text {
                    required property string section
                    height: 30; verticalAlignment: Text.AlignBottom; bottomPadding: 4
                    text: section === "port" ? qsTr("Ports reconocidos") : section === "rom" ? qsTr("ROMs y volcados") : qsTr("Juegos de PC")
                    color: Theme.color.muted; font.family: Theme.font.family; font.pixelSize: Theme.font.size.caption; font.weight: Font.DemiBold; font.letterSpacing: 1.2
                }
                delegate: Rectangle {
                    id: row
                    required property var modelData
                    required property int index
                    readonly property bool on: !!wz.checked[modelData.key]
                    readonly property bool owned: !!modelData.existingId
                    readonly property bool focused: wz.current === index && list.activeFocus
                    width: ListView.view.width - 12; height: 52; radius: Theme.radius.sm
                    color: on ? Theme.color.accentSoft : (rowMa.containsMouse || focused ? Theme.color.glassFillStrong : Theme.color.glassFillSoft)
                    border.color: focused ? Theme.color.accent : (on ? "#664DA3FF" : "transparent")
                    opacity: owned ? 0.6 : 1
                    CheckMark { id: box; x: 14; anchors.verticalCenter: parent.verticalCenter; on: row.on; disabled: row.owned }
                    Column {
                        anchors { left: box.right; leftMargin: 14; right: tags.left; rightMargin: 12; verticalCenter: parent.verticalCenter }
                        spacing: 2
                        Text { width: parent.width; text: row.modelData.name; elide: Text.ElideRight; color: Theme.color.ink; font.family: Theme.font.family; font.pixelSize: Theme.font.size.body; font.weight: Font.DemiBold }
                        Text {
                            width: parent.width; elide: Text.ElideMiddle; color: Theme.color.muted; font.family: Theme.font.family; font.pixelSize: Theme.font.size.caption + 1
                            text: [row.modelData.type === "rom" ? row.modelData.systemName : (row.modelData.recognized || ""),
                                   row.modelData.fileName || row.modelData.path.split("/").pop()].filter(Boolean).join("  ·  ")
                        }
                    }
                    Row {
                        id: tags
                        anchors { right: parent.right; rightMargin: 14; verticalCenter: parent.verticalCenter }
                        spacing: 6
                        Tag { visible: row.owned; text: qsTr("Ya en tu biblioteca"); tone: "muted" }
                        Tag { visible: !row.owned && !!row.modelData.portKey; text: qsTr("Su port está en la carpeta"); tone: "ok" }
                        Tag { visible: !!row.modelData.dump; text: qsTr("Volcado"); tone: "muted" }
                        Tag { text: wz.typeLabel(row.modelData.type); tone: row.modelData.type === "port" ? "accent" : "muted" }
                    }
                    MouseArea { id: rowMa; anchors.fill: parent; hoverEnabled: true; cursorShape: row.owned ? Qt.ArrowCursor : Qt.PointingHandCursor
                        onClicked: { wz.current = row.index; wz.toggle(row.modelData) } }
                }
                Text {
                    anchors.centerIn: parent; width: parent.width - 40; horizontalAlignment: Text.AlignHCenter; wrapMode: Text.WordWrap
                    visible: wz.items.length > 0 && wz.visibleItems.length === 0
                    text: qsTr("Nada coincide con «%1».").arg(wz.query); color: Theme.color.muted; font.family: Theme.font.family; font.pixelSize: Theme.font.size.body
                }
            }
            Text {
                anchors.centerIn: parent; width: parent.width - 40; horizontalAlignment: Text.AlignHCenter; wrapMode: Text.WordWrap
                visible: wz.error !== "" && wz.items.length === 0
                text: wz.error; color: Theme.color.warning; font.family: Theme.font.family; font.pixelSize: Theme.font.size.bodyLarge
            }
        }

        // ---- 4 resultado
        Flickable {
            visible: wz.step === "done"
            anchors { left: parent.left; right: parent.right; top: head.bottom; bottom: foot.top; leftMargin: 24; rightMargin: 24; topMargin: 18 }
            clip: true; contentHeight: doneCol.implicitHeight; boundsBehavior: Flickable.StopAtBounds
            Column {
                id: doneCol
                width: parent.width; spacing: 10
                readonly property var res: wz.result || ({ added: [], failed: [], portsFound: [] })
                readonly property var fresh: res.added.filter(function(a) { return !a.existing })
                Row {
                    spacing: 12
                    Rectangle { width: 40; height: 40; radius: 20; color: "#337EE0A1"; anchors.verticalCenter: parent.verticalCenter
                        LucideIcon { anchors.centerIn: parent; width: 20; height: 20; name: "check"; color: Theme.color.ok } }
                    Text { anchors.verticalCenter: parent.verticalCenter; color: Theme.color.ink; font.family: Theme.font.family; font.pixelSize: Theme.font.size.title; font.weight: Font.DemiBold
                        text: doneCol.fresh.length === 1 ? qsTr("Se añadió 1 juego a la biblioteca.")
                            : doneCol.fresh.length ? qsTr("Se añadieron %1 juegos a la biblioteca.").arg(doneCol.fresh.length)
                            : qsTr("No se añadió ningún juego nuevo.") }
                }
                Text { width: parent.width; wrapMode: Text.WordWrap; visible: doneCol.fresh.length > 0
                    text: doneCol.fresh.map(function(a) { return a.name }).join(" · "); color: Theme.color.soft; font.family: Theme.font.family; font.pixelSize: Theme.font.size.small }

                // ports de las ROMs añadidas
                Text { visible: doneCol.res.portsFound.length > 0; topPadding: 10; text: qsTr("Encontramos el port de lo que añadiste")
                    color: Theme.color.muted; font.family: Theme.font.family; font.pixelSize: Theme.font.size.caption; font.weight: Font.DemiBold; font.letterSpacing: 1.2 }
                Repeater {
                    model: doneCol.res.portsFound
                    delegate: Rectangle {
                        id: pf
                        required property var modelData
                        width: doneCol.width; height: 56; radius: Theme.radius.sm; color: Theme.color.glassFillSoft; border.color: Theme.color.glassBorder
                        Column { anchors { left: parent.left; leftMargin: 14; right: pfBtn.left; rightMargin: 12; verticalCenter: parent.verticalCenter } spacing: 2
                            Text { width: parent.width; elide: Text.ElideRight; text: pf.modelData.name + "  ·  " + pf.modelData.recognized; color: Theme.color.ink; font.family: Theme.font.family; font.pixelSize: Theme.font.size.body; font.weight: Font.DemiBold }
                            Text { width: parent.width; elide: Text.ElideMiddle; text: pf.modelData.path; color: Theme.color.muted; font.family: Theme.font.family; font.pixelSize: Theme.font.size.caption + 1 } }
                        Rectangle { id: pfBtn; anchors { right: parent.right; rightMargin: 10; verticalCenter: parent.verticalCenter }
                            width: pfText.implicitWidth + 28; height: 32; radius: Theme.radius.sm; color: pfMa.containsMouse ? Theme.color.accentLight : Theme.color.accent
                            Text { id: pfText; anchors.centerIn: parent; text: qsTr("Añadir port"); color: Theme.color.accentInk; font.family: Theme.font.family; font.pixelSize: Theme.font.size.small; font.weight: Font.DemiBold }
                            MouseArea { id: pfMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: wz.addPort(pf.modelData) } }
                    }
                }
                Text { width: parent.width; wrapMode: Text.WordWrap; topPadding: 6
                    visible: doneCol.res.added.some(function(a) { return a.type === "rom" })
                    text: qsTr("Si una ROM o un volcado tiene un port publicado en el catálogo, su ficha en la biblioteca mostrará «Instalar port».")
                    color: Theme.color.muted; font.family: Theme.font.family; font.pixelSize: Theme.font.size.small }

                // fallos
                Text { visible: doneCol.res.failed.length > 0; topPadding: 10; text: qsTr("No se pudieron añadir")
                    color: Theme.color.warning; font.family: Theme.font.family; font.pixelSize: Theme.font.size.caption; font.weight: Font.DemiBold; font.letterSpacing: 1.2 }
                Repeater {
                    model: doneCol.res.failed
                    delegate: Text {
                        required property var modelData
                        width: doneCol.width; wrapMode: Text.WordWrap
                        text: (modelData.name || modelData.path) + " — " + modelData.error
                        color: Theme.color.soft; font.family: Theme.font.family; font.pixelSize: Theme.font.size.small
                    }
                }
                Text { visible: wz.error !== ""; width: parent.width; wrapMode: Text.WordWrap; text: wz.error; color: Theme.color.warning; font.family: Theme.font.family; font.pixelSize: Theme.font.size.small }
            }
        }

        // ---- pie
        Item {
            id: foot
            visible: wz.step === "pick" || wz.step === "done"
            anchors { left: parent.left; right: parent.right; bottom: parent.bottom; leftMargin: 24; rightMargin: 24 }
            height: 68
            Rectangle { anchors { left: parent.left; right: parent.right; top: parent.top } height: 1; color: Theme.color.glassBorder }
            Text {
                anchors { left: parent.left; right: buttons.left; rightMargin: 16; verticalCenter: parent.verticalCenter }
                elide: Text.ElideRight; color: wz.error && wz.step === "pick" && wz.items.length ? Theme.color.warning : Theme.color.muted
                font.family: Theme.font.family; font.pixelSize: Theme.font.size.small
                text: wz.step === "done" ? qsTr("Enter cierra")
                    : (wz.error && wz.items.length ? wz.error
                    : wz.limited ? qsTr("La carpeta es muy grande: se muestra una parte. Elige una subcarpeta para ver el resto.")
                    : qsTr("Clic o Espacio marca · Ctrl+F busca · Ctrl+A marca todos · Esc vuelve"))
            }
            Row {
                id: buttons
                anchors { right: parent.right; verticalCenter: parent.verticalCenter }
                spacing: 10
                Rectangle {
                    visible: wz.step === "pick"
                    width: backText.implicitWidth + 32; height: Theme.size.control; radius: Theme.radius.sm
                    color: backMa.containsMouse ? Theme.color.glassFillStrong : Theme.color.inset; border.color: Theme.color.glassBorder
                    Text { id: backText; anchors.centerIn: parent; text: qsTr("Atrás"); color: Theme.color.ink; font.family: Theme.font.family; font.pixelSize: Theme.font.size.body }
                    MouseArea { id: backMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: wz.back() }
                }
                Rectangle {
                    id: primary
                    readonly property bool ready: wz.step === "done" || (wz.chosen.length > 0 && !wz.busy)
                    width: Math.max(150, primaryText.implicitWidth + 36); height: Theme.size.control; radius: Theme.radius.sm
                    color: ready ? (priMa.containsMouse ? Theme.color.accentLight : Theme.color.accent) : Theme.color.inset
                    opacity: ready ? 1 : 0.6
                    Text {
                        id: primaryText; anchors.centerIn: parent
                        color: primary.ready ? Theme.color.accentInk : Theme.color.muted; font.family: Theme.font.family; font.pixelSize: Theme.font.size.body; font.weight: Font.DemiBold
                        text: wz.step === "done" ? (doneCol.fresh.length === 1 ? qsTr("Ver en la biblioteca") : qsTr("Terminar"))
                            : wz.busy ? qsTr("Añadiendo…") : qsTr("Añadir %1").arg(wz.chosen.length)
                    }
                    MouseArea { id: priMa; anchors.fill: parent; enabled: primary.ready; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                        onClicked: wz.step === "done" ? wz.close() : wz.addChosen() }
                }
            }
        }
    }

    // casilla de verificación de escritorio
    component CheckMark: Rectangle {
        property bool on: false
        property bool disabled: false
        width: 20; height: 20; radius: 6
        color: on ? Theme.color.accent : "transparent"
        border.color: on ? Theme.color.accent : (disabled ? Theme.color.glassBorder : Theme.color.muted)
        border.width: 1.5
        opacity: disabled ? 0.5 : 1
        LucideIcon { anchors.centerIn: parent; visible: parent.on; width: 14; height: 14; name: "check"; color: Theme.color.accentInk }
    }
    component Tag: Rectangle {
        property alias text: label.text
        property string tone: "muted"
        width: label.implicitWidth + 16; height: 22; radius: 11
        color: tone === "accent" ? Theme.color.accentSoft : tone === "ok" ? "#267EE0A1" : Theme.color.glassFill
        Text { id: label; anchors.centerIn: parent; font.family: Theme.font.family; font.pixelSize: Theme.font.size.caption; font.weight: Font.DemiBold
            color: parent.tone === "accent" ? Theme.color.accentLight : parent.tone === "ok" ? Theme.color.ok : Theme.color.soft }
    }
}

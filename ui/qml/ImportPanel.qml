import QtQuick

// Importar la biblioteca anterior (Bazzite): vista previa de lo que se añade y de lo que se omite, y luego aplicar.
FocusScope {
    id: ip
    property var api
    property string path: ""
    signal finished
    signal imported(int count)

    property var plan: null
    property string note: ""
    property bool busy: false
    readonly property int nNew: plan ? plan.summary.new : 0

    function load() {
        api.importPreview(path, function (st, b) {
            if (st === 200) { plan = b; list.reset() }          // el cursor vuelve a «Importar» ahora que está activa
            else note = b.error || qsTr("Error %1").arg(st)
        })
    }
    readonly property var rows: [
        { text: busy ? qsTr("Importando…") : (nNew > 0 ? qsTr("Importar %1 juegos").arg(nNew) : qsTr("No hay nada nuevo que importar")),
          sub: nNew > 0 ? qsTr("Se añaden a tu biblioteca; no se toca nada más") : "", accent: nNew > 0, disabled: nNew === 0 || busy },
        { text: qsTr("Cancelar") }]

    function run(i) {
        if (i === 1) { ip.finished(); return }
        busy = true
        api.importApply(path, function (st, b) {
            busy = false
            if (st === 200) { note = qsTr("Importados: %1").arg(b.count); plan = null; ip.imported(b.count) }      // se vacía la lista antes de cerrar
            else note = b.error || qsTr("Error %1").arg(st)
        })
    }
    function mark(status) { return status === "new" ? "plus" : (status === "existing" ? "check" : "minus") }
    function color(status) { return status === "new" ? "#7fd69f" : (status === "existing" ? "#c9bf8a" : "#8c8560") }

    Component.onCompleted: { load(); forceActiveFocus() }
    focus: true
    Keys.onPressed: function (e) {
        if (e.key === Qt.Key_Down) { list.moveSelection(1); e.accepted = true }
        else if (e.key === Qt.Key_Up) { list.moveSelection(-1); e.accepted = true }
        else if (e.key === Qt.Key_Return || e.key === Qt.Key_Enter) { list.activate(); e.accepted = true }
        else if (e.key === Qt.Key_PageDown) { items.contentY = Math.min(items.contentHeight - items.height, items.contentY + items.height * 0.8); e.accepted = true }
        else if (e.key === Qt.Key_PageUp) { items.contentY = Math.max(0, items.contentY - items.height * 0.8); e.accepted = true }
        else if (e.key === Qt.Key_Escape) { ip.finished(); e.accepted = true }
    }
    Connections {
        target: ip.api
        function onPadKey(key) {
            if (key === "d") list.moveSelection(1); else if (key === "u") list.moveSelection(-1)
            else if (key === "A") list.activate(); else if (key === "B") ip.finished()
            else if (key === "RB") items.contentY = Math.min(Math.max(0, items.contentHeight - items.height), items.contentY + items.height * 0.8)
            else if (key === "LB") items.contentY = Math.max(0, items.contentY - items.height * 0.8)
        }
    }

    Modal {
        anchors.fill: parent
        title: qsTr("Importar mi biblioteca anterior")
        footer: "↑↓ elegir  ·  Enter/A aceptar  ·  LB/RB o RePág/AvPág: desplazar la lista  ·  Esc/B cancelar"
        onCloseRequested: ip.finished()
        Column {
            anchors.fill: parent
            spacing: 10
            Text { width: parent.width; wrapMode: Text.WordWrap; color: "#c9bf8a"; font.pixelSize: 16
            text: ip.plan ? qsTr("%1 nuevos · %2 ya importados · %3 omitidos").arg(ip.plan.summary.new).arg(ip.plan.summary.existing).arg(ip.plan.summary.skip) : qsTr("Leyendo la biblioteca…") }
            Repeater { model: ip.plan ? ip.plan.warnings : []
                       Text { required property string modelData; width: parent.width; wrapMode: Text.WordWrap; text: "⚠ " + modelData; color: "#e6c27a"; font.pixelSize: 15 } }
            Text { visible: ip.note !== ""; width: parent.width; wrapMode: Text.WordWrap; text: ip.note; color: "#7fd69f"; font.pixelSize: 16 }
            OptionList { id: list; width: parent.width; height: 120; items: ip.rows; onActivated: function (i) { ip.run(i) } }
            ListView {
                id: items
                width: parent.width; height: parent.height - y; clip: true; spacing: 2
                model: ip.plan ? ip.plan.items : []
                delegate: Item {
                    required property var modelData
                    width: items.width; height: 30
                    LucideIcon { x: 8; anchors.verticalCenter: parent.verticalCenter; name: ip.mark(parent.modelData.status); color: ip.color(parent.modelData.status) }
                    Text { x: 40; anchors.verticalCenter: parent.verticalCenter; width: parent.width * 0.42; elide: Text.ElideRight
                           text: parent.modelData.name; color: ip.color(parent.modelData.status); font.pixelSize: 16 }
                    Text { x: parent.width * 0.46 + 30; anchors.verticalCenter: parent.verticalCenter; width: parent.width * 0.54 - 40; elide: Text.ElideRight
                           text: parent.modelData.status === "new" ? parent.modelData.src + (parent.modelData.hasSaves ? "  ·  con carpeta de partidas" : "") : parent.modelData.reason
                           color: "#a89f74"; font.pixelSize: 14 }
                }
            }
        }
    }
}

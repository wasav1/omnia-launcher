pragma ComponentBehavior: Bound

import QtQuick

/** Descargas de Big Mode: lo que se descarga o instala ahora y lo que falló. Se maneja con mando:
 *  ↑/↓ elegir · A acción principal (pausar/reanudar, reintentar, abrir ficha) · X cancelar o descartar · Y descartar las fallidas · B volver.
 *  Un éxito se quita solo a los pocos segundos; un fallo se queda hasta que se descarte. */
Item {
    id: dl
    required property var host
    signal back()
    readonly property real s: dl.host.s
    property int index: 0
    property string selectedJobId: ""
    function selectRow(row) {
        index = Math.max(0, Math.min(Math.max(0, rows.length - 1), row))
        selectedJobId = rows[index]?.id || ""
    }
    onRowsChanged: {
        const keep = rows.findIndex(job => job.id === selectedJobId)
        selectRow(keep < 0 ? index : keep)
    }
    readonly property var jobs: host.dlJobs
    readonly property var running: jobs.filter(function(j) { return ["queued", "downloading", "verifying", "extracting", "finalizing", "paused"].indexOf(j.status) >= 0 })
    readonly property var failed: jobs.filter(function(j) { return ["failed", "cancelled", "interrupted"].indexOf(j.status) >= 0 })
    readonly property var done: jobs.filter(function(j) { return j.status === "completed" })
    readonly property var rows: running.filter(j => j.status !== "queued").concat(running.filter(j => j.status === "queued"), failed, done)
    readonly property var monitoredJob: current || rows[0] || null
    function canPause(job) { return !!job && !job.external && job.kind !== "store"
        && ["queued", "paused", "downloading", "extracting"].includes(job.status) }
    function canCancel(job) { return !!job && !job.external && isBusy(job) && job.status !== "finalizing" }
    readonly property var current: rows.length > 0 ? rows[Math.max(0, Math.min(index, rows.length - 1))] : null

    function isBusy(j) { return !!j && ["queued", "downloading", "verifying", "extracting", "finalizing", "paused"].indexOf(j.status) >= 0 }
    function isBad(j) { return !!j && ["failed", "cancelled", "interrupted"].indexOf(j.status) >= 0 }
    function statusLabel(status) {
        const names = { queued: qsTr("En cola"), downloading: qsTr("Descargando"), verifying: qsTr("Verificando"), extracting: qsTr("Extrayendo"),
                        finalizing: qsTr("Finalizando"), paused: qsTr("En pausa"), failed: qsTr("Falló"), cancelled: qsTr("Cancelada"),
                        interrupted: qsTr("Interrumpida"), completed: qsTr("Instalado") }
        return names[status] || status
    }
    function load() {
        dl.host.pollDownloads()
    }
    function after(st, body) {
        if (st !== 200 && body && body.error) dl.host.api.notify(body.error)
        dl.load()
    }
    function primary() {
        const j = current
        if (!j) return
        if (j.external) Qt.openUrlExternally("steam://nav/downloads")
        else if (canPause(j)) (j.status === "paused" ? dl.host.api.resumeInstallation : dl.host.api.pauseInstallation)(j.id, dl.after)
        else if (isBad(j) && j.kind === "store") dl.host.openStore()
        else if (isBad(j)) dl.host.api.retryInstallation(j.id, dl.after)
        else if (j.status === "completed" && j.gameId) { dl.host.selectById(j.gameId); dl.back() }
    }
    function secondary() {
        const j = current
        if (!j || j.external) return
        if (canCancel(j)) dl.host.api.cancelInstallation(j.id, dl.after)
        else if (isBad(j)) dl.host.api.dismissInstallations(j.id, dl.after)
    }
    function pad(k) {
        if (k === "u") selectRow(index - 1)
        else if (k === "d") selectRow(index + 1)
        else if (k === "A") primary()
        else if (k === "X") secondary()
        else if (k === "Y" && failed.length > 0) dl.host.api.dismissInstallations(true, dl.after)
        else if (k === "B" || k === "START") back()
    }
    function key(e) {
        dl.host.keySound(e)
        if (e.key === Qt.Key_Up) pad("u")
        else if (e.key === Qt.Key_Down) pad("d")
        else if (e.key === Qt.Key_Return || e.key === Qt.Key_Enter) pad("A")
        else if (e.key === Qt.Key_Delete || e.key === Qt.Key_X) pad("X")
        else if (e.key === Qt.Key_Escape || e.key === Qt.Key_Backspace) pad("B")
        else return false
        return true
    }
    Keys.onPressed: function(e) { e.accepted = dl.key(e) }
    onVisibleChanged: if (visible) { selectRow(0); load() }
    Timer { interval: 1200; repeat: true; running: dl.visible; triggeredOnStart: true; onTriggered: dl.load() }

    Rectangle { anchors.fill: parent; color: dl.host.pageShade }
    Rectangle {
        id: backB
        x: dl.s * 48; y: dl.s * 30
        width: bRow.implicitWidth + dl.s * 44; height: dl.s * 54; radius: height / 2
        color: Qt.rgba(0.05, 0.08, 0.12, 0.70); border.width: 1; border.color: Qt.rgba(1, 1, 1, 0.26)
        Row {
            id: bRow; anchors.centerIn: parent; spacing: dl.s * 10
            LucideIcon { width: dl.s * 26; height: dl.s * 26; name: "chevron-left"; color: dl.host.ink; anchors.verticalCenter: parent.verticalCenter }
            Text { text: qsTr("Volver"); color: dl.host.ink; font.family: dl.host.uiFont; font.pixelSize: dl.s * 24; anchors.verticalCenter: parent.verticalCenter }
        }
        MouseArea { anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: dl.back() }
    }
    Text { anchors { left: backB.right; leftMargin: dl.s * 22; verticalCenter: backB.verticalCenter } text: qsTr("Descargas"); color: dl.host.ink; font.family: dl.host.uiFont; font.pixelSize: dl.s * 40; font.weight: Font.Medium }

    TransferMonitor {
        id: monitor
        anchors { left: list.left; right: list.right; top: backB.bottom; topMargin: dl.s * 14 }
        job: dl.monitoredJob
        uiScale: dl.s * 1.10
        ink: dl.host.ink; muted: dl.host.ink2; accent: dl.host.ring
        api: dl.host.api
        readonly property var game: (api.games || []).find(game => game.id === job?.gameId)
        artwork: game?.fondo || game?.portada || ""
    }
    Text {
        id: queueTitle
        visible: !!dl.monitoredJob
        anchors { left: monitor.left; top: monitor.bottom; topMargin: dl.s * 12 }
        text: qsTr("Cola de descargas e instalaciones") + " · " + dl.running.filter(j => j.status === "queued").length
        font.pixelSize: dl.s * 21; font.weight: Font.DemiBold; color: dl.host.ink
    }
    ListView {
        id: list
        anchors { left: parent.left; right: parent.right; top: queueTitle.visible ? queueTitle.bottom : backB.bottom; bottom: hints.top; leftMargin: dl.s * 48; rightMargin: dl.s * 48; topMargin: dl.s * 26; bottomMargin: dl.s * 16 }
        clip: true; spacing: dl.s * 12
        model: dl.rows
        currentIndex: dl.index
        highlightMoveDuration: 120
        delegate: Rectangle {
            id: card
            required property var modelData
            required property int index
            readonly property bool sel: index === dl.index
            readonly property bool bad: dl.isBad(modelData)
            width: ListView.view.width; height: dl.s * 112; radius: dl.s * 20
            color: sel ? dl.host.surfaceFocus : dl.host.surface
            border.width: sel ? 2 : 1
            border.color: sel ? dl.host.accent : (bad ? "#6A3F3F" : (modelData.status === "completed" ? "#2E6B4A" : Qt.rgba(1, 1, 1, 0.10)))
            Column {
                anchors { left: parent.left; right: parent.right; verticalCenter: parent.verticalCenter; leftMargin: dl.s * 28; rightMargin: dl.s * 28 }
                spacing: dl.s * 10
                Text { width: parent.width; elide: Text.ElideRight; color: dl.host.ink; font.family: dl.host.uiFont; font.pixelSize: dl.s * 25; font.weight: Font.DemiBold
                       text: card.modelData.name + (card.modelData.external ? "  ·  Steam" : "") + "  ·  " + dl.statusLabel(card.modelData.status) }
                Rectangle {
                    visible: !card.bad
                    width: parent.width; height: dl.s * 9; radius: height / 2; color: Qt.rgba(1, 1, 1, 0.10)
                    Rectangle { width: parent.width * Math.max(0, Math.min(1, Number(card.modelData.progress || 0) / 100)); height: parent.height; radius: height / 2
                                color: card.modelData.status === "completed" ? "#4FBF86" : dl.host.accent; Behavior on width { NumberAnimation { duration: 200 } } }
                }
                Text { width: parent.width; elide: Text.ElideRight; color: card.bad ? "#E8B86D" : dl.host.ink2; font.family: dl.host.uiFont; font.pixelSize: dl.s * 18
                       text: card.bad ? (card.modelData.error || qsTr("No terminó.")) : (card.modelData.destination || "") }
            }
            MouseArea { anchors.fill: parent; onClicked: dl.selectRow(card.index); onDoubleClicked: { dl.selectRow(card.index); dl.primary() } }
        }
    }
    Text {
        visible: dl.rows.length === 0
        anchors.centerIn: parent; width: parent.width * 0.6; horizontalAlignment: Text.AlignHCenter; wrapMode: Text.WordWrap
        color: dl.host.ink2; font.family: dl.host.uiFont; font.pixelSize: dl.s * 28
        text: qsTr("No hay descargas en curso. Lo que instales aparecerá aquí; al terminar con éxito se quita solo.")
    }
    Row {
        id: hints
        anchors { left: parent.left; right: parent.right; bottom: parent.bottom; leftMargin: dl.s * 48; bottomMargin: dl.s * 28 }
        spacing: dl.s * 34
        Text {
            visible: !!dl.current && (dl.current.external || dl.canPause(dl.current) || dl.isBad(dl.current) || dl.current.status === "completed")
            color: dl.host.ink2; font.family: dl.host.uiFont; font.pixelSize: dl.s * 21
            text: !dl.current ? "" : dl.current.external ? qsTr("A  %1").arg(qsTr("Abrir descargas de Steam"))
                : dl.canPause(dl.current) ? qsTr("A  %1").arg(dl.current.status === "paused" ? qsTr("Reanudar") : qsTr("Pausar"))
                : dl.isBad(dl.current) ? qsTr("A  %1").arg(dl.current.kind === "store" ? qsTr("Abrir tienda") : qsTr("Reintentar"))
                : qsTr("A  Abrir ficha")
        }
        Text {
            visible: dl.canCancel(dl.current) || dl.isBad(dl.current)
            color: dl.host.ink2; font.family: dl.host.uiFont; font.pixelSize: dl.s * 21
            text: dl.canCancel(dl.current) ? qsTr("X  Cancelar") : qsTr("X  Descartar")
        }
        Text { visible: dl.failed.length > 0; color: dl.host.ink2; font.family: dl.host.uiFont; font.pixelSize: dl.s * 21; text: qsTr("Y  Descartar las fallidas (%1)").arg(dl.failed.length) }
        Text { color: dl.host.ink2; font.family: dl.host.uiFont; font.pixelSize: dl.s * 21; text: qsTr("B  Volver") }
    }
}

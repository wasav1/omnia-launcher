import QtQuick

// Descargas e instalaciones de la app de escritorio. Pantalla propia con dos pestañas:
//  · En curso: lo que se descarga o instala ahora, y lo que falló (con Reintentar y Descartar). Un éxito se quita solo a los pocos segundos.
//  · Instalados: los paquetes que Omnia instaló, con Actualizar, Abrir ficha y Quitar.
Item {
    id: dl
    property var manager
    property var api
    property string tab: "active"                       // active | installed
    readonly property real s: manager ? manager.s : 1
    readonly property var jobs: manager ? manager.installJobs : []
    readonly property var running: jobs.filter(function(j) { return ["queued", "downloading", "verifying", "extracting", "finalizing", "paused"].indexOf(j.status) >= 0 })
    readonly property var failed: jobs.filter(function(j) { return ["failed", "cancelled", "interrupted"].indexOf(j.status) >= 0 })
    readonly property var done: jobs.filter(function(j) { return j.status === "completed" })
    readonly property var activeList: running.filter(j => j.status !== "queued").concat(running.filter(j => j.status === "queued"), failed, done)
    property string highlightedJobId: ""
    readonly property var monitoredJob: activeList.find(j => j.id === highlightedJobId) || activeList[0] || null
    readonly property var installedList: manager ? manager.installedPackages : []

    function statusLabel(status) {
        const names = { queued: qsTr("En cola"), downloading: qsTr("Descargando"), verifying: qsTr("Verificando"), extracting: qsTr("Extrayendo"),
                        finalizing: qsTr("Finalizando"), paused: qsTr("En pausa"), failed: qsTr("Falló"), cancelled: qsTr("Cancelada"),
                        interrupted: qsTr("Interrumpida"), completed: qsTr("Instalado") }
        return names[status] || status
    }
    function gameOf(id) { return (api.games || []).find(function(g) { return g.id === id }) || null }
    function refresh() { manager.loadInstallations() }

    Text { x: dl.s * 32; y: dl.s * 22; text: qsTr("Descargas"); color: manager.ink; font.family: "Hanken Grotesk"; font.pixelSize: dl.s * 28; font.weight: Font.Bold }
    Text { x: dl.s * 32; y: dl.s * 58; text: qsTr("Sigue instalaciones y gestiona los juegos de Omnia."); color: manager.muted; font.family: "Hanken Grotesk"; font.pixelSize: dl.s * 13 }

    // ---- pestañas
    Row {
        id: tabs
        anchors { left: parent.left; top: parent.top; leftMargin: dl.s * 32; topMargin: dl.s * 88 }
        spacing: dl.s * 10
        Repeater {
            model: [{ key: "active", label: qsTr("En curso"), n: dl.running.length + dl.failed.length },
                    { key: "installed", label: qsTr("Instalados"), n: dl.installedList.length }]
            delegate: Rectangle {
                id: chip
                required property var modelData
                readonly property bool on: dl.tab === modelData.key
                width: chipText.implicitWidth + dl.s * 34; height: dl.s * 38; radius: height / 2
                color: on ? "#45CFC9" : (chipMa.containsMouse ? manager.surface2 : manager.surface)
                Text { id: chipText; anchors.centerIn: parent; text: chip.modelData.label + (chip.modelData.n > 0 ? "  " + chip.modelData.n : "")
                       color: chip.on ? "#0B0F14" : manager.ink; font.family: "Hanken Grotesk"; font.pixelSize: dl.s * 14; font.weight: Font.DemiBold }
                MouseArea { id: chipMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: dl.tab = chip.modelData.key }
            }
        }
    }
    Rectangle {          // descartar todos los que no salieron bien
        visible: dl.tab === "active" && dl.failed.length > 0
        anchors { right: parent.right; rightMargin: dl.s * 32; verticalCenter: tabs.verticalCenter }
        width: clearText.implicitWidth + dl.s * 34; height: dl.s * 38; radius: height / 2; color: "#50343A"
        Text { id: clearText; anchors.centerIn: parent; text: qsTr("Descartar %1 fallidas").arg(dl.failed.length); color: manager.ink; font.family: "Hanken Grotesk"; font.pixelSize: dl.s * 13 }
        MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: dl.api.dismissInstallations(true, function() { dl.refresh() }) }
    }

    TransferMonitor {
        id: monitor
        visible: dl.tab === "active" && !!job
        anchors { left: parent.left; right: parent.right; top: tabs.bottom; margins: dl.s * 32; topMargin: dl.s * 12 }
        job: dl.monitoredJob
        uiScale: dl.s
        ink: manager.ink; muted: manager.muted
        api: dl.api
        readonly property var game: dl.gameOf(job?.gameId)
        artwork: game?.fondo || game?.portada || ""
    }
    Text {
        id: queueTitle
        visible: monitor.visible
        anchors { left: monitor.left; top: monitor.bottom; topMargin: dl.s * 10 }
        height: visible ? dl.s * 24 : 0
        text: qsTr("Cola de descargas e instalaciones") + " · " + dl.running.filter(j => j.status === "queued").length
        color: manager.ink; font.pixelSize: dl.s * 15; font.weight: Font.DemiBold
    }

    // ---- En curso
    ListView {
        id: activeView
        visible: dl.tab === "active"
        anchors { left: parent.left; right: parent.right; top: queueTitle.visible ? queueTitle.bottom : tabs.bottom; bottom: parent.bottom; margins: dl.s * 32; topMargin: dl.s * 10 }
        clip: true; spacing: dl.s * 10
        model: dl.activeList
        delegate: Rectangle {
            id: card
            required property var modelData
            readonly property bool bad: ["failed", "cancelled", "interrupted"].indexOf(modelData.status) >= 0
            readonly property bool busy: ["queued", "downloading", "verifying", "extracting", "finalizing", "paused"].indexOf(modelData.status) >= 0
            width: ListView.view.width; height: dl.s * 96; radius: dl.s * 15; color: manager.surface
            border.color: modelData.id === dl.monitoredJob?.id ? "#5CBBB7" : bad ? "#6A3F3F" : (modelData.status === "completed" ? "#2E6B4A" : "transparent")
            MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: dl.highlightedJobId = card.modelData.id }
            Column {
                anchors { left: parent.left; right: actions.left; verticalCenter: parent.verticalCenter; leftMargin: dl.s * 20; rightMargin: dl.s * 12 }
                spacing: dl.s * 8
                Text { width: parent.width; elide: Text.ElideRight; color: manager.ink; font.family: "Hanken Grotesk"; font.pixelSize: dl.s * 15; font.weight: Font.DemiBold
                       text: card.modelData.name + (card.modelData.external ? "  ·  Steam" : "") + "  ·  " + dl.statusLabel(card.modelData.status) }
                Rectangle {
                    visible: !card.bad
                    width: parent.width; height: dl.s * 6; radius: height / 2; color: manager.surface2
                    Rectangle { width: parent.width * Math.max(0, Math.min(1, Number(card.modelData.progress || 0) / 100)); height: parent.height; radius: height / 2
                                color: card.modelData.status === "completed" ? "#4FBF86" : "#45CFC9"; Behavior on width { NumberAnimation { duration: 200 } } }
                }
                Text { width: parent.width; elide: Text.ElideMiddle; font.family: "Hanken Grotesk"; font.pixelSize: dl.s * 12
                       color: card.bad ? "#E8B86D" : manager.muted
                       text: card.bad ? manager.installationErrorText(card.modelData.error || qsTr("No terminó.")) : (card.modelData.destination || "") }
            }
            Row {
                id: actions
                anchors { right: parent.right; verticalCenter: parent.verticalCenter; rightMargin: dl.s * 16 }
                spacing: dl.s * 8
                Repeater {
                    model: {
                        const m = card.modelData, out = []
                        if (m.external) {
                            out.push({ k: "steam", l: qsTr("Abrir descargas de Steam"), c: "s2" })
                        } else if (card.busy) {
                            if (m.kind !== "store" && ["queued", "paused", "downloading", "extracting"].includes(m.status))
                                out.push({ k: m.status === "paused" ? "resume" : "pause", l: m.status === "paused" ? qsTr("Reanudar") : qsTr("Pausar"), c: "s2" })
                            if (m.status !== "finalizing") out.push({ k: "cancel", l: qsTr("Cancelar"), c: "danger" })
                        } else if (card.bad) {
                            out.push(m.kind === "store" ? {k: "store", l: qsTr("Abrir tienda"), c: "accent"}
                                : {k: "retry", l: qsTr("Reintentar"), c: "accent"})
                            out.push({ k: "dismiss", l: qsTr("Descartar"), c: "s2" })
                        } else if (m.status === "completed" && m.gameId) {
                            out.push({ k: "open", l: qsTr("Abrir ficha"), c: "accent" })
                        }
                        return out
                    }
                    delegate: Rectangle {
                        id: btn
                        required property var modelData
                        width: btnText.implicitWidth + dl.s * 30; height: dl.s * 36; radius: height / 2
                        color: modelData.c === "accent" ? "#197781" : (modelData.c === "danger" ? "#50343A" : manager.surface2)
                        opacity: btnMa.containsMouse ? 0.88 : 1
                        Text { id: btnText; anchors.centerIn: parent; text: btn.modelData.l; color: manager.ink; font.family: "Hanken Grotesk"; font.pixelSize: dl.s * 12 }
                        MouseArea {
                            id: btnMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                const id = card.modelData.id, done = function(st, b) {
                                    if (st !== 200 && b && b.error) dl.api.notify(b.error)
                                    dl.refresh()
                                }
                                switch (btn.modelData.k) {
                                case "steam": Qt.openUrlExternally("steam://nav/downloads"); break
                                case "pause": dl.api.pauseInstallation(id, done); break
                                case "resume": dl.api.resumeInstallation(id, done); break
                                case "cancel": dl.api.cancelInstallation(id, done); break
                                case "store": dl.manager.selectPage("catalog"); break
                                case "retry": dl.api.retryInstallation(id, done); break
                                case "dismiss": dl.api.dismissInstallations(id, done); break
                                case "open": dl.manager.openGameInLibrary(dl.gameOf(card.modelData.gameId)); break
                                }
                            }
                        }
                    }
                }
            }
        }
        Text {
            visible: dl.activeList.length === 0
            anchors.centerIn: parent; horizontalAlignment: Text.AlignHCenter; width: parent.width * 0.7; wrapMode: Text.WordWrap
            color: manager.muted; font.family: "Hanken Grotesk"; font.pixelSize: dl.s * 16
            text: qsTr("No hay descargas en curso. Lo que instales aparecerá aquí mientras se descarga; al terminar con éxito se quita solo y pasa a «Instalados».")
        }
    }

    // ---- Instalados
    ListView {
        id: installedView
        visible: dl.tab === "installed"
        anchors { left: parent.left; right: parent.right; top: tabs.bottom; bottom: parent.bottom; margins: dl.s * 32; topMargin: dl.s * 20 }
        clip: true; spacing: dl.s * 10
        model: dl.installedList
        delegate: Rectangle {
            id: row
            required property var modelData
            readonly property var game: dl.gameOf(modelData.gameId)
            readonly property bool canUpdate: !!game && !!game.updateAvailable && !game.running
            width: ListView.view.width; height: dl.s * 84; radius: dl.s * 15; color: manager.surface
            FadedImage { x: dl.s * 12; anchors.verticalCenter: parent.verticalCenter; width: dl.s * 58; height: dl.s * 58; source: row.game && row.game.portada ? row.game.portada : ""; cornerRadius: dl.s * 10 }
            Column {
                anchors { left: parent.left; right: rowActions.left; verticalCenter: parent.verticalCenter; leftMargin: dl.s * 84; rightMargin: dl.s * 12 }
                spacing: dl.s * 5
                Text { width: parent.width; elide: Text.ElideRight; color: manager.ink; font.family: "Hanken Grotesk"; font.pixelSize: dl.s * 15; font.weight: Font.DemiBold
                       text: (row.game ? row.game.name : row.modelData.name) + (row.modelData.version ? "  ·  " + row.modelData.version : "") }
                Text { visible: row.canUpdate; width: parent.width; elide: Text.ElideRight; color: "#E0A24B"; font.family: "Hanken Grotesk"; font.pixelSize: dl.s * 12
                       text: row.game && row.game.updateAvailable ? qsTr("Actualización disponible: %1").arg(row.game.updateAvailable.version) : "" }
                Text { width: parent.width; elide: Text.ElideMiddle; color: manager.muted; font.family: "Hanken Grotesk"; font.pixelSize: dl.s * 12; text: row.modelData.path || "" }
            }
            Row {
                id: rowActions
                anchors { right: parent.right; verticalCenter: parent.verticalCenter; rightMargin: dl.s * 16 }
                spacing: dl.s * 8
                Repeater {
                    model: {
                        const out = []
                        if (row.canUpdate) out.push({ k: "update", l: qsTr("Actualizar"), c: "warn" })
                        if (row.game) out.push({ k: "open", l: qsTr("Abrir ficha"), c: "s2" })
                        out.push({ k: "remove", l: qsTr("Quitar"), c: "danger" })
                        return out
                    }
                    delegate: Rectangle {
                        id: rbtn
                        required property var modelData
                        width: rbtnText.implicitWidth + dl.s * 30; height: dl.s * 36; radius: height / 2
                        color: modelData.c === "warn" ? "#B8862F" : (modelData.c === "danger" ? "#50343A" : manager.surface2)
                        opacity: rbtnMa.containsMouse ? 0.88 : 1
                        Text { id: rbtnText; anchors.centerIn: parent; text: rbtn.modelData.l; color: manager.ink; font.family: "Hanken Grotesk"; font.pixelSize: dl.s * 12 }
                        MouseArea {
                            id: rbtnMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                if (rbtn.modelData.k === "update") dl.manager.updateFor(row.game)
                                else if (rbtn.modelData.k === "open") dl.manager.openGameInLibrary(row.game)
                                else { dl.manager.removeGameId = row.modelData.gameId; dl.manager.askUninstall() }
                            }
                        }
                    }
                }
            }
        }
        Text {
            visible: dl.installedList.length === 0
            anchors.centerIn: parent; horizontalAlignment: Text.AlignHCenter; width: parent.width * 0.7; wrapMode: Text.WordWrap
            color: manager.muted; font.family: "Hanken Grotesk"; font.pixelSize: dl.s * 16
            text: qsTr("Aún no has instalado ningún port desde el catálogo de Omnia. Búscalo en «Explorar».")
        }
    }
}

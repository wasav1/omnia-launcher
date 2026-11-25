pragma ComponentBehavior: Bound
import QtQuick

Rectangle {
    id: monitor
    property var job: null
    property url artwork: ""
    property var api: null
    property url catalogArtwork: ""
    readonly property string catalogSlug: visible ? job?.slug || "" : ""
    onCatalogSlugChanged: {
        catalogArtwork = ""
        if (!catalogSlug || !api) return
        const slug = catalogSlug
        api.catalogGame(slug, (status, payload) => {
            if (monitor.catalogSlug !== slug || status !== 200) return
            const art = (payload.data?.artwork || []).find(item => item.type === "hero" && item.imageUrl)
            if (art) monitor.catalogArtwork = art.localUrl || (art.imageUrl.startsWith("/") ? payload.baseUrl : "") + art.imageUrl
        })
    }
    property real uiScale: 1
    property color ink: "#F0F3F7"
    property color muted: "#C3CDD7"
    property color accent: "#6ADCD6"
    readonly property color diskInk: "#8AE395"
    readonly property var samples: job?.rateHistory || []
    readonly property real maxRate: Math.max(1, ...samples.map(sample => Math.max(sample.network || 0, sample.disk || 0)))
    readonly property real networkPercent: job?.downloadTotal > 0 ? 100 * job.downloadedBytes / job.downloadTotal :
                                           job?.status === "downloading" ? job.progress || 0 : 0
    readonly property var installation: job?.writeTotal > 0 ? 100 * job.writtenBytes / job.writeTotal
        : job?.downloadTotal > 0 && ["extracting", "finalizing", "completed"].includes(job?.status)
          ? Math.max(0, (job.progress - 75) * 4) : null
    readonly property string transferPhase: ({queued: qsTr("En cola"), downloading: qsTr("Descargando"),
        verifying: qsTr("Verificando"), extracting: qsTr("Extrayendo"), finalizing: qsTr("Finalizando"),
        paused: qsTr("En pausa"), failed: qsTr("Falló"), cancelled: qsTr("Cancelada"),
        interrupted: qsTr("Interrumpida"), completed: qsTr("Instalado")})[job?.status] || ""
    visible: !!job
    height: visible ? uiScale * 222 : 0
    radius: uiScale * 16
    color: "#142432"

    function bytes(value) {
        if (value >= 1073741824) return (value / 1073741824).toFixed(2) + " GiB"
        if (value >= 1048576) return (value / 1048576).toFixed(1) + " MiB"
        return (value / 1024).toFixed(0) + " KiB"
    }
    function rate(value) { return value == null ? "—" : bytes(value) + "/s" }
    function eta(value) {
        return value >= 3600 ? Math.floor(value / 3600) + " h " + Math.floor(value % 3600 / 60) + " min"
           : value >= 60 ? Math.floor(value / 60) + " min " + value % 60 + " s" : value + " s"
    }

    FadedImage {
        anchors.fill: parent
        source: monitor.artwork.toString() ? monitor.artwork : monitor.catalogArtwork
        cornerRadius: monitor.radius; fadeLeft: 0.55
        opacity: 0.34
    }
    Rectangle {
        anchors.fill: parent; radius: monitor.radius
        color: "#770C1723"; border.color: "#375260"
    }
    Column {
        anchors { top: parent.top; left: parent.left; right: parent.right; margins: monitor.uiScale * 14 }
        spacing: monitor.uiScale * 5
        Text {
            width: parent.width; elide: Text.ElideRight
            text: monitor.job?.name || ""
            textFormat: Text.PlainText; color: monitor.ink; font.family: "Hanken Grotesk"
            font.pixelSize: monitor.uiScale * 24; font.weight: Font.Bold
        }
        Text {
            width: parent.width; elide: Text.ElideRight
            text: monitor.transferPhase + (monitor.job?.source === "steam" ? " · Steam" : "")
                + (monitor.job?.etaSeconds != null ? " · " + qsTr("Tiempo restante: %1").arg(monitor.eta(monitor.job.etaSeconds))
                : monitor.job?.eta ? " · " + qsTr("Tiempo restante: %1").arg(monitor.job.eta) : "")
            textFormat: Text.PlainText; color: monitor.muted; font.pixelSize: monitor.uiScale * 13
        }
        Text {
            text: qsTr("Datos descargados") + (monitor.job?.downloadTotal > 0
                ? "   " + monitor.bytes(monitor.job.downloadedBytes) + " / " + monitor.bytes(monitor.job.downloadTotal) : "")
            color: monitor.ink; font.pixelSize: monitor.uiScale * 13
        }
        TransferProgress { width: parent.width; height: monitor.uiScale * 5; ink: monitor.accent; percent: monitor.networkPercent }
        Text {
            text: qsTr("Instalación de archivos") + (monitor.installation != null ? "   " + Math.floor(monitor.installation) + "%" : "   —")
            color: monitor.ink; font.pixelSize: monitor.uiScale * 13
        }
        TransferProgress { width: parent.width; height: monitor.uiScale * 5; ink: monitor.diskInk; percent: monitor.installation || 0 }
        Row {
            width: parent.width
            spacing: monitor.uiScale * 15
            Column {
                width: parent.width * 0.36
                spacing: monitor.uiScale * 3
                Repeater {
                    model: [
                        [qsTr("Red"), monitor.job?.networkRate == null && monitor.job?.speed ? monitor.job.speed : monitor.rate(monitor.job?.networkRate)],
                        [qsTr("Pico de velocidad"), monitor.rate(monitor.job?.networkPeak)],
                        [qsTr("Escritura en disco"), monitor.rate(monitor.job?.diskRate)]
                    ]
                    delegate: Text {
                        required property var modelData
                        width: parent.width
                        text: modelData[0] + "   " + modelData[1]
                        textFormat: Text.PlainText; elide: Text.ElideRight
                        color: monitor.muted; font.pixelSize: monitor.uiScale * 13
                    }
                }
            }
            Item {
                width: parent.width * 0.64 - parent.spacing
                height: monitor.uiScale * 58
                Row {
                    anchors.fill: parent
                    spacing: monitor.uiScale * 3
                    Repeater {
                        model: monitor.samples
                        delegate: Item {
                            required property var modelData
                            width: Math.max(2, (parent.width + parent.spacing) / 40 - parent.spacing)
                            height: parent.height
                            Rectangle {
                                anchors.bottom: parent.bottom; width: parent.width
                                height: parent.height * (parent.modelData.network || 0) / monitor.maxRate
                                color: monitor.accent; radius: 2
                            }
                            Rectangle {
                                anchors.bottom: parent.bottom
                                width: parent.width
                                height: Math.max(0, (parent.modelData.disk || 0) / monitor.maxRate * parent.height)
                                color: monitor.diskInk; opacity: 0.55; radius: 2
                            }
                        }
                    }
                }
            }
        }
    }
}

pragma ComponentBehavior: Bound

import QtQuick

Column {
    id: facts

    required property var api
    property var game: null
    property var catalog: null
    property var offer: null
    property var metadata: ({})
    property real uiScale: 1
    property color ink: "#EAF1F6"
    property color muted: "#BECBD6"
    property string uiFont: "Hanken Grotesk"
    property real downloadBytes: 0
    property bool showDescription: true
    property bool fetch: true
    readonly property string query: !fetch || !visible ? "" : game?.id
        ? "id=" + encodeURIComponent(game.id) : catalog?.slug
        ? "slug=" + encodeURIComponent(catalog.slug) : offer?.rawId
        ? "store=" + encodeURIComponent(offer.store) + "&product=" + encodeURIComponent(offer.rawId) : ""
    readonly property string requestKey: query ? query + "&lang=" + api.language : ""
    readonly property var info: Object.assign({}, offer?.metadata || {}, metadata)
    readonly property var rows: {
        const size = downloadBytes || info.downloadBytes || 0
        const formattedSize = bytes => bytes > 0 ? (bytes >= 1073741824
            ? (bytes / 1073741824).toFixed(2) + " GiB"
            : (bytes / 1048576).toFixed(1) + " MiB") : ""
        const releaseLabel = info.releaseSource === "steam" ? qsTr("Lanzamiento en Steam")
            : info.releaseSource === "gog" ? qsTr("Lanzamiento en GOG") : qsTr("Lanzamiento")
        const entries = [
            [releaseLabel, info.release || catalog?.releaseYear],
            [qsTr("Géneros"), info.genres],
            [qsTr("Desarrolladora"), info.developer],
            [qsTr("Editora"), info.publisher],
            [info.fullDownload ? qsTr("Descarga completa") : qsTr("Descarga"), formattedSize(size)],
            [info.fullDownload ? qsTr("Tamaño en disco · instalación completa") : qsTr("Tamaño en disco"), formattedSize(info.diskBytes)]
        ]
        const port = (game?.requirements || []).map(r => [r.label, r.need].filter(Boolean).join(" ")).filter(Boolean)
        if (port.length) entries.push([qsTr("Requisitos del port"), port.join(" · ")])
        const labels = {linux: "Linux", pc: "Windows", mac: "macOS"}
        Object.keys(labels).forEach(platform => {
            const req = info.requirements?.[platform]
            if (req?.minimum) entries.push([qsTr("Mínimos · %1").arg(labels[platform]), req.minimum])
            if (req?.recommended) entries.push([qsTr("Recomendados · %1").arg(labels[platform]), req.recommended])
        })
        return entries.filter(item => !!item[1])
    }
    spacing: 8 * uiScale

    onRequestKeyChanged: {
        if (!fetch) return
        metadata = {}
        if (requestKey) requestDelay.restart()
        else requestDelay.stop()
    }

    Timer {
        id: requestDelay
        interval: 150
        onTriggered: {
            const key = facts.requestKey
            facts.api.call("GET", "/game/metadata?" + key, function(status, body) {
                if (status === 200 && facts.requestKey === key) facts.metadata = body.metadata || {}
            })
        }
    }

    Text {
        visible: facts.showDescription
        width: facts.width
        text: facts.info.description || facts.catalog?.description || facts.game?.description || qsTr("Sin descripción disponible.")
        color: facts.ink
        font.family: facts.uiFont
        font.pixelSize: 16 * facts.uiScale
        textFormat: Text.PlainText
        wrapMode: Text.Wrap
        lineHeight: 1.18
    }

    Repeater {
        model: facts.rows
        delegate: Column {
            required property var modelData
            width: facts.width
            spacing: 2 * facts.uiScale
            Text {
                width: parent.width
                text: parent.modelData[0]
                color: facts.ink
                font.family: facts.uiFont
                font.pixelSize: 13 * facts.uiScale
                font.weight: Font.DemiBold
                textFormat: Text.PlainText
                wrapMode: Text.Wrap
            }
            Text {
                width: parent.width
                text: parent.modelData[1]
                color: facts.muted
                font.family: facts.uiFont
                font.pixelSize: 13 * facts.uiScale
                textFormat: Text.PlainText
                wrapMode: Text.Wrap
            }
        }
    }
}

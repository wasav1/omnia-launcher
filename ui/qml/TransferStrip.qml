pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls

Button {
    id: strip
    property var jobs: []
    property real uiScale: 1
    property color ink: "#F0F3F7"
    property color accent: "#6ADCD6"
    property string shortcutHint: ""
    readonly property var active: jobs.filter(job => ["downloading", "verifying", "extracting", "finalizing"].includes(job.status))
    readonly property var queued: jobs.filter(job => job.status === "queued")
    readonly property var current: active[0] || queued[0] || null
    readonly property var phase: ({queued: qsTr("En cola"), downloading: qsTr("Descargando"), verifying: qsTr("Verificando"),
                                  extracting: qsTr("Extrayendo"), finalizing: qsTr("Finalizando")})
    visible: !!current
    height: visible ? uiScale * 49 : 0
    padding: uiScale * 12
    Accessible.name: qsTr("Abrir descargas")
    background: Rectangle {
        radius: strip.uiScale * 10
        color: strip.hovered ? "#28434F" : "#182831"
        border.color: strip.visualFocus ? strip.accent : "#375260"
    }
    contentItem: Item {
        LucideIcon {
            id: glyph
            anchors { left: parent.left; verticalCenter: parent.verticalCenter }
            width: strip.uiScale * 20; height: width; name: "download"; color: strip.accent
        }
        Text {
            anchors { left: glyph.right; leftMargin: strip.uiScale * 9; right: stat.left; rightMargin: strip.uiScale * 8; verticalCenter: parent.verticalCenter }
            text: strip.current ? strip.current.name + " · " + strip.phase[strip.current.status] : ""
            color: strip.ink; textFormat: Text.PlainText; font.family: "Hanken Grotesk"; font.pixelSize: strip.uiScale * 15
            elide: Text.ElideRight
        }
        Text {
            id: stat
            anchors { right: parent.right; verticalCenter: parent.verticalCenter }
            text: strip.current ? Math.floor(strip.current.progress || 0) + "%"
                + (strip.queued.length ? " · " + qsTr("En cola: %1").arg(strip.queued.length) : "")
                + (strip.shortcutHint ? " · " + strip.shortcutHint : "") : ""
            color: strip.ink; font.family: "Hanken Grotesk"; font.pixelSize: strip.uiScale * 14
        }
        TransferProgress {
            anchors { left: parent.left; right: parent.right; bottom: parent.bottom; bottomMargin: -strip.uiScale * 7 }
            height: Math.max(2, strip.uiScale * 3)
            percent: strip.current?.progress || 0
            ink: strip.accent
        }
    }
}

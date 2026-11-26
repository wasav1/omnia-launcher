import QtQuick

/** Mando conectado y su batería. Se muestra en la barra superior de todas las pantallas de BigMode.
 *  Sin mando no se ve; si el sistema no expone la batería, solo muestra el nombre (nunca inventa un porcentaje). */
Rectangle {
    id: chip
    required property var api
    required property real uiScale
    required property string uiFont
    property color ink: "#F0F3F7"
    property color muted: "#B8C3D0"
    property bool compact: false             // solo icono y batería (cabeceras con poco espacio)

    readonly property var bat: api.padBattery
    readonly property int level: bat && bat.level !== undefined ? Number(bat.level) : -1
    readonly property bool charging: !!(bat && bat.charging)
    readonly property bool known: level >= 0
    readonly property bool low: known && !charging && level <= 30
    readonly property bool critical: known && !charging && level <= 10
    readonly property color tone: charging ? "#7FD4A0" : critical ? "#FF8A8A" : low ? "#E8B86D" : muted
    readonly property string shortName: {
        const n = String(api.padName || "").toLowerCase()
        if (n.indexOf("dualsense") >= 0) return "DualSense"
        if (n.indexOf("dualshock") >= 0) return "DualShock 4"
        if (n.indexOf("pro controller") >= 0) return "Pro Controller"
        if (n.indexOf("joy-con") >= 0) return "Joy-Con"
        if (n.indexOf("steam") >= 0 || n.indexOf("deck") >= 0) return "Steam Deck"
        if (n.indexOf("xbox") >= 0) return "Xbox"
        const words = String(api.padName || "").split(/\s+/).filter(w => w)
        return words.length ? words.slice(0, 2).join(" ") : qsTr("Mando")
    }

    visible: api.padOn
    height: uiScale * 42
    width: row.implicitWidth + uiScale * 28
    radius: height / 2
    color: "#b30b0f14"
    border.width: low ? 2 : 1
    border.color: low ? tone : "#30ffffff"

    Row {
        id: row
        anchors.centerIn: parent
        spacing: chip.uiScale * 9
        LucideIcon { anchors.verticalCenter: parent.verticalCenter; width: chip.uiScale * 19; height: width; name: "gamepad-2"; color: chip.tone }
        Text {
            visible: !chip.compact || !chip.known
            anchors.verticalCenter: parent.verticalCenter
            text: chip.shortName
            color: chip.ink
            font.family: chip.uiFont; font.pixelSize: chip.uiScale * 16
        }
        Item {                      // pila: se llena según el nivel
            visible: chip.known
            anchors.verticalCenter: parent.verticalCenter
            width: chip.uiScale * 28; height: chip.uiScale * 13
            Rectangle { x: 0; y: 0; width: parent.width - chip.uiScale * 3; height: parent.height; radius: chip.uiScale * 3; color: "transparent"; border.width: 1; border.color: chip.tone }
            Rectangle {
                x: chip.uiScale * 2; y: chip.uiScale * 2
                width: Math.max(chip.uiScale * 2, (parent.width - chip.uiScale * 7) * Math.max(0, Math.min(100, chip.level)) / 100)
                height: parent.height - chip.uiScale * 4; radius: chip.uiScale
                color: chip.tone
            }
            Rectangle { x: parent.width - chip.uiScale * 3; y: chip.uiScale * 4; width: chip.uiScale * 3; height: parent.height - chip.uiScale * 8; radius: 1; color: chip.tone }
        }
        Text {
            visible: chip.known
            anchors.verticalCenter: parent.verticalCenter
            text: (chip.charging ? qsTr("Cargando · ") : "") + chip.level + " %"
            color: chip.tone === chip.muted ? chip.ink : chip.tone
            font.family: chip.uiFont; font.pixelSize: chip.uiScale * 16; font.weight: Font.DemiBold
        }
    }
}

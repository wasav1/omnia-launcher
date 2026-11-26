import qs.services
import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import QtQuick.Layouts

// Mando conectado y su batería, para la cabecera del panel rápido. Sin mando muestra «Sin mando» en tono apagado.
// Si el sistema no expone la batería, solo muestra el nombre (nunca inventa un porcentaje).
Rectangle {
    id: chip
    readonly property bool on: OmniaApi.padOn
    readonly property var bat: OmniaApi.padBattery
    readonly property int level: bat && bat.level !== undefined ? Number(bat.level) : -1
    readonly property bool charging: !!(bat && bat.charging)
    readonly property bool known: on && level >= 0
    readonly property bool low: known && !charging && level <= 30
    readonly property bool critical: known && !charging && level <= 10
    readonly property color tone: !on ? OmniaTheme.inkDim : charging ? OmniaTheme.ok : critical ? "#ff8a8a" : low ? "#E8B86D" : OmniaTheme.inkDim
    readonly property string shortName: {
        if (!on) return OmniaApi.tr("Sin mando", "No controller");
        const n = String(OmniaApi.padName || "").toLowerCase();
        if (n.indexOf("dualsense") >= 0) return "DualSense";
        if (n.indexOf("dualshock") >= 0) return "DualShock 4";
        if (n.indexOf("pro controller") >= 0) return "Pro Controller";
        if (n.indexOf("joy-con") >= 0) return "Joy-Con";
        if (n.indexOf("steam") >= 0 || n.indexOf("deck") >= 0) return "Steam Deck";
        if (n.indexOf("xbox") >= 0) return "Xbox";
        const words = String(OmniaApi.padName || "").split(/\s+/).filter(w => w);
        return words.length ? words.slice(0, 2).join(" ") : OmniaApi.tr("Mando", "Controller");
    }

    implicitHeight: 30
    implicitWidth: chipRow.implicitWidth + 24
    radius: height / 2
    color: Qt.rgba(1, 1, 1, 0.08)
    border.width: low ? 2 : 1
    border.color: low ? tone : Qt.rgba(1, 1, 1, 0.12)
    opacity: on ? 1 : 0.7

    RowLayout {
        id: chipRow
        anchors.centerIn: parent
        spacing: 7
        OmniaLucide { name: "gamepad-2"; width: 16; height: 16; color: chip.tone; Layout.alignment: Qt.AlignVCenter }
        StyledText {
            text: chip.shortName
            font.pixelSize: Appearance.font.pixelSize.small
            color: chip.on ? OmniaTheme.ink : OmniaTheme.inkDim
        }
        Item {      // pila: se llena según el nivel
            visible: chip.known
            Layout.alignment: Qt.AlignVCenter
            implicitWidth: 24; implicitHeight: 11
            Rectangle { x: 0; y: 0; width: parent.width - 3; height: parent.height; radius: 3; color: "transparent"; border.width: 1; border.color: chip.tone }
            Rectangle {
                x: 2; y: 2
                width: Math.max(2, (parent.width - 7) * Math.max(0, Math.min(100, chip.level)) / 100)
                height: parent.height - 4; radius: 1
                color: chip.tone
            }
            Rectangle { x: parent.width - 3; y: 3; width: 3; height: parent.height - 6; radius: 1; color: chip.tone }
        }
        StyledText {
            visible: chip.known
            text: (chip.charging ? "Cargando · " : "") + chip.level + " %"
            font.pixelSize: Appearance.font.pixelSize.small
            font.weight: Font.DemiBold
            color: chip.low || chip.charging ? chip.tone : OmniaTheme.ink
        }
    }
}

import QtQuick
import Quickshell.Io
import qs.Common
import qs.Widgets
import qs.DCommon.Widgets
import qs.Modules.Plugins

// Botón de Omnia en la barra de Dux: abre el panel rápido (pestaña del dashboard) y, si hay un mando conectado, muestra su nombre y su batería
// (datos del núcleo de Omnia, GET /pad; si el sistema no expone la batería solo se muestra el nombre, nunca un porcentaje inventado).
PluginComponent {
    id: root

    readonly property string dir: Qt.resolvedUrl(".").toString().replace("file://", "")
    property bool padOn: false
    property string padName: ""
    property int padLevel: -1
    property bool padCharging: false
    readonly property bool padKnown: padOn && padLevel >= 0
    readonly property bool padLow: padKnown && !padCharging && padLevel <= 30
    readonly property bool padCritical: padKnown && !padCharging && padLevel <= 10
    readonly property color padTone: padCritical ? "#E86D6D" : padLow ? "#E8B86D" : padCharging ? "#7FD69F" : Theme.widgetTextColor
    readonly property string padShort: {
        const n = padName.toLowerCase();
        if (n.indexOf("dualsense") >= 0) return "DualSense";
        if (n.indexOf("dualshock") >= 0) return "DualShock 4";
        if (n.indexOf("pro controller") >= 0) return "Pro Controller";
        if (n.indexOf("joy-con") >= 0) return "Joy-Con";
        if (n.indexOf("steam") >= 0 || n.indexOf("deck") >= 0) return "Steam Deck";
        if (n.indexOf("xbox") >= 0) return "Xbox";
        const words = padName.split(/\s+/).filter(w => w);
        return words.length ? words.slice(0, 2).join(" ") : "Mando";
    }
    readonly property string batteryIcon: {
        if (padCharging) return "battery_charging_full";
        if (padLevel <= 10) return "battery_alert";
        if (padLevel <= 20) return "battery_1_bar";
        if (padLevel <= 35) return "battery_2_bar";
        if (padLevel <= 50) return "battery_3_bar";
        if (padLevel <= 65) return "battery_4_bar";
        if (padLevel <= 80) return "battery_5_bar";
        if (padLevel <= 92) return "battery_6_bar";
        return "battery_full";
    }

    function applyPad(text) {
        let data = {};
        try { data = JSON.parse(text); } catch (e) { data = {}; }
        padOn = data.connected === true;
        padName = padOn ? String(data.name || "") : "";
        const bat = padOn && data.battery ? data.battery : null;
        padLevel = bat && bat.level !== undefined && bat.level !== null ? Math.max(0, Math.min(100, Number(bat.level))) : -1;
        padCharging = !!(bat && bat.charging);
    }

    Process {
        id: padPoll
        command: [root.dir + "pad-status.sh"]
        stdout: StdioCollector { onStreamFinished: root.applyPad(text) }
    }
    Timer {
        interval: 5000
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: if (!padPoll.running) padPoll.running = true
    }

    property var popoutService: null

    // El panel es la pestaña «Omnia» del dashboard de Dux (OmniaDashboard.qml), anclada a este botón como la de ASUS TUF.
    pillClickAction: (x, y, width, section, screen) =>
        popoutService?.toggleDankDash("plugin_omniaPanel", x, y, width, section, screen)

    horizontalBarPill: Component {
        Row {
            spacing: Theme.spacingXS
            Image {
                source: Qt.resolvedUrl("gamepad-2.svg")
                sourceSize.width: root.iconSize
                sourceSize.height: root.iconSize
                width: root.iconSize
                height: root.iconSize
                fillMode: Image.PreserveAspectFit
                anchors.verticalCenter: parent.verticalCenter
            }
            StyledText {
                text: root.padOn ? root.padShort : "Omnia"
                font.pixelSize: root.textSize
                color: Theme.widgetTextColor
                anchors.verticalCenter: parent.verticalCenter
            }
            DankIcon {
                visible: root.padKnown
                name: root.batteryIcon
                size: root.iconSize
                color: root.padTone
                anchors.verticalCenter: parent.verticalCenter
            }
            StyledText {
                visible: root.padKnown
                text: root.padLevel + "%"
                font.pixelSize: root.textSize
                color: root.padTone
                anchors.verticalCenter: parent.verticalCenter
            }
        }
    }

    verticalBarPill: Column {
        spacing: Theme.spacingXS
        Image {
            source: Qt.resolvedUrl("gamepad-2.svg")
            sourceSize.width: root.iconSize
            sourceSize.height: root.iconSize
            width: root.iconSize
            height: root.iconSize
            fillMode: Image.PreserveAspectFit
            anchors.horizontalCenter: parent.horizontalCenter
        }
        DankIcon {
            visible: root.padKnown
            name: root.batteryIcon
            size: root.iconSize
            color: root.padTone
            anchors.horizontalCenter: parent.horizontalCenter
        }
    }
}

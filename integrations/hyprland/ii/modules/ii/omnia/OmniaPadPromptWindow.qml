pragma ComponentBehavior: Bound

import qs.services
import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland

/**
 * Aviso flotante en el centro del monitor con el foco: «Mando conectado · ¿Abrir Omnia?» (prototipo A).
 * Capa Overlay sin teclado: el mando llega por el núcleo (OmniaPadPrompt escucha A y B).
 */
PanelWindow {
    id: win
    required property var modelData
    screen: modelData

    readonly property var pp: OmniaPadPrompt
    readonly property bool mine: (Hyprland.focusedMonitor?.name ?? Quickshell.screens[0].name) === modelData.name
    readonly property bool ps: pp.family === "ps"
    visible: pp.shown && mine
    color: "transparent"
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.namespace: "quickshell:omniaPadPrompt"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
    implicitWidth: 380
    implicitHeight: card.implicitHeight + 24

    readonly property string shortName: {
        const n = String(pp.name || "").toLowerCase();
        if (n.indexOf("dualsense") >= 0) return "DualSense";
        if (n.indexOf("dualshock") >= 0) return "DualShock 4";
        if (n.indexOf("pro controller") >= 0) return "Pro Controller";
        if (n.indexOf("steam") >= 0 || n.indexOf("deck") >= 0) return "Steam Deck";
        return pp.name || OmniaApi.tr("Mando", "Controller");
    }
    readonly property string batteryText: pp.battery && pp.battery.level !== undefined ? " · " + Math.round(Number(pp.battery.level)) + " %" : ""

    Rectangle {
        id: card
        anchors.centerIn: parent
        width: 340
        implicitHeight: col.implicitHeight + 36
        height: implicitHeight
        radius: 18
        color: Qt.rgba(0.063, 0.094, 0.125, 0.96)
        border.width: 1
        border.color: Qt.rgba(1, 1, 1, 0.16)
        scale: win.visible ? 1 : 0.94
        opacity: win.visible ? 1 : 0
        Behavior on scale { NumberAnimation { duration: 200; easing.type: Easing.OutBack; easing.overshoot: 1.6 } }
        Behavior on opacity { NumberAnimation { duration: 160 } }

        ColumnLayout {
            id: col
            anchors { left: parent.left; right: parent.right; top: parent.top; margins: 18 }
            spacing: 6
            Rectangle {
                Layout.alignment: Qt.AlignHCenter
                implicitWidth: 64; implicitHeight: 64; radius: 32
                color: "#0b0f14"; border.width: 3; border.color: "#5b9be0"
                OmniaLucide { anchors.centerIn: parent; name: "gamepad-2"; width: 30; height: 30; color: OmniaTheme.ink }
            }
            StyledText { Layout.alignment: Qt.AlignHCenter; Layout.topMargin: 6; text: OmniaApi.tr("Mando conectado", "Controller connected"); font.pixelSize: Appearance.font.pixelSize.larger; font.weight: Font.DemiBold; color: OmniaTheme.ink }
            StyledText { Layout.alignment: Qt.AlignHCenter; text: win.shortName + win.batteryText; font.pixelSize: Appearance.font.pixelSize.smaller; color: OmniaTheme.inkDim }
            StyledText { Layout.alignment: Qt.AlignHCenter; Layout.topMargin: 8; text: OmniaApi.tr("¿Abrir Omnia?", "Open Omnia?"); font.pixelSize: Appearance.font.pixelSize.normal; color: OmniaTheme.ink }
            RowLayout {
                Layout.alignment: Qt.AlignHCenter
                Layout.topMargin: 6
                spacing: 8
                Rectangle {
                    implicitWidth: yes.implicitWidth + 28; implicitHeight: 36; radius: 10
                    color: yesMa.containsMouse ? OmniaTheme.accentHi : OmniaTheme.accent
                    RowLayout {
                        id: yes
                        anchors.centerIn: parent
                        spacing: 8
                        Rectangle { implicitWidth: 22; implicitHeight: 22; radius: 11; color: "#4caf50"
                            StyledText { anchors.centerIn: parent; text: win.ps ? "✕" : "A"; font.pixelSize: 12; font.weight: Font.DemiBold; color: "white" } }
                        StyledText { text: OmniaApi.tr("Abrir Big Mode", "Open Big Mode"); color: OmniaTheme.ink }
                    }
                    MouseArea { id: yesMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: win.pp.accept() }
                }
                Rectangle {
                    implicitWidth: no.implicitWidth + 28; implicitHeight: 36; radius: 10
                    color: noMa.containsMouse ? Qt.rgba(1, 1, 1, 0.12) : "transparent"
                    border.width: 1; border.color: Qt.rgba(1, 1, 1, 0.3)
                    RowLayout {
                        id: no
                        anchors.centerIn: parent
                        spacing: 8
                        Rectangle { implicitWidth: 22; implicitHeight: 22; radius: 11; color: "#e0524a"
                            StyledText { anchors.centerIn: parent; text: win.ps ? "○" : "B"; font.pixelSize: 12; font.weight: Font.DemiBold; color: "white" } }
                        StyledText { text: OmniaApi.tr("Ahora no", "Not now"); color: OmniaTheme.ink }
                    }
                    MouseArea { id: noMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: win.pp.decline() }
                }
            }
            Rectangle {      // cuenta atrás
                Layout.fillWidth: true; Layout.topMargin: 10
                implicitHeight: 4; radius: 2; color: Qt.rgba(1, 1, 1, 0.12)
                Rectangle { width: parent.width * win.pp.remaining; height: parent.height; radius: 2; color: "#5b9be0" }
            }
        }
    }
}

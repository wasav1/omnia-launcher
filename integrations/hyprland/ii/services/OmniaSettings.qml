pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io

/**
 * Ajustes propios de Omnia en ~/.config/omnia/hyprland.json (no toca el config.json de illogical-impulse).
 * Todos los valores tienen un predeterminado; el archivo es opcional.
 */
Singleton {
    id: root

    readonly property string path: (Quickshell.env("XDG_CONFIG_HOME") || (Quickshell.env("HOME") + "/.config")) + "/omnia/hyprland.json"

    readonly property int port: adapter.port
    readonly property string tokenFile: adapter.tokenFile || ((Quickshell.env("XDG_RUNTIME_DIR") || "/run/user/1000") + "/omnia/token")
    readonly property string activation: ["bar", "edge", "both"].indexOf(adapter.activation) >= 0 ? adapter.activation : "both"   // bar | edge | both
    readonly property string edgeSide: ["left", "right", "top", "bottom"].indexOf(adapter.edgeSide) >= 0 ? adapter.edgeSide : "right"
    readonly property string edgePosition: ["start", "center", "end"].indexOf(adapter.edgePosition) >= 0 ? adapter.edgePosition : "center"
    readonly property bool barEnabled: activation !== "edge"
    readonly property bool edgeEnabled: activation !== "bar"
    readonly property bool blur: adapter.blur
    readonly property string edgeMonitors: adapter.edgeMonitors          // "rightmost" | "all"
    readonly property int revealDelayMs: Math.max(50, adapter.revealDelayMs)
    readonly property int zoneHeightPct: Math.min(90, Math.max(10, adapter.zoneHeightPct))
    readonly property int zoneWidthPx: Math.max(1, adapter.zoneWidthPx)
    readonly property int closeGraceMs: Math.max(100, adapter.closeGraceMs)
    readonly property real rotateMinutes: Math.max(0.1, adapter.rotateMinutes)
    readonly property var libraryCommand: adapter.libraryCommand
    readonly property var desktopCommand: adapter.desktopCommand         // la app de escritorio (Omnia Desktop Suite)

    // Guarda un ajuste en hyprland.json (los demás conservan su valor).
    function set(name, value) {
        if (adapter[name] === value) return;
        adapter[name] = value;
        file.writeAdapter();
    }

    FileView {
        id: file
        path: root.path
        watchChanges: true
        printErrors: false
        onFileChanged: reload()
        adapter: JsonAdapter {
            id: adapter
            property int port: 47831
            property string tokenFile: ""             // solo para pruebas con un núcleo aislado
            property string activation: "both"
            property string edgeSide: "right"
            property string edgePosition: "center"
            property bool blur: true
            property string edgeMonitors: "rightmost"
            property int revealDelayMs: 300
            property int zoneHeightPct: 35
            property int zoneWidthPx: 2
            property int closeGraceMs: 600
            property list<string> libraryCommand: ["omnia-ui", "--window"]
            property list<string> desktopCommand: ["omnia-ui", "--manager"]
        }
    }
}

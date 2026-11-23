pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Hyprland

/**
 * Aviso «Mando conectado · ¿Abrir Omnia?». Se muestra al conectar un mando (no al arrancar con él ya conectado) si el ajuste está
 * encendido y no estorba: sin el panel abierto, sin Big Mode abierto y sin un juego en marcha. A (o clic) abre Big Mode; B (o clic) lo
 * descarta y no vuelve a preguntar hasta la próxima conexión; sin respuesta se cierra solo a los 12 s.
 */
Singleton {
    id: root

    property bool shown: false
    property string name: ""
    property var battery: null
    property string family: ""
    readonly property int timeoutMs: 12000
    property real remaining: 1                       // 1 → 0 durante la cuenta atrás

    // Mientras el ajuste esté encendido, el servicio escucha al núcleo para detectar la conexión.
    Binding { target: OmniaApi; property: "padWatching"; value: OmniaSettings.padPrompt }

    readonly property bool bigModeOpen: {
        try {
            return Hyprland.toplevels.values.some(t => (t.lastIpcObject?.class ?? "") === "org.omnia.bigmode.qml6");
        } catch (e) { return false; }
    }

    function accept() {
        if (!shown) return;
        shown = false;
        OmniaApi.openLibrary();
    }
    function decline() { shown = false; }
    // Para probarlo sin conectar un mando:  qs -c ii ipc call omnia padprompt
    function preview() {
        name = OmniaApi.padName || "Xbox Wireless Controller"; battery = OmniaApi.padBattery; family = OmniaApi.padFamily || "xbox";
        remaining = 1; shown = true;
    }

    Connections {
        target: OmniaApi
        function onPadConnected(name, battery, family) {
            if (!OmniaSettings.padPrompt || OmniaPanelState.shown || root.bigModeOpen) return;
            root.name = name; root.battery = battery; root.family = family;
            OmniaApi.refresh();                          // el estado de los juegos puede estar atrasado: se confirma antes de decidir
            decide.restart();
        }
        function onPadKey(key) {
            if (!root.shown) return;
            if (key === "A") root.accept();
            else if (key === "B") root.decline();
        }
    }
    Timer {
        id: decide
        interval: 500
        onTriggered: {
            if (OmniaApi.games.some(g => g.running) || root.bigModeOpen || OmniaPanelState.shown) return;
            root.remaining = 1;
            root.shown = true;
        }
    }
    NumberAnimation {
        id: countdown
        target: root; property: "remaining"; from: 1; to: 0; duration: root.timeoutMs
        running: root.shown
        onFinished: root.decline()
    }
    onShownChanged: if (!shown) countdown.stop()
}

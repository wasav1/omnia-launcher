pragma Singleton
pragma ComponentBehavior: Bound

import qs
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland

/**
 * Estado único del panel de Omnia (una sola instancia, en el monitor donde se activó).
 *   mode:   closed | peek (asomado por el borde, sin foco) | pinned (con foco: Esc, clic fuera, mismo botón)
 *   origin: bar (se despliega desde el botón de la barra) | edge (entra y sale por el borde configurado)
 */
Singleton {
    id: root

    property string mode: "closed"
    property string origin: "bar"
    property string screenName: ""
    property real anchorX: 0                      // centro del botón en coordenadas de la pantalla (origin == bar)
    property double clearedAt: 0                  // el grab de foco cerró el panel (evita reabrir con el mismo clic)
    property string previousFocus: ""             // ventana que tenía el foco al abrir: se le devuelve al cerrar
    property bool externalBlock: false
    property bool autoClose: false                // se cierra solo cuando el cursor no está sobre el panel (todos los orígenes)
    property bool enteredOnce: false              // el cursor ya estuvo sobre el panel (desde entonces vale «sin hover»)
    property double openedAt: 0
    property bool exclusiveKeys: false            // abierto por atajo: toma el teclado sin necesidad de clic
    property bool hoverPanel: false
    property bool hoverZone: false
    property rect panelRect: Qt.rect(0, 0, 0, 0)   // cuerpo del panel en coordenadas globales (lo informa la ventana)
    property bool pointerInside: false            // según la posición real del cursor (no depende de eventos de hover)
    property bool keepOpen: false                 // menú ⋯ o ajustes abiertos: no se cierra solo
    signal viewRequested(string view)
    signal navRequested(string key)               // diagnóstico: simula teclas (up/down/left/right/accept/back/menu/tab)

    readonly property bool shown: mode !== "closed"
    readonly property bool fullscreenAny: Hyprland.workspaces.values.some(ws =>
        ws.active && ws.toplevels.values.some(t => t.wayland?.fullscreen))
    readonly property bool otherPanelOpen: externalBlock || GlobalStates.sidebarRightOpen || GlobalStates.sidebarLeftOpen
        || GlobalStates.overviewOpen || GlobalStates.searchOpen || GlobalStates.sessionOpen || GlobalStates.screenLocked
    readonly property bool canPeek: OmniaSettings.edgeEnabled && !otherPanelOpen && !fullscreenAny

    onOtherPanelOpenChanged: if (otherPanelOpen) close()

    function open(newOrigin, screen, newMode, x) {
        if (otherPanelOpen) return;
        if (mode === "closed") previousFocus = Hyprland.activeToplevel?.address ?? "";
        origin = newOrigin;
        autoClose = true;
        enteredOnce = false;
        openedAt = Date.now();
        exclusiveKeys = false;
        screenName = screen;
        anchorX = x ?? 0;
        mode = newMode;
        OmniaApi.refresh();
    }
    function close() {
        graceTimer.stop();
        autoClose = false;
        if (mode === "closed") return;
        const wasPinned = mode === "pinned";
        mode = "closed";
        if (wasPinned) restoreFocus();
    }
    function pin() { if (mode === "peek") { mode = "pinned"; } }
    function touch() { openedAt = Date.now(); }       // actividad de teclado/mando: reinicia la espera del cursor
    function peek(screen) { if (mode === "closed" && canPeek) open("edge", screen, "peek"); }

    // El grab de foco ya devolvió el foco al hacer clic fuera: no se fuerza otra ventana.
    function focusLost() { console.log("[Omnia] panel cerrado: clic fuera (foco perdido)"); clearedAt = Date.now(); graceTimer.stop(); autoClose = false; mode = "closed"; }

    function restoreFocus() {
        const addr = previousFocus;
        previousFocus = "";
        if (addr !== "") focusTimer.addr = addr, focusTimer.restart();
    }
    Timer {
        id: focusTimer
        property string addr: ""
        interval: 60
        onTriggered: Quickshell.execDetached(["hyprctl", "dispatch", 'hl.dsp.focus({ window = "address:' + addr + '" })'])
    }

    // Botón de la barra: cerrado → abre desplegado desde el botón; asomado → fija; fijado → cierra.
    function toggleFromBar(screen, x) {
        if (mode === "closed") open("bar", screen, "pinned", x);
        else if (mode === "peek") pin();
        else close();
    }
    // Atajo global y diagnóstico: panel fijado en el borde configurado del monitor con el foco.
    function toggleShortcut() {
        if (mode === "closed") { open("edge", Hyprland.focusedMonitor?.name ?? Quickshell.screens[0].name, "pinned"); exclusiveKeys = true; }
        else close();
    }

    function holdOpen() { graceTimer.stop(); }
    // Al perder el hover se espera un poco y se vuelve a comprobar: pasar del borde al panel no debe cerrarlo, y un orden
    // distinto de eventos (el panel recibe el hover antes de que la zona lo pierda) tampoco.
    function leave() { if (autoClose && shown) graceTimer.restart(); }

    // La posición real del cursor manda: tras abrir bajo un puntero quieto el compositor puede no enviar el «enter» al
    // panel hasta que se mueva, y eso cerraba el panel con el puntero encima.
    Timer {
        id: watch
        interval: 250
        repeat: true
        running: root.autoClose && root.shown && !root.keepOpen
        onTriggered: if (!cursorProc.running) cursorProc.running = true
    }
    Process {
        id: cursorProc
        command: ["hyprctl", "cursorpos", "-j"]
        stdout: StdioCollector { id: cursorOut }
        onExited: {
            try {
                const c = JSON.parse(cursorOut.text), r = root.panelRect, m = 10;
                root.pointerInside = c.x >= r.x - m && c.x <= r.x + r.width + m && c.y >= r.y - m && c.y <= r.y + r.height + m;
            } catch (e) { root.pointerInside = true; }          // sin datos: no cerrar
            if (root.pointerInside) { root.enteredOnce = true; graceTimer.stop(); }
            else if (root.autoClose && root.shown && !graceTimer.running) {
                // Sin hover: se cierra tras la espera. Si el cursor aún no ha entrado (p. ej. abierto con el atajo), se le da
                // un margen largo y la actividad de teclado lo renueva.
                if (root.enteredOnce) graceTimer.restart();
                else if (Date.now() - root.openedAt > 8000) graceTimer.restart();
            }
        }
    }
    Timer {
        id: graceTimer
        interval: OmniaSettings.closeGraceMs
        onTriggered: {
            if (!root.autoClose || root.pointerInside || root.keepOpen) return;      // manda la posición real del cursor
            console.log("[Omnia] panel cerrado: el puntero salió");
            root.close();
        }
    }

    property GlobalShortcut shortcut: GlobalShortcut {
        name: "omniaToggle"
        description: "Abrir o cerrar el panel de Omnia"
        onPressed: root.toggleShortcut()
    }

    // Control y diagnóstico por IPC:  qs -c ii ipc call omnia toggle | open | close | status | settings | bigmode | padprompt | setting
    IpcHandler {
        target: "omnia"
        function toggle(): void { root.toggleShortcut(); }
        function open(): void { if (root.mode === "closed") root.toggleShortcut(); }
        function close(): void { root.close(); }
        function pin(): void { root.pin(); }
        function settings(): void { if (root.mode === "closed") root.toggleShortcut(); root.viewRequested("settings"); }
        function bar(x: int): void { root.close(); root.open("bar", Hyprland.focusedMonitor?.name ?? Quickshell.screens[0].name, "pinned", x); }
        function barToggle(x: int): void {
            if (root.mode === "closed") root.open("bar", Hyprland.focusedMonitor?.name ?? Quickshell.screens[0].name, "pinned", x);
            else root.close();
        }
        function key(name: string): void { root.navRequested(name); }
        function menu(): void { if (root.mode === "closed") root.toggleShortcut(); root.viewRequested("menu"); }
        function setting(name: string, json: string): string {
            try { OmniaSettings.set(name, JSON.parse(json)); return "ok"; } catch (e) { return "error: " + e; }
        }
        function bigmode(): void { OmniaApi.openLibrary(); }
        function padprompt(): void { OmniaPadPrompt.preview(); }
        function library(): void { OmniaApi.openLibrary(); }
        function libraryCommand(): string { return JSON.stringify(OmniaSettings.libraryCommand); }
        function status(): string {
            return JSON.stringify({ mode: root.mode, origin: root.origin, screen: root.screenName, anchorX: root.anchorX,
                otherPanelOpen: root.otherPanelOpen, fullscreen: root.fullscreenAny, canPeek: root.canPeek,
                focused: Hyprland.focusedMonitor?.name ?? "", api: OmniaApi.status, activation: OmniaSettings.activation,
                edge: OmniaSettings.edgeSide + "/" + OmniaSettings.edgePosition, autoClose: root.autoClose, hoverPanel: root.hoverPanel, hoverZone: root.hoverZone, pointerInside: root.pointerInside, rect: [root.panelRect.x, root.panelRect.y, root.panelRect.width, root.panelRect.height], pinnedWallpaper: OmniaWallpaper.pinned });
        }
    }
}

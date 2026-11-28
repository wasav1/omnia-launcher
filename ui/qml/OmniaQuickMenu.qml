pragma ComponentBehavior: Bound

import QtQuick
import "Theme.js" as Theme

/** Menú rápido de Big Mode (rediseño D, fase 5a). Se abre con el botón Start del mando, con el
 *  botón de la barra superior o con Ctrl+M. Reúne lo que se cambia sin salir del sofá: volumen,
 *  perfil de energía y límite de FPS (fase 7), HUD de rendimiento, todos los ajustes, volver al escritorio,
 *  suspender y apagar.
 *
 *  Mando: ↑/↓ mueven, ←/→ cambian el valor, A elige, B o Start cierran.
 *  Apagar pide confirmación: hay que elegirlo dos veces. */
Item {
    id: menu
    required property var host
    readonly property var api: host.api
    readonly property real s: host.s
    property bool open: false
    property int current: 0
    property int volume: -1                 // -1 mientras no se conoce
    property bool muted: false
    property bool confirmShutdown: false

    signal settingsRequested()
    signal desktopRequested()

    readonly property var items: [
        { key: "volume", label: qsTr("Volumen"), icon: "speaker" },
        { key: "profile", label: qsTr("Perfil de energía"), icon: "power" },
        { key: "fps", label: qsTr("Límite de FPS"), icon: "gamepad-2" },
        { key: "hud", label: qsTr("HUD de rendimiento"), icon: "activity" },
        { key: "settings", label: qsTr("Todos los ajustes"), icon: "settings" },
        { key: "desktop", label: qsTr("Ir al escritorio"), icon: "monitor" },
        { key: "suspend", label: qsTr("Suspender"), icon: "clock" },
        { key: "shutdown", label: confirmShutdown ? qsTr("Pulsa otra vez para apagar") : qsTr("Apagar"), icon: "power" }
    ]

    function show() {
        current = 0
        confirmShutdown = false
        open = true
        refreshVolume()
        if (api.loadPower) api.loadPower()
        menu.forceActiveFocus()
    }
    function hide() { open = false; confirmShutdown = false }
    function toggle() { if (open) hide(); else show() }

    function refreshVolume() {
        api.setAudioLevel("output", {}, function(status, body) {
            if (status === 200 && body) { menu.volume = Math.min(100, Number(body.volume) || 0); menu.muted = body.muted === true }
        })
    }
    function changeVolume(delta) {
        const next = Math.max(0, Math.min(100, (volume < 0 ? 50 : volume) + delta))
        volume = next
        api.setAudioLevel("output", { volume: next, muted: false }, function(status, body) {
            if (status === 200 && body) { menu.volume = Math.min(100, Number(body.volume) || 0); menu.muted = body.muted === true }
            else menu.api.notify((body && body.error) || qsTr("No se pudo cambiar el volumen."))
        })
    }
    function toggleMute() {
        api.setAudioLevel("output", { muted: !muted }, function(status, body) {
            if (status === 200 && body) { menu.volume = Math.min(100, Number(body.volume) || 0); menu.muted = body.muted === true }
        })
    }
    function saved(status, body) {
        if (status !== 200) menu.api.notify((body && body.error) || qsTr("No se pudo guardar el ajuste."))
    }
    // HUD: se muestra u oculta en todos los juegos con MangoHud (no_display en el archivo de Omnia).
    function toggleHud() { api.setPerformance({ hud_visible: !api.hudVisible }, saved) }
    function stepFps(direction) {
        const list = api.fpsLimits || [0]
        const i = Math.max(0, list.indexOf(api.fpsLimit))
        const next = list[Math.max(0, Math.min(list.length - 1, i + direction))]
        if (next !== api.fpsLimit) api.setPerformance({ fps_limit: next }, saved)
    }
    function stepProfile(direction, wrap) {
        const list = (api.powerProfile && api.powerProfile.profiles) || []
        if (!list.length) { api.notify(qsTr("El perfil de energía no está disponible en este equipo.")); return }
        const i = Math.max(0, list.indexOf(api.powerProfile.current))
        let n = i + direction
        n = wrap ? (n + list.length) % list.length : Math.max(0, Math.min(list.length - 1, n))
        if (n !== i) api.setPowerProfile(list[n], saved)
    }
    function activate(i) {
        const key = items[i] ? items[i].key : ""
        if (key !== "shutdown") confirmShutdown = false
        if (key === "volume") toggleMute()
        else if (key === "hud") toggleHud()
        else if (key === "profile") stepProfile(1, true)
        else if (key === "fps") stepFps(1)
        else if (key === "settings") { hide(); settingsRequested() }
        else if (key === "desktop") { hide(); desktopRequested() }
        else if (key === "suspend") { hide(); api.power("suspend") }
        else if (key === "shutdown") {
            if (!confirmShutdown) { confirmShutdown = true; return }
            hide(); api.power("shutdown")
        }
    }
    function adjust(direction) {          // ←/→
        const key = items[current].key
        if (key === "volume") changeVolume(direction * 5)
        else if (key === "hud") { if ((direction > 0) !== api.hudVisible) toggleHud() }
        else if (key === "profile") stepProfile(direction, false)
        else if (key === "fps") stepFps(direction)
    }
    function move(delta) {
        current = (current + delta + items.length) % items.length
        if (items[current].key !== "shutdown") confirmShutdown = false
    }
    // Devuelve true si consumió la tecla lógica del mando.
    function pad(k) {
        if (!open) return false
        if (k === "u") move(-1)
        else if (k === "d") move(1)
        else if (k === "l") adjust(-1)
        else if (k === "r") adjust(1)
        else if (k === "A") activate(current)
        else if (k === "B" || k === "START") hide()
        return true
    }
    Keys.onPressed: function(e) {
        const map = { [Qt.Key_Up]: "u", [Qt.Key_Down]: "d", [Qt.Key_Left]: "l", [Qt.Key_Right]: "r",
                      [Qt.Key_Return]: "A", [Qt.Key_Enter]: "A", [Qt.Key_Space]: "A", [Qt.Key_Escape]: "B" }
        if (e.key === Qt.Key_M && (e.modifiers & Qt.ControlModifier)) { hide(); e.accepted = true; return }
        e.accepted = !!map[e.key] && pad(map[e.key])
    }

    anchors.fill: parent
    visible: open
    z: 60

    Rectangle {        // velo: tocar fuera cierra
        anchors.fill: parent
        color: "#8C03060B"
        MouseArea { anchors.fill: parent; onClicked: menu.hide() }
    }

    Rectangle {
        id: panel
        anchors { right: parent.right; top: parent.top; bottom: parent.bottom; margins: menu.s * 28 }
        width: menu.s * 460
        radius: menu.s * 26
        color: "#F20C121B"
        border.color: Theme.color.glassBorderStrong
        MouseArea { anchors.fill: parent }          // los clics dentro no cierran
        Rectangle { anchors { left: parent.left; right: parent.right; top: parent.top; leftMargin: parent.radius; rightMargin: parent.radius } height: 1; color: Theme.color.glassHighlight }

        // ---- cabecera: título, hora y mando
        Column {
            id: head
            anchors { left: parent.left; right: parent.right; top: parent.top; margins: menu.s * 28 }
            spacing: menu.s * 6
            Item {
                width: parent.width; height: menu.s * 40
                Text { anchors.verticalCenter: parent.verticalCenter; text: qsTr("Menú rápido"); color: Theme.color.ink; font.family: menu.host.uiFont; font.pixelSize: menu.s * 30; font.weight: Font.Bold }
                Text { anchors { right: parent.right; verticalCenter: parent.verticalCenter } text: menu.host.clockLabel; color: Theme.color.soft; font.family: menu.host.uiFont; font.pixelSize: menu.s * 20 }
            }
            Text {
                width: parent.width
                text: menu.api.padOn
                      ? (menu.api.padName || qsTr("Mando conectado")) + (menu.api.padBattery && menu.api.padBattery.level !== undefined ? "  ·  " + qsTr("Batería %1 %").arg(menu.api.padBattery.level) : "")
                      : qsTr("Sin mando conectado")
                color: Theme.color.muted; font.family: menu.host.uiFont; font.pixelSize: menu.s * 17; elide: Text.ElideRight
            }
        }
        Rectangle { id: divider; anchors { left: parent.left; right: parent.right; top: head.bottom; topMargin: menu.s * 18 } height: 1; color: Theme.color.glassBorder }

        // ---- opciones
        Column {
            anchors { left: parent.left; right: parent.right; top: divider.bottom; margins: menu.s * 16; topMargin: menu.s * 14 }
            spacing: menu.s * 6
            Repeater {
                model: menu.items
                delegate: Rectangle {
                    id: row
                    required property var modelData
                    required property int index
                    readonly property bool focused: menu.current === index
                    readonly property bool danger: modelData.key === "shutdown" && menu.confirmShutdown
                    width: parent.width
                    height: modelData.key === "volume" ? menu.s * 92 : menu.s * 62
                    radius: menu.s * 16
                    color: focused ? Theme.color.accentSoft : (rowMa.containsMouse ? Theme.color.glassFill : "transparent")
                    border.width: focused ? menu.s * 3 : 0
                    border.color: danger ? Theme.color.danger : Theme.color.accent

                    LucideIcon { x: menu.s * 18; y: menu.s * 19; width: menu.s * 24; height: width; name: row.modelData.icon; color: row.danger ? Theme.color.danger : (row.focused ? Theme.color.accentLight : Theme.color.soft) }
                    Text {
                        x: menu.s * 58; y: menu.s * 16
                        text: row.modelData.label
                        color: row.danger ? Theme.color.danger : Theme.color.ink
                        font.family: menu.host.uiFont; font.pixelSize: menu.s * 21; font.weight: row.focused ? Font.DemiBold : Font.Normal
                    }
                    // volumen: barra y porcentaje
                    Item {
                        visible: row.modelData.key === "volume"
                        anchors { left: parent.left; right: parent.right; bottom: parent.bottom; leftMargin: menu.s * 58; rightMargin: menu.s * 20; bottomMargin: menu.s * 18 }
                        height: menu.s * 22
                        Rectangle {
                            id: track
                            anchors { left: parent.left; right: volText.left; rightMargin: menu.s * 14; verticalCenter: parent.verticalCenter }
                            height: menu.s * 8; radius: height / 2; color: Theme.color.inset
                            Rectangle { width: Math.max(0, menu.volume) / 100 * parent.width; height: parent.height; radius: parent.radius; color: menu.muted ? Theme.color.muted : Theme.color.accent }
                            MouseArea {
                                anchors.fill: parent; anchors.margins: -menu.s * 8
                                cursorShape: Qt.PointingHandCursor
                                onClicked: mouse => { menu.current = row.index; menu.changeVolume(Math.round(mouse.x / track.width * 20) * 5 - Math.max(0, menu.volume)) }
                            }
                        }
                        Text { id: volText; anchors { right: parent.right; verticalCenter: parent.verticalCenter } width: menu.s * 64; horizontalAlignment: Text.AlignRight
                            text: menu.volume < 0 ? "…" : (menu.muted ? qsTr("Silencio") : menu.volume + " %")
                            color: Theme.color.soft; font.family: Theme.font.numeric; font.pixelSize: menu.s * 22; font.weight: Font.DemiBold }
                    }
                    // perfil y límite de FPS: valor actual con flechas
                    Row {
                        visible: row.modelData.key === "profile" || row.modelData.key === "fps"
                        anchors { right: parent.right; rightMargin: menu.s * 20; verticalCenter: parent.verticalCenter }
                        spacing: menu.s * 10
                        LucideIcon { anchors.verticalCenter: parent.verticalCenter; width: menu.s * 20; height: width; name: "chevron-left"; color: row.focused ? Theme.color.accentLight : Theme.color.muted }
                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            text: row.modelData.key === "fps" ? menu.api.fpsLabel(menu.api.fpsLimit)
                                : (menu.api.powerProfile && menu.api.powerProfile.available ? menu.api.profileLabel(menu.api.powerProfile.current) : qsTr("No disponible"))
                            color: Theme.color.ink; font.family: menu.host.uiFont; font.pixelSize: menu.s * 19; font.weight: Font.DemiBold
                        }
                        LucideIcon { anchors.verticalCenter: parent.verticalCenter; width: menu.s * 20; height: width; name: "chevron-right"; color: row.focused ? Theme.color.accentLight : Theme.color.muted }
                    }
                    // HUD: interruptor
                    Rectangle {
                        visible: row.modelData.key === "hud"
                        anchors { right: parent.right; rightMargin: menu.s * 20; verticalCenter: parent.verticalCenter }
                        width: menu.s * 58; height: menu.s * 32; radius: height / 2
                        color: menu.api.hudVisible ? Theme.color.accent : Theme.color.inset
                        border.color: menu.api.hudVisible ? Theme.color.accent : Theme.color.glassBorderStrong
                        Rectangle {
                            x: menu.api.hudVisible ? parent.width - width - menu.s * 4 : menu.s * 4
                            anchors.verticalCenter: parent.verticalCenter
                            width: menu.s * 24; height: width; radius: width / 2
                            color: menu.api.hudVisible ? Theme.color.accentInk : Theme.color.soft
                            Behavior on x { NumberAnimation { duration: 120 } }
                        }
                    }
                    MouseArea {
                        id: rowMa
                        anchors.fill: parent
                        enabled: row.modelData.key !== "volume"
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: { menu.current = row.index; menu.activate(row.index) }
                    }
                }
            }
        }

        // ---- ayuda de botones
        Row {
            anchors { left: parent.left; bottom: parent.bottom; margins: menu.s * 28 }
            spacing: menu.s * 22
            Repeater {
                model: [{ k: "A", l: qsTr("Elegir / silenciar") }, { k: "←→", l: qsTr("Ajustar") }, { k: "B", l: qsTr("Cerrar") }]
                delegate: Row {
                    id: hint
                    required property var modelData
                    spacing: menu.s * 8
                    Rectangle {
                        anchors.verticalCenter: parent.verticalCenter
                        width: Math.max(menu.s * 30, hintKey.implicitWidth + menu.s * 14); height: menu.s * 30; radius: height / 2
                        color: Theme.color.inset; border.color: Theme.color.glassBorderStrong
                        Text { id: hintKey; anchors.centerIn: parent; text: hint.modelData.k; color: Theme.color.ink; font.family: menu.host.uiFont; font.pixelSize: menu.s * 15; font.weight: Font.Bold }
                    }
                    Text { anchors.verticalCenter: parent.verticalCenter; text: hint.modelData.l; color: Theme.color.muted; font.family: menu.host.uiFont; font.pixelSize: menu.s * 17 }
                }
            }
        }
    }
}

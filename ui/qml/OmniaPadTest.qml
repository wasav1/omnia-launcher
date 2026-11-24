pragma ComponentBehavior: Bound

import QtQuick

/** Prueba en vivo de un mando: cada botón, stick, gatillo y la cruceta se iluminan al usarlos. Se cierra manteniendo B 1,2 s,
 *  con Esc o pulsando «Cerrar». Lee /pads cada 60 ms (el estado crudo no pasa por el filtro de teclas de la interfaz). */
Item {
    id: t
    required property var host
    property string padId: ""
    signal closed()
    readonly property real s: t.host.s
    property var pad: null
    property real heldB: 0
    property bool done: false
    readonly property string family: t.pad ? t.pad.family : "xbox"
    readonly property bool nintendo: t.family === "switch"
    function down(label) { return !!t.pad && t.pad.buttons.indexOf(label) >= 0 }
    function finish() { if (!t.done) { t.done = true; t.closed() } }
    focus: true
    Component.onCompleted: forceActiveFocus()
    Keys.onPressed: function(e) { if (e.key === Qt.Key_Escape) t.finish(); e.accepted = true }

    Timer {
        interval: 60; running: !t.done; repeat: true; triggeredOnStart: true
        onTriggered: t.host.api.loadPads(function(st, body) {
            if (st !== 200) return
            t.pad = (body.pads || []).find(function(x) { return x.id === t.padId }) || null
            t.heldB = t.down("B") ? t.heldB + 0.06 : 0
            if (t.heldB >= 1.2) t.finish()
        })
    }

    Rectangle { anchors.fill: parent; color: Qt.rgba(0.02, 0.03, 0.05, 0.93) }
    MouseArea { anchors.fill: parent }

    Item {
        id: card
        anchors.centerIn: parent
        width: t.s * 1180; height: t.s * 700
        Text { anchors { horizontalCenter: parent.horizontalCenter; top: parent.top } text: t.pad ? qsTr("Prueba · %1").arg(t.pad.nickname || t.pad.name) : qsTr("El mando se desconectó"); color: t.host.ink; font.family: t.host.uiFont; font.pixelSize: t.s * 34; font.weight: Font.DemiBold }

        component Glyph: PadGlyph {
            property bool on: false
            family: t.family
            size: t.s * 62
            opacity: on ? 1 : 0.3
            scale: on ? 1.2 : 1
            Behavior on opacity { NumberAnimation { duration: 80 } }
            Behavior on scale { NumberAnimation { duration: 80 } }
        }
        component Stick: Item {
            id: stick
            property real ax: 0
            property real ay: 0
            property bool pressed: false
            width: t.s * 190; height: width
            Rectangle { anchors.fill: parent; radius: width / 2; color: stick.pressed ? Qt.rgba(0.36, 0.61, 0.88, 0.35) : Qt.rgba(1, 1, 1, 0.06); border.width: 2; border.color: Qt.rgba(1, 1, 1, 0.3) }
            Rectangle { x: parent.width / 2 - width / 2; y: parent.height / 2 - height / 2; width: 1; height: 1; color: "transparent" }
            Rectangle { id: dot; width: stick.width * 0.34; height: width; radius: width / 2; color: t.host.ring
                x: stick.width / 2 - width / 2 + stick.ax * stick.width * 0.33; y: stick.height / 2 - height / 2 + stick.ay * stick.height * 0.33
                Behavior on x { NumberAnimation { duration: 50 } }
                Behavior on y { NumberAnimation { duration: 50 } } }
        }
        component Trigger: Item {
            id: trig
            property real value: 0
            property string label: ""
            width: t.s * 64; height: t.s * 150
            Rectangle { anchors.fill: parent; radius: t.s * 12; color: Qt.rgba(1, 1, 1, 0.07); border.width: 2; border.color: Qt.rgba(1, 1, 1, 0.3) }
            Rectangle { anchors { left: parent.left; right: parent.right; bottom: parent.bottom } height: parent.height * Math.min(1, trig.value); radius: t.s * 12; color: t.host.ring }
            Text { anchors { horizontalCenter: parent.horizontalCenter; top: parent.bottom; topMargin: t.s * 8 } text: trig.label + "  " + Math.round(trig.value * 100) + " %"; color: t.host.ink2; font.family: t.host.uiFont; font.pixelSize: t.s * 18 }
        }

        // hombros y gatillos
        Glyph { x: t.s * 200; y: t.s * 100; key: "LB"; on: t.down("LB") }
        Glyph { x: card.width - t.s * 262; y: t.s * 100; key: "RB"; on: t.down("RB") }
        Trigger { x: t.s * 90; y: t.s * 100; label: "LT"; value: t.pad ? t.pad.lt : 0 }
        Trigger { x: card.width - t.s * 154; y: t.s * 100; label: "RT"; value: t.pad ? t.pad.rt : 0 }
        // sticks
        Stick { x: t.s * 170; y: t.s * 240; ax: t.pad ? t.pad.lx : 0; ay: t.pad ? t.pad.ly : 0; pressed: t.down("LS") }
        Stick { x: card.width - t.s * 530; y: t.s * 430; ax: t.pad ? t.pad.rx : 0; ay: t.pad ? t.pad.ry : 0; pressed: t.down("RS") }
        // cruceta
        Item {
            x: t.s * 410; y: t.s * 440; width: t.s * 160; height: width
            Rectangle { x: parent.width / 2 - width / 2; y: 0; width: t.s * 50; height: t.s * 64; radius: t.s * 8; color: t.pad && t.pad.haty < 0 ? t.host.ring : Qt.rgba(1, 1, 1, 0.14) }
            Rectangle { x: parent.width / 2 - width / 2; y: parent.height - height; width: t.s * 50; height: t.s * 64; radius: t.s * 8; color: t.pad && t.pad.haty > 0 ? t.host.ring : Qt.rgba(1, 1, 1, 0.14) }
            Rectangle { x: 0; y: parent.height / 2 - height / 2; width: t.s * 64; height: t.s * 50; radius: t.s * 8; color: t.pad && t.pad.hatx < 0 ? t.host.ring : Qt.rgba(1, 1, 1, 0.14) }
            Rectangle { x: parent.width - width; y: parent.height / 2 - height / 2; width: t.s * 64; height: t.s * 50; radius: t.s * 8; color: t.pad && t.pad.hatx > 0 ? t.host.ring : Qt.rgba(1, 1, 1, 0.14) }
        }
        // botones de acción (la posición sigue al mando: en Nintendo A está a la derecha y B abajo)
        Item {
            x: card.width - t.s * 360; y: t.s * 250; width: t.s * 220; height: width
            Glyph { x: parent.width / 2 - width / 2; y: parent.height - height; key: t.nintendo ? "B" : "A"; on: t.down(key) }
            Glyph { x: parent.width - width; y: parent.height / 2 - height / 2; key: t.nintendo ? "A" : "B"; on: t.down(key) }
            Glyph { x: 0; y: parent.height / 2 - height / 2; key: t.nintendo ? "Y" : "X"; on: t.down(key) }
            Glyph { x: parent.width / 2 - width / 2; y: 0; key: t.nintendo ? "X" : "Y"; on: t.down(key) }
        }
        // sistema
        Row {
            x: card.width / 2 - width / 2; y: t.s * 270; spacing: t.s * 28
            Glyph { key: "SELECT"; on: t.down("SELECT") }
            Glyph { key: "MODE"; on: t.down("MODE") }
            Glyph { key: "START"; on: t.down("START") }
        }
        // salida
        Rectangle {
            anchors { horizontalCenter: parent.horizontalCenter; bottom: parent.bottom }
            width: t.s * 560; height: t.s * 54; radius: height / 2; color: Qt.rgba(1, 1, 1, 0.08); border.width: 1; border.color: Qt.rgba(1, 1, 1, 0.2)
            Rectangle { visible: t.heldB > 0; x: 0; y: 0; height: parent.height; width: parent.width * Math.min(1, t.heldB / 1.2); radius: height / 2; color: Qt.rgba(0.36, 0.61, 0.88, 0.45) }
            Text { anchors.centerIn: parent; text: qsTr("Mantén B 1 s para salir · Esc · clic aquí"); color: t.host.ink; font.family: t.host.uiFont; font.pixelSize: t.s * 21 }
            MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: t.finish() }
        }
    }
}

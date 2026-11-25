pragma ComponentBehavior: Bound

import QtQuick

/** Teclado virtual para el mando: se mueve con el D-pad, A escribe, X borra, Y espacio, START/«Buscar» acepta, B cierra.
 *  El texto se aplica en vivo (`textChanged2`). */
Item {
    id: kb
    property string text: ""
    property real uiScale: 1
    property color ink: "#F0F3F7"
    property color ink2: "#B8C3D0"
    property color accent: "#336599"
    property string uiFont: "Hanken Grotesk"
    property bool open: false
    signal textChanged2(string value)
    signal closed(bool accepted)
    property bool pathMode: false
    property bool caps: false
    readonly property var rows: [
        ["1","2","3","4","5","6","7","8","9","0"],
        ["q","w","e","r","t","y","u","i","o","p"],
        ["a","s","d","f","g","h","j","k","l","ñ"],
        ["z","x","c","v","b","n","m","-",pathMode ? "/" : "'", "."],
        pathMode ? ["@shift", "@underscore", "@space", "@back", "@ok"] : ["@space", "@back", "@clear", "@ok"]
    ]
    property int r: 1
    property int c: 0
    visible: open || shade.opacity > 0.01
    function show(initial, mode) {
        text = initial || ""; pathMode = mode === "path"; caps = false; r = 1; c = 0; open = true
        forceActiveFocus()
    }
    function close(accepted) { if (open) { open = false; closed(accepted === true) } }
    function setText(t) { text = t; textChanged2(t) }
    function press(code) {
        if (code === "@space") setText(text + " ")
        else if (code === "@back") setText(text.slice(0, -1))
        else if (code === "@clear") setText("")
        else if (code === "@ok") close(true)
        else if (code === "@shift") caps = !caps
        else if (code === "@underscore") setText(text + "_")
        else setText(text + (caps ? code.toUpperCase() : code))
    }
    function pad(k) {
        const n = rows[r].length
        if (k === "l") c = (c + n - 1) % n
        else if (k === "r") c = (c + 1) % n
        else if (k === "u") { r = (r + rows.length - 1) % rows.length; c = Math.min(c, rows[r].length - 1) }
        else if (k === "d") { r = (r + 1) % rows.length; c = Math.min(c, rows[r].length - 1) }
        else if (k === "A") press(rows[r][c])
        else if (k === "X") press("@back")
        else if (k === "Y") press("@space")
        else if (k === "START") close(true)
        else if (k === "LB" && pathMode) caps = !caps
        else if (k === "B") close()
    }
    function key(event) {
        if (event.key === Qt.Key_Escape) close()
        else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) close(true)
        else if (event.key === Qt.Key_Backspace) press("@back")
        else if (event.text && event.text.length === 1 && event.text >= " " && !(event.modifiers & Qt.ControlModifier))
            setText(text + event.text)
        return true
    }
    Keys.onPressed: function(event) { event.accepted = kb.open && kb.key(event) }
    Rectangle {
        id: shade
        anchors.fill: parent; color: "#000000"; opacity: kb.open ? 0.5 : 0
        Behavior on opacity { NumberAnimation { duration: 160 } }
        MouseArea { anchors.fill: parent; onClicked: kb.close() }
    }
    Rectangle {
        id: panel
        width: kb.uiScale * 860
        height: kb.uiScale * 520
        anchors.horizontalCenter: parent.horizontalCenter
        y: kb.open ? parent.height - height - kb.uiScale * 120 : parent.height + kb.uiScale * 20
        Behavior on y { NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }
        radius: kb.uiScale * 24
        color: "#F2101820"; border.color: "#2effffff"
        MouseArea { anchors.fill: parent }
        Rectangle {      // campo de texto
            x: kb.uiScale * 24; y: kb.uiScale * 22
            width: parent.width - kb.uiScale * 48; height: kb.uiScale * 56; radius: height / 2
            color: "#14ffffff"; border.color: "#5b9be0"
            LucideIcon { x: kb.uiScale * 18; anchors.verticalCenter: parent.verticalCenter; width: kb.uiScale * 22; height: width; name: "search"; color: kb.ink }
            Text {
                anchors { left: parent.left; leftMargin: kb.uiScale * 54; right: parent.right; rightMargin: kb.uiScale * 20; verticalCenter: parent.verticalCenter }
                text: kb.text !== "" ? kb.text : kb.pathMode ? qsTr("Ruta de la carpeta…") : qsTr("Buscar juego…")
                color: kb.text !== "" ? kb.ink : kb.ink2
                font.family: kb.uiFont; font.pixelSize: kb.uiScale * 24; elide: Text.ElideLeft
            }
        }
        Column {
            x: kb.uiScale * 24; y: kb.uiScale * 100
            width: parent.width - kb.uiScale * 48
            spacing: kb.uiScale * 10
            Repeater {
                model: kb.rows
                delegate: Row {
                    id: kRow
                    required property var modelData
                    required property int index
                    spacing: kb.uiScale * 10
                    anchors.horizontalCenter: parent.horizontalCenter
                    Repeater {
                        model: kRow.modelData
                        delegate: Rectangle {
                            id: key
                            required property string modelData
                            required property int index
                            readonly property bool special: modelData.charAt(0) === "@"
                            readonly property bool on: kb.r === kRow.index && kb.c === index
                            width: special ? kb.uiScale * (kb.pathMode ? 146 : 190) : kb.uiScale * 70
                            height: kb.uiScale * 62
                            radius: kb.uiScale * 14
                            color: on ? kb.accent : (kma.containsMouse ? "#26ffffff" : "#14ffffff")
                            border.color: on ? "#5b9be0" : "#1fffffff"; border.width: on ? 2 : 1
                            Text {
                                anchors.centerIn: parent
                                text: {
                                    const value = key.modelData
                                    if (value === "@space") return qsTr("Espacio")
                                    if (value === "@back") return qsTr("Borrar")
                                    if (value === "@clear") return qsTr("Limpiar")
                                    if (value === "@shift") return kb.caps ? "ABC" : "abc"
                                    if (value === "@underscore") return "_"
                                    if (value === "@ok") return kb.pathMode ? qsTr("Guardar") : qsTr("Buscar")
                                    return kb.pathMode && !kb.caps ? value : value.toUpperCase()
                                }
                                color: kb.ink; font.family: kb.uiFont; font.pixelSize: kb.uiScale * (key.special ? 20 : 26); font.weight: Font.DemiBold
                            }
                            MouseArea {
                                id: kma; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                                onClicked: { kb.r = kRow.index; kb.c = key.index; kb.press(key.modelData) }
                            }
                        }
                    }
                }
            }
        }
        Text {
            anchors { horizontalCenter: parent.horizontalCenter; bottom: parent.bottom; bottomMargin: kb.uiScale * 14 }
            text: kb.pathMode ? qsTr("A escribir · LB mayúsculas · START guardar · B cancelar") : qsTr("A escribir · X borrar · Y espacio · START buscar · B cerrar")
            color: kb.ink2; font.family: kb.uiFont; font.pixelSize: kb.uiScale * 15
        }
    }
}

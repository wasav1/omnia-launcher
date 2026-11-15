import QtQuick

// Fila del monitor del PC: nombre, valor y barra fina (compacta).
Item {
    id: hr
    property string label: ""
    property string sub: ""
    property real pct: 0
    property string vtext: ""
    property string extra: ""
    property color extraColor: ink2
    property color acc: "#e6d9a0"
    property color ink: "#f3efe3"
    property color ink2: "#d6d0bf"
    property color ink3: "#a59f8f"
    property string hudFont: "Rajdhani"
    width: 320; height: 42
    Row {
        width: parent.width
        Text { id: hl; text: hr.label; color: hr.ink; font.family: hr.hudFont; font.pixelSize: 18; font.weight: Font.DemiBold; font.letterSpacing: 1.2 }
        Text { text: "  " + hr.sub.toUpperCase(); color: hr.ink3; font.family: hr.hudFont; font.pixelSize: 13; font.letterSpacing: 1.3; y: 4 }
    }
    Row {
        anchors.right: parent.right; spacing: 8
        Text { text: hr.vtext; color: hr.ink; font.family: hr.hudFont; font.pixelSize: 18; font.weight: Font.DemiBold }
        Text { visible: hr.extra !== ""; text: hr.extra; color: hr.extraColor; font.family: hr.hudFont; font.pixelSize: 18; font.weight: Font.Medium }
    }
    Rectangle {
        y: 28; width: parent.width; height: 3; radius: 2; color: "#2effffff"
        Rectangle {
            height: parent.height; radius: 2
            width: parent.width * Math.max(0, Math.min(1, hr.pct / 100))
            color: hr.pct >= 90 ? "#e2604f" : (hr.pct >= 75 ? "#e6a850" : hr.acc)
            Behavior on width { NumberAnimation { duration: 800 } }
        }
    }
}

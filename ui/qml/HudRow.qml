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
    property color acc: "#91a9c2"
    property color ink: "#f3efe3"
    property color ink2: "#d6d0bf"
    property color ink3: "#a59f8f"
    property string hudFont: "Rajdhani"
    property bool charge: false          // true = nivel de carga (batería): rojo con poca y verde con mucha, en vez de aviso por saturación
    readonly property var chargeStops: [[0, "#e2443f"], [20, "#e8743f"], [40, "#e6b450"], [60, "#c9d45a"], [80, "#8fd46a"], [100, "#5fd08c"]]
    readonly property var usageStops: [[0, "#5fd08c"], [20, "#8fd46a"], [40, "#c9d45a"], [60, "#e6b450"], [80, "#e8743f"], [100, "#e2443f"]]
    function chargeColor(p) {
        const v = Math.max(0, Math.min(100, p))
        for (let i = 1; i < chargeStops.length; i++) {
            if (v <= chargeStops[i][0]) {
                const a = chargeStops[i - 1], b = chargeStops[i], f = (v - a[0]) / (b[0] - a[0])
                const ca = Qt.color(a[1]), cb = Qt.color(b[1])
                return Qt.rgba(ca.r + (cb.r - ca.r) * f, ca.g + (cb.g - ca.g) * f, ca.b + (cb.b - ca.b) * f, 1)
            }
        }
        return chargeStops[chargeStops.length - 1][1]
    }
    function usageColor(p) {
        const v = Math.max(0, Math.min(100, p))
        for (let i = 1; i < usageStops.length; i++) {
            if (v <= usageStops[i][0]) {
                const a = usageStops[i - 1], b = usageStops[i], f = (v - a[0]) / (b[0] - a[0])
                const ca = Qt.color(a[1]), cb = Qt.color(b[1])
                return Qt.rgba(ca.r + (cb.r - ca.r) * f, ca.g + (cb.g - ca.g) * f, ca.b + (cb.b - ca.b) * f, 1)
            }
        }
        return usageStops[usageStops.length - 1][1]
    }
    width: 320; height: 42
    Row {
        width: parent.width
        Text { id: hl; text: hr.label; color: hr.ink; font.family: hr.hudFont; font.pixelSize: 18; font.weight: Font.DemiBold; font.letterSpacing: 1.2 }
        Text { width: Math.max(0, hr.width - hl.implicitWidth - values.implicitWidth - 16); text: "  " + hr.sub.toUpperCase(); color: hr.ink3; font.family: hr.hudFont; font.pixelSize: 13; font.letterSpacing: 1.3; y: 4; elide: Text.ElideRight }
    }
    Row { id: values
        anchors.right: parent.right; spacing: 8
        Text { text: hr.vtext; color: hr.ink; font.family: hr.hudFont; font.pixelSize: 18; font.weight: Font.DemiBold }
        Text { visible: hr.extra !== ""; text: hr.extra; color: hr.extraColor; font.family: hr.hudFont; font.pixelSize: 18; font.weight: Font.Medium }
    }
    Rectangle {
        y: 28; width: parent.width; height: 3; radius: 2; color: "#2effffff"
        Rectangle {
            height: parent.height; radius: 2
            width: parent.width * Math.max(0, Math.min(1, hr.pct / 100))
            color: hr.charge ? hr.chargeColor(hr.pct) : hr.usageColor(hr.pct)
            Behavior on width { NumberAnimation { duration: 800 } }
        }
    }
}

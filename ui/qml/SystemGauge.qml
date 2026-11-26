import QtQuick

/** Anillo de uso (CPU, GPU, RAM) del panel Sistema de Big Mode: porcentaje en el centro, nombre debajo y una línea de detalle
 *  (temperatura, memoria…) con el color que le toque. `value` va de 0 a 1; negativo = sin dato. */
Item {
    id: g
    property real value: -1
    property string label: ""
    property string centerText: ""
    property string detail: ""
    property color detailColor: "#B8C3D0"
    property color ink: "#F0F3F7"
    property color ink2: "#B8C3D0"
    property color ringColor: "#5B9BE0"
    property string uiFont: "Hanken Grotesk"
    property real s: 1
    implicitWidth: s * 96
    implicitHeight: ring.height + col.implicitHeight

    Canvas {
        id: ring
        width: g.s * 78; height: width
        anchors.horizontalCenter: parent.horizontalCenter
        onPaint: {
            const ctx = getContext("2d")
            ctx.reset()
            const cx = width / 2, cy = height / 2, r = width / 2 - g.s * 6
            ctx.lineWidth = g.s * 7
            ctx.strokeStyle = "#243142"
            ctx.beginPath(); ctx.arc(cx, cy, r, 0, Math.PI * 2); ctx.stroke()
            if (g.value >= 0) {
                ctx.strokeStyle = g.ringColor
                ctx.lineCap = "round"
                ctx.beginPath()
                ctx.arc(cx, cy, r, -Math.PI / 2, -Math.PI / 2 + Math.PI * 2 * Math.max(0.02, Math.min(1, g.value)))
                ctx.stroke()
            }
        }
        Connections { target: g; function onValueChanged() { ring.requestPaint() } function onRingColorChanged() { ring.requestPaint() } }
        Component.onCompleted: requestPaint()
        Text { anchors.centerIn: parent; text: g.centerText; color: g.ink; font.family: g.uiFont; font.pixelSize: g.s * 19; font.weight: Font.DemiBold }
    }
    Column {
        id: col
        anchors { top: ring.bottom; topMargin: g.s * 6; horizontalCenter: parent.horizontalCenter }
        spacing: g.s * 2
        Text { anchors.horizontalCenter: parent.horizontalCenter; text: g.label; color: g.ink2; font.family: g.uiFont; font.pixelSize: g.s * 15 }
        Text { anchors.horizontalCenter: parent.horizontalCenter; visible: g.detail !== ""; text: g.detail; color: g.detailColor; font.family: g.uiFont; font.pixelSize: g.s * 15 }
    }
}

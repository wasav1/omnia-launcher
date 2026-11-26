import QtQuick

Row {
    id: hint
    required property real uiScale
    required property string uiFont
    required property color ink
    required property color muted
    required property string label
    property string glyph: ""
    property string icon: ""
    property bool roundButton: false
    // Con mando: teclas lógicas del núcleo (p. ej. ["A"] o ["LB", "RB"]) que se dibujan con los iconos reales del mando.
    property var padKeys: []
    property string padFamily: "xbox"

    spacing: uiScale * 9

    LucideIcon {
        anchors.verticalCenter: parent.verticalCenter
        width: hint.uiScale * 23
        height: width
        name: hint.icon
        color: hint.muted
        visible: hint.icon !== ""
    }
    Row {
        anchors.verticalCenter: parent.verticalCenter
        visible: hint.padKeys.length > 0
        spacing: hint.uiScale * 4
        Repeater {
            model: hint.padKeys
            delegate: PadGlyph {
                required property string modelData
                family: hint.padFamily
                key: modelData
                size: hint.uiScale * 34
            }
        }
    }
    Rectangle {
        anchors.verticalCenter: parent.verticalCenter
        visible: hint.glyph !== "" && hint.padKeys.length === 0
        height: hint.uiScale * 29
        width: Math.max(height, keyLabel.implicitWidth + hint.uiScale * 14)
        radius: hint.roundButton ? height / 2 : hint.uiScale * 7
        color: "transparent"
        border.color: hint.muted
        Text {
            id: keyLabel
            anchors.centerIn: parent
            text: hint.glyph
            color: hint.ink
            font.family: hint.uiFont
            font.pixelSize: hint.uiScale * 15
            font.weight: Font.DemiBold
        }
    }
    Text {
        anchors.verticalCenter: parent.verticalCenter
        text: hint.label
        color: hint.ink
        font.family: hint.uiFont
        font.pixelSize: hint.uiScale * 18
    }
}

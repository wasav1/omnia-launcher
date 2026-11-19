import QtQuick

Flow {
    id: guide
    property string padName: ""
    property var hints: []
    property int iconSize: 34
    property int fontPx: 16
    property color textColor: "#e9e6d6"
    property string fontFamily: "Rajdhani"
    spacing: 16

    readonly property string kind: {
        const name = padName.toLowerCase()
        if (/dualsense|dualshock|playstation|sony|ps[345]/.test(name)) return "ps"
        if (/nintendo|switch|joy-?con|pro controller/.test(name)) return "switch"
        if (/steam|valve|deck/.test(name)) return "deck"
        return "xbox"
    }

    function platformLabel(key) {
        const labels = {
            ps: { A: "×", B: "○", X: "□", Y: "△", LB: "L1", RB: "R1", LT: "L2", RT: "R2", SELECT: "Crear", START: "Opciones" },
            switch: { A: "B", B: "A", X: "Y", Y: "X", LB: "L", RB: "R", LT: "ZL", RT: "ZR", SELECT: "−", START: "+" },
            deck: { LB: "L1", RB: "R1", LT: "L2", RT: "R2", SELECT: "Vista", START: "Menú" },
            xbox: { SELECT: "Vista", START: "Menú" }
        }
        return labels[kind][key] || key
    }

    Repeater {
        model: guide.hints
        delegate: Row {
            id: hint
            required property var modelData
            spacing: 6
            Repeater {
                model: hint.modelData.k.split("+")
                delegate: Rectangle {
                    id: keycap
                    required property string modelData
                    readonly property var glyphNames: ({ "↑": "arrow-up", "↓": "arrow-down",
                        "←": "arrow-left", "→": "arrow-right", DPAD: "gamepad-2", LS: "gamepad-2" })
                    readonly property string glyph: glyphNames[modelData] || ""
                    width: glyph ? guide.iconSize : Math.max(guide.iconSize, keyLabel.implicitWidth + 8)
                    height: guide.iconSize
                    radius: height / 2
                    color: "#3217222e"
                    border.color: "#887e91a1"
                    LucideIcon {
                        anchors.centerIn: parent
                        width: parent.height * 0.72; height: width
                        name: keycap.glyph
                        color: guide.textColor
                        visible: name !== ""
                    }
                    Text {
                        id: keyLabel
                        anchors.centerIn: parent
                        visible: keycap.glyph === ""
                        text: guide.platformLabel(keycap.modelData)
                        color: guide.textColor
                        font.family: guide.fontFamily
                        font.pixelSize: guide.fontPx
                        font.bold: true
                    }
                }
            }
            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: hint.modelData.t
                color: guide.textColor
                font.family: guide.fontFamily
                font.pixelSize: guide.fontPx
                font.weight: Font.DemiBold
                font.letterSpacing: 0.6
            }
        }
    }
}

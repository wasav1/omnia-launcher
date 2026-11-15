import QtQuick

// Esquema de botones del mando conectado, con los iconos reales (Kenney Input Prompts, CC0) del tipo de mando detectado.
Flow {
    id: g
    property string padName: ""
    property var hints: []            // [{k: "A", t: "Jugar"}, ...]
    property int iconSize: 34
    property int fontPx: 16
    property color textColor: "#e9e6d6"
    property string fontFamily: "Rajdhani"
    spacing: 16

    readonly property string kind: {
        var n = padName.toLowerCase()
        if (/dualsense|dualshock|playstation|sony|ps[345]/.test(n)) return "ps"
        if (/nintendo|switch|joy-?con|pro controller/.test(n)) return "switch"
        if (/steam|valve|deck/.test(n)) return "deck"
        return "xbox"                  // Xbox y compatibles (por defecto)
    }
    readonly property var map: ({
        xbox:   { A: "xbox_button_a", B: "xbox_button_b", X: "xbox_button_x", Y: "xbox_button_y", LB: "xbox_lb", RB: "xbox_rb", LT: "xbox_lt", RT: "xbox_rt",
                  SELECT: "xbox_button_view", START: "xbox_button_menu", DPAD: "xbox_dpad", LS: "xbox_stick_l" },
        ps:     { A: "playstation_button_cross", B: "playstation_button_circle", X: "playstation_button_square", Y: "playstation_button_triangle",
                  LB: "playstation_trigger_l1", RB: "playstation_trigger_r1", LT: "playstation_trigger_l2", RT: "playstation_trigger_r2",
                  SELECT: "playstation5_button_create", START: "playstation5_button_options", DPAD: "playstation_dpad", LS: "playstation_stick_l" },
        // Nintendo: el botón de abajo se llama B y el de la derecha A (mismas posiciones físicas que el resto)
        "switch": { A: "switch_button_b", B: "switch_button_a", X: "switch_button_y", Y: "switch_button_x", LB: "switch_button_l", RB: "switch_button_r",
                  LT: "switch_button_zl", RT: "switch_button_zr", SELECT: "switch_button_minus", START: "switch_button_plus", DPAD: "switch_dpad", LS: "switch_stick_l" },
        deck:   { A: "steamdeck_button_a", B: "steamdeck_button_b", X: "steamdeck_button_x", Y: "steamdeck_button_y", LB: "steamdeck_button_l1", RB: "steamdeck_button_r1",
                  LT: "steamdeck_button_l2", RT: "steamdeck_button_r2", SELECT: "steamdeck_button_view", START: "steamdeck_button_options",
                  DPAD: "steamdeck_dpad", LS: "steamdeck_stick_l" }
    })
    function icon(k) { var m = map[kind]; return Qt.resolvedUrl("images/pad/" + kind + "/" + (m[k] || m.A) + ".png") }

    Repeater {
        model: g.hints
        delegate: Row {
            required property var modelData
            spacing: 6
            Repeater {
                model: modelData.k.split("+")
                delegate: Image {
                    required property string modelData
                    source: g.icon(modelData); width: g.iconSize; height: g.iconSize; smooth: true; mipmap: true; asynchronous: true
                    sourceSize.width: 96; sourceSize.height: 96
                }
            }
            Text { anchors.verticalCenter: parent.verticalCenter; text: modelData.t; color: g.textColor
                font.family: g.fontFamily; font.pixelSize: g.fontPx; font.weight: Font.DemiBold; font.letterSpacing: 0.6 }
        }
    }
}

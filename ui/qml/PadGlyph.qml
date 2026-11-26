import QtQuick

/** Icono real de un botón del mando (Kenney «Input Prompts», CC0; ver images/pad/LICENSE-Kenney-CC0.txt).
 *  `key` es la tecla lógica del núcleo (A B X Y LB RB LT RT START SELECT l r u d DPAD LS); `family` es el tipo de mando
 *  que detecta omnia-core (xbox | ps | switch | deck). La tecla «A» es siempre confirmar: en PlayStation es la cruz y
 *  en Switch el botón A (el derecho), tal como las etiqueta omnia-core. */
Image {
    id: glyph
    property string family: "xbox"
    property string key: ""
    property real size: 32

    readonly property var table: ({
        xbox:   { dir: "xbox",   A: "xbox_button_a", B: "xbox_button_b", X: "xbox_button_x", Y: "xbox_button_y",
                  LB: "xbox_lb", RB: "xbox_rb", LT: "xbox_lt", RT: "xbox_rt", START: "xbox_button_menu", SELECT: "xbox_button_view",
                  MODE: "xbox_guide", l: "xbox_dpad_horizontal", r: "xbox_dpad_horizontal", u: "xbox_dpad_vertical",
                  d: "xbox_dpad_vertical", DPAD: "xbox_dpad_all", LS: "xbox_stick_l" },
        ps:     { dir: "ps",     A: "playstation_button_cross", B: "playstation_button_circle", X: "playstation_button_square",
                  Y: "playstation_button_triangle", LB: "playstation_trigger_l1", RB: "playstation_trigger_r1",
                  LT: "playstation_trigger_l2", RT: "playstation_trigger_r2", START: "playstation5_button_options",
                  SELECT: "playstation5_button_create", MODE: "", l: "playstation_dpad_horizontal", r: "playstation_dpad_horizontal",
                  u: "playstation_dpad_vertical", d: "playstation_dpad_vertical", DPAD: "playstation_dpad_all", LS: "playstation_stick_l" },
        switch: { dir: "switch", A: "switch_button_a", B: "switch_button_b", X: "switch_button_x", Y: "switch_button_y",
                  LB: "switch_button_l", RB: "switch_button_r", LT: "switch_button_zl", RT: "switch_button_zr",
                  START: "switch_button_plus", SELECT: "switch_button_minus", MODE: "switch_button_home",
                  l: "switch_dpad_horizontal", r: "switch_dpad_horizontal", u: "switch_dpad_vertical", d: "switch_dpad_vertical",
                  DPAD: "switch_dpad_all", LS: "switch_stick_l" },
        deck:   { dir: "deck",   A: "steamdeck_button_a", B: "steamdeck_button_b", X: "steamdeck_button_x", Y: "steamdeck_button_y",
                  LB: "steamdeck_button_l1", RB: "steamdeck_button_r1", LT: "steamdeck_button_l2", RT: "steamdeck_button_r2",
                  START: "steamdeck_button_options", SELECT: "steamdeck_button_view", MODE: "steamdeck_button_guide",
                  l: "steamdeck_dpad_horizontal", r: "steamdeck_dpad_horizontal", u: "steamdeck_dpad_vertical",
                  d: "steamdeck_dpad_vertical", DPAD: "steamdeck_dpad_all", LS: "steamdeck_stick_l" }
    })
    readonly property var entry: table[family] || table.xbox
    readonly property string file: entry[key] || ""
    readonly property bool available: file !== "" && status === Image.Ready

    source: file ? Qt.resolvedUrl("images/pad/" + entry.dir + "/" + file + ".png") : ""
    width: size
    height: size
    sourceSize: Qt.size(Math.round(size * 2), Math.round(size * 2))
    fillMode: Image.PreserveAspectFit
    smooth: true
    mipmap: true
    asynchronous: true
}

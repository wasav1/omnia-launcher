pragma ComponentBehavior: Bound

import qs
import qs.services
import qs.modules.common
import QtQuick
import QtQuick.Shapes
import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland

/**
 * Superficie del panel (una por monitor, visible solo en el monitor donde se activó): capa Wayland `Top` de
 * wlr-layer-shell con namespace «quickshell:omniaPanel». Hyprland desenfoca lo que hay detrás con la regla
 *   layer_rule { match = { namespace = "quickshell:omniaPanel" }, blur = true, ignore_alpha = 0.88 }
 * (ignore_alpha alto: solo se desenfoca el interior opaco; los píxeles antialiasados de las esquinas no, y así no asoma
 * un halo del fondo fuera de las esquinas redondeadas).
 *   · desde la barra: se despliega desde el botón (con rebote) y se une a la barra con esquinas cóncavas;
 *   · desde el borde: entra y sale por el borde configurado (con rebote) y se une a él con esquinas cóncavas.
 * Se cierra únicamente al pulsar «Jugar» o cuando el cursor no está sobre el panel (también con Esc y ✕ explícitos).
 * La superficie es mayor que el panel: deja margen para el rebote y para las esquinas cóncavas; la entrada del ratón
 * se limita al cuerpo del panel (mask), así que el margen transparente no tapa nada.
 */
PanelWindow {
    id: win
    required property var modelData
    screen: modelData

    readonly property var ps: OmniaPanelState
    readonly property bool mine: ps.screenName === modelData.name
    readonly property bool want: ps.shown && mine
    readonly property bool fromBar: ps.origin === "bar"
    readonly property bool barBottom: Config.options.bar.bottom
    readonly property real barH: Appearance.sizes.barHeight
    readonly property string pos: OmniaSettings.edgePosition
    // borde al que se pega el panel
    readonly property string attach: fromBar ? (barBottom ? "bottom" : "top") : OmniaSettings.edgeSide
    readonly property bool atTop: attach === "top"
    readonly property bool atBottom: attach === "bottom"
    readonly property bool atLeft: attach === "left"
    readonly property bool atRight: attach === "right"
    readonly property bool horiz: atTop || atBottom          // el panel se pega a un borde horizontal

    readonly property real cs: 20                            // radio de las esquinas cóncavas
    readonly property real r: 18                             // radio de las esquinas redondeadas
    readonly property real ovs: 28                           // margen para el rebote (lado interior)
    readonly property real along: cs + 8                     // margen a lo largo del borde (esquinas cóncavas)
    readonly property real padL: atRight ? ovs : (horiz ? along : 0)
    readonly property real padR: atLeft ? ovs : (horiz ? along : 0)
    readonly property real padT: atBottom ? ovs : (!horiz ? along : 0)
    readonly property real padB: atTop ? ovs : (!horiz ? along : 0)

    readonly property real bodyW: Math.max(1, Math.min(840, modelData.width - padL - padR - 8))
    readonly property real maxBodyH: modelData.height - barH - padT - padB - 8
    // El panel no debe crecer por encima del área visible en monitores bajos.
    readonly property real bodyH: Math.max(1, Math.min(content.implicitHeight, maxBodyH))
    implicitWidth: bodyW + padL + padR
    implicitHeight: bodyH + padT + padB

    // ---- animación con rebote (estilo Caelestia): sobrepasa un poco y se asienta
    property real progress: want ? 1 : 0
    Behavior on progress {
        NumberAnimation {
            duration: win.want ? 420 : 160
            easing.type: win.want ? Easing.OutBack : Easing.InCubic
            easing.overshoot: 1.35
        }
    }
    visible: progress > 0.001
    color: "transparent"
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.namespace: "quickshell:omniaPanel"
    WlrLayershell.layer: WlrLayer.Top
    // Sin HyprlandFocusGrab: con el grab activo Hyprland trataba los clics DENTRO del panel como «fuera» y lo cerraba.
    // El panel se cierra solo con «Jugar» o cuando el puntero no está encima (ver OmniaPanelState).
    WlrLayershell.keyboardFocus: !want || ps.mode !== "pinned" ? WlrKeyboardFocus.None : (ps.exclusiveKeys ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.OnDemand)
    // Región de entrada explícita (con números): `Region { item: body }` no se actualizaba y el panel dejaba de recibir clics.
    mask: Region { x: win.padL; y: win.padT; width: win.bodyW; height: win.bodyH }

    // ---- posición (el cuerpo queda donde corresponde; la superficie se extiende por el margen)
    readonly property real barLeft: Math.max(4, Math.min(modelData.width - implicitWidth - 4, ps.anchorX - implicitWidth / 2))
    readonly property real barTopOff: barBottom ? 0 : barH
    readonly property real barBotOff: barBottom ? barH : 0
    anchors {
        top: atTop || (!horiz && pos === "start")
        bottom: atBottom || (!horiz && pos === "end")
        left: atLeft || (horiz && (fromBar || pos === "start"))
        right: atRight || (horiz && !fromBar && pos === "end")
    }
    margins {
        top: atTop ? barTopOff : (!horiz && pos === "start" ? barTopOff + 4 : 0)
        bottom: atBottom ? barBotOff : (!horiz && pos === "end" ? barBotOff + 4 : 0)
        left: fromBar ? barLeft : (horiz && pos === "start" ? 4 : 0)
        right: horiz && !fromBar && pos === "end" ? 4 : 0
    }

    readonly property real depth: horiz ? bodyH : bodyW
    readonly property real animatedDepth: Math.max(cs + r, Math.min(depth + 9, depth * progress))

    // Contorno SVG del panel. Se calcula en un marco (u = a lo largo del borde, v = hacia dentro) con el borde en v = 0 y
    // se proyecta a la superficie según el borde al que se pega.
    readonly property string silhouette: {
        const W = implicitWidth, H = implicitHeight, cs = win.cs, r = win.r;
        const bu = horiz ? padL : padT, bw = horiz ? bodyW : bodyH, bd = animatedDepth;
        const flip = atBottom || atLeft;                       // la proyección invierte el sentido de los arcos
        const f = flip ? 1 : 0, c = flip ? 0 : 1;              // barrido de las esquinas cóncavas y de las redondeadas
        const P = (u, v) => (atTop ? u + " " + v : atBottom ? u + " " + (H - v) : atLeft ? v + " " + u : (W - v) + " " + u);
        const A = (rad, sweep, u, v) => "A " + rad + " " + rad + " 0 0 " + sweep + " " + P(u, v);
        return "M " + P(bu - cs, 0) + " L " + P(bu + bw + cs, 0)
            + " " + A(cs, f, bu + bw, cs)
            + " L " + P(bu + bw, bd - r)
            + " " + A(r, c, bu + bw - r, bd)
            + " L " + P(bu + r, bd)
            + " " + A(r, c, bu, bd - r)
            + " L " + P(bu, cs)
            + " " + A(cs, f, bu - cs, 0) + " Z";
    }

    // rectángulo del cuerpo en coordenadas globales: lo usa el estado para saber si el cursor está encima
    readonly property real winX: anchors.left ? modelData.x + margins.left : anchors.right ? modelData.x + modelData.width - margins.right - implicitWidth : modelData.x + (modelData.width - implicitWidth) / 2
    readonly property real winY: anchors.top ? modelData.y + margins.top : anchors.bottom ? modelData.y + modelData.height - margins.bottom - implicitHeight : modelData.y + (modelData.height - implicitHeight) / 2
    Binding {
        target: win.ps
        property: "panelRect"
        value: Qt.rect(win.winX + win.padL, win.winY + win.padT, win.bodyW, win.bodyH)
        when: win.want
    }

    Item {
        id: stage
        anchors.fill: parent
        opacity: Math.min(1, win.progress * 1.5)
        // Silueta ÚNICA del panel (cuerpo + esquinas cóncavas + esquinas redondeadas del lado interior) en un solo trazo:
        // no hay costuras ni capas superpuestas entre el cuerpo y las esquinas cóncavas, y el antialiasing es uniforme.
        Shape {
            anchors.fill: parent
            preferredRendererType: Shape.CurveRenderer
            layer.enabled: true
            layer.smooth: true
            layer.samples: 4
            ShapePath {
                strokeWidth: -1
                fillColor: OmniaTheme.panel(OmniaSettings.blur)
                PathSvg { path: win.silhouette }
            }
        }
        Item {      // geometría del cuerpo: contenido, máscara de entrada y clics
            id: body
            opacity: Math.max(0, Math.min(1, (win.progress - 0.78) / 0.22))
            x: win.padL
            y: win.padT
            width: win.bodyW
            height: win.bodyH
            OmniaPanelContent {
                id: content
                anchors.fill: parent
                screenName: win.modelData.name
                onCloseRequested: win.ps.close()
            }
        }

        // asomado por el borde: mantener abierto mientras el puntero esté encima; un clic lo fija
        HoverHandler {
            onHoveredChanged: {
                win.ps.hoverPanel = hovered;
                if (hovered) win.ps.holdOpen(); else win.ps.leave();
            }
        }
        MouseArea {
            x: body.x; y: body.y; width: body.width; height: body.height
            z: 10
            acceptedButtons: Qt.LeftButton
            propagateComposedEvents: true
            onPressed: mouse => { win.ps.pin(); mouse.accepted = false; }
        }
    }

    onWantChanged: if (want && ps.mode === "pinned") content.forceActiveFocus()
    Connections {
        target: win.ps
        function onModeChanged() { if (win.ps.mode === "pinned" && win.want) content.forceActiveFocus(); }
    }
}

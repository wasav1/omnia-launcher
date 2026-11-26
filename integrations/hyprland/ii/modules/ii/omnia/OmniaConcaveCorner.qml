import QtQuick
import QtQuick.Shapes

/**
 * Esquina cóncava (fileteado) en la unión del panel con el borde de la pantalla o con la barra: rellena el hueco entre
 * el lateral del panel y el borde con un cuarto de círculo, como los paneles de Caelestia.
 *   edge: borde al que se pega el panel (top | bottom | left | right)
 *   end:  extremo del panel a lo largo de ese borde (start = izquierda/arriba, end = derecha/abajo)
 * El dibujo base es el de «barra superior, extremo izquierdo»; el resto son giros y reflejos de él.
 */
Item {
    id: c
    property color color: "#0B0F14"
    property string edge: "top"
    property string end: "start"
    property real size: 20
    implicitWidth: size
    implicitHeight: size
    readonly property bool vertical: edge === "left" || edge === "right"
    readonly property bool mirrorX: vertical ? edge === "left" : end === "end"
    readonly property bool mirrorY: vertical ? end === "end" : edge === "bottom"

    Shape {
        anchors.fill: parent
        preferredRendererType: Shape.CurveRenderer
        layer.enabled: true
        layer.smooth: true
        layer.samples: 4
        transform: [
            Rotation { angle: c.vertical ? 90 : 0; origin.x: c.width / 2; origin.y: c.height / 2 },
            Scale { xScale: c.mirrorX ? -1 : 1; origin.x: c.width / 2; origin.y: c.height / 2 },
            Scale { yScale: c.mirrorY ? -1 : 1; origin.x: c.width / 2; origin.y: c.height / 2 }
        ]
        ShapePath {
            strokeWidth: 0
            fillColor: c.color
            startX: 0; startY: 0
            PathLine { x: c.size + 0.5; y: 0 }                    // +0.5 px: solapa con el cuerpo y no deja costura
            PathLine { x: c.size + 0.5; y: c.size }
            PathLine { x: c.size; y: c.size }
            PathArc { x: 0; y: 0; radiusX: c.size; radiusY: c.size; direction: PathArc.Counterclockwise }
        }
    }
}

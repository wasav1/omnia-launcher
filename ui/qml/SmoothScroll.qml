import QtQuick

/** Desplazamiento suave para listas y cuadrículas que se recorren con mando o teclado.
 *  `positionViewAtIndex` salta de golpe; esto anima `contentY` hasta dejar visible el elemento elegido.
 *
 *    ListView { id: list
 *        SmoothScroll { id: smooth; view: list }
 *        onCurrentIndexChanged: smooth.show(currentIndex)
 *    } */
NumberAnimation {
    id: smooth
    property var view: null                     // ListView, GridView o Flickable
    property real margin: 0
    target: view
    property: "contentY"
    duration: 220
    easing.type: Easing.OutCubic

    function scrollTo(y) {
        if (!view) return
        const minY = view.originY
        const maxY = Math.max(minY, view.originY + view.contentHeight - view.height)
        const target = Math.max(minY, Math.min(maxY, y))
        if (Math.abs(target - view.contentY) < 1) return
        smooth.stop()
        smooth.from = view.contentY
        smooth.to = target
        smooth.start()
    }
    // Deja visible el tramo [top, bottom] (en coordenadas del contenido) moviendo lo mínimo.
    function showRange(top, bottom, extra) {
        if (!view) return
        const m = extra === undefined ? margin : extra
        let y = running ? to : view.contentY
        if (top - m < y) y = top - m
        else if (bottom + m > y + view.height) y = bottom + m - view.height
        scrollTo(y)
    }
    // ListView/GridView: deja visible el delegado `index`; si aún no existe, salta como antes.
    function show(index, extra) {
        if (!view || index < 0) return
        const v = view                                   // ListView o GridView (Flickable no declara estas funciones)
        const item = v["itemAtIndex"] ? v["itemAtIndex"](index) : null
        if (!item) { if (v["positionViewAtIndex"]) v["positionViewAtIndex"](index, ListView.Contain); return }
        showRange(item.y, item.y + item.height, extra)
    }
}

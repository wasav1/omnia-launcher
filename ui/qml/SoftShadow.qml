import QtQuick

/** Sombra suave y continua detrás de un elemento rectangular (sin capas apiladas ni escalones). Se dibuja con Canvas.
 *  Colócala con el mismo tamaño que el elemento: el lienzo es más grande (margen) para que la sombra no se corte. */
Canvas {
    id: sh
    property real radius: 14
    property real blur: 34
    property real offsetY: 14
    property color shadowColor: "#99000000"
    readonly property real margin: blur * 1.6 + Math.abs(offsetY)
    x: -margin; y: -margin
    width: parent ? Math.round(parent.width + margin * 2) : 0         // enteros: un lienzo de tamaño fraccionario sale en blanco
    height: parent ? Math.round(parent.height + margin * 2) : 0
    renderStrategy: Canvas.Cooperative
    onWidthChanged: requestPaint()
    onHeightChanged: requestPaint()
    onRadiusChanged: requestPaint()
    onBlurChanged: requestPaint()
    onShadowColorChanged: requestPaint()
    onPaint: {
        const ctx = getContext("2d")
        ctx.reset()
        ctx.clearRect(0, 0, width, height)
        const w = width - margin * 2, h = height - margin * 2, r = Math.min(radius, w / 2, h / 2)
        if (w < 2 || h < 2) return
        ctx.shadowColor = Qt.rgba(shadowColor.r, shadowColor.g, shadowColor.b, shadowColor.a)
        ctx.shadowBlur = blur
        ctx.shadowOffsetX = 0
        ctx.shadowOffsetY = offsetY
        ctx.fillStyle = "#000000"
        const x0 = margin, y0 = margin
        ctx.beginPath()
        ctx.moveTo(x0 + r, y0); ctx.lineTo(x0 + w - r, y0); ctx.arcTo(x0 + w, y0, x0 + w, y0 + r, r)
        ctx.lineTo(x0 + w, y0 + h - r); ctx.arcTo(x0 + w, y0 + h, x0 + w - r, y0 + h, r)
        ctx.lineTo(x0 + r, y0 + h); ctx.arcTo(x0, y0 + h, x0, y0 + h - r, r)
        ctx.lineTo(x0, y0 + r); ctx.arcTo(x0, y0, x0 + r, y0, r); ctx.closePath()
        ctx.fill()
        // se borra el propio rectángulo: queda solo la sombra alrededor, nunca un bloque negro bajo el elemento
        ctx.shadowColor = "rgba(0,0,0,0)"; ctx.shadowBlur = 0; ctx.shadowOffsetY = 0
        ctx.globalCompositeOperation = "destination-out"
        ctx.fillStyle = "#000000"
        ctx.fill()
        ctx.globalCompositeOperation = "source-over"
    }
}

import QtQuick

/** Reflejo de espejo de una tarjeta (su borde inferior, invertido y desvanecido hacia abajo). Se dibuja con Canvas y composición
 *  `destination-in`: sin shaders. El lienzo mide el alto del reflejo; `cardHeight` es el alto de la tarjeta reflejada.
 *  Sin portada refleja el color de la tarjeta (`tileColor`). */
Canvas {
    id: rf
    property url source: ""
    property real cardHeight: 100
    property real radius: 0
    property real strength: 0.30
    property color tileColor: "#223244"
    property bool ready: false
    readonly property url resolved: {
        const t = source.toString()
        return t !== "" && t.charAt(0) === "/" ? "file://" + t : source
    }
    renderStrategy: Canvas.Cooperative
    canvasSize: Qt.size(Math.max(1, Math.round(width)), Math.max(1, Math.round(height)))
    Image { id: probe; source: rf.resolved; visible: false; asynchronous: true; onStatusChanged: if (status === Image.Ready) rf.requestPaint() }
    onResolvedChanged: { ready = false; if (resolved.toString() !== "") loadImage(resolved); requestPaint() }
    Component.onCompleted: { if (resolved.toString() !== "") loadImage(resolved) }
    onImageLoaded: { ready = resolved.toString() !== "" && isImageLoaded(resolved); requestPaint() }
    onWidthChanged: requestPaint()
    onHeightChanged: requestPaint()
    onCardHeightChanged: requestPaint()
    onTileColorChanged: requestPaint()
    onPaint: {
        const ctx = getContext("2d")
        ctx.reset()
        const w = canvasSize.width, h = canvasSize.height, ch = Math.max(h, Math.round(cardHeight))
        ctx.clearRect(0, 0, w, h)
        if (w < 2 || h < 2) return
        ctx.save()
        ctx.translate(0, ch)
        ctx.scale(1, -1)                                  // a partir de aquí se dibuja la tarjeta invertida
        const r = Math.min(radius, w / 2, ch / 2)
        ctx.beginPath()
        ctx.moveTo(r, 0); ctx.lineTo(w - r, 0); ctx.arcTo(w, 0, w, r, r); ctx.lineTo(w, ch - r); ctx.arcTo(w, ch, w - r, ch, r)
        ctx.lineTo(r, ch); ctx.arcTo(0, ch, 0, ch - r, r); ctx.lineTo(0, r); ctx.arcTo(0, 0, r, 0, r); ctx.closePath()
        ctx.clip()
        if (resolved.toString() !== "" && isImageLoaded(resolved)) {
            let sx = 0, sy = 0, sw = probe.implicitWidth, sh = probe.implicitHeight
            if (sw > 0 && sh > 0) {
                const k = Math.max(w / sw, ch / sh)
                const cw = w / k, chh = ch / k
                sx = (sw - cw) / 2; sy = (sh - chh) / 2; sw = cw; sh = chh
                ctx.drawImage(resolved, sx, sy, sw, sh, 0, 0, w, ch)
            } else ctx.drawImage(resolved, 0, 0, w, ch)
        } else {
            ctx.fillStyle = "rgba(255,255,255,0.55)"          // sin arte: reflejo translúcido
            ctx.fillRect(0, 0, w, ch)
        }
        ctx.restore()
        ctx.globalCompositeOperation = "destination-in"   // desvanecido: fuerte junto a la tarjeta, nulo abajo
        const g = ctx.createLinearGradient(0, 0, 0, h)
        g.addColorStop(0, "rgba(0,0,0," + strength + ")")
        g.addColorStop(1, "rgba(0,0,0,0)")
        ctx.fillStyle = g
        ctx.fillRect(0, 0, w, h)
        ctx.globalCompositeOperation = "source-over"
    }
}

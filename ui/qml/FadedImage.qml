import QtQuick

/** Imagen cuyo borde se desvanece hacia la transparencia (sin marco ni esquinas duras) o con esquinas redondeadas.
 *  Se dibuja con Canvas y composición `destination-in`, sin shaders, así que se ve igual con cualquier renderizador.
 *  La imagen cubre el área (recorte centrado, como PreserveAspectCrop). Las fracciones de desvanecido son del ancho/alto. */
Canvas {
    id: cv
    property url source: ""
    property real fadeLeft: 0
    property real fadeRight: 0
    property real fadeTop: 0
    property real fadeBottom: 0
    property real cornerRadius: 0
    property real alignX: 0.5                      // 0 = recorta mostrando la izquierda, 1 = la derecha
    property bool retainWhileLoading: false
    property bool ready: false                     // la imagen ya está cargada y dibujada
    readonly property url resolved: {
        const t = source.toString()
        return t !== "" && t.charAt(0) === "/" ? "file://" + t : source
    }
    renderStrategy: Canvas.Cooperative
    canvasSize: Qt.size(Math.max(1, Math.round(width)), Math.max(1, Math.round(height)))     // un ancho fraccionario deja el lienzo en blanco
    Image {                                       // solo para conocer el tamaño real y recortar sin deformar
        id: probe
        source: cv.resolved
        visible: false
        asynchronous: true
        onStatusChanged: if (status === Image.Ready || (cv.retainWhileLoading && status === Image.Error)) cv.requestPaint()
    }
    onResolvedChanged: { ready = false; if (resolved.toString() !== "") loadImage(resolved); requestPaint() }
    Component.onCompleted: { if (resolved.toString() !== "") loadImage(resolved) }
    onImageLoaded: { ready = resolved.toString() !== "" && isImageLoaded(resolved); requestPaint() }
    onWidthChanged: requestPaint()
    onHeightChanged: requestPaint()
    onFadeLeftChanged: requestPaint()
    onFadeRightChanged: requestPaint()
    onFadeTopChanged: requestPaint()
    onFadeBottomChanged: requestPaint()
    onPaint: {
        if (retainWhileLoading && resolved.toString() !== "" && !isImageLoaded(resolved) && probe.status !== Image.Error) return
        const ctx = getContext("2d")
        ctx.reset()
        ctx.clearRect(0, 0, canvasSize.width, canvasSize.height)
        const w = canvasSize.width, h = canvasSize.height
        if (resolved.toString() === "" || !isImageLoaded(resolved) || w < 2 || h < 2) return
        ctx.save()
        if (cornerRadius > 0) {
            const r = Math.min(cornerRadius, w / 2, h / 2)
            ctx.beginPath()
            ctx.moveTo(r, 0); ctx.lineTo(w - r, 0); ctx.arcTo(w, 0, w, r, r); ctx.lineTo(w, h - r); ctx.arcTo(w, h, w - r, h, r)
            ctx.lineTo(r, h); ctx.arcTo(0, h, 0, h - r, r); ctx.lineTo(0, r); ctx.arcTo(0, 0, r, 0, r); ctx.closePath()
            ctx.clip()
        }
        // recorte «cubrir»: la imagen llena el área sin deformarse
        let sx = 0, sy = 0, sw = probe.implicitWidth, sh = probe.implicitHeight
        if (sw > 0 && sh > 0) {
            const k = Math.max(w / sw, h / sh)
            const cw = w / k, ch = h / k
            sx = (sw - cw) * alignX; sy = (sh - ch) / 2; sw = cw; sh = ch
            ctx.drawImage(resolved, sx, sy, sw, sh, 0, 0, w, h)
        } else {
            ctx.drawImage(resolved, 0, 0, w, h)
        }
        ctx.restore()
        ctx.globalCompositeOperation = "destination-in"
        if (fadeLeft > 0 || fadeRight > 0) {
            const g = ctx.createLinearGradient(0, 0, w, 0)
            g.addColorStop(0, fadeLeft > 0 ? "rgba(0,0,0,0)" : "rgba(0,0,0,1)")
            if (fadeLeft > 0) g.addColorStop(Math.min(0.99, fadeLeft), "rgba(0,0,0,1)")
            if (fadeRight > 0) g.addColorStop(Math.max(0.01, 1 - fadeRight), "rgba(0,0,0,1)")
            g.addColorStop(1, fadeRight > 0 ? "rgba(0,0,0,0)" : "rgba(0,0,0,1)")
            ctx.fillStyle = g; ctx.fillRect(0, 0, w, h)
        }
        if (fadeTop > 0 || fadeBottom > 0) {
            const g = ctx.createLinearGradient(0, 0, 0, h)
            g.addColorStop(0, fadeTop > 0 ? "rgba(0,0,0,0)" : "rgba(0,0,0,1)")
            if (fadeTop > 0) g.addColorStop(Math.min(0.99, fadeTop), "rgba(0,0,0,1)")
            if (fadeBottom > 0) g.addColorStop(Math.max(0.01, 1 - fadeBottom), "rgba(0,0,0,1)")
            g.addColorStop(1, fadeBottom > 0 ? "rgba(0,0,0,0)" : "rgba(0,0,0,1)")
            ctx.fillStyle = g; ctx.fillRect(0, 0, w, h)
        }
        ctx.globalCompositeOperation = "source-over"
    }
}

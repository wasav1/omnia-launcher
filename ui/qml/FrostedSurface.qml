import QtQuick
import QtQuick.Effects

Item {
    id: surface
    property Item backdrop
    property rect backdropRect: Qt.rect(0, 0, width, height)
    property color tint: "#a6182230"
    property real feather: 12
    property real radius: 16
    property bool sampling: visible && backdrop && width > 0 && height > 0

    ShaderEffectSource {
        id: sample
        visible: false
        sourceItem: surface.sampling ? surface.backdrop : null
        sourceRect: surface.backdropRect
        textureSize: Qt.size(Math.max(1, Math.ceil(surface.width / 2)),
                             Math.max(1, Math.ceil(surface.height / 2)))
        smooth: true
    }

    Canvas {
        id: edgeMask
        anchors.fill: parent
        visible: !surface.sampling
        opacity: surface.sampling ? 1 : surface.tint.a
        layer.enabled: surface.sampling
        onVisibleChanged: requestPaint()
        onWidthChanged: requestPaint()
        onHeightChanged: requestPaint()
        Connections {
            target: surface
            function onFeatherChanged() { edgeMask.requestPaint() }
            function onRadiusChanged() { edgeMask.requestPaint() }
            function onTintChanged() { edgeMask.requestPaint() }
        }
        onPaint: {
            const ctx = getContext("2d")
            ctx.clearRect(0, 0, width, height)
            const steps = Math.max(1, Math.min(Math.ceil(surface.feather),
                                              Math.floor(Math.min(width, height) / 2)))
            ctx.fillStyle = surface.sampling ? "white" : Qt.rgba(surface.tint.r, surface.tint.g, surface.tint.b, 1)
            for (let i = 0; i < steps; ++i) {
                const w = width - 2 * i
                const h = height - 2 * i
                const r = Math.max(0, Math.min(surface.radius - i, w / 2, h / 2))
                ctx.globalAlpha = 1 / (steps - i)
                ctx.beginPath()
                ctx.roundedRect(i, i, w, h, r, r)
                ctx.fill()
            }
        }
    }

    Item {
        anchors.fill: parent
        visible: surface.sampling
        layer.enabled: surface.sampling
        layer.effect: MultiEffect { maskEnabled: true; maskSource: edgeMask }
        MultiEffect {
            anchors.fill: parent
            visible: surface.sampling
            source: sample
            blurEnabled: true
            blurMax: 24
            blur: 0.75
            autoPaddingEnabled: false
        }
        Rectangle { anchors.fill: parent; radius: surface.radius; color: surface.tint }
    }
}

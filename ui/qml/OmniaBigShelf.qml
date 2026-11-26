pragma ComponentBehavior: Bound

import QtQuick
import Qt5Compat.GraphicalEffects

/** Estantería horizontal de Big Mode: tarjetas, reflejo, zoom y navegación por páginas. */
Item {
    id: shelf
    required property var host
    required property var sounds
    property real transferInset: 0
    anchors { left: parent.left; right: parent.right; bottom: parent.bottom; bottomMargin: shelf.host.s * 108 + shelf.transferInset }
    anchors.leftMargin: shelf.host.contentInset
    anchors.rightMargin: shelf.host.contentInset
    readonly property real zoomGutter: Math.ceil(shelf.host.libraryCoverWidth * 0.024) + shelf.host.s * 3
    readonly property real reflectH: shelf.host.s * 68
    readonly property real headroom: shelf.host.s * 30
    height: shelf.host.s * 310 + reflectH + headroom
    function page(dir) { list.page(dir) }

    ListView {
        id: list
        anchors.fill: parent
        visible: shelf.host.page === "library"
        leftMargin: shelf.zoomGutter
        rightMargin: shelf.zoomGutter
        readonly property real minX: originX - leftMargin
        orientation: ListView.Horizontal
        spacing: shelf.host.s * 18
        model: shelf.host.visibleGames
        currentIndex: shelf.host.index
        // El desplazamiento es propio (no el de ListView) para separarlo de la selección: la rueda mueve la estantería sin cambiar
        // el juego seleccionado y los saltos de página llevan la selección a la página nueva.
        highlightFollowsCurrentItem: false
        highlightRangeMode: ListView.NoHighlightRange
        boundsBehavior: Flickable.StopAtBounds
        interactive: false          // sin arrastre: la estantería avanza con la rueda, las flechas, los gatillos o la navegación
        readonly property real cardStep: shelf.host.libraryCoverWidth + spacing                 // ancho de una tarjeta más su separación
        readonly property real hlBegin: fadeOk ? fadeWidth + shelf.zoomGutter : shelf.zoomGutter     // la tarjeta seleccionada queda entre estos dos bordes
        readonly property real hlEnd: width * 0.62
        readonly property real maxX: Math.max(minX, originX + contentWidth - width + rightMargin)
        readonly property int perPage: Math.max(2, Math.floor((width + spacing) / cardStep))   // tarjetas completas que caben
        property bool paging: false
        function clampX(x) { return Math.max(minX, Math.min(maxX, x)) }
        function scrollTo(x, animate, ms) {
            x = clampX(x)
            scrollAnim.stop()
            if (!animate) { contentX = x; return }
            scrollAnim.duration = ms || 260
            scrollAnim.to = x
            scrollAnim.restart()
        }
        function scrollBy(dx) { scrollTo((scrollAnim.running ? scrollAnim.to : contentX) + dx, true, 160) }
        // Lo mismo que hacía highlightRangeMode: ApplyRange: la tarjeta seleccionada queda dentro de [hlBegin, hlEnd].
        function revealIndex(i, animate) {
            if (count <= 0 || contentWidth + leftMargin + rightMargin <= width || i <= 0) { scrollTo(minX, animate); return }
            if (i >= count - 1) { scrollTo(maxX, animate); return }
            const left = originX + i * cardStep, right = left + shelf.host.libraryCoverWidth
            if (left < contentX + hlBegin) scrollTo(left - hlBegin, animate)
            else if (right > contentX + hlEnd) scrollTo(right - hlEnd, animate)
        }
        // Salta una página (los juegos visibles menos uno, para conservar una referencia) y lleva la selección a su primera tarjeta.
    function page(dir) {
            const n = shelf.host.visibleGames.length
            if (n === 0) return
            const jump = Math.max(1, perPage - 1)
            const from = Math.max(0, Math.min(n - 1, Math.round(((scrollAnim.running ? scrollAnim.to : contentX) + hlBegin - originX) / cardStep)))
            const first = Math.max(0, Math.min(n - 1, from + dir * jump))
            paging = true
            shelf.host.select(first)
            paging = false
            revealIndex(first, true)
            shelf.sounds.play("page")
        }
        NumberAnimation { id: scrollAnim; target: list; property: "contentX"; duration: 260; easing.type: Easing.OutCubic }
        Connections {
            target: shelf.host
            function onIndexChanged() { if (!list.paging) list.revealIndex(shelf.host.index, true) }
        }
        onCountChanged: Qt.callLater(function() { list.revealIndex(shelf.host.index, false) })
        onWidthChanged: Qt.callLater(function() { list.revealIndex(shelf.host.index, false) })
        // Rueda del mouse (o del panel táctil): desplaza la estantería una tarjeta por muesca, sin tocar la selección.
        WheelHandler {
            acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
            onWheel: function(ev) {
                const d = ev.angleDelta.y !== 0 ? ev.angleDelta.y : ev.angleDelta.x
                if (d !== 0) list.scrollBy(-d / 120 * list.cardStep)
            }
        }
        clip: true
        cacheBuffer: 1200
        // Las tarjetas que quedan cortadas en un extremo se desvanecen hacia ese extremo (solo del lado donde hay más contenido).
        // Con el renderizador por software no hay shaders y se omite.
        readonly property bool fadeOk: GraphicsInfo.api !== GraphicsInfo.Software
        readonly property real fadeWidth: Math.min(shelf.host.s * 120, width * 0.3)
        // El desvanecido izquierdo se aplica siempre que la seleccionada no sea la primera (aunque la lista esté en su inicio): la
        // primera asoma desvanecida mientras se está sobre la segunda y vuelve a verse normal al volver a ella. Se anima.
        property real leftAmount: shelf.host.index > 0 || !atXBeginning ? 1 : 0
        Behavior on leftAmount { NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }
        layer.enabled: fadeOk && contentWidth > width
        layer.effect: OpacityMask {
            maskSource: Rectangle {
                width: list.width; height: list.height
                gradient: Gradient {
                    orientation: Gradient.Horizontal
                    GradientStop { position: 0; color: Qt.rgba(0, 0, 0, 1 - list.leftAmount) }
                    GradientStop { position: Math.max(0.001, list.leftAmount * list.fadeWidth / list.width); color: "#FF000000" }
                    GradientStop { position: list.atXEnd ? 0.999 : 1 - list.fadeWidth / list.width; color: "#FF000000" }
                    GradientStop { position: 1; color: list.atXEnd ? "#FF000000" : "#00000000" }
                }
            }
        }
        delegate: Item {
            id: card
            required property var modelData
            required property int index
            readonly property bool sel: index === shelf.host.index
            width: shelf.host.libraryCoverWidth
            height: list.height
            z: card.sel ? 2 : cardMa.containsMouse ? 1 : 0
            Item {
                id: face
                anchors { left: parent.left; right: parent.right; bottom: parent.bottom; bottomMargin: shelf.reflectH + (card.sel ? shelf.host.s * 8 : 0) }
                height: card.sel ? shelf.host.libraryFocusedCoverHeight : shelf.host.libraryCoverHeight
                scale: card.sel ? 1.038 : cardMa.containsMouse ? 1.025 : 1
                // rebote al cambiar de selección: la seleccionada sube con sobreimpulso y se asienta
                Behavior on height { NumberAnimation { duration: 420; easing.type: Easing.OutBack; easing.overshoot: 2.6 } }
                Behavior on anchors.bottomMargin { NumberAnimation { duration: 420; easing.type: Easing.OutBack; easing.overshoot: 3.2 } }
                Behavior on scale { NumberAnimation { duration: 140 } }

                Rectangle {      // tarjeta sin portada
                    id: tile
                    anchors.fill: parent
                    radius: shelf.host.s * 20
                    color: "#16ffffff"          // sin arte: translúcida
                    border.color: "#1fffffff"; border.width: 1
                    visible: cover.status !== Image.Ready
                    Text {
                        anchors.centerIn: parent
                        width: parent.width - shelf.host.s * 30
                        horizontalAlignment: Text.AlignHCenter
                        text: card.modelData.name
                        color: shelf.host.ink
                        font.family: shelf.host.uiFont
                        font.pixelSize: shelf.host.s * 30
                        font.weight: Font.Bold
                        wrapMode: Text.WordWrap
                        visible: cover.status !== Image.Ready
                    }
                }
                Image {
                    id: cover
                    anchors.fill: parent
                    source: card.modelData.portada || ""
                    fillMode: Image.PreserveAspectCrop
                    asynchronous: true
                    smooth: true
                    mipmap: true
                    sourceSize.height: Math.round(shelf.host.s * 768)
                    visible: false
                }
                Rectangle { id: coverMask; anchors.fill: parent; radius: shelf.host.s * 20; visible: false }
                OpacityMask { anchors.fill: parent; source: cover; maskSource: coverMask; visible: cover.status === Image.Ready }
                Rectangle {      // anillo de selección
                    anchors.fill: parent
                    radius: coverMask.radius
                    color: "#243DD8D0"
                    border.width: card.sel ? Math.max(2, shelf.host.s * 4) : Math.max(1, shelf.host.s * 2)
                    border.color: card.sel ? shelf.host.ring : "#6CE2DC"
                    opacity: card.sel || cardMa.containsMouse ? 1 : 0
                    Behavior on opacity { NumberAnimation { duration: 140 } }
                }
                Rectangle {      // «en ejecución»
                    visible: card.modelData.running
                    anchors { left: parent.left; top: parent.top; margins: shelf.host.s * 12 }
                    width: runTxt.implicitWidth + shelf.host.s * 20; height: shelf.host.s * 26; radius: height / 2
                    color: "#6fc3a0"
                    Text { id: runTxt; anchors.centerIn: parent; text: qsTranslate("OmniaLibrary", "En juego"); color: shelf.host.base; font.family: shelf.host.uiFont; font.pixelSize: shelf.host.s * 14; font.weight: Font.DemiBold }
                }
                Rectangle {      // port disponible
                    visible: !!card.modelData.portAvailable
                    anchors { left: parent.left; bottom: parent.bottom; margins: shelf.host.s * 10 }
                    width: portTxt.implicitWidth + shelf.host.s * 20; height: shelf.host.s * 26; radius: height / 2
                    color: "#5b9be0"
                    Text { id: portTxt; anchors.centerIn: parent; text: qsTranslate("OmniaLibrary", "Port disponible"); color: shelf.host.base; font.family: shelf.host.uiFont; font.pixelSize: shelf.host.s * 13; font.weight: Font.DemiBold }
                }
                Rectangle {      // actualización disponible
                    visible: !!card.modelData.updateAvailable && !card.modelData.portAvailable
                    anchors { left: parent.left; bottom: parent.bottom; margins: shelf.host.s * 10 }
                    width: updTxt.implicitWidth + shelf.host.s * 20; height: shelf.host.s * 26; radius: height / 2
                    color: "#e0a24b"
                    Text { id: updTxt; anchors.centerIn: parent; text: qsTranslate("OmniaLibrary", "Actualización"); color: shelf.host.base; font.family: shelf.host.uiFont; font.pixelSize: shelf.host.s * 13; font.weight: Font.DemiBold }
                }
                Rectangle {      // favorito
                    visible: card.modelData.fav
                    anchors { right: parent.right; top: parent.top; margins: shelf.host.s * 12 }
                    width: shelf.host.s * 30; height: shelf.host.s * 30; radius: width / 2
                    color: Qt.rgba(0.04, 0.06, 0.08, 0.7)
                    LucideIcon { anchors.centerIn: parent; width: shelf.host.s * 16; height: shelf.host.s * 16; name: "star"; color: "#f5b83d" }
                }
            }
            // reflejo corto de espejo bajo la tarjeta (Canvas, sin shaders)
            ReflectionImage {
                anchors { left: parent.left; right: parent.right; top: face.bottom; topMargin: shelf.host.s * 3 }
                height: shelf.reflectH - shelf.host.s * 3
                source: card.modelData.portada || ""
                cardHeight: face.height
                radius: shelf.host.s * 20
                strength: card.sel ? 0.32 : 0.24
                tileColor: card.modelData.pal ? Qt.darker(card.modelData.pal[1] || "#223244", 1.4) : "#223244"
            }
            MouseArea {
                id: cardMa
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                acceptedButtons: Qt.LeftButton | Qt.RightButton
                onClicked: function(m) {
                    shelf.sounds.play(m.button === Qt.RightButton ? "menu" : "move")
                    shelf.host.select(card.index)
                    if (m.button === Qt.RightButton) shelf.host.openMenu(card.modelData)
                }
                onDoubleClicked: function(m) { if (m.button === Qt.LeftButton) { shelf.host.select(card.index); shelf.host.play() } }
            }
        }
        }

    Repeater {      // flechas para el ratón: saltan una página. Con mando se sustituyen por LT / RT, que hacen lo mismo

        model: [-1, 1]
        delegate: Rectangle {
            id: shelfArrow
            required property int modelData
            readonly property bool previous: modelData < 0
            visible: shelf.host.page === "library" && list.contentWidth + list.leftMargin + list.rightMargin > list.width
                && (previous ? !list.atXBeginning : !list.atXEnd)
            x: previous ? list.x - width - shelf.host.s * 12 : list.x + list.width + shelf.host.s * 12
            y: list.y + shelf.headroom + (list.height - shelf.headroom - shelf.reflectH - height) / 2
            width: shelf.host.s * 42
            height: width
            radius: width / 2
            color: shelfArrowMouse.containsMouse ? shelf.host.accent : shelf.host.surface
            border.color: "#40ffffff"
            Accessible.role: Accessible.Button
            Accessible.name: previous ? qsTranslate("OmniaLibrary", "Página anterior") : qsTranslate("OmniaLibrary", "Página siguiente")
            LucideIcon { visible: !shelf.host.padOn; anchors.centerIn: parent; width: shelf.host.s * 21; height: width; name: shelfArrow.previous ? "arrow-left" : "arrow-right"; color: shelf.host.ink }
            PadGlyph { visible: shelf.host.padOn; anchors.centerIn: parent; size: shelf.host.s * 34; family: shelf.host.api.padFamily || "xbox"; key: shelfArrow.previous ? "LT" : "RT" }
            MouseArea {
                id: shelfArrowMouse
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: list.page(shelfArrow.modelData)
            }
        }
        }
}

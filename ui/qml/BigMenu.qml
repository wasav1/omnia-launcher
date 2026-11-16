import QtQuick
import Qt5Compat.GraphicalEffects
import org.kde.kirigami as Kirigami

// Big Menu: lanzador de aplicaciones (panel de cristal centrado, 56 x 43 u; 1 u = 0,84 % del ancho de la pantalla).
// Categorías en píldoras con carrusel, favoritos arriba, fichas de color y modo «Energía y sesión» con confirmación.
// Teclado, ratón y mando.
FocusScope {
    id: menu
    property var api
    property bool open: false
    signal closeRequested

    // ---- estado
    property string mode: "apps"            // "apps" | "power"
    property string zone: "grid"            // "q" (búsqueda) | "cats" | "grid"
    property string query: ""
    property string category: "Todas"
    property int idx: 0                     // seleccionado dentro de favs + list
    property int pwIdx: 0
    property string pwConfirm: ""           // acción pendiente de confirmar ("" = ninguna)
    property int pwCI: 0                    // 0 = Cancelar, 1 = Confirmar
    property bool shown: false              // objetivo de las animaciones de entrada/salida
    property real panelDim: 0.88            // oscurecido del cristal: alto porque sin el efecto de KWin no hay desenfoque detrás
    readonly property bool fading: container.opacity > 0.01

    readonly property real u: width / 100 * 0.84
    readonly property var cats: ["Todas", "Favoritos"].concat(api ? api.appGroups : [])
    readonly property int cols: 6
    readonly property var pwItems: [
        { id: "lock",     t: "Bloquear",      icon: "system-lock-screen", c: false },
        { id: "suspend",  t: "Suspender",     icon: "system-suspend",     c: false },
        { id: "logout",   t: "Cerrar sesión", icon: "system-log-out",     c: true, q: "¿Cerrar la sesión?" },
        { id: "reboot",   t: "Reiniciar",     icon: "system-reboot",      c: true, q: "¿Reiniciar el equipo?" },
        { id: "shutdown", t: "Apagar",        icon: "system-shutdown",    c: true, q: "¿Apagar el equipo?" }
    ]
    readonly property var pal: ["#5865f2","#4d4de8","#1fa0e8","#6b7280","#e8923a","#7b6cf0","#c9965a","#f05a5a","#f0b84a","#3a8fd8","#e0572c","#41c460","#7a8794","#6c63e8","#2f9e6e","#d6492f","#8a5cf0","#2aa7c9","#e6b422"]

    // favs = favoritos (o los más usados) de la vista «Todas»; list = el resto; rows = filas para la lista virtualizada
    property var favs: []
    property var list: []
    property var rows: []
    readonly property var current: all()[idx] || null

    function all() { return favs.concat(list) }
    function norm(s) { return (s || "").normalize("NFD").replace(/[̀-ͯ]/g, "").toLowerCase() }
    function color(n) { let h = 0; for (let i = 0; i < n.length; i++) h = (h * 31 + n.charCodeAt(i)) >>> 0; return pal[h % pal.length] }
    function initials(n) {
        const w = n.replace(/[^A-Za-zÁÉÍÓÚÑáéíóúñ0-9 ]/g, " ").trim().split(/\s+/)
        return w.length > 1 ? (w[0][0] + w[1][0]).toUpperCase() : n.substring(0, 2)
    }
    function icon(a) { return a.icon && a.icon.charAt(0) === "/" ? "file://" + a.icon : (a.icon || "application-x-executable") }

    function update() {
        const apps = api ? api.apps : [], nq = norm(query.trim())
        let l = [], t = []
        for (let i = 0; i < apps.length; i++) {
            const a = apps[i]
            if (nq) {                                                   // buscando: se ignora la categoría
                const n = norm(a.name)
                const score = n.indexOf(nq) === 0 ? 3 : n.indexOf(nq) > 0 ? 2
                            : norm((a.keywords || []).join(" ")).indexOf(nq) >= 0 ? 1 : norm(a.comment).indexOf(nq) >= 0 ? 1 : 0
                if (score > 0) l.push({ a: a, score: score })
            } else if (category === "Todas" || (category === "Favoritos" && a.fav) || a.group === category) l.push({ a: a, score: 0 })
        }
        l.sort(function (x, y) {
            if (x.score !== y.score) return y.score - x.score
            if (!nq && x.a.fav !== y.a.fav) return x.a.fav ? -1 : 1
            if (x.a.uses !== y.a.uses) return y.a.uses - x.a.uses
            return x.a.name.localeCompare(y.a.name)
        })
        l = l.map(function (o) { return o.a })
        if (!nq && category === "Todas") {
            t = apps.filter(function (a) { return a.fav })
            if (!t.length) t = apps.slice().sort(function (x, y) { return y.uses - x.uses }).filter(function (a) { return a.uses > 0 }).slice(0, 5)
            t = t.slice(0, cols)
            const ids = {}; for (let k = 0; k < t.length; k++) ids[t[k].id] = 1
            l = l.filter(function (a) { return !ids[a.id] })            // sin repetir los de arriba
        }
        const r = []
        function chunk(arr, base) { for (let i = 0; i < arr.length; i += cols) r.push({ k: "row", items: arr.slice(i, i + cols), base: base + i }) }
        if (t.length) r.push({ k: "label", t: "FAVORITOS", first: true })
        chunk(t, 0)
        if (t.length) r.push({ k: "label", t: "TODAS LAS APLICACIONES", first: false })
        chunk(l, t.length)
        if (!t.length && !l.length) r.push({ k: "empty" })
        favs = t; list = l; rows = r
        idx = Math.max(0, Math.min(idx, t.length + l.length - 1))
    }
    onQueryChanged: { idx = 0; update() }
    onCategoryChanged: update()
    Connections { target: menu.api; function onAppsChanged() { menu.update() } }

    function selectCategory(c) { category = c; query = ""; idx = 0; update() }
    function stepCategory(d) { selectCategory(cats[Math.max(0, Math.min(cats.length - 1, cats.indexOf(category) + d))]) }
    function launchCurrent() { if (current) api.launchApp(current, function (ok) { if (ok) menu.closeRequested() }) }
    function toggleFav(a) { if (a) api.toggleAppFav(a) }
    function enter() {
        if (mode === "power") { pwActivate(); return }
        if (zone === "grid") launchCurrent()
        else if (zone === "cats") { zone = "grid"; idx = 0 }
        else { const a = all(); if (a.length) { idx = 0; launchCurrent() } }
    }
    function back() {
        if (mode === "power") pwBack()
        else if (query !== "") query = ""
        else closeRequested()
    }
    function togglePower() { mode = mode === "power" ? "apps" : "power"; pwConfirm = ""; pwIdx = 0; pwCI = 0 }
    function pwActivate() {
        const it = pwItems[pwIdx]
        if (pwConfirm !== "") {
            if (pwCI === 1) { api.power(pwConfirm); closeRequested() } else pwConfirm = ""
            return
        }
        if (it.c) { pwConfirm = it.id; pwCI = 0 } else { api.power(it.id); closeRequested() }
    }
    function pwBack() { if (pwConfirm !== "") pwConfirm = ""; else mode = "apps" }
    function pwQuestion() { for (let i = 0; i < pwItems.length; i++) if (pwItems[i].id === pwConfirm) return pwItems[i].q; return "" }

    // navegación por zonas (buscador / categorías / mosaico), igual con teclado y mando
    function nav(d) {
        if (mode === "power") {
            if (pwConfirm !== "") { if (d === "l") pwCI = 0; else if (d === "r") pwCI = 1 }
            else if (d === "l") pwIdx = Math.max(0, pwIdx - 1)
            else if (d === "r") pwIdx = Math.min(pwItems.length - 1, pwIdx + 1)
            return
        }
        const n = favs.length + list.length
        if (zone === "grid") {
            if (d === "r") idx = Math.min(n - 1, idx + 1)
            else if (d === "l") idx = Math.max(0, idx - 1)
            else if (d === "d") {
                if (favs.length && idx < favs.length) idx = Math.min(n - 1, favs.length + Math.min(idx, Math.max(0, list.length - 1)))
                else idx = Math.min(n - 1, idx + cols)
            } else if (d === "u") {
                if (favs.length && idx >= favs.length && idx - cols < favs.length) idx = Math.min(favs.length - 1, Math.max(0, idx - favs.length))
                else if (idx < cols && (!favs.length || idx < favs.length)) zone = "cats"
                else idx = idx - cols
            }
        } else if (zone === "cats") {
            if (d === "r") stepCategory(1)
            else if (d === "l") stepCategory(-1)
            else if (d === "d") { zone = "grid"; idx = 0 }
            else if (d === "u") zone = "q"
        } else if (d === "d") zone = "cats"
    }

    onOpenChanged: {
        if (open) {
            mode = "apps"; pwConfirm = ""; pwIdx = 0; pwCI = 0
            query = ""; category = "Todas"; zone = "cats"; idx = 0
            api.loadApps()
            update()
            showTimer.restart()
            body.forceActiveFocus()
        } else { showTimer.stop(); shown = false }
    }
    Timer { id: showTimer; interval: 70; onTriggered: menu.shown = menu.open }          // deja que la ventana aparezca antes de animar
    onZoneChanged: { if (zone === "q") input.forceActiveFocus(); else body.forceActiveFocus() }

    Connections {
        target: menu.api
        function onPadKey(key) {
            if (!menu.open) return
            if (key === "r") menu.nav("r"); else if (key === "l") menu.nav("l")
            else if (key === "d") menu.nav("d"); else if (key === "u") menu.nav("u")
            else if (key === "A") menu.enter()
            else if (key === "B") menu.back()
            else if (key === "X") { if (menu.mode === "apps") menu.toggleFav(menu.current) }
            else if (key === "Y") { if (menu.mode === "apps") menu.zone = "q" }
            else if (key === "RB") { if (menu.mode === "apps") menu.stepCategory(1) }
            else if (key === "LB") { if (menu.mode === "apps") menu.stepCategory(-1) }
            else if (key === "SELECT") menu.togglePower()
        }
    }

    // ================================================================ composición
    Item {
        id: container
        anchors.fill: parent
        opacity: menu.shown ? 1 : 0
        Behavior on opacity { NumberAnimation { duration: 300; easing.type: Easing.InOutCubic } }

        // sin telón: detrás del panel se ve lo que haya en pantalla; un clic fuera lo cierra
        MouseArea { anchors.fill: parent; onClicked: menu.closeRequested() }
        RectangularGlow {
            x: (parent.width - 56 * menu.u) / 2; y: 0.53 * parent.height - 21.5 * menu.u + 2 * menu.u
            width: 56 * menu.u; height: 43 * menu.u
            glowRadius: menu.u * 3.5; spread: 0; color: "#99000000"; cornerRadius: 2 * menu.u + glowRadius; cached: true
        }

        FocusScope {
            id: body
            x: (parent.width - width) / 2; y: 0.53 * parent.height - height / 2
            width: 56 * menu.u; height: 43 * menu.u
            focus: true
            Keys.onPressed: function (e) {
                const k = e.key
                let handled = true
                if (k === Qt.Key_Escape) menu.back()
                else if (k === Qt.Key_P && (e.modifiers & Qt.ControlModifier)) menu.togglePower()
                else if (k === Qt.Key_Right) menu.nav("r")
                else if (k === Qt.Key_Left) menu.nav("l")
                else if (k === Qt.Key_Down) menu.nav("d")
                else if (k === Qt.Key_Up) menu.nav("u")
                else if (k === Qt.Key_Return || k === Qt.Key_Enter) menu.enter()
                else if (k === Qt.Key_Tab) menu.zone = menu.zone === "q" ? "cats" : (menu.zone === "cats" ? "grid" : "q")
                else if (k === Qt.Key_Backtab) menu.zone = menu.zone === "grid" ? "cats" : (menu.zone === "cats" ? "q" : "grid")
                else if ((k === Qt.Key_F || k === Qt.Key_D) && (e.modifiers & Qt.ControlModifier)) menu.toggleFav(menu.current)
                else if (menu.mode === "apps" && e.text.length > 0 && !(e.modifiers & (Qt.ControlModifier | Qt.MetaModifier))) {
                    menu.zone = "q"; input.forceActiveFocus(); input.text += e.text       // escribir en cualquier zona busca
                } else handled = false
                e.accepted = handled
            }

            Item {
                id: panel
                anchors.fill: parent
                transformOrigin: Item.Center
                scale: menu.shown ? 1 : 0.97
                y: menu.shown ? 0 : menu.u * 1.2
                Behavior on scale { NumberAnimation { duration: 300; easing.type: Easing.InOutCubic } }
                Behavior on y { NumberAnimation { duration: 300; easing.type: Easing.InOutCubic } }
                MouseArea { anchors.fill: parent }                         // los clics dentro del panel no lo cierran

                // ---- cristal: oscurecido + tinte + brillo superior + borde dorado
                Rectangle { id: glassMask; anchors.fill: parent; radius: menu.u * 2; visible: false }
                Item {
                    anchors.fill: parent
                    layer.enabled: true
                    layer.effect: OpacityMask { maskSource: glassMask }
                    Rectangle { anchors.fill: parent; color: "#030a07"; opacity: menu.panelDim }
                    LinearGradient {
                        anchors.fill: parent; start: Qt.point(0, 0); end: Qt.point(width, height)
                        gradient: Gradient {
                            GradientStop { position: 0.0; color: "#0ed2f5e8" }
                            GradientStop { position: 0.45; color: "#6b0e221a" }
                            GradientStop { position: 1.0; color: "#9406120d" }
                        }
                    }
                    Rectangle { x: menu.u * 2; width: parent.width - menu.u * 4; height: 1; color: "#38fff6c8" }
                }
                Rectangle { anchors.fill: parent; radius: menu.u * 2; color: "transparent"; border.width: 1; border.color: "#33e6d9a0" }

                Column {
                    anchors.fill: parent; spacing: 0

                    // ---- cabecera: búsqueda + energía
                    Item {
                        width: parent.width; height: menu.u * 5.3
                        Row {
                            x: menu.u * 1.8; y: menu.u * 1.3; width: parent.width - menu.u * 3.6; spacing: menu.u * 1.2
                            Rectangle {
                                width: parent.width - menu.u * 4.2; height: menu.u * 3.0; radius: height / 2
                                color: "#73040c09"; border.width: 1; border.color: input.activeFocus || menu.zone === "q" ? "#e6d9a0" : "#33e6d9a0"
                                Kirigami.Icon { x: menu.u * 1.2; anchors.verticalCenter: parent.verticalCenter; width: menu.u * 1.3; height: width; source: "search"; color: "#e6d9a0" }
                                TextInput {
                                    id: input
                                    x: menu.u * 3.1; width: parent.width - menu.u * 3.8; height: parent.height; clip: true
                                    font.pixelSize: menu.u * 1.2; font.family: "Noto Sans"; color: "#e9e6d6"; selectByMouse: true
                                    verticalAlignment: TextInput.AlignVCenter
                                    text: menu.query
                                    onTextChanged: if (text !== menu.query) menu.query = text
                                    Connections { target: menu; function onQueryChanged() { if (input.text !== menu.query) input.text = menu.query } }
                                    Text { visible: !input.text; anchors.verticalCenter: parent.verticalCenter; text: "Buscar aplicaciones…"; color: "#73e9e6d6"; font: input.font }
                                    Keys.onPressed: function (e) {
                                        if (e.key === Qt.Key_Down || e.key === Qt.Key_Tab) { menu.zone = "cats"; e.accepted = true }
                                        else if (e.key === Qt.Key_Return || e.key === Qt.Key_Enter) { menu.enter(); e.accepted = true }
                                        else if (e.key === Qt.Key_Escape) { if (text !== "") text = ""; else menu.closeRequested(); e.accepted = true }
                                        else if (e.key === Qt.Key_P && (e.modifiers & Qt.ControlModifier)) { menu.togglePower(); e.accepted = true }
                                    }
                                }
                            }
                            Rectangle {
                                width: menu.u * 3.0; height: width; radius: width / 2
                                color: menu.mode === "power" ? "#33e6d9a0" : "transparent"; border.width: 1; border.color: "#59e6d9a0"
                                Kirigami.Icon { anchors.centerIn: parent; width: menu.u * 1.45; height: width; source: "system-shutdown-symbolic"; color: "#e6d9a0" }
                                MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: menu.togglePower() }
                            }
                        }
                    }

                    // ---- categorías: píldoras en carrusel (el seleccionado avanza al centro y el carrusel lo acompaña)
                    Item {
                        id: catVp
                        visible: menu.mode === "apps"
                        width: parent.width; height: menu.mode === "apps" ? menu.u * 3.7 : 0; clip: true
                        readonly property real pad: menu.u * 1.8
                        readonly property real viewW: width - 2 * pad
                        property real scrollX: 0
                        function recalc() {
                            const it = catRep.itemAt(menu.cats.indexOf(menu.category))
                            if (!it) return
                            scrollX = Math.max(0, Math.min(it.x + it.width / 2 - viewW / 2, Math.max(0, catRow.width - viewW)))
                        }
                        Behavior on scrollX { NumberAnimation { duration: 300; easing.type: Easing.OutCubic } }
                        Connections { target: menu; function onCategoryChanged() { catVp.recalc() } }
                        onViewWChanged: recalc()
                        Component.onCompleted: recalc()
                        Row {
                            id: catRow
                            x: catVp.pad - catVp.scrollX; y: 0; height: menu.u * 2.5; spacing: menu.u * 0.6
                            onWidthChanged: catVp.recalc()
                            Repeater {
                                id: catRep
                                model: menu.cats
                                delegate: Rectangle {
                                    id: pill
                                    required property string modelData
                                    readonly property bool on: menu.category === modelData
                                    readonly property real cx: x + width / 2 - catVp.scrollX + catVp.pad
                                    readonly property real edge: menu.u * 5
                                    readonly property bool moreL: catVp.scrollX > 1
                                    readonly property bool moreR: catVp.scrollX < catRow.width - catVp.viewW - 1
                                    height: catRow.height; radius: height / 2; width: pt.implicitWidth + menu.u * 2.3
                                    // se desvanece solo en el borde que tiene más píldoras detrás
                                    opacity: Math.max(0.1, Math.min(moreL ? Math.min(1, (cx - catVp.pad * 0.3) / edge) : 1, moreR ? Math.min(1, (catVp.width - cx - catVp.pad * 0.3) / edge) : 1))
                                    color: on ? "#e6d9a0" : "#12e9e6d6"
                                    Behavior on color { ColorAnimation { duration: 180 } }
                                    border.width: menu.zone === "cats" && on ? 2 : 0; border.color: "#ffffff"
                                    Text { id: pt; anchors.centerIn: parent; text: pill.modelData.toUpperCase()
                                        font.pixelSize: menu.u * 1.0; font.family: "Rajdhani"; font.weight: Font.DemiBold; font.letterSpacing: menu.u * 0.09
                                        color: pill.on ? "#14211a" : "#bfe9e6d6" }
                                    MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: { menu.zone = "cats"; menu.selectCategory(pill.modelData) } }
                                }
                            }
                        }
                        MouseArea { anchors.fill: parent; acceptedButtons: Qt.NoButton
                            onWheel: function (w) { menu.zone = "cats"; menu.stepCategory((w.angleDelta.y > 0 || w.angleDelta.x > 0) ? -1 : 1) } }
                    }

                    // ---- mosaico (lista virtualizada: solo se crean las filas visibles) y vista de energía
                    Item {
                        id: area
                        width: parent.width; height: parent.height - menu.u * 5.3 - catVp.height - menu.u * 2.8
                        ListView {
                            id: gridList
                            visible: menu.mode === "apps"
                            x: menu.u * 1.8; y: menu.u * 0.4; width: parent.width - menu.u * 3.6; height: parent.height - menu.u * 0.4
                            clip: true; model: menu.rows; cacheBuffer: Math.max(0, height); reuseItems: true
                            boundsBehavior: Flickable.StopAtBounds
                            readonly property real rowH: menu.u * (0.78 * 2 + 5.6 + 0.6 + 2.0)
                            readonly property real tileW: width / menu.cols
                            NumberAnimation { id: scrollAnim; target: gridList; property: "contentY"; duration: 220; easing.type: Easing.OutCubic }
                            delegate: Item {
                                id: rowD
                                required property var modelData
                                required property int index
                                width: gridList.width
                                height: modelData.k === "row" ? gridList.rowH : (modelData.k === "label" ? menu.u * (modelData.first ? 3.0 : 3.6) : menu.u * 14)
                                Item { visible: rowD.modelData.k === "label"; anchors.fill: parent
                                    Text { id: lb; y: menu.u * (rowD.modelData.first ? 0.9 : 1.5); text: rowD.modelData.t || ""; color: "#e6d9a0"
                                        font.pixelSize: menu.u; font.family: "Rajdhani"; font.weight: Font.DemiBold; font.letterSpacing: menu.u * 0.22 }
                                    Rectangle { x: lb.implicitWidth + menu.u; y: lb.y + lb.implicitHeight / 2; width: parent.width - x; height: 1; color: "#38e6d9a0" } }
                                Row { id: tileRow; visible: rowD.modelData.k === "row"; property int gbase: rowD.modelData.base || 0
                                    Repeater { model: rowD.modelData.k === "row" ? rowD.modelData.items : []
                                        delegate: Item {
                                            id: tile
                                            required property var modelData
                                            required property int index
                                            readonly property int gi: tileRow.gbase + index
                                            readonly property bool sel: menu.zone === "grid" && menu.idx === gi
                                            readonly property real isz: menu.u * 5.6
                                            readonly property color col: menu.color(modelData.name)
                                            width: gridList.tileW; height: gridList.rowH
                                            Rectangle { anchors.fill: parent; anchors.margins: menu.u * 0.25; radius: menu.u * 1.3
                                                color: tile.sel ? "#29e6d9a0" : (tm.containsMouse ? "#17e9e6d6" : "transparent"); border.width: tile.sel ? 1 : 0; border.color: "#8ce6d9a0" }
                                            Item {
                                                id: icBox
                                                width: tile.isz; height: tile.isz; x: (parent.width - width) / 2; y: menu.u * 0.78
                                                scale: tm.containsMouse || tile.sel ? 1.06 : 1
                                                Behavior on scale { NumberAnimation { duration: 140; easing.type: Easing.OutCubic } }
                                                // «squircle» con el color de cada app, brillo de cristal arriba y el icono real encima
                                                Rectangle {
                                                    anchors.fill: parent; radius: width * 0.24
                                                    gradient: Gradient {
                                                        GradientStop { position: 0.0; color: Qt.rgba(tile.col.r, tile.col.g, tile.col.b, 0.50) }
                                                        GradientStop { position: 1.0; color: Qt.rgba(tile.col.r * 0.4, tile.col.g * 0.4, tile.col.b * 0.4, 0.62) }
                                                    }
                                                    border.width: 1; border.color: "#4dffffff"
                                                    Rectangle { x: 1; y: 1; width: parent.width - 2; height: parent.height * 0.48; radius: parent.radius - 1
                                                        gradient: Gradient { GradientStop { position: 0; color: "#38ffffff" } GradientStop { position: 1; color: "#00ffffff" } } }
                                                }
                                                Text { anchors.centerIn: parent; visible: !realIcon.valid; text: menu.initials(tile.modelData.name); color: "#ffffff"
                                                    font.pixelSize: tile.isz * 0.4; font.family: "Rajdhani"; font.weight: Font.Bold }
                                                Kirigami.Icon { id: realIcon; anchors.centerIn: parent; width: parent.width * 0.66; height: width; source: menu.icon(tile.modelData); visible: valid }
                                            }
                                            Text { y: icBox.y + icBox.height + menu.u * 0.6; width: parent.width - menu.u * 0.6; x: menu.u * 0.3; horizontalAlignment: Text.AlignHCenter; elide: Text.ElideRight
                                                text: tile.modelData.name; color: "#e9e6d6"; font.pixelSize: menu.u * 1.1; font.family: "Noto Sans"; font.weight: Font.Medium }
                                            Text { visible: tile.modelData.fav || tm.containsMouse; anchors.right: parent.right; anchors.top: parent.top; anchors.margins: menu.u * 0.5
                                                text: "★"; font.pixelSize: menu.u * 1.2; color: tile.modelData.fav ? "#e6d9a0" : "#a6e9e6d6" }
                                            MouseArea { id: tm; anchors.fill: parent; z: 1; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                                                acceptedButtons: Qt.LeftButton | Qt.RightButton
                                                onClicked: function (m) {
                                                    menu.zone = "grid"; menu.idx = tile.gi
                                                    if (m.button === Qt.RightButton) menu.toggleFav(tile.modelData); else menu.launchCurrent()
                                                } }
                                        } } }
                                Text { visible: rowD.modelData.k === "empty"; anchors.centerIn: parent
                                    text: menu.query ? "Sin resultados para «" + menu.query + "»" : (menu.category === "Favoritos" ? "Aún no hay favoritos: pulsa Ctrl+F o X sobre una aplicación" : "Sin aplicaciones")
                                    color: "#99e9e6d6"; font.pixelSize: menu.u * 1.4; font.family: "Noto Sans" }
                            }
                            // mantiene visible la selección con desplazamiento suave (y su etiqueta de sección)
                            Connections { target: menu; function onIdxChanged() { gridList.follow() } }
                            function follow() {
                                let ri = -1
                                for (let r = 0; r < menu.rows.length; r++) { const q = menu.rows[r]; if (q.k === "row" && menu.idx >= q.base && menu.idx < q.base + q.items.length) { ri = r; break } }
                                if (ri < 0) return
                                let y = 0
                                for (let k = 0; k < ri; k++) { const m = menu.rows[k]; y += m.k === "row" ? rowH : (m.k === "label" ? menu.u * (m.first ? 3.0 : 3.6) : menu.u * 14) }
                                let target = contentY
                                if (ri > 0 && menu.rows[ri - 1].k === "label") y -= menu.u * (menu.rows[ri - 1].first ? 3.0 : 3.6)
                                if (y < contentY) target = Math.max(0, y)
                                else if (y + rowH > contentY + height) target = y + rowH - height + menu.u * 0.4
                                if (target !== contentY) { scrollAnim.stop(); scrollAnim.to = target; scrollAnim.start() }
                            }
                        }

                        // ---- Energía y sesión
                        Item {
                            id: pwView
                            visible: menu.mode === "power"
                            anchors.fill: parent
                            opacity: visible ? 1 : 0
                            Behavior on opacity { NumberAnimation { duration: 200 } }
                            Column {
                                anchors.centerIn: parent; spacing: menu.u * 1.8
                                Text {
                                    anchors.horizontalCenter: parent.horizontalCenter
                                    text: menu.pwConfirm === "" ? "Energía y sesión" : menu.pwQuestion()
                                    color: "#ffffff"; font.pixelSize: menu.u * 2.2; font.family: "Noto Sans"; font.weight: Font.Light
                                }
                                Row {
                                    visible: menu.pwConfirm === ""
                                    anchors.horizontalCenter: parent.horizontalCenter; spacing: menu.u * 0.6
                                    Repeater {
                                        model: menu.pwItems
                                        delegate: Item {
                                            id: pwi
                                            required property var modelData
                                            required property int index
                                            readonly property bool sel: menu.pwIdx === index
                                            width: menu.u * 8.4; height: menu.u * 9.2
                                            scale: sel ? 1.06 : 1
                                            Behavior on scale { NumberAnimation { duration: 140; easing.type: Easing.OutCubic } }
                                            Rectangle { anchors.fill: parent; radius: menu.u * 1.4; color: pwi.sel ? "#33e6d9a0" : (pm.containsMouse ? "#1affffff" : "transparent"); border.width: pwi.sel ? 2 : 0; border.color: "#e6d9a0" }
                                            Kirigami.Icon { source: pwi.modelData.icon; width: menu.u * 4; height: width; anchors.horizontalCenter: parent.horizontalCenter; y: menu.u * 1.4 }
                                            Text { y: menu.u * 6.6; width: parent.width; horizontalAlignment: Text.AlignHCenter; text: pwi.modelData.t; color: "#e9e6d6"; font.pixelSize: menu.u * 1.1; font.family: "Noto Sans" }
                                            MouseArea { id: pm; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: { menu.pwIdx = pwi.index; menu.pwActivate() } }
                                        }
                                    }
                                }
                                Row {
                                    visible: menu.pwConfirm !== ""
                                    anchors.horizontalCenter: parent.horizontalCenter; spacing: menu.u * 1.4
                                    Repeater {
                                        model: ["Cancelar", "Confirmar"]
                                        delegate: Rectangle {
                                            id: cb
                                            required property string modelData
                                            required property int index
                                            readonly property bool sel: menu.pwCI === index
                                            width: menu.u * 12; height: menu.u * 3.8; radius: height / 2
                                            color: sel ? (index === 1 ? "#e6c25a4a" : "#e6e6d9a0") : "#1fffffff"
                                            border.width: sel ? 2 : 0; border.color: "#e6d9a0"
                                            Text { anchors.centerIn: parent; text: cb.modelData; color: cb.sel && index === 0 ? "#14211a" : "#f3efe3"; font.pixelSize: menu.u * 1.3; font.family: "Noto Sans"; font.weight: Font.DemiBold }
                                            MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: { menu.pwCI = cb.index; menu.pwActivate() } }
                                        }
                                    }
                                }
                                Text {
                                    anchors.horizontalCenter: parent.horizontalCenter
                                    text: menu.pwConfirm === "" ? "← →  elegir · A / Intro  aceptar · B / Esc  volver" : "← →  elegir · A / Intro  aceptar · B / Esc  cancelar"
                                    color: "#99e9e6d6"; font.pixelSize: menu.u * 0.95; font.family: "Noto Sans"
                                }
                            }
                        }
                    }

                    // ---- pie
                    Item {
                        width: parent.width; height: menu.u * 2.8
                        Text { visible: menu.mode === "apps"; x: menu.u * 1.8; anchors.verticalCenter: parent.verticalCenter
                            text: (menu.favs.length + menu.list.length) + " apps"; color: "#8ce9e6d6"; font.pixelSize: menu.u * 0.95; font.family: "Noto Sans" }
                        PadGuide {
                            visible: menu.mode === "apps" && menu.api && menu.api.padOn
                            anchors.right: parent.right; anchors.rightMargin: menu.u * 1.8; anchors.verticalCenter: parent.verticalCenter
                            width: menu.u * 40
                            padName: menu.api ? menu.api.padName : ""
                            iconSize: menu.u * 1.5; fontPx: menu.u * 0.85; spacing: menu.u * 0.8
                            textColor: "#b3e9e6d6"; fontFamily: "Noto Sans"
                            hints: [{ k: "A", t: "Abrir" }, { k: "B", t: "Cerrar" }, { k: "X", t: "Favorito" }, { k: "Y", t: "Buscar" }, { k: "LB+RB", t: "Categoría" }, { k: "SELECT", t: "Energía" }]
                        }
                        Text { visible: menu.mode === "apps" && !(menu.api && menu.api.padOn); anchors.right: parent.right; anchors.rightMargin: menu.u * 1.8; anchors.verticalCenter: parent.verticalCenter
                            text: "Intro abre · Ctrl+F favorito · Ctrl+P energía · Tab cambia de zona · Esc cierra"; color: "#8ce9e6d6"; font.pixelSize: menu.u * 0.95; font.family: "Noto Sans" }
                    }
                }
            }
        }
    }
}

import QtQuick
import org.kde.kirigami as Kirigami

// Big Menu: lanzador de aplicaciones con búsqueda, categorías y favoritos. Teclado, ratón y mando.
FocusScope {
    id: menu
    property var api
    property bool open: false
    signal closeRequested

    property string query: ""
    property string category: "Todas"
    readonly property var cats: ["Favoritos", "Todas"].concat(api ? api.appGroups : [])
    readonly property int cols: Math.max(1, Math.floor(grid.width / grid.cellWidth))
    readonly property var shown: compute(api ? api.apps : [], query, category)
    readonly property var current: (grid.currentIndex >= 0 && grid.currentIndex < shown.length) ? shown[grid.currentIndex] : null

    function norm(s) { return (s || "").normalize("NFD").replace(/[̀-ͯ]/g, "").toLowerCase() }

    function compute(list, q, cat) {
        const nq = norm(q.trim())
        let out = []
        for (let i = 0; i < list.length; i++) {
            const a = list[i]
            if (nq === "") {
                if (cat === "Favoritos" && !a.fav) continue
                if (cat !== "Favoritos" && cat !== "Todas" && a.group !== cat) continue
                out.push({ a: a, score: 0 })
            } else {                                                  // buscando: se ignora la categoría
                const n = norm(a.name)
                let score = n.indexOf(nq) === 0 ? 3 : n.indexOf(nq) > 0 ? 2
                          : norm(a.keywords.join(" ")).indexOf(nq) >= 0 ? 1 : norm(a.comment).indexOf(nq) >= 0 ? 1 : 0
                if (score > 0) out.push({ a: a, score: score })
            }
        }
        out.sort(function (x, y) {
            if (x.score !== y.score) return y.score - x.score
            if (nq === "" && x.a.fav !== y.a.fav) return x.a.fav ? -1 : 1
            if (x.a.uses !== y.a.uses) return y.a.uses - x.a.uses
            return x.a.name.localeCompare(y.a.name)
        })
        return out.map(function (o) { return o.a })
    }

    function icon(a) { return a.icon && a.icon.charAt(0) === "/" ? "file://" + a.icon : (a.icon || "application-x-executable") }
    function move(dx, dy) {
        const n = shown.length
        if (n === 0) return
        grid.currentIndex = Math.max(0, Math.min(n - 1, grid.currentIndex + dx + dy * cols))
    }
    function step(d) {
        const i = cats.indexOf(category)
        category = cats[(i + d + cats.length) % cats.length]
        grid.currentIndex = 0
    }
    function launchCurrent() {
        if (!current) return
        api.launchApp(current, function (ok) { if (ok) menu.closeRequested() })
    }

    onOpenChanged: {
        if (!open) return
        query = ""
        api.loadApps()
        grid.currentIndex = 0
        input.forceActiveFocus()
    }
    // «Favoritos» vacío no tiene sentido: al abrir se parte de «Todas» hasta que haya favoritos
    onShownChanged: if (grid.currentIndex >= shown.length) grid.currentIndex = Math.max(0, shown.length - 1)
    Connections {
        target: menu.api
        function onAppsChanged() { if (menu.open && menu.category === "Favoritos" && menu.shown.length === 0) menu.category = "Todas" }
        function onPadKey(key) {
            if (!menu.open) return
            if (key === "r") menu.move(1, 0); else if (key === "l") menu.move(-1, 0)
            else if (key === "d") menu.move(0, 1); else if (key === "u") menu.move(0, -1)
            else if (key === "A") menu.launchCurrent(); else if (key === "B") menu.closeRequested()
            else if (key === "X" && menu.current) menu.api.toggleAppFav(menu.current)
            else if (key === "RB") menu.step(1); else if (key === "LB") menu.step(-1)
        }
    }

    // telón y panel
    Rectangle { anchors.fill: parent; color: Qt.rgba(0.02, 0.07, 0.05, 0.86); MouseArea { anchors.fill: parent; onClicked: menu.closeRequested() } }
    Rectangle {
        id: panel
        width: Math.min(1180, parent.width * 0.78); height: Math.min(760, parent.height * 0.80)
        anchors.centerIn: parent
        radius: 28; color: Qt.rgba(0.06, 0.14, 0.11, 0.985)
        border.width: 1; border.color: Qt.rgba(0.9, 0.85, 0.63, 0.25)
        MouseArea { anchors.fill: parent }                         // los clics dentro del panel no lo cierran

        // búsqueda
        Rectangle {
            id: searchBox
            anchors { top: parent.top; left: parent.left; right: parent.right; margins: 28 }
            height: 56; radius: 28; color: Qt.rgba(1, 1, 1, 0.08)
            Text { id: lens; anchors { left: parent.left; leftMargin: 20; verticalCenter: parent.verticalCenter } text: "⌕"; color: "#c9bf8a"; font.pixelSize: 28 }
            TextInput {
                id: input
                anchors { left: lens.right; leftMargin: 12; right: parent.right; rightMargin: 20; verticalCenter: parent.verticalCenter }
                color: "#f4efd8"; font.pixelSize: 22; clip: true; focus: true
                text: menu.query
                onTextChanged: { menu.query = text; grid.currentIndex = 0 }
                Text { visible: !input.text; anchors.verticalCenter: parent.verticalCenter; text: "Escribe para buscar…"; color: "#8c8560"; font.pixelSize: 22 }
                Keys.onPressed: function (e) {
                    if (e.key === Qt.Key_Escape) { if (input.text) input.text = ""; else menu.closeRequested(); e.accepted = true }
                    else if (e.key === Qt.Key_Right) { menu.move(1, 0); e.accepted = true }
                    else if (e.key === Qt.Key_Left) { menu.move(-1, 0); e.accepted = true }
                    else if (e.key === Qt.Key_Down) { menu.move(0, 1); e.accepted = true }
                    else if (e.key === Qt.Key_Up) { menu.move(0, -1); e.accepted = true }
                    else if (e.key === Qt.Key_Tab) { menu.step(1); e.accepted = true }
                    else if (e.key === Qt.Key_Backtab) { menu.step(-1); e.accepted = true }
                    else if (e.key === Qt.Key_Return || e.key === Qt.Key_Enter) { menu.launchCurrent(); e.accepted = true }
                    else if ((e.modifiers & Qt.ControlModifier) && e.key === Qt.Key_D && menu.current) { menu.api.toggleAppFav(menu.current); e.accepted = true }
                }
            }
        }

        // categorías
        ListView {
            id: tabs
            anchors { top: searchBox.bottom; topMargin: 16; left: parent.left; right: parent.right; leftMargin: 28; rightMargin: 28 }
            height: 40; orientation: ListView.Horizontal; spacing: 10; clip: true
            interactive: contentWidth > width
            model: menu.cats
            delegate: Rectangle {
                required property string modelData
                height: 40; width: lbl.width + 36; radius: 20
                readonly property bool on: menu.query === "" && menu.category === modelData
                color: on ? "#2e8b57" : Qt.rgba(1, 1, 1, 0.07)
                Text { id: lbl; anchors.centerIn: parent; text: modelData === "Favoritos" ? "★ Favoritos" : modelData
                       color: on ? "white" : "#c9bf8a"; font.pixelSize: 17; font.bold: on }
                MouseArea { anchors.fill: parent; onClicked: { menu.category = modelData; menu.query = ""; input.text = ""; grid.currentIndex = 0 } }
            }
        }

        // aplicaciones
        GridView {
            id: grid
            anchors { top: tabs.bottom; topMargin: 18; left: parent.left; right: parent.right; bottom: hint.top; leftMargin: 28; rightMargin: 28; bottomMargin: 8 }
            cellWidth: Math.floor(width / Math.max(1, Math.floor(width / 168))); cellHeight: 150
            clip: true; model: menu.shown; currentIndex: 0; keyNavigationEnabled: false
            highlightFollowsCurrentItem: true; highlightMoveDuration: 0
            delegate: Item {
                id: tile
                required property var modelData
                required property int index
                width: grid.cellWidth; height: grid.cellHeight
                readonly property bool cur: GridView.isCurrentItem
                Rectangle {
                    anchors { fill: parent; margins: 6 }
                    radius: 18; color: tile.cur ? Qt.rgba(0.9, 0.85, 0.63, 0.16) : (hov.containsMouse ? Qt.rgba(1, 1, 1, 0.07) : "transparent")
                    border.width: tile.cur ? 2 : 0; border.color: "#e6d9a0"
                }
                Column {
                    anchors.centerIn: parent; spacing: 8; width: parent.width - 20
                    Kirigami.Icon { anchors.horizontalCenter: parent.horizontalCenter; width: 64; height: 64; source: menu.icon(tile.modelData) }
                    Text { width: parent.width; horizontalAlignment: Text.AlignHCenter; wrapMode: Text.WordWrap; maximumLineCount: 2; elide: Text.ElideRight
                           text: tile.modelData.name; color: "#f4efd8"; font.pixelSize: 15 }
                }
                Text { visible: tile.modelData.fav; anchors { top: parent.top; right: parent.right; margins: 12 } text: "★"; color: "#e6d9a0"; font.pixelSize: 18 }
                MouseArea {
                    id: hov; anchors.fill: parent; hoverEnabled: true; acceptedButtons: Qt.LeftButton | Qt.RightButton
                    onClicked: function (m) {
                        grid.currentIndex = tile.index
                        if (m.button === Qt.RightButton) menu.api.toggleAppFav(tile.modelData); else menu.launchCurrent()
                    }
                }
            }
            Text { visible: menu.shown.length === 0; anchors.centerIn: parent; color: "#8c8560"; font.pixelSize: 20
                   text: menu.query ? "Sin resultados para «" + menu.query + "»" : (menu.category === "Favoritos" ? "Aún no hay favoritos: pulsa Ctrl+D o X sobre una aplicación" : "Sin aplicaciones") }
        }
        Text {
            id: hint
            anchors { bottom: parent.bottom; left: parent.left; right: parent.right; margins: 22 }
            horizontalAlignment: Text.AlignHCenter; color: "#8c8560"; font.pixelSize: 15
            text: "Escribe para buscar  ·  ← → ↑ ↓ elegir  ·  Tab categoría  ·  Enter abrir  ·  Ctrl+D favorito  ·  Esc cerrar"
        }
    }
}

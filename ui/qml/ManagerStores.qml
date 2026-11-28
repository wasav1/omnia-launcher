import QtQuick
import QtQuick.Controls
import "Theme.js" as Theme
import QtQuick.Dialogs

// Tiendas de la app de escritorio: una biblioteca unificada (Steam, Epic, GOG, Amazon) con filtros por tienda.
// Las cuentas se conectan en el navegador: Omnia abre la página de la tienda y el usuario pega la dirección de retorno.
Item {
    id: st
    property var manager
    property var api
    // En Explorar el contenido de las tiendas se presenta como una sección integrada.
    // Este modo conserva sus datos y el diálogo de cuentas, pero oculta la pantalla independiente.
    property bool compactHost: false
    property bool controllerHost: false   // Ajustes de Big Mode dibuja sus propias filas
    property string filter: "all"                         // all | steam | epic | gog | amazon
    property var stores: []                               // estado que devuelve /stores
    property var remote: ({})                             // id de tienda -> juegos de su biblioteca en línea
    property var loading: ({})
    property bool checking: false
    property var refreshAfterCheck: null
    property bool ready: false
    property var batch: ({})
    readonly property bool loadingContent: !ready || checking || Object.keys(loading).length > 0
    function publishBatch() {
        if (checking || Object.keys(loading).length) return
        remote = Object.assign({}, remote, batch)
        batch = ({})
        ready = true
    }
    property string message: ""
    property bool accountsOpen: false
    property Item accountsContainer: null
    readonly property real accountsHeight: accCol.implicitHeight + s * 44
    property string linking: ""                           // tienda cuyo inicio de sesión está en curso
    property string pasted: ""
    property bool busy: false
    property string requesting: ""
    property string connecting: ""                        // tienda que se está conectando (muestra el indicador)
    readonly property var loginWindow: webLoader.item
    readonly property real s: manager ? manager.s : 1
    readonly property var names: ({ steam: "Steam", epic: "Epic", gog: "GOG", amazon: "Amazon" })

    function storeOf(g) {
        if (g.src === "Steam") return "steam"
        const sub = String(g.sub || "")
        if (sub.indexOf("Epic") >= 0) return "epic"
        if (sub.indexOf("GOG") >= 0) return "gog"
        if (sub.indexOf("Amazon") >= 0) return "amazon"
        return ""
    }
    readonly property var localGames: (api && api.games ? api.games : []).filter(function(g) { return !g.hidden && storeOf(g) !== "" })
    readonly property var allItems: {
        const out = []
        const localNames = {}
        localGames.forEach(function(g) { localNames[storeOf(g) + "|" + String(g.name).toLowerCase()] = true })
        localGames.forEach(function(g) { out.push({ id: g.id, name: g.name, store: storeOf(g), art: g.portada || "", installed: true, local: g }) })
        Object.keys(remote).forEach(function(sid) {
            (remote[sid] || []).forEach(function(r) {
                if (!r.installed && !localNames[sid + "|" + String(r.title).toLowerCase()]) out.push({ id: sid + "-" + r.id, rawId: r.id, name: r.title, store: sid, art: r.art || "", hero: r.hero || "", metadata: r.metadata || {}, installed: false, local: null })
            })
        })
        out.sort(function(a, b) { return a.name.toLowerCase() < b.name.toLowerCase() ? -1 : 1 })
        return out
    }
    readonly property var items: allItems.filter(function(i) { return filter === "all" || i.store === filter })
    function count(sid) { return allItems.filter(function(i) { return i.store === sid }).length }
    function status(sid) { return stores.find(function(x) { return x.id === sid }) || null }
    readonly property var disconnected: ["steam", "epic", "gog", "amazon"].filter(function(sid) { const x = status(sid); return x && x.available && !x.logged_in })

    Connections {
        target: st.api
        function onStoreInstallationRemoved(store, product) {
            for (const key of ["remote", "batch"]) {
                const source = st[key]
                if (source[store]) st[key] = Object.assign({}, source, {
                    [store]: source[store].map(item => String(item.id) === product ? Object.assign({}, item, {installed: false}) : item)
                })
            }
        }
    }

    property var installTarget: null
    function installSteam(item) {
        Qt.openUrlExternally("steam://install/" + item.rawId)
        st.api.notify(qsTr("Steam abrió el diálogo para instalar «%1»; confírmalo allí.").arg(item.name))
    }
    function askInstall(item) { st.installTarget = item; installFolder.open() }
    FolderDialog {
        id: installFolder
        title: st.installTarget ? qsTr("Elige dónde instalar %1").arg(st.installTarget.name) : ""
        onAccepted: {
            const t = st.installTarget
            if (!t) return
            const path = decodeURIComponent(selectedFolder.toString().replace(/^file:\/\//, ""))
            api.storeInstall(t.store, t.rawId, t.name, path, function(code, body) {
                if (code !== 200) { st.message = body.error || qsTr("No se pudo empezar la instalación."); return }
                st.message = qsTr("Instalando «%1»: sigue el progreso en Descargas.").arg(t.name)
                st.manager.selectPage("installs")
            })
        }
    }
    function open() { refreshStores() }
    function refreshStores(done) {
        if (checking) {
            if (done) refreshAfterCheck = done
            return
        }
        checking = true
        api.loadStores(function(code, body) {
            if (code !== 200) st.message = qsTr("No se pudo consultar las tiendas.")
            else {
                st.stores = body.stores || []
                st.stores.forEach(function(x) { if (x.logged_in && !st.remote[x.id] && !st.loading[x.id]) st.loadLibrary(x.id) })
            }
            st.checking = false
            st.publishBatch()
            if (done) done()
            if (st.refreshAfterCheck) {
                const after = st.refreshAfterCheck
                st.refreshAfterCheck = null
                st.refreshStores(after)
            }
        })
    }
    function loadLibrary(sid) {
        const l = Object.assign({}, st.loading); l[sid] = true; st.loading = l
        api.storeLibrary(sid, function(code, body) {
            const l2 = Object.assign({}, st.loading); delete l2[sid]; st.loading = l2
            if (code === 200) { const r = Object.assign({}, st.batch); r[sid] = body.games || []; st.batch = r }
            else st.message = body.error || qsTr("No se pudo leer la biblioteca de %1.").arg(st.names[sid])
            st.publishBatch()
        })
    }
    function webLogin(sid, url) {
        // ventana propia con QtWebEngine (opcional); false si no está disponible
        webLoader.active = true
        if (webLoader.status !== Loader.Ready || !webLoader.item) { webLoader.active = false; return false }
        webLoader.item.begin(sid, url)
        return true
    }
    function startLink(sid, external) {
        if (requesting || connecting || busy) return
        st.message = ""
        st.requesting = sid
        api.storeLoginUrl(sid, function(code, body) {
            st.requesting = ""
            if (code !== 200) { st.message = body.error || qsTr("No se pudo abrir el inicio de sesión."); return }
            st.pasted = ""
            if (!external && st.webLogin(sid, body.url)) {
                st.linking = ""
                if (sid === "steam") { st.connecting = "steam"; st.message = qsTr("Conectando con Steam…") }
                else st.message = qsTr("Inicia sesión en la ventana de %1; Omnia te conecta sola.").arg(st.names[sid])
                return
            }
            if (sid === "steam") { st.message = qsTr("Steam necesita el componente qt6-webengine para conectarse desde Omnia."); return }
            st.linking = sid
            Qt.openUrlExternally(body.url)
        })
    }
    // Detección del portapapeles mientras se conecta una tienda por el navegador: al copiar el texto de la página de retorno
    // y volver a Omnia, se conecta sola. Solo se mira mientras hay un inicio de sesión abierto y solo se actúa si el texto encaja.
    TextEdit { id: clip; visible: false; width: 1; height: 1 }
    function clipboardLooksRight(sid, t) {
        if (!t || t.length > 4000) return false
        if (sid === "epic") return t.indexOf("authorizationCode") >= 0 || /^\s*"?[A-Za-z0-9]{16,64}"?\s*$/.test(t)
        if (sid === "gog") return t.indexOf("embed.gog.com/on_login_success") >= 0
        if (sid === "amazon") return t.indexOf("openid.oa2.authorization_code=") >= 0
        return false
    }
    function pasteLink() {
        if (!st.linking || st.busy) return false
        clip.text = ""
        clip.paste()
        const value = clip.text
        clip.text = ""
        if (!st.clipboardLooksRight(st.linking, value)) return false
        st.pasted = value
        st.finishLink()
        return true
    }
    Timer {
        interval: 1000; repeat: true
        running: st.accountsOpen && st.linking !== "" && !st.busy
        onTriggered: st.pasteLink()
    }
    Loader {
        id: webLoader
        active: false
        source: "StoreLogin.qml"
        onLoaded: {
            item.codeCaptured.connect(function(sid, text) { st.submit(sid, text.trim()) })
            item.abandoned.connect(function(sid) { st.connecting = "" })
        }
    }
    function finishLink() {
        if (!st.linking || st.pasted.trim() === "") return
        st.submit(st.linking, st.pasted.trim())
    }
    function submit(sid, text) {
        st.busy = true; st.connecting = sid; st.message = ""
        api.storeLogin(sid, text, function(code, body) {
            st.busy = false
            if (code !== 200) { st.connecting = ""; st.message = body.error || qsTr("No se pudo conectar."); return }
            st.linking = ""; st.pasted = ""; st.message = qsTr("%1 conectada.").arg(st.names[sid])
            // el indicador sigue hasta que el estado de la tienda ya diga «conectada»: así no reaparecen las opciones de inicio de sesión
            st.refreshStores(function() { st.connecting = "" })
        })
    }
    function unlink(sid) {
        if (requesting || connecting || busy) return
        st.requesting = sid
        api.storeLogout(sid, function(code, body) {
            st.requesting = ""
            if (code !== 200) { st.message = body.error || qsTr("No se pudo desconectar."); return }
            st.message = qsTr("%1 desconectada.").arg(st.names[sid])
            const r = Object.assign({}, st.remote); delete r[sid]; st.remote = r
            st.refreshStores()
        })
    }

    // ---- filtros por tienda
    Flow {
        id: chips
        visible: !st.compactHost
        anchors { left: parent.left; right: accountsBtn.left; top: parent.top; leftMargin: st.s * 32; rightMargin: st.s * 16; topMargin: st.s * 22 }
        spacing: st.s * 10
        Repeater {
            model: [{ k: "all", l: qsTr("Todas") }, { k: "steam", l: "Steam" }, { k: "epic", l: "Epic" }, { k: "gog", l: "GOG" }, { k: "amazon", l: "Amazon" }]
            delegate: Rectangle {
                id: chip
                required property var modelData
                readonly property bool on: st.filter === modelData.k
                readonly property int n: modelData.k === "all" ? st.allItems.length : st.count(modelData.k)
                width: chipText.implicitWidth + st.s * 34; height: st.s * 38; radius: height / 2
                color: on ? "#45CFC9" : (chipMa.containsMouse ? st.manager.surface2 : st.manager.surface)
                Text { id: chipText; anchors.centerIn: parent; text: chip.modelData.l + (chip.n > 0 ? "  " + chip.n : "")
                       color: chip.on ? "#0B0F14" : st.manager.ink; font.family: "Hanken Grotesk"; font.pixelSize: st.s * 14; font.weight: Font.DemiBold }
                MouseArea { id: chipMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: st.filter = chip.modelData.k }
            }
        }
    }
    Rectangle {
        id: accountsBtn
        visible: !st.compactHost
        anchors { right: parent.right; top: parent.top; rightMargin: st.s * 32; topMargin: st.s * 22 }
        width: accText.implicitWidth + st.s * 34; height: st.s * 38; radius: height / 2
        color: accMa.containsMouse ? st.manager.surface2 : st.manager.surface
        Text { id: accText; anchors.centerIn: parent; text: qsTr("Cuentas"); color: st.manager.ink; font.family: "Hanken Grotesk"; font.pixelSize: st.s * 14; font.weight: Font.DemiBold }
        MouseArea { id: accMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: { st.accountsOpen = true; st.refreshStores() } }
    }

    // ---- aviso de tiendas sin conectar
    Rectangle {
        id: banner
        visible: !st.compactHost && st.disconnected.length > 0
        anchors { left: parent.left; right: parent.right; top: chips.bottom; leftMargin: st.s * 32; rightMargin: st.s * 32; topMargin: st.s * 14 }
        height: visible ? st.s * 42 : 0; radius: st.s * 10; color: "#2A2415"
        Text { anchors { left: parent.left; leftMargin: st.s * 14; verticalCenter: parent.verticalCenter }
               text: qsTr("Conecta %1 para ver aquí todos tus juegos.").arg(st.disconnected.map(function(x) { return st.names[x] }).join(", "))
               color: "#E8C872"; font.family: "Hanken Grotesk"; font.pixelSize: st.s * 14 }
        Text { anchors { right: parent.right; rightMargin: st.s * 14; verticalCenter: parent.verticalCenter } text: qsTr("Conectar")
               color: "#F0F3F7"; font.family: "Hanken Grotesk"; font.pixelSize: st.s * 14; font.weight: Font.DemiBold
               MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: st.accountsOpen = true } }
    }
    Text {
        visible: !st.compactHost && st.message !== ""
        anchors { left: parent.left; right: parent.right; top: banner.visible ? banner.bottom : chips.bottom; leftMargin: st.s * 32; topMargin: st.s * 8 }
        text: st.message; color: st.manager.muted; font.family: "Hanken Grotesk"; font.pixelSize: st.s * 13; wrapMode: Text.Wrap
    }

    // ---- cuadrícula
    GridView {
        id: grid
        visible: !st.compactHost
        anchors { left: parent.left; right: parent.right; bottom: parent.bottom; top: parent.top; topMargin: st.s * 110 + (banner.visible ? st.s * 56 : 0); leftMargin: st.s * 32; rightMargin: st.s * 16 }
        clip: true
        cellWidth: Math.floor(width / Math.max(3, Math.floor(width / (st.s * 190)))); cellHeight: cellWidth * 1.5 + st.s * 34
        model: st.items
        delegate: Item {
            id: cell
            required property var modelData
            width: grid.cellWidth; height: grid.cellHeight
            Rectangle {
                anchors { fill: parent; margins: st.s * 8 }
                radius: st.s * 12; color: st.manager.surface; clip: true
                Image { id: cov; anchors { left: parent.left; right: parent.right; top: parent.top } height: width * 1.4
                        source: cell.modelData.art; fillMode: Image.PreserveAspectCrop; asynchronous: true; cache: true; sourceSize.width: 400 }
                Text { anchors.centerIn: cov; visible: cov.status !== Image.Ready; width: cov.width - st.s * 16; horizontalAlignment: Text.AlignHCenter; wrapMode: Text.Wrap
                       text: cell.modelData.name; color: st.manager.muted; font.family: "Hanken Grotesk"; font.pixelSize: st.s * 14 }
                Rectangle { anchors { left: parent.left; top: parent.top; margins: st.s * 8 } width: badge.implicitWidth + st.s * 14; height: st.s * 22; radius: height / 2; color: "#CC0B0F14"
                    Text { id: badge; anchors.centerIn: parent; text: st.names[cell.modelData.store]; color: "#F0F3F7"; font.family: "Hanken Grotesk"; font.pixelSize: st.s * 11 } }
                Rectangle { visible: cell.modelData.installed; anchors { right: parent.right; top: parent.top; margins: st.s * 8 } width: st.s * 22; height: width; radius: width / 2; color: "#2E9E6B"
                    Text { anchors.centerIn: parent; text: "✓"; color: "#0B0F14"; font.pixelSize: st.s * 13; font.weight: Font.Bold } }
                Text { anchors { left: parent.left; right: parent.right; top: cov.bottom; margins: st.s * 8 } elide: Text.ElideRight
                       text: cell.modelData.name; color: st.manager.ink; font.family: "Hanken Grotesk"; font.pixelSize: st.s * 13 }
                MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor
                    onClicked: { if (cell.modelData.local) { st.manager.selectPage("library") } else if (cell.modelData.store === "steam") st.installSteam(cell.modelData); else st.askInstall(cell.modelData) } }
            }
        }
    }
    Text {
        visible: !st.compactHost && st.items.length === 0
        anchors.centerIn: parent
        text: Object.keys(st.loading).length > 0 ? qsTr("Cargando tus bibliotecas…") : qsTr("Aún no hay juegos de esta tienda. Conecta tu cuenta en «Cuentas».")
        color: st.manager.muted; font.family: "Hanken Grotesk"; font.pixelSize: st.s * 15
    }

    // ---- cuentas
    // Botón de la hoja de cuentas con el estilo del rediseño D (Ajustes → Tiendas y cuentas).
    component AccountButton: Button {
        id: ab
        property bool primary: false
        implicitHeight: 34
        leftPadding: 14; rightPadding: 14
        contentItem: Text { text: ab.text; color: ab.primary ? Theme.color.accentInk : Theme.color.ink; font.family: Theme.font.family; font.pixelSize: Theme.font.size.body; font.weight: ab.primary ? Font.DemiBold : Font.Normal; verticalAlignment: Text.AlignVCenter; horizontalAlignment: Text.AlignHCenter }
        background: Rectangle { radius: Theme.radius.sm; color: ab.primary ? Theme.color.accent : (ab.hovered ? Theme.color.glassFillStrong : Theme.color.inset); border.color: ab.primary ? "transparent" : Theme.color.glassBorder }
    }
    Rectangle {
        visible: st.accountsOpen && !st.controllerHost && !st.accountsContainer
        anchors.fill: parent; color: "#B0000000"; z: 20
        MouseArea { anchors.fill: parent; onClicked: { st.accountsOpen = false; st.linking = "" } }
        Rectangle {
            id: accountSheet
            anchors.centerIn: parent; width: Math.min(parent.width - st.s * 60, st.s * 640); height: st.accountsHeight
            radius: st.s * 16; color: st.manager.surface
            MouseArea { anchors.fill: parent }
            Column {
                id: accCol
                parent: st.accountsContainer || accountSheet
                visible: st.accountsOpen
                anchors { left: parent.left; right: parent.right; top: parent.top; margins: st.accountsContainer ? 0 : st.s * 22 }
                spacing: st.s * 12
                Text { visible: !st.accountsContainer; text: qsTr("Cuentas de tiendas"); color: st.manager.ink; font.family: "Hanken Grotesk"; font.pixelSize: st.s * 20; font.weight: Font.DemiBold }
                Text { width: parent.width; wrapMode: Text.Wrap; color: st.manager.muted; font.family: "Hanken Grotesk"; font.pixelSize: st.s * 13
                       visible: !st.accountsContainer
                       text: qsTr("Inicias sesión en el navegador de cada tienda. Omnia nunca ve tu contraseña: solo guarda la sesión en este equipo.") }
                Repeater {
                    model: ["steam", "epic", "gog", "amazon"]
                    delegate: Rectangle {
                        id: acc
                        required property string modelData
                        readonly property var info: st.status(modelData)
                        width: accCol.width; height: accIn.implicitHeight + st.s * 24; radius: Theme.radius.md; color: Theme.color.inset; border.color: Theme.color.glassBorder
                        Column {
                            id: accIn
                            anchors { left: parent.left; right: parent.right; top: parent.top; margins: st.s * 12 }
                            spacing: st.s * 8
                            Row {
                                width: parent.width; spacing: st.s * 10
                                Image {
                                    source: "images/stores/" + acc.modelData + ".svg"
                                    width: st.s * 34; height: width
                                    fillMode: Image.PreserveAspectFit
                                    anchors.verticalCenter: parent.verticalCenter
                                }
                                Text { text: st.names[acc.modelData]; color: st.manager.ink; font.family: "Hanken Grotesk"; font.pixelSize: st.s * 16; font.weight: Font.DemiBold; anchors.verticalCenter: parent.verticalCenter }
                                Text { anchors.verticalCenter: parent.verticalCenter; color: st.manager.muted; font.family: "Hanken Grotesk"; font.pixelSize: st.s * 13
                                       text: !acc.info ? "…" : (!acc.info.available ? qsTr("Falta la herramienta (instala Heroic)") : (acc.info.logged_in ? qsTr("Conectada") + (acc.info.account ? " · " + acc.info.account : "") : qsTr("Sin conectar"))) }
                            }
                            Row {
                                visible: st.connecting === acc.modelData
                                spacing: st.s * 10
                                BusyIndicator { running: parent.visible; width: st.s * 28; height: width }
                                Text { anchors.verticalCenter: parent.verticalCenter; text: qsTr("Conectando…"); color: st.manager.muted; font.family: "Hanken Grotesk"; font.pixelSize: st.s * 13 }
                            }
                            Row {
                                visible: st.connecting !== acc.modelData
                                spacing: st.s * 8
                                AccountButton { primary: true; visible: acc.info && acc.info.available && !acc.info.logged_in; text: qsTr("Abrir inicio de sesión"); onClicked: st.startLink(acc.modelData) }
                                AccountButton { text: qsTr("Usar mi navegador"); visible: acc.modelData !== "steam" && acc.info && acc.info.available && !acc.info.logged_in; onClicked: st.startLink(acc.modelData, true) }
                                AccountButton { visible: acc.modelData === "steam" && acc.info && acc.info.logged_in; text: qsTr("Actualizar"); onClicked: st.startLink("steam") }
                                AccountButton { visible: acc.info && acc.info.logged_in; text: qsTr("Cerrar sesión"); onClicked: st.unlink(acc.modelData) }
                            }
                            Column {
                                visible: st.linking === acc.modelData
                                width: parent.width; spacing: st.s * 6
                                Text { width: parent.width; wrapMode: Text.Wrap; color: st.manager.muted; font.family: "Hanken Grotesk"; font.pixelSize: st.s * 12
                                       text: acc.modelData === "epic" ? qsTr("Inicia sesión; cuando veas el texto con el código, pulsa Ctrl+A y Ctrl+C y vuelve a Omnia: se conecta sola.")
                                                                      : qsTr("Inicia sesión; cuando termines, copia la dirección completa de la barra (Ctrl+L, Ctrl+C) y vuelve a Omnia: se conecta sola.") }
                                Row {
                                    spacing: st.s * 8; width: parent.width
                                    TextField { id: codeField; width: parent.width - connectBtn.width - st.s * 8; placeholderText: qsTr("Pega aquí el código o la dirección"); text: st.pasted; onTextEdited: st.pasted = text; onAccepted: st.finishLink() }
                                    AccountButton { id: connectBtn; primary: true; text: st.busy ? qsTr("Conectando…") : qsTr("Conectar"); onClicked: st.finishLink() }
                                }
                            }
                        }
                    }
                }
                Text { width: parent.width; wrapMode: Text.Wrap; color: st.manager.muted; font.family: "Hanken Grotesk"; font.pixelSize: st.s * 12
                       text: qsTr("Las sesiones que abres en las ventanas de las tiendas se guardan en este equipo para no repetirlas. Puedes borrarlas: se aplica al abrir Omnia otra vez y no cierra las conexiones.") }
                Text { visible: !!st.message; width: parent.width; text: st.message; wrapMode: Text.Wrap; color: st.manager.ink }
                Row {
                    spacing: st.s * 8
                    AccountButton { text: qsTr("Actualizar"); onClicked: st.refreshStores() }
                    AccountButton { text: qsTr("Borrar sesión web"); onClicked: api.clearStoresWebSession(function(code, body) { st.message = code === 200 ? qsTr("Listo: la sesión web se borrará al abrir Omnia otra vez.") : qsTr("No se pudo marcar el borrado.") }) }
                    AccountButton { visible: !st.accountsContainer; text: qsTr("Cerrar"); onClicked: { st.accountsOpen = false; st.linking = "" } }
                }
            }
        }
    }
}

import QtQuick

/** (También sirve para actualizar un port ya instalado: `show(offer, name, gameId)` con `gameId` activa el modo «Actualizar»:
 *  sin casilla de licencia ni destino, y se superpone sobre la carpeta existente conservando partidas y datos.)
 *  Confirmación para instalar el port de un juego detectado («Port disponible»). Muestra paquete, versión, tamaño, fuente y licencia;
 *  exige aceptar la licencia y usa la carpeta de instalación predeterminada. Ratón, teclado y mando (↑/↓, A, B). */
Item {
    id: dlg
    property var api: null
    property var offer: null            // { slug, packageId, title, version, sizeBytes, licenseName, sourceName }
    property string gameName: ""
    property string updateGameId: ""
    readonly property bool updating: updateGameId !== ""
    property real uiScale: 1
    property color ink: "#F0F3F7"
    property color ink2: "#B8C3D0"
    property color accent: "#336599"
    property string uiFont: "Hanken Grotesk"
    property bool open: false
    property bool accepted: false
    property bool busy: false
    property string error: ""
    property int index: 1
    signal closed()
    signal started(string name)

    readonly property string root: api ? api.installRoot : ""
    readonly property bool canInstall: updating ? !busy : (accepted && root !== "" && !busy)
    readonly property string sizeText: offer && offer.sizeBytes > 0 ? (offer.sizeBytes >= 1073741824 ? (offer.sizeBytes / 1073741824).toFixed(2) + " GiB" : Math.round(offer.sizeBytes / 1048576) + " MB") : ""
    visible: open || shade.opacity > 0.01

    function show(o, name, gameId) {
        offer = o; gameName = name || ""; updateGameId = gameId || ""
        accepted = false; busy = false; error = ""; index = updateGameId !== "" ? 1 : 0; open = true
    }
    function close() { if (open) { open = false; closed() } }
    function install() {
        if (!canInstall || !offer) return
        busy = true; error = ""
        const done = function(status, body) {
            dlg.busy = false
            if (status === 200) { dlg.started(dlg.offer.title); dlg.close() }
            else dlg.error = (body && body.error) || (dlg.updating ? qsTr("No se pudo iniciar la actualización.") : qsTr("No se pudo iniciar la instalación."))
        }
        if (updating) api.updateInstallation(updateGameId, done)
        else api.startInstallation(offer.slug, offer.packageId, root, done)
    }
    function activate(i) {
        if (i === 0) accepted = !accepted
        else if (i === 1) install()
        else close()
    }
    function pad(k) {
        if (k === "u") index = Math.max(updating ? 1 : 0, index - 1)
        else if (k === "d") index = Math.min(2, index + 1)
        else if (k === "A") activate(index)
        else if (k === "B") close()
    }
    function key(e) {
        if (e.key === Qt.Key_Up) pad("u")
        else if (e.key === Qt.Key_Down) pad("d")
        else if (e.key === Qt.Key_Return || e.key === Qt.Key_Enter || e.key === Qt.Key_Space) pad("A")
        else if (e.key === Qt.Key_Escape) close()
        else return false
        return true
    }

    Rectangle {
        id: shade
        anchors.fill: parent; color: "#000000"; opacity: dlg.open ? 0.6 : 0
        Behavior on opacity { NumberAnimation { duration: 160 } }
        MouseArea { anchors.fill: parent; onClicked: dlg.close() }
    }
    Rectangle {
        anchors.centerIn: parent
        width: dlg.uiScale * 640
        height: col.implicitHeight + dlg.uiScale * 44
        radius: dlg.uiScale * 22
        color: "#F2101820"; border.color: "#2effffff"
        opacity: dlg.open ? 1 : 0; scale: dlg.open ? 1 : 0.95
        Behavior on opacity { NumberAnimation { duration: 160 } }
        Behavior on scale { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }
        MouseArea { anchors.fill: parent }
        Column {
            id: col
            anchors { left: parent.left; right: parent.right; top: parent.top; margins: dlg.uiScale * 24 }
            spacing: dlg.uiScale * 12
            Text { width: parent.width; text: dlg.updating ? qsTr("Actualización disponible") : qsTr("Port disponible"); color: dlg.ink2; font.family: dlg.uiFont; font.pixelSize: dlg.uiScale * 15; font.letterSpacing: 1.2 }
            Text { width: parent.width; text: dlg.gameName; color: dlg.ink; font.family: dlg.uiFont; font.pixelSize: dlg.uiScale * 30; font.weight: Font.Bold; elide: Text.ElideRight }
            Text { width: parent.width; wrapMode: Text.WordWrap; text: dlg.offer ? dlg.offer.title : ""; color: dlg.ink; font.family: dlg.uiFont; font.pixelSize: dlg.uiScale * 18 }
            Text { width: parent.width; wrapMode: Text.WordWrap; color: dlg.ink2; font.family: dlg.uiFont; font.pixelSize: dlg.uiScale * 15
                   text: dlg.offer ? [dlg.updating && dlg.offer.current ? dlg.offer.current + " → " + dlg.offer.version : dlg.offer.version, dlg.sizeText, dlg.offer.sourceName].filter(function(x) { return x }).join("  ·  ") : "" }
            Text { width: parent.width; wrapMode: Text.WordWrap; color: dlg.ink2; font.family: dlg.uiFont; font.pixelSize: dlg.uiScale * 14
                   text: dlg.updating ? qsTr("Se descarga la versión nueva, se verifica su SHA-256 y se superpone sobre la carpeta actual. Tus partidas y los archivos que el port preparó se conservan. Cierra el juego antes de actualizar.")
                                      : qsTr("Se descarga de la release del desarrollador y se verifica su SHA-256 antes de instalarlo. Necesitas tu propia copia del juego: el port te la pedirá al abrirlo.") }
            Text { visible: !dlg.updating; width: parent.width; elide: Text.ElideMiddle; font.family: dlg.uiFont; font.pixelSize: dlg.uiScale * 14
                   color: dlg.root ? dlg.ink2 : "#E8B86D"
                   text: dlg.root ? qsTr("Destino: %1").arg(dlg.root) : qsTr("Elige una carpeta de instalación en la app de escritorio (Ajustes → General).") }
            Rectangle {      // aceptar licencia
                id: accept
                visible: !dlg.updating
                width: parent.width; height: dlg.uiScale * 52; radius: dlg.uiScale * 14
                color: dlg.index === 0 ? "#26FFFFFF" : (acceptMa.containsMouse ? "#14FFFFFF" : "transparent")
                border.color: dlg.index === 0 ? "#5B9BE0" : "#334352"
                Row { anchors { left: parent.left; leftMargin: dlg.uiScale * 16; verticalCenter: parent.verticalCenter } spacing: dlg.uiScale * 12
                    Rectangle { width: dlg.uiScale * 24; height: width; radius: dlg.uiScale * 6; anchors.verticalCenter: parent.verticalCenter
                        color: dlg.accepted ? dlg.accent : "transparent"; border.color: dlg.accepted ? dlg.accent : dlg.ink2
                        Text { anchors.centerIn: parent; text: dlg.accepted ? "✓" : ""; color: "white"; font.pixelSize: dlg.uiScale * 16 } }
                    Text { anchors.verticalCenter: parent.verticalCenter; color: dlg.ink; font.family: dlg.uiFont; font.pixelSize: dlg.uiScale * 17
                           text: qsTr("Acepto la licencia (%1) y la descarga desde la fuente indicada").arg(dlg.offer ? dlg.offer.licenseName : "") } }
                MouseArea { id: acceptMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: { dlg.index = 0; dlg.activate(0) } }
            }
            Row {
                spacing: dlg.uiScale * 12
                Rectangle {
                    width: dlg.uiScale * 220; height: dlg.uiScale * 50; radius: dlg.uiScale * 14
                    opacity: dlg.canInstall ? 1 : 0.5
                    color: dlg.index === 1 ? Qt.lighter(dlg.accent, 1.2) : dlg.accent
                    border.color: dlg.index === 1 ? "#5B9BE0" : "transparent"; border.width: 2
                    Text { anchors.centerIn: parent; color: dlg.ink; font.family: dlg.uiFont; font.pixelSize: dlg.uiScale * 19; font.weight: Font.DemiBold
                           text: dlg.busy ? qsTr("Iniciando…") : (dlg.updating ? qsTr("Actualizar") : qsTr("Instalar port")) }
                    MouseArea { anchors.fill: parent; cursorShape: dlg.canInstall ? Qt.PointingHandCursor : Qt.ArrowCursor; onClicked: { dlg.index = 1; dlg.activate(1) } }
                }
                Rectangle {
                    width: dlg.uiScale * 160; height: dlg.uiScale * 50; radius: dlg.uiScale * 14
                    color: dlg.index === 2 ? "#26FFFFFF" : "transparent"; border.color: dlg.index === 2 ? "#5B9BE0" : "#66ffffff"
                    Text { anchors.centerIn: parent; text: qsTr("Cancelar"); color: dlg.ink; font.family: dlg.uiFont; font.pixelSize: dlg.uiScale * 19 }
                    MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: dlg.close() }
                }
            }
            Text { visible: dlg.error !== ""; width: parent.width; wrapMode: Text.WordWrap; text: dlg.error; color: "#E8B86D"; font.family: dlg.uiFont; font.pixelSize: dlg.uiScale * 15 }
        }
    }
}

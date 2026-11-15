import QtQuick

// Contenido de la prueba: color de fondo, hora, y un botón que llama a omnia-core con el token.
Rectangle {
    id: root
    color: "#0f2a1e"
    property string status: "sin probar"
    property string tokenPath: Qt.application.arguments.indexOf("--token") >= 0
        ? Qt.application.arguments[Qt.application.arguments.indexOf("--token") + 1] : ""

    function readToken() {
        var x = new XMLHttpRequest()
        x.open("GET", "file://" + tokenPath, false)      // síncrono: solo en la prueba
        x.send()
        return x.responseText.trim()
    }
    function probarApi() {
        try {
            var tok = readToken()
            if (!tok) { status = "token vacío (¿QML_XHR_ALLOW_FILE_READ=1?)"; return }
            var x = new XMLHttpRequest()
            x.onreadystatechange = function () {
                if (x.readyState !== 4) return
                if (x.status === 200) {
                    var n = JSON.parse(x.responseText).games
                    status = "API ok: " + n.length + " juegos — " + n.map(function (g) { return g.name }).join(", ")
                } else status = "API error " + x.status
            }
            x.open("GET", "http://127.0.0.1:47831/library")
            x.setRequestHeader("Authorization", "Bearer " + tok)
            x.send()
        } catch (e) { status = "fallo: " + e }
    }

    Component.onCompleted: if (Qt.application.arguments.indexOf("--auto") >= 0) probarApi()

    Column {
        anchors.centerIn: parent
        spacing: 24
        Text { id: clock; anchors.horizontalCenter: parent.horizontalCenter; color: "#e6d9a0"; font.pixelSize: 96
               text: Qt.formatTime(new Date(), "hh:mm:ss")
               Timer { running: true; repeat: true; interval: 1000; onTriggered: clock.text = Qt.formatTime(new Date(), "hh:mm:ss") } }
        Text { anchors.horizontalCenter: parent.horizontalCenter; color: "#e6d9a0"; font.pixelSize: 22; text: "Omnia · prueba de capa de fondo" }
        Rectangle {
            anchors.horizontalCenter: parent.horizontalCenter; width: 300; height: 64; radius: 16; color: "#1f5a40"
            border.color: "#e6d9a0"; border.width: 2
            Text { anchors.centerIn: parent; color: "#e6d9a0"; font.pixelSize: 24; text: "Probar API" }
            MouseArea { anchors.fill: parent; onClicked: root.probarApi() }
        }
        Text { anchors.horizontalCenter: parent.horizontalCenter; color: "#e6d9a0"; font.pixelSize: 20; text: root.status
               width: 1200; wrapMode: Text.WordWrap; horizontalAlignment: Text.AlignHCenter }
    }
}

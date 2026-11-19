import QtQuick
import org.kde.plasma.plasmoid
import "../../../../../omnia/ui/session" as OmniaSession
import "../../../../../omnia/ui/qml" as Omnia

WallpaperItem {
    id: root
    property var selected: ({ id: "", name: "", fondo: "", pal: ["#10150f"], acc: "#e6d9a0", revision: -1 })
    property string token: OmniaSession.SessionToken.value
    property int requestSerial: 0

    Rectangle {
        anchors.fill: parent
        color: root.selected.pal && root.selected.pal.length ? root.selected.pal[0] : "#10150f"
    }
    Omnia.Backdrop {
        anchors.fill: parent
        source: root.selected.fondo || ""
        blur: 0
        saturation: 0
    }
    // Scrim de la tarjeta hero del prototipo: base inferior y sombra horizontal tras el texto.
    Rectangle {
        anchors.fill: parent
        gradient: Gradient {
            GradientStop { position: 0.0; color: "#0004070B" }
            GradientStop { position: 0.55; color: "#0004070B" }
            GradientStop { position: 1.0; color: "#BF04070B" }
        }
    }
    Rectangle {
        anchors.fill: parent
        gradient: Gradient {
            orientation: Gradient.Horizontal
            GradientStop { position: 0.0; color: "#F004070B" }
            GradientStop { position: 0.08; color: "#F004070B" }
            GradientStop { position: 0.42; color: "#B804070B" }
            GradientStop { position: 0.78; color: "#8C04070B" }
            GradientStop { position: 1.0; color: "#8C04070B" }
        }
    }

    function refreshSelection() {
        const serial = ++requestSerial
        if (!token) { retry.start(); return }
        const xhr = new XMLHttpRequest()
        xhr.onreadystatechange = function() {
            if (xhr.readyState !== XMLHttpRequest.DONE || serial !== root.requestSerial) return
            if (xhr.status !== 200) { retry.start(); return }
            try {
                const next = JSON.parse(xhr.responseText)
                // Solo una selección real trae revisión. Un 200 de otro programa en el puerto
                // (Estantería devolvía {"error": ...}) dejaría el fondo vacío y en bucle.
                if (!next || typeof next !== "object" || next.revision === undefined) {
                    console.warn("Omnia wallpaper: respuesta sin selección; reintentando")
                    retry.start()
                    return
                }
                root.selected = next
                root.refreshSelection()
            } catch (e) { console.warn("Omnia wallpaper: respuesta inválida"); retry.start() }
        }
        const since = root.selected.revision >= 0 ? "?since=" + root.selected.revision + "&wait=25" : ""
        xhr.open("GET", "http://127.0.0.1:47831/selection" + since)
        xhr.setRequestHeader("Authorization", "Bearer " + token)
        xhr.send()
    }
    Timer { id: retry; interval: 900; repeat: false; onTriggered: root.refreshSelection() }
    onTokenChanged: refreshSelection()
    Component.onCompleted: refreshSelection()
}

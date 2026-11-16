import QtQuick
import org.kde.plasma.plasmoid
import org.omnia.session 1.0 as OmniaSession
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
    // Cortina oscura gris azulada sobre el arte, sin blur.
    Rectangle { anchors.fill: parent; color: "#80303B4A" }

    function refreshSelection() {
        const serial = ++requestSerial
        if (!token) { retry.start(); return }
        const xhr = new XMLHttpRequest()
        xhr.onreadystatechange = function() {
            if (xhr.readyState !== XMLHttpRequest.DONE || serial !== root.requestSerial) return
            if (xhr.status !== 200) { retry.start(); return }
            try {
                const next = JSON.parse(xhr.responseText)
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

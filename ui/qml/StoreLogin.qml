import QtQuick
import QtQuick.Window
import QtWebEngine

// Ventana de inicio de sesión de una tienda (como la de Heroic): muestra la página oficial de la tienda y, cuando la tienda
// redirige con el código, lo captura y lo entrega a Omnia. Navegación aislada (sin cookies guardadas) y solo a la tienda.
// Se carga de forma opcional: si falta QtWebEngine, ManagerStores usa el navegador del sistema y el pegado manual.
Window {
    id: win
    property string store: ""
    property bool captured: false
    signal codeCaptured(string store, string text)
    width: 520; height: 720; minimumWidth: 420; minimumHeight: 560
    color: "#0B0F14"
    title: store === "epic" ? "Epic Games" : (store === "gog" ? "GOG" : "Amazon")

    function begin(sid, url) {
        store = sid; captured = false
        view.url = url
        visible = true; raise(); requestActivate()
    }
    function deliver(text) {
        if (captured) return
        captured = true
        codeCaptured(store, text)
        visible = false
        view.url = "about:blank"
    }
    function check(u) {
        const s = String(u)
        if (store === "gog" && s.indexOf("https://embed.gog.com/on_login_success") === 0) deliver(s)
        else if (store === "amazon" && s.indexOf("openid.oa2.authorization_code=") >= 0 && /^https:\/\/(www\.)?amazon\.com\//.test(s)) deliver(s)
    }

    WebEngineView {
        id: view
        anchors.fill: parent
        profile: WebEngineProfile {
            offTheRecord: true
            // las tiendas rechazan navegadores que se anuncian como «QtWebEngine» (su antibots falla): se presenta como el Chrome en que se basa
            Component.onCompleted: httpUserAgent = httpUserAgent.replace(/ QtWebEngine\/[0-9.]+/, "")
        }
        onUrlChanged: win.check(url)
        onLoadingChanged: function(r) {
            if (r.status !== WebEngineView.LoadSucceededStatus) return
            win.check(url)
            // Epic muestra el código en la propia página (JSON con authorizationCode)
            if (win.store === "epic" && String(url).indexOf("https://www.epicgames.com/id/api/redirect") === 0)
                runJavaScript("document.body ? document.body.innerText : ''", function(t) { if (t) win.deliver(String(t)) })
        }
    }
    onClosing: if (!captured) captured = true
}

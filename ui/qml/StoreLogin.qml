import QtQuick
import QtQuick.Window
import QtWebEngine

// Ventana de inicio de sesión de una tienda (como la de Heroic): muestra la página oficial de la tienda y, cuando la tienda
// redirige con el código, lo captura y lo entrega a Omnia. El perfil se guarda en disco (el antibots de Epic lo exige).
// Se carga de forma opcional: si falta QtWebEngine, ManagerStores usa el navegador del sistema y el pegado manual.
Window {
    id: win
    property string store: ""
    property bool captured: false
    property int attempts: 0
    signal codeCaptured(string store, string text)
    signal abandoned(string store)
    width: 520; height: 720; minimumWidth: 420; minimumHeight: 560
    color: "#0B0F14"
    title: store === "steam" ? "Steam" : store === "epic" ? "Epic Games" : (store === "gog" ? "GOG" : "Amazon")

    function begin(sid, url) {
        store = sid; captured = false; attempts = 0
        view.url = url
        if (sid === "steam") { visible = false; showTimer.restart(); return }     // si ya hay sesión web, se actualiza sin mostrar la ventana
        visible = true; raise(); requestActivate()
    }
    function reveal() { showTimer.stop(); if (!captured) { visible = true; raise(); requestActivate() } }
    Timer { id: showTimer; interval: 8000; onTriggered: win.reveal() }
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
            // Perfil guardado en disco y con el idioma del sistema: el antibots de Epic (hCaptcha) lo acepta; sin perfil guardado o con otro
            // idioma el captcha respondía «Respuesta incorrecta» (probado con tools/epic-login-test.qml, variante c).
            storageName: "omnia-stores"
            offTheRecord: false
            httpAcceptLanguage: Qt.locale().name.replace("_", "-") + "," + Qt.locale().name.split("_")[0] + ";q=0.9,en;q=0.8"
            // las tiendas rechazan navegadores que se anuncian como «QtWebEngine»: se presenta como el Chrome en que se basa
            Component.onCompleted: httpUserAgent = httpUserAgent.replace(/ QtWebEngine\/[0-9.]+/, "")
        }
        onUrlChanged: win.check(url)
        onLoadingChanged: function(r) {
            if (r.status !== WebEngineView.LoadSucceededStatus) return
            win.check(url)
            // Epic muestra el código en la propia página (JSON con authorizationCode)
            if (win.store === "steam") {
                if (String(url).indexOf("/login") >= 0) { win.reveal(); return }
                if (/^https:\/\/steamcommunity\.com\/(id|profiles)\//.test(String(url)))
                    // lista de juegos de la propia cuenta (XML); XHR síncrono con la sesión web de esta ventana
                    // lista de juegos de la propia cuenta: primero el XML clásico y, si no hay, la página moderna (lista en JSON dentro del HTML);
                    // XHR síncrono con la sesión web de esta ventana. Entrega un sobre JSON con el id de la cuenta que expone el perfil.
                    runJavaScript("(function(){function get(u){try{var x=new XMLHttpRequest();x.open('GET',u,false);x.send();return x.status===200?x.responseText:''}catch(e){return ''}}"
                                  + "var pd=window.g_rgProfileData||{};var xml=get('/my/games?tab=all&xml=1');var ok=xml.indexOf('<gamesList')>=0;"
                                  + "var html=ok?'':get('/my/games/?tab=all');"
                                  + "return JSON.stringify({steamid:pd.steamid||window.g_steamID||'',name:pd.personaname||'',xml:ok?xml:'',html:html})})()",
                                  function(t) {
                                      if (win.attempts >= 2) return
                                      win.attempts += 1
                                      if (t) win.deliver(String(t))
                                  })
            }
            if (win.store === "epic" && String(url).indexOf("https://www.epicgames.com/id/api/redirect") === 0)
                runJavaScript("document.body ? document.body.innerText : ''", function(t) { if (t) win.deliver(String(t)) })
        }
    }
    onClosing: { if (!captured) { captured = true; abandoned(store) } }
}

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
    title: ({ steam: "Steam", epic: "Epic Games", gog: "GOG", amazon: "Amazon", ubisoft: "Ubisoft Connect", ea: "EA" })[store] || store
    // EA (entrega 6): tras iniciar sesión en ea.com, la ventana pide el token de la cuenta con su propia sesión web.
    readonly property string eaTokenUrl: "https://accounts.ea.com/connect/auth?client_id=ORIGIN_JS_SDK&response_type=token&redirect_uri=nucleus:rest&prompt=none"

    function begin(sid, url) {
        store = sid; captured = false; attempts = 0
        view.url = url
        // si ya hay sesión web, se actualiza sin mostrar la ventana (Steam, y EA al renovar el token)
        if (sid === "steam" || (sid === "ea" && String(url) === eaTokenUrl)) { visible = false; showTimer.restart(); return }
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
                    // de la propia página de juegos de la cuenta (con la sesión web de esta ventana) se toma el token de corta duración de la Web API
                    // y el id de la cuenta; Omnia consulta después la lista y no guarda el token. XHR síncrono, mismo origen.
                    runJavaScript("(function(){function get(u){try{var x=new XMLHttpRequest();x.open('GET',u,false);x.send();return x.status===200?x.responseText:''}catch(e){return ''}}"
                                  + "var c={};try{c=JSON.parse(get('/chat/clientjstoken'))}catch(e){}"
                                  + "var h=get('/my/games/?tab=all');var i=h.indexOf('strWebAPIToken');var m=i<0?null:/[A-Za-z0-9_.-]{80,}/.exec(h.substr(i+14,900));"
                                  + "return JSON.stringify({steamid:c.steamid||'',name:c.account_name||'',token:m?m[0]:''})})()",
                                  function(t) {
                                      if (win.attempts >= 2) return
                                      win.attempts += 1
                                      if (t) win.deliver(String(t))
                                  })
            }
            const here = String(url)
            if (win.store === "ubisoft" && /^https:\/\/connect\.ubisoft\.com\/(ready|change_domain)/.test(here))
                // Ubisoft guarda la sesión en el localStorage de su página: se entrega a Omnia (ticket, sesión y «recordarme»)
                runJavaScript("JSON.stringify({loginData:localStorage.getItem('PRODloginData'),rememberMe:localStorage.getItem('PRODrememberMe'),"
                              + "lastProfile:localStorage.getItem('PRODlastProfile')})",
                              function(t) { try { if (JSON.parse(t).loginData) win.deliver(String(t)) } catch (e) {} })
            if (win.store === "ea") {
                if (here.indexOf("https://accounts.ea.com/connect/auth") === 0)
                    runJavaScript("document.body ? document.body.innerText : ''", function(t) {
                        if (t && t.indexOf("access_token") >= 0) win.deliver(String(t))
                        else { win.reveal(); view.url = "https://www.ea.com/login" }      // sin sesión web: hay que iniciarla
                    })
                else if (/^https:\/\/(www\.)?ea\.com\//.test(here) && here.indexOf("/login") < 0 && !win.captured)
                    view.url = win.eaTokenUrl                                             // ya inició sesión: se pide el token
                else if (here.indexOf("signin.ea.com") >= 0 || here.indexOf("/login") >= 0) win.reveal()
            }
            if (win.store === "epic" && String(url).indexOf("https://www.epicgames.com/id/api/redirect") === 0)
                runJavaScript("document.body ? document.body.innerText : ''", function(t) { if (t) win.deliver(String(t)) })
        }
    }
    onClosing: { if (!captured) { captured = true; abandoned(store) } }
}

import QtQuick
import QtQuick.Window
import QtWebEngine

// Diagnóstico del acceso a Steam desde la ventana de Omnia (mismo perfil «omnia-stores»). Uso:
//   MANGOHUD=0 DISABLE_MANGOHUD=1 qml6 tools/steam-login-test.qml
// Inicia sesión si lo pide. Escribe en consola qué recibió (tamaños y marcas), nunca nombres, juegos ni identificadores.
Window {
    id: win
    width: 520; height: 760; visible: true; title: "Prueba Steam"
    property int tries: 0
    WebEngineView {
        id: view
        anchors.fill: parent
        profile: WebEngineProfile {
            storageName: "omnia-stores"
            offTheRecord: false
            httpAcceptLanguage: Qt.locale().name.replace("_", "-") + "," + Qt.locale().name.split("_")[0] + ";q=0.9,en;q=0.8"
            Component.onCompleted: httpUserAgent = httpUserAgent.replace(/ QtWebEngine\/[0-9.]+/, "")
        }
        url: "https://steamcommunity.com/my/"
        onLoadingChanged: function(r) {
            const u = String(url).replace(/\/(id|profiles)\/[^/?#]+/, "/$1/<cuenta>")
            console.log("CARGA estado=" + r.status + " url=" + u)
            if (r.status !== WebEngineView.LoadSucceededStatus) return
            if (!/^https:\/\/steamcommunity\.com\/(id|profiles)\//.test(String(url))) return
            if (win.tries >= 2) return
            win.tries += 1
            runJavaScript("(function(){function get(u){try{var x=new XMLHttpRequest();x.open('GET',u,false);x.send();return x.status+':'+x.responseText}catch(e){return 'ERR:'+e}}"
                + "var pd=window.g_rgProfileData||{};var a=get('/my/games?tab=all&xml=1');var b=get('/my/games/?tab=all');"
                + "return JSON.stringify({perfil_tiene_steamid:!!(pd.steamid||window.g_steamID),"
                + "xml_estado:a.split(':')[0],xml_tamano:a.length,xml_marca:a.indexOf('<gamesList')>=0,xml_error:a.indexOf('<error')>=0,"
                + "html_estado:b.split(':')[0],html_tamano:b.length,html_marca_lista:b.indexOf('data-profile-gameslist')>=0,"
                + "html_marca_react:b.indexOf('gameslist_config')>=0,html_menciona_login:b.indexOf('login')>=0})})()",
                function(t) { console.log("RESULTADO " + t); if (win.tries >= 1) Qt.quit() })
        }
    }
}

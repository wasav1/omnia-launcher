import QtQuick
import QtQuick.Window
import QtWebEngine

// Banco de pruebas del inicio de sesión de Epic dentro de una ventana embebida (captcha). Variante por argumento:
//   qml6 tools/epic-login-test.qml -- a   (sin perfil guardado, como Omnia hoy)
//   qml6 tools/epic-login-test.qml -- b   (perfil guardado en ~/.cache/omnia/webtest)
//   qml6 tools/epic-login-test.qml -- c   (perfil guardado + cabeceras de idioma y sin pistas de automatización)
// Cierra la ventana al ver el texto con authorizationCode; solo escribe en consola si la prueba pasó (nunca el código).
Window {
    id: win
    width: 520; height: 760; visible: true; title: "Prueba Epic"
    readonly property string variant: Qt.application.arguments.length > 0 ? Qt.application.arguments[Qt.application.arguments.length - 1] : "a"
    WebEngineView {
        id: view
        anchors.fill: parent
        profile: WebEngineProfile {
            storageName: win.variant === "a" ? "" : "omnia-epic-test-" + win.variant
            offTheRecord: win.variant === "a"
            httpAcceptLanguage: win.variant === "c" ? "es-CO,es;q=0.9,en;q=0.8" : httpAcceptLanguage
            Component.onCompleted: httpUserAgent = httpUserAgent.replace(/ QtWebEngine\/[0-9.]+/, "")
        }
        url: "https://www.epicgames.com/id/login?redirectUrl=https%3A%2F%2Fwww.epicgames.com%2Fid%2Fapi%2Fredirect%3FclientId%3D34a02cf8f4414e29b15921876da36f9a%26responseType%3Dcode"
        onLoadingChanged: function(r) {
            if (r.status === WebEngineView.LoadSucceededStatus && String(url).indexOf("/id/api/redirect") >= 0)
                runJavaScript("document.body.innerText", function(t) {
                    console.log(t.indexOf("authorizationCode") >= 0 ? "VARIANTE " + win.variant + ": FUNCIONA" : "VARIANTE " + win.variant + ": sin código")
                    Qt.quit()
                })
        }
    }
}

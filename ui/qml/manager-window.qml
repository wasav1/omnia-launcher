import QtQuick
import QtQuick.Window

Window {
    id: win
    visible: false      // se muestra al fijar el identificador de la ventana (ver Component.onCompleted)
    width: 1440
    height: 900
    minimumWidth: 1000
    minimumHeight: 650
    color: "#0B0F14"
    title: "Omnia Desktop Suite"
    // Qt compone el app_id de Wayland como «<dominio al revés>.qml6»: con este dominio queda «org.omnia.app.qml6», que
    // coincide con StartupWMClass de org.omnia.app.desktop y la barra de tareas muestra el icono de Omnia.
    Component.onCompleted: { Qt.application.domain = "app.omnia.org"; win.visible = true }
    OmniaManager { anchors.fill: parent }
}

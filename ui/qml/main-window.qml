import QtQuick
import QtQuick.Window

// BigMode: omnia-ui en una ventana de pantalla completa.
Window {
    id: win
    visible: false; visibility: Window.FullScreen; width: Screen.width; height: Screen.height; title: "Omnia BigMode"
    // app_id «org.omnia.bigmode.qml6» (ver manager-window.qml): coincide con StartupWMClass de org.omnia.bigmode.desktop
    Component.onCompleted: { Qt.application.domain = "bigmode.omnia.org"; win.visible = true }
    OmniaLibrary { anchors.fill: parent; onCloseRequested: Qt.quit() }
}

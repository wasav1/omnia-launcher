pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Window

/** Ventana de Big Mode; el gestor de escritorio controla su ciclo de vida. */
Window {
    id: bigWindow
    required property var manager
    width: Screen.width
    height: Screen.height
    visibility: Window.FullScreen
    color: "transparent"
    title: "Omnia Big Mode"

    OmniaLibrary {
        anchors.fill: parent
        backend: bigWindow.manager.desktopBackend
        sharedBackend: true
        onCloseRequested: bigWindow.manager.closeBigMode()
    }
    onClosing: {
        if (bigWindow.manager.bigModeWindow === bigWindow) {
            bigWindow.manager.bigModeWindow = null
            bigWindow.manager.desktopBackend.controlsEnabled = false
        }
        bigWindow.destroy()
    }
}

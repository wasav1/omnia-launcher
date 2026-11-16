import QtQuick
import QtQuick.Window
import org.kde.plasma.plasmoid
import org.kde.plasma.core as PlasmaCore
import org.omnia.session 1.0 as OmniaSession
import "omnia" as Omnia

PlasmoidItem {
    id: root
    preferredRepresentation: fullRepresentation
    Plasmoid.backgroundHints: PlasmaCore.Types.NoBackground
    fullRepresentation: Omnia.OmniaShell {
        id: shell
        sectionMode: "carousel"
        externalWallpaper: true
        implicitWidth: sectionViewport.width
        implicitHeight: sectionViewport.height
        tokenSource: OmniaSession.SessionToken.value
    }
    Window {
        id: menuWindow
        visibility: shell.menuOpen || bigMenu.fading ? Window.FullScreen : Window.Hidden
        flags: Qt.FramelessWindowHint | Qt.WindowStaysOnTopHint | Qt.Tool
        color: "transparent"
        title: "Omnia Menú"
        onVisibleChanged: if (visible) requestActivate()
        Omnia.BigMenu {
            id: bigMenu
            anchors.fill: parent
            api: shell.backend
            open: shell.menuOpen
            startMode: shell.menuStartMode
            onCloseRequested: shell.menuOpen = false
        }
    }
}

import QtQuick
import QtQuick.Layouts
import QtQuick.Window
import org.kde.plasma.plasmoid
import org.kde.plasma.core as PlasmaCore
import org.omnia.session 1.0 as OmniaSession
import "../../../../../omnia/ui/qml" as Omnia

PlasmoidItem {
    id: root
    preferredRepresentation: fullRepresentation
    Layout.minimumWidth: Math.max(1, Screen.width)
    Layout.minimumHeight: Math.max(1, Screen.height)
    Plasmoid.backgroundHints: PlasmaCore.Types.NoBackground

    fullRepresentation: Omnia.OmniaShell {
        id: shell
        anchors.fill: parent
        embedMenu: false
        externalWallpaper: true
        tokenSource: OmniaSession.SessionToken.value
    }
}

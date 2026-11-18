import QtQuick
import QtQuick.Layouts
import QtQuick.Window
import org.kde.plasma.plasmoid
import org.kde.plasma.core as PlasmaCore
import "../../../../../omnia/ui/session" as OmniaSession
import "../../../../../omnia/ui/qml" as Omnia

PlasmoidItem {
    id: root
    preferredRepresentation: fullRepresentation
    Layout.minimumWidth: Math.max(1, Screen.width)
    Layout.minimumHeight: Math.max(1, Screen.height)
    Plasmoid.backgroundHints: PlasmaCore.Types.NoBackground

    fullRepresentation: Item {
        id: representation

        Omnia.DesktopSurface {
            id: surface
            viewport: root.Window.window ? root.Window.window.contentItem : representation
            visible: root.visible && !(Plasmoid.containment && Plasmoid.containment.corona.editMode)

            Omnia.OmniaShell {
                id: shell
                anchors.fill: parent
                embedMenu: false
                externalWallpaper: true
                tokenSource: OmniaSession.SessionToken.value
            }

            Timer {
                id: reportSize
                interval: 250
                onTriggered: console.info("Omnia viewport", root.Screen.name,
                    "origin", surface.x, surface.y, "size", surface.width, surface.height)
            }
            onWidthChanged: reportSize.restart()
            onHeightChanged: reportSize.restart()
            Component.onCompleted: reportSize.restart()
        }
    }
}

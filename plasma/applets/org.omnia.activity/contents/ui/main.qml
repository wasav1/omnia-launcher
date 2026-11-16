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
        sectionMode: "activity"
        externalWallpaper: true
        implicitWidth: sectionViewport.width
        implicitHeight: sectionViewport.height
        tokenSource: OmniaSession.SessionToken.value
    }
}

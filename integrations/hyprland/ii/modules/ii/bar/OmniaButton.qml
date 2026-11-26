import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.ii.bar
import qs.modules.ii.omnia
import QtQuick
import Quickshell

/**
 * Botón de Omnia para la barra (junto al de ASUS). El panel se despliega desde este botón: aquí solo se avisa del
 * monitor y de la posición del botón; la superficie del panel la crea OmniaEdge (una por monitor).
 */
CircleUtilButton {
    id: root
    visible: OmniaSettings.barEnabled
    pointingHandCursor: true

    readonly property string screenName: QsWindow.window?.screen?.name ?? ""
    readonly property bool shown: OmniaPanelState.shown && OmniaPanelState.origin === "bar" && OmniaPanelState.screenName === root.screenName

    onClicked: {
        const p = root.mapToItem(null, root.width / 2, 0);
        OmniaPanelState.toggleFromBar(root.screenName, p.x);
    }

    content: Item {
        id: logo
        implicitWidth: Appearance.font.pixelSize.large
        implicitHeight: implicitWidth

        OmniaLucide {
            anchors.centerIn: parent
            width: logo.implicitWidth
            height: width
            name: "gamepad-2"
            color: root.shown ? Appearance.m3colors.m3primary : Appearance.colors.colOnLayer2
        }
    }
}

import QtQuick
import QtQuick.Window

Window {
    id: window
    width: 760
    height: 680
    minimumWidth: 600
    minimumHeight: 470
    visible: true
    title: qsTr("Omnia Game Suite · Conectar tiendas")
    color: "#101b28"

    Api { id: backend; controlsEnabled: false }
    Flickable {
        anchors.fill: parent
        clip: true
        contentHeight: accounts.accountsHeight + 24
        contentWidth: width
        Item { id: holder; width: parent.width; height: accounts.accountsHeight }
    }
    ManagerStores {
        id: accounts
        anchors.fill: parent
        compactHost: true
        accountsOpen: true
        accountsContainer: holder
        api: backend
        manager: QtObject {
            readonly property real s: 1
            readonly property color ink: "#eef5ff"
            readonly property color muted: "#aec4db"
            readonly property color surface: "#152638"
            readonly property color surface2: "#1b3147"
        }
        Component.onCompleted: if (backend.ok) refreshStores()
    }
    Connections { target: backend; function onOkChanged() { if (backend.ok) accounts.refreshStores() } }
}

pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls
import "Theme.js" as Theme

/** Ficha de un juego que no está en tu biblioteca, dentro del panel derecho de Biblioteca
 *  (rediseño D, fase 2b). Muestra un port del catálogo de Omnia (`manager.detailGame`: paquete,
 *  destino, licencia e Instalar) o un juego de tus tiendas (`manager.storeDetailItem`: Instalar o
 *  Instalar en Steam). Las acciones son las mismas funciones del gestor que usaba la ventana
 *  emergente (`ManagerCatalogDetails`), que sigue sirviendo para abrir fichas desde Inicio. */
Item {
    id: rd
    required property var manager
    required property var api
    required property var stores
    signal closeRequested()
    signal chooseInstallFolder()

    readonly property var port: manager.detailGame
    readonly property var offer: port ? null : manager.storeDetailItem
    readonly property var local: port ? manager.localMatch(port) : null
    readonly property string artwork: port ? manager.imageFor(port, ["hero", "grid"])
                                           : (offer ? (offer.hero || offer.art || "") : "")
    readonly property string originLabel: port ? qsTr("Omnia · ports")
                                               : (offer ? (stores && stores.names ? stores.names[offer.store] || "" : "") : "")
    readonly property string originLogo: port ? "images/stores/omnia.svg" : (offer ? manager.storeLogo(offer.store) : "")
    readonly property bool canInstallPort: !!port && !local && manager.packageOptions.length > 0
    readonly property bool installReady: canInstallPort && manager.acceptLicense && !!api.installRoot && !!manager.selectedPackage

    // ---------------- arte y título
    Item {
        id: hero
        anchors { left: parent.left; right: parent.right; top: parent.top }
        height: Theme.size.detailArtHeight
        Item {
            anchors.fill: parent
            clip: true
            FadedImage {
                width: parent.width; height: parent.height + Theme.radius.xl
                source: rd.artwork
                cornerRadius: Theme.radius.xl
                fadeBottom: 0.65
                alignX: 0.5
            }
            Rectangle { width: parent.width; height: parent.height + Theme.radius.xl; radius: Theme.radius.xl
                gradient: Gradient { GradientStop { position: 0.3; color: "#000B0F14" } GradientStop { position: 0.88; color: "#D90B0F14" } } }
        }
        Rectangle {
            anchors { right: parent.right; top: parent.top; margins: 12 }
            width: 32; height: 32; radius: 16
            color: closeMa.containsMouse ? "#B3000000" : "#80000000"
            border.color: Theme.color.glassBorder
            LucideIcon { anchors.centerIn: parent; width: 16; height: 16; name: "x"; color: Theme.color.ink }
            ToolTip.visible: closeMa.containsMouse; ToolTip.text: qsTr("Cerrar ficha"); ToolTip.delay: 400
            MouseArea { id: closeMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: rd.closeRequested() }
        }
        Column {
            anchors { left: parent.left; bottom: parent.bottom; leftMargin: 20; bottomMargin: 14 }
            width: parent.width - 40
            spacing: 4
            Row {
                spacing: 8
                Image { visible: !!rd.originLogo; anchors.verticalCenter: parent.verticalCenter; width: 18; height: 18; source: rd.originLogo; sourceSize.width: 36; sourceSize.height: 36; fillMode: Image.PreserveAspectFit }
                Text { anchors.verticalCenter: parent.verticalCenter; text: rd.originLabel.toUpperCase(); color: Theme.color.soft; font.family: Theme.font.family; font.pixelSize: Theme.font.size.caption + 1; font.letterSpacing: 1.1 }
            }
            Text { width: parent.width; text: rd.port ? (rd.port.name || "") : (rd.offer ? rd.offer.name : ""); elide: Text.ElideRight; maximumLineCount: 2; wrapMode: Text.WordWrap
                color: Theme.color.inkStrong; font.family: Theme.font.family; font.pixelSize: Theme.font.size.heading + 2; font.weight: Font.Bold }
        }
    }

    // ---------------- acción principal
    Rectangle {
        id: primary
        anchors { left: parent.left; right: parent.right; top: hero.bottom; leftMargin: 20; rightMargin: 20; topMargin: 6 }
        height: Theme.size.controlLarge; radius: Theme.radius.md
        readonly property bool enabledAction: !!rd.offer || !!rd.local || rd.installReady
        readonly property string label: rd.offer ? (rd.offer.store === "steam" ? qsTr("Instalar en Steam") : qsTr("Instalar"))
                                       : rd.local ? qsTr("Jugar")
                                       : rd.canInstallPort ? qsTr("Instalar")
                                       : (rd.manager.packagesBusy ? qsTr("Consultando paquetes…") : qsTr("Sin paquete publicado"))
        color: rd.local ? "#2E8B57" : (enabledAction ? Theme.color.accent : Theme.color.inset)
        border.color: enabledAction ? "transparent" : Theme.color.glassBorder
        Row { anchors.centerIn: parent; spacing: 8
            LucideIcon { anchors.verticalCenter: parent.verticalCenter; width: 18; height: 18; name: rd.local ? "play" : "download"
                color: rd.local ? "white" : (primary.enabledAction ? Theme.color.accentInk : Theme.color.muted) }
            Text { anchors.verticalCenter: parent.verticalCenter; text: primary.label; font.family: Theme.font.family; font.pixelSize: Theme.font.size.title; font.weight: Font.DemiBold
                color: rd.local ? "white" : (primary.enabledAction ? Theme.color.accentInk : Theme.color.muted) }
        }
        MouseArea {
            anchors.fill: parent
            enabled: primary.enabledAction
            cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
            onClicked: {
                if (rd.offer) rd.manager.installStoreDetail()
                else if (rd.local) rd.manager.launch(rd.local)
                else rd.manager.startPackageInstall()
            }
        }
    }

    // ---------------- paquete, destino y licencia (solo ports sin instalar)
    Column {
        id: packageBox
        anchors { left: parent.left; right: parent.right; top: primary.bottom; leftMargin: 20; rightMargin: 20; topMargin: 12 }
        visible: !!rd.port && !rd.local
        height: visible ? implicitHeight : 0
        spacing: 8
        Text { visible: !rd.manager.packagesBusy && rd.manager.packageOptions.length === 0 && !!rd.manager.packageMessage; width: parent.width
            text: rd.manager.packageMessage; color: Theme.color.muted; font.family: Theme.font.family; font.pixelSize: Theme.font.size.small; wrapMode: Text.WordWrap }
        ComboBox {
            id: packageChoice
            visible: rd.manager.packageOptions.length > 0
            width: parent.width; height: 34
            model: rd.manager.packageOptions.map(p => p.title + " · " + p.version)
            onActivated: rd.manager.selectedPackage = rd.manager.packageOptions[currentIndex]
            contentItem: Text { leftPadding: 12; rightPadding: 26; text: packageChoice.displayText; color: Theme.color.ink; font.family: Theme.font.family; font.pixelSize: Theme.font.size.small; verticalAlignment: Text.AlignVCenter; elide: Text.ElideRight }
            background: Rectangle { radius: Theme.radius.sm; color: Theme.color.inset; border.color: packageChoice.activeFocus ? Theme.color.accent : Theme.color.glassBorder }
        }
        Item {
            visible: rd.manager.selectedPackage !== null
            width: parent.width; height: 32
            Text {
                anchors { left: parent.left; right: destButton.left; rightMargin: 8; verticalCenter: parent.verticalCenter }
                text: rd.manager.selectedPackage ? rd.manager.selectedPackage.sourceName + " · " + rd.manager.selectedPackage.licenseName + " · " + (Number(rd.manager.selectedPackage.sizeBytes) / 1073741824).toFixed(2) + " GiB" : ""
                color: Theme.color.muted; font.family: Theme.font.family; font.pixelSize: Theme.font.size.caption + 1; elide: Text.ElideRight
            }
            Rectangle {
                id: destButton
                anchors { right: parent.right; verticalCenter: parent.verticalCenter }
                width: destText.implicitWidth + 22; height: 30; radius: Theme.radius.sm; color: destMa.containsMouse ? Theme.color.glassFillStrong : Theme.color.inset; border.color: Theme.color.glassBorder
                Text { id: destText; anchors.centerIn: parent; text: rd.api.installRoot ? qsTr("Destino") : qsTr("Elegir destino"); color: Theme.color.ink; font.family: Theme.font.family; font.pixelSize: Theme.font.size.small }
                ToolTip.visible: destMa.containsMouse && !!rd.api.installRoot; ToolTip.text: rd.api.installRoot || ""; ToolTip.delay: 400
                MouseArea { id: destMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: rd.chooseInstallFolder() }
            }
        }
        Row {
            visible: rd.manager.selectedPackage !== null
            spacing: 8
            Rectangle {
                width: 20; height: 20; radius: 5
                color: rd.manager.acceptLicense ? Theme.color.accent : "transparent"
                border.color: rd.manager.acceptLicense ? Theme.color.accent : Theme.color.muted
                LucideIcon { visible: rd.manager.acceptLicense; anchors.centerIn: parent; width: 14; height: 14; name: "check"; color: Theme.color.accentInk }
                MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: rd.manager.acceptLicense = !rd.manager.acceptLicense }
            }
            Text { width: packageBox.width - 28; text: qsTr("Acepto la licencia y la descarga desde la fuente indicada."); color: Theme.color.muted; font.family: Theme.font.family; font.pixelSize: Theme.font.size.small; wrapMode: Text.WordWrap }
        }
        Text { visible: !!rd.manager.packageMessage && !rd.manager.packagesBusy && rd.manager.packageOptions.length > 0; width: parent.width
            text: rd.manager.packageMessage; color: Theme.color.warning; font.family: Theme.font.family; font.pixelSize: Theme.font.size.small; wrapMode: Text.WordWrap }
    }

    Rectangle { id: divider; anchors { left: parent.left; right: parent.right; top: packageBox.bottom; topMargin: 14 } height: 1; color: Theme.color.glassBorder }

    // ---------------- datos del juego
    ScrollView {
        id: factsScroll
        anchors { left: parent.left; right: parent.right; top: divider.bottom; bottom: parent.bottom; margins: 20; topMargin: 14 }
        clip: true
        contentWidth: availableWidth
        ScrollBar.horizontal.policy: ScrollBar.AlwaysOff
        GameFacts {
            width: factsScroll.availableWidth
            api: rd.manager.desktopBackend
            catalog: rd.port
            offer: rd.offer
            uiScale: 1
            ink: Theme.color.ink; muted: Theme.color.muted
            downloadBytes: rd.manager.selectedPackage?.sizeBytes || 0
        }
    }
}

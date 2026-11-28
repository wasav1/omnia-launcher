pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls

/** Fichas superpuestas de catálogo y ofertas; las acciones siguen en el gestor anfitrión.
 *  En Biblioteca no se usan: ahí la misma ficha se muestra en el panel derecho (CatalogDetailPanel). */
Item {
    id: details
    required property var manager
    required property var api
    required property var stores
    signal chooseInstallFolder()
Rectangle {
    anchors.fill: parent; visible: details.manager.detailGame !== null && details.manager.page !== "library"; z: 10; color: "#99000000"
    MouseArea { anchors.fill: parent; onClicked: details.manager.detailGame = null }
    Rectangle {
        anchors.centerIn: parent; width: Math.min(parent.width * 0.8, details.manager.s * 920); height: details.manager.s * 520; radius: details.manager.s * 24; color: details.manager.surface; clip: true
        MouseArea { anchors.fill: parent; onClicked: function(mouse) { mouse.accepted = true } }
        FadedImage { anchors.fill: parent; source: details.manager.imageFor(details.manager.detailGame, ["hero", "grid"]); cornerRadius: details.manager.s * 24; opacity: 0.3 }
        Rectangle { anchors.fill: parent; radius: details.manager.s * 24; gradient: Gradient { GradientStop { position: 0; color: "#B3151D27" } GradientStop { position: 1; color: "#F0151D27" } } }
        Text {
            id: catalogDetailTitle
            anchors { left: parent.left; right: parent.right; top: parent.top; margins: details.manager.s * 30 }
            text: details.manager.detailGame?.name || ""; color: details.manager.ink; font.family: "Hanken Grotesk"
            font.pixelSize: details.manager.s * 30; font.weight: Font.Bold; wrapMode: Text.Wrap
        }
        ScrollView {
            id: catalogFactsScroll
            anchors {
                left: catalogDetailTitle.left; right: catalogDetailTitle.right; top: catalogDetailTitle.bottom
                bottom: catalogPackageOptions.visible ? catalogPackageOptions.top : catalogDetailActions.top
                topMargin: details.manager.s * 12; bottomMargin: details.manager.s * 12
            }
            clip: true; contentWidth: availableWidth
            GameFacts {
                width: catalogFactsScroll.availableWidth
                api: details.manager.desktopBackend; catalog: details.manager.detailGame; uiScale: details.manager.s
                ink: details.manager.ink; muted: details.manager.muted
                downloadBytes: details.manager.selectedPackage?.sizeBytes || 0
            }
        }
        Row {
            id: catalogDetailActions
            anchors { left: parent.left; bottom: parent.bottom; margins: details.manager.s * 30 }
            spacing: details.manager.s * 12
            Rectangle { visible: !!details.manager.localMatch(details.manager.detailGame) || details.manager.packageOptions.length === 0; width: details.manager.s * 180; height: details.manager.s * 44; radius: height/2; color: details.manager.localMatch(details.manager.detailGame) ? details.manager.accent : details.manager.surface2; Text { anchors.centerIn: parent; width: parent.width - details.manager.s * 10; horizontalAlignment: Text.AlignHCenter; text: details.manager.localMatch(details.manager.detailGame) ? qsTranslate("OmniaManager", "Jugar") : qsTranslate("OmniaManager", "Sin paquete publicado"); color: details.manager.ink; font.family: "Hanken Grotesk"; font.pixelSize: details.manager.s * 14; elide: Text.ElideRight } MouseArea { anchors.fill: parent; enabled: !!details.manager.localMatch(details.manager.detailGame); cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor; onClicked: details.manager.launch(details.manager.localMatch(details.manager.detailGame)) } }
            Rectangle { visible: !details.manager.localMatch(details.manager.detailGame) && details.manager.packageOptions.length > 0; width: details.manager.s * 150; height: details.manager.s * 44; radius: height/2; color: details.manager.acceptLicense && details.api.installRoot ? details.manager.accent : details.manager.surface2; opacity: details.manager.acceptLicense && details.api.installRoot ? 1 : 0.55; Text { anchors.centerIn: parent; text: qsTranslate("OmniaManager", "Instalar"); color: details.manager.ink; font.family: "Hanken Grotesk"; font.pixelSize: details.manager.s * 14; font.weight: Font.DemiBold } MouseArea { anchors.fill: parent; enabled: details.manager.acceptLicense && details.api.installRoot && !!details.manager.selectedPackage; cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor; onClicked: details.manager.startPackageInstall() } }
            Rectangle { width: details.manager.s * 110; height: details.manager.s * 44; radius: height/2; color: "#33434F5C"; Text { anchors.centerIn: parent; text: qsTranslate("OmniaManager", "Cerrar"); color: details.manager.ink; font.family: "Hanken Grotesk"; font.pixelSize: details.manager.s * 14 } MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: details.manager.detailGame = null } }
        }
        Column {
            id: catalogPackageOptions
            anchors { left: parent.left; right: parent.right; bottom: parent.bottom; bottomMargin: details.manager.s * 92; leftMargin: details.manager.s * 30; rightMargin: details.manager.s * 30 }
            visible: details.manager.detailGame && !details.manager.localMatch(details.manager.detailGame); spacing: details.manager.s * 7
            Text { visible: details.manager.packagesBusy; text: qsTranslate("OmniaManager", "Consultando paquetes…"); color: details.manager.muted; font.family: "Hanken Grotesk"; font.pixelSize: details.manager.s * 13 }
            Text { visible: !details.manager.packagesBusy && details.manager.packageOptions.length === 0; text: details.manager.packageMessage; color: details.manager.muted; font.family: "Hanken Grotesk"; font.pixelSize: details.manager.s * 12; wrapMode: Text.WordWrap }
            Row { visible: details.manager.packageOptions.length > 0; spacing: details.manager.s * 8
                ComboBox { id: packageChoice; width: Math.min(details.manager.s * 640, Math.max(details.manager.s * 300, parent.parent.width - destButton.width - details.manager.s * 8)); height: details.manager.s * 36; model: details.manager.packageOptions.map(p => p.title + " · " + p.version); onActivated: details.manager.selectedPackage = details.manager.packageOptions[currentIndex] }
                Rectangle { id: destButton; width: Math.max(details.manager.s * 160, destText.implicitWidth + details.manager.s * 28); height: details.manager.s * 36; radius: details.manager.s * 10; color: details.manager.surface2; Text { id: destText; anchors.centerIn: parent; text: details.api.installRoot ? qsTranslate("OmniaManager", "Destino predeterminado") : qsTranslate("OmniaManager", "Elegir destino"); color: details.manager.ink; font.family: "Hanken Grotesk"; font.pixelSize: details.manager.s * 12 } MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: details.chooseInstallFolder() } }
            }
            Text { visible: details.manager.selectedPackage !== null; width: parent.width; text: details.manager.selectedPackage ? qsTranslate("OmniaManager", "Fuente: ") + details.manager.selectedPackage.sourceName + " · " + qsTranslate("OmniaManager", "Licencia: ") + details.manager.selectedPackage.licenseName + " · " + (Number(details.manager.selectedPackage.sizeBytes) / 1073741824).toFixed(2) + " GiB" : ""; color: details.manager.muted; font.family: "Hanken Grotesk"; font.pixelSize: details.manager.s * 11; elide: Text.ElideRight }
            Row { visible: details.manager.selectedPackage !== null; spacing: details.manager.s * 8
                Rectangle { width: details.manager.s * 20; height: width; radius: details.manager.s * 5; color: details.manager.acceptLicense ? details.manager.accent : "transparent"; border.color: details.manager.acceptLicense ? details.manager.accent : details.manager.muted; Text { anchors.centerIn: parent; text: details.manager.acceptLicense ? "✓" : ""; color: "white" } MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: details.manager.acceptLicense = !details.manager.acceptLicense } }
                Text { width: parent.parent.width - details.manager.s * 28; text: qsTranslate("OmniaManager", "Acepto la licencia y la descarga desde la fuente indicada."); color: details.manager.muted; font.family: "Hanken Grotesk"; font.pixelSize: details.manager.s * 11; wrapMode: Text.WordWrap }
            }
            Text { visible: !!details.manager.packageMessage && !details.manager.packagesBusy && details.manager.packageOptions.length > 0; text: details.manager.packageMessage; color: "#E8B86D"; font.family: "Hanken Grotesk"; font.pixelSize: details.manager.s * 11 }
        }
    }
}
Rectangle {
    visible: details.manager.storeDetailItem !== null && details.manager.page !== "library"
    anchors.fill: parent
    z: 12
    color: "#B9000000"
    MouseArea { anchors.fill: parent; onClicked: details.manager.storeDetailItem = null }
    Rectangle {
        anchors.centerIn: parent
        width: Math.min(parent.width * 0.84, details.manager.s * 980)
        height: Math.min(parent.height * 0.78, details.manager.s * 560)
        radius: details.manager.s * 22
        color: details.manager.surface
        border.color: "#294253"
        clip: true
        MouseArea { anchors.fill: parent; onClicked: function(mouse) { mouse.accepted = true } }
        FadedImage {
            anchors { left: parent.left; top: parent.top; bottom: parent.bottom }
            width: parent.width * 0.38
            source: details.manager.storeDetailItem ? details.manager.storeDetailItem.hero || details.manager.storeDetailItem.art : ""
            cornerRadius: details.manager.s * 22
        }
        Rectangle {
            anchors { left: parent.left; right: parent.right; top: parent.top; bottom: parent.bottom }
            gradient: Gradient {
                orientation: Gradient.Horizontal
                GradientStop { position: 0; color: "#00111C27" }
                GradientStop { position: 0.35; color: "#A8111C27" }
                GradientStop { position: 0.48; color: details.manager.surface }
                GradientStop { position: 1; color: details.manager.surface }
            }
        }
        Rectangle {
            anchors { top: parent.top; right: parent.right; margins: details.manager.s * 16 }
            width: details.manager.s * 38; height: width; radius: width / 2; color: "#253642"
            Text { anchors.centerIn: parent; text: "×"; color: details.manager.ink; font.pixelSize: details.manager.s * 24 }
            MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: details.manager.storeDetailItem = null }
        }
        Column {
            id: storeDetailHeading
            anchors { left: parent.left; right: parent.right; top: parent.top; leftMargin: parent.width * 0.43; rightMargin: details.manager.s * 34; topMargin: details.manager.s * 54 }
            spacing: details.manager.s * 12
            Row {
                spacing: details.manager.s * 9
                Image {
                    width: details.manager.s * 32; height: width
                    anchors.verticalCenter: parent.verticalCenter
                    source: details.manager.storeDetailItem ? details.manager.storeLogo(details.manager.storeDetailItem.store) : ""
                    fillMode: Image.PreserveAspectFit
                }
                Text { anchors.verticalCenter: parent.verticalCenter; text: details.manager.storeDetailItem ? (details.stores.names[details.manager.storeDetailItem.store] || "") : ""; color: "#9CD0FF"; font.family: "Hanken Grotesk"; font.pixelSize: details.manager.s * 12; font.weight: Font.Bold; font.letterSpacing: 1 }
            }
            Text { width: parent.width; text: details.manager.storeDetailItem ? details.manager.storeDetailItem.name : ""; color: details.manager.ink; font.family: "Hanken Grotesk"; font.pixelSize: details.manager.s * 30; font.weight: Font.Bold; wrapMode: Text.WordWrap; maximumLineCount: 3; elide: Text.ElideRight }
            Text { width: parent.width; text: details.manager.storeDetailItem ? ((details.manager.storeDetailItem.local && details.manager.storeDetailItem.local.platform) || "PC") + "  ·  " + (details.stores.names[details.manager.storeDetailItem.store] || "") : ""; color: details.manager.muted; font.family: "Hanken Grotesk"; font.pixelSize: details.manager.s * 15 }
        }
        ScrollView {
            id: storeFactsScroll
            anchors { left: storeDetailHeading.left; right: storeDetailHeading.right; top: storeDetailHeading.bottom; bottom: storeDetailActions.top; topMargin: details.manager.s * 12; bottomMargin: details.manager.s * 12 }
            clip: true; contentWidth: availableWidth
            GameFacts {
                width: storeFactsScroll.availableWidth
                api: details.manager.desktopBackend; offer: details.manager.storeDetailItem; uiScale: details.manager.s
                ink: details.manager.ink; muted: details.manager.muted
            }
        }
        Row {
            id: storeDetailActions
            anchors { left: parent.left; bottom: parent.bottom; leftMargin: parent.width * 0.43; bottomMargin: details.manager.s * 30 }
            spacing: details.manager.s * 10
            Rectangle {
                width: details.manager.s * 176; height: details.manager.s * 42; radius: height / 2; color: details.manager.accent
                Text { anchors.centerIn: parent; text: details.manager.storeDetailItem && details.manager.storeDetailItem.store === "steam" ? qsTranslate("OmniaManager", "Instalar en Steam") : qsTranslate("OmniaManager", "Instalar"); color: details.manager.ink; font.family: "Hanken Grotesk"; font.pixelSize: details.manager.s * 13; font.weight: Font.DemiBold }
                MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: details.manager.installStoreDetail() }
            }
            Rectangle {
                width: details.manager.s * 110; height: details.manager.s * 42; radius: height / 2; color: "#283844"
                Text { anchors.centerIn: parent; text: qsTranslate("OmniaManager", "Cerrar"); color: details.manager.ink; font.family: "Hanken Grotesk"; font.pixelSize: details.manager.s * 13 }
                MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: details.manager.storeDetailItem = null }
            }
        }
    }
}
}

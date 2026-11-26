pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls
import QtQuick.Dialogs

/** Ajustes de la app de escritorio; el gestor anfitrión conserva navegación y estado. */
Item {
    id: settings
    required property var manager
    required property var api
    required property var stores
    required property real contentPad
    required property real contentTop
    property alias accountsContainer: accountHost
    signal chooseInstallFolder()
    visible: settings.manager.page === "settings"
    Text { x: settings.contentPad; y: settings.contentTop; text: qsTranslate("OmniaManager", "Ajustes"); color: settings.manager.ink; font.family: "Hanken Grotesk"; font.pixelSize: settings.manager.s * 28; font.weight: Font.Bold }
    Column {
        x: settings.contentPad; y: settings.contentTop + settings.manager.s * 48; width: settings.manager.s * 190; spacing: settings.manager.s * 4
        Repeater {
            model: [{ k: "general", l: qsTranslate("OmniaManager", "General") }, { k: "library", l: qsTranslate("OmniaManager", "Biblioteca") }, { k: "bigmode", l: qsTranslate("OmniaManager", "Big Mode") }, { k: "stores", l: qsTranslate("OmniaManager", "Cuentas de tiendas") }, { k: "about", l: qsTranslate("OmniaManager", "Acerca de") }]
            delegate: Rectangle {
                id: setTab
                required property var modelData
                readonly property bool on: settings.manager.settingsSection === modelData.k
                width: parent.width; height: settings.manager.s * 42; radius: settings.manager.s * 10
                color: on ? "#16434E" : (setMa.containsMouse ? "#14FFFFFF" : "transparent")
                Text { anchors { left: parent.left; leftMargin: settings.manager.s * 14; verticalCenter: parent.verticalCenter } text: setTab.modelData.l; color: settings.manager.ink; font.family: "Hanken Grotesk"; font.pixelSize: settings.manager.s * 16; font.weight: setTab.on ? Font.DemiBold : Font.Normal }
                MouseArea { id: setMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: settings.manager.settingsSection = setTab.modelData.k }
            }
        }
    }
    ScrollView {
        visible: settings.manager.storeSettingsOpen
        anchors { left: parent.left; right: parent.right; top: parent.top; bottom: parent.bottom
            leftMargin: settings.contentPad + settings.manager.s * 214; rightMargin: settings.contentPad
            topMargin: settings.contentTop + settings.manager.s * 48; bottomMargin: settings.manager.s * 12 }
        contentWidth: availableWidth
        clip: true
        Item {
            id: accountHost
            width: parent.width
            implicitHeight: settings.stores.accountsHeight
        }
    }
    Column {
        x: settings.contentPad + settings.manager.s * 214; y: settings.contentTop + settings.manager.s * 48; width: parent.width - settings.contentPad * 2 - settings.manager.s * 214; spacing: settings.manager.s * 14
        Rectangle {
            visible: settings.manager.settingsSection === "about"
            width: parent.width; height: settings.manager.s * 150; radius: settings.manager.s * 16; color: settings.manager.surface
            Row { anchors { left: parent.left; verticalCenter: parent.verticalCenter; leftMargin: settings.manager.s * 22 } spacing: settings.manager.s * 18
                Image { width: settings.manager.s * 72; height: width; anchors.verticalCenter: parent.verticalCenter; source: Qt.resolvedUrl("images/omnia-mark.svg"); sourceSize.height: 192; fillMode: Image.PreserveAspectFit }
                Column { anchors.verticalCenter: parent.verticalCenter; spacing: settings.manager.s * 5
                    Text { text: "Omnia Game Suite"; color: settings.manager.ink; font.family: "Hanken Grotesk"; font.pixelSize: settings.manager.s * 22; font.weight: Font.DemiBold }
                    Text { text: qsTranslate("OmniaManager", "Biblioteca de juegos y Big Mode para Linux. "); color: settings.manager.muted; font.family: "Hanken Grotesk"; font.pixelSize: settings.manager.s * 14 }
                    Text { text: qsTranslate("OmniaManager", "Los juegos y sus archivos viven en este equipo; Omnia no incluye ni descarga ROMs."); color: settings.manager.muted; font.family: "Hanken Grotesk"; font.pixelSize: settings.manager.s * 13 } }
            }
        }
        Rectangle {
            visible: settings.manager.settingsSection === "bigmode"
            width: parent.width; height: settings.manager.s * 86; radius: settings.manager.s * 16; color: settings.manager.surface
            Column { anchors { left: parent.left; verticalCenter: parent.verticalCenter; leftMargin: settings.manager.s * 18 } spacing: settings.manager.s * 4
                Text { text: qsTranslate("OmniaManager", "Fondo animado"); color: settings.manager.ink; font.family: "Hanken Grotesk"; font.pixelSize: settings.manager.s * 16; font.weight: Font.DemiBold }
                Text { text: qsTranslate("OmniaManager", "Constelación en el Inicio y ondas en la Biblioteca de Big Mode."); color: settings.manager.muted; font.family: "Hanken Grotesk"; font.pixelSize: settings.manager.s * 12 } }
            Switch { anchors { right: parent.right; verticalCenter: parent.verticalCenter; rightMargin: settings.manager.s * 18 }
                checked: settings.api.animatedBackground
                onToggled: settings.api.setAnimatedBackground(checked, function(status) { if (status !== 200) settings.api.notify(qsTranslate("OmniaManager", "No se pudo guardar el ajuste.")) }) }
        }
        Rectangle {
            visible: settings.manager.settingsSection === "bigmode"
            width: parent.width; height: settings.manager.s * 86; radius: settings.manager.s * 16; color: settings.manager.surface
            Text { anchors { left: parent.left; verticalCenter: parent.verticalCenter; leftMargin: settings.manager.s * 18 } text: qsTranslate("OmniaManager", "Abrir Big Mode a pantalla completa"); color: settings.manager.ink; font.family: "Hanken Grotesk"; font.pixelSize: settings.manager.s * 16; font.weight: Font.DemiBold }
            Rectangle { anchors { right: parent.right; verticalCenter: parent.verticalCenter; rightMargin: settings.manager.s * 16 } width: settings.manager.s * 148; height: settings.manager.s * 40; radius: height / 2; color: settings.manager.accent
                Text { anchors.centerIn: parent; text: qsTranslate("OmniaManager", "Abrir"); color: settings.manager.ink; font.family: "Hanken Grotesk"; font.pixelSize: settings.manager.s * 14; font.weight: Font.DemiBold }
                MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: settings.manager.openBigMode() } }
        }
        Rectangle {
            visible: settings.manager.settingsSection === "general"
            width: parent.width; height: settings.manager.s * 86; radius: settings.manager.s * 16; color: settings.manager.surface
            Text { anchors { left: parent.left; verticalCenter: parent.verticalCenter; leftMargin: settings.manager.s * 18 } text: qsTranslate("OmniaManager", "Idioma de Omnia"); color: settings.manager.ink; font.family: "Hanken Grotesk"; font.pixelSize: settings.manager.s * 16; font.weight: Font.DemiBold }
            ComboBox {
                anchors { right: parent.right; verticalCenter: parent.verticalCenter; rightMargin: settings.manager.s * 18 }
                width: settings.manager.s * 220
                model: [qsTranslate("OmniaManager", "Español"), qsTranslate("OmniaManager", "English")]
                currentIndex: settings.api.language === "en" ? 1 : 0
                onActivated: function(index) {
                    settings.api.setLanguage(index === 1 ? "en" : "es", function(status, body) {
                        if (status === 200) settings.api.notify(qsTranslate("OmniaManager", "Idioma actualizado."))
                        else settings.api.notify((body && body.error) || qsTranslate("OmniaManager", "No se pudo guardar el idioma."))
                    })
                }
            }
        }
        Rectangle {
            visible: settings.manager.settingsSection === "general"
            width: parent.width; height: settings.manager.s * 88; radius: settings.manager.s * 16; color: settings.manager.surface
            Column { anchors { left: parent.left; right: installRootButton.left; verticalCenter: parent.verticalCenter; leftMargin: settings.manager.s * 18; rightMargin: settings.manager.s * 12 } spacing: settings.manager.s * 4
                Text { text: qsTranslate("OmniaManager", "Carpeta predeterminada de instalación"); color: settings.manager.ink; font.family: "Hanken Grotesk"; font.pixelSize: settings.manager.s * 16; font.weight: Font.DemiBold }
                Text { width: parent.width; text: settings.api.installRoot || qsTranslate("OmniaManager", "Sin configurar; elige una ubicación"); color: settings.manager.muted; font.family: "Hanken Grotesk"; font.pixelSize: settings.manager.s * 12; elide: Text.ElideMiddle }
            }
            Rectangle { id: installRootButton; anchors { right: parent.right; verticalCenter: parent.verticalCenter; rightMargin: settings.manager.s * 16 } width: settings.manager.s * 148; height: settings.manager.s * 40; radius: height / 2; color: settings.manager.surface2
                Text { anchors.centerIn: parent; text: qsTranslate("OmniaManager", "Elegir carpeta"); color: settings.manager.ink; font.family: "Hanken Grotesk"; font.pixelSize: settings.manager.s * 13 }
                MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: settings.chooseInstallFolder() }
            }
        }
        Rectangle {
            visible: settings.manager.settingsSection === "general"
            width: parent.width; height: settings.manager.s * 86; radius: settings.manager.s * 16; color: settings.manager.surface
            Column { anchors { left: parent.left; verticalCenter: parent.verticalCenter; leftMargin: settings.manager.s * 18 } spacing: settings.manager.s * 4
                Text { text: qsTranslate("OmniaManager", "Buscar actualizaciones de ports"); color: settings.manager.ink; font.family: "Hanken Grotesk"; font.pixelSize: settings.manager.s * 16; font.weight: Font.DemiBold }
                Text { text: qsTranslate("OmniaManager", "Avisa cuando un port instalado desde el catálogo tiene una versión nueva. Nunca se actualiza sin confirmar."); color: settings.manager.muted; font.family: "Hanken Grotesk"; font.pixelSize: settings.manager.s * 12 } }
            Switch { anchors { right: parent.right; verticalCenter: parent.verticalCenter; rightMargin: settings.manager.s * 18 }
                checked: settings.api.updateCheck
                onToggled: settings.api.setUpdateCheck(checked, function(status) { if (status !== 200) settings.api.notify(qsTranslate("OmniaManager", "No se pudo guardar el ajuste.")) }) }
        }
        Rectangle {
            visible: settings.manager.settingsSection === "general"
            width: parent.width; height: settings.manager.s * 86; radius: settings.manager.s * 16; color: settings.manager.surface
            Column { anchors { left: parent.left; verticalCenter: parent.verticalCenter; leftMargin: settings.manager.s * 18 } spacing: settings.manager.s * 4
                Text { text: qsTranslate("OmniaManager", "Monitor de rendimiento en los juegos"); color: settings.manager.ink; font.family: "Hanken Grotesk"; font.pixelSize: settings.manager.s * 16; font.weight: Font.DemiBold }
                Text { text: settings.api.mangohudInstalled ? qsTranslate("OmniaManager", "Muestra FPS, GPU, CPU, VRAM y RAM en una sola línea, con el estilo de Omnia, sobre los juegos que lanzas desde aquí.") : qsTranslate("OmniaManager", "Necesita MangoHud: instálalo desde el gestor de paquetes."); color: settings.manager.muted; font.family: "Hanken Grotesk"; font.pixelSize: settings.manager.s * 12 } }
            Switch { anchors { right: parent.right; verticalCenter: parent.verticalCenter; rightMargin: settings.manager.s * 18 }
                checked: settings.api.mangohud
                enabled: settings.api.mangohudInstalled || settings.api.mangohud
                onToggled: settings.api.setMangohud(checked, function(status, body) { if (status !== 200) { checked = settings.api.mangohud; settings.api.notify((body && body.error) || qsTranslate("OmniaManager", "No se pudo guardar el ajuste.")) } }) }
        }
        Rectangle {
            visible: settings.manager.settingsSection === "library"
            width: parent.width; height: settings.manager.s * 116; radius: settings.manager.s * 16; color: settings.manager.surface
            Column { anchors { left: parent.left; top: parent.top; margins: settings.manager.s * 18 } spacing: settings.manager.s * 5
                Text { text: qsTranslate("OmniaManager", "Carpetas de la biblioteca"); color: settings.manager.ink; font.family: "Hanken Grotesk"; font.pixelSize: settings.manager.s * 17; font.weight: Font.DemiBold }
                Text { text: qsTranslate("OmniaManager", "Añade aquí tus carpetas de juegos y ROMs: Omnia las detecta solas, sin elegir emulador. Retirar una carpeta no elimina los archivos."); color: settings.manager.muted; font.family: "Hanken Grotesk"; font.pixelSize: settings.manager.s * 13 }
            }
            Row {
                anchors { right: parent.right; bottom: parent.bottom; margins: settings.manager.s * 14 } spacing: settings.manager.s * 8
                TextField { id: rootInput; width: settings.manager.s * 420; height: settings.manager.s * 40; placeholderText: qsTranslate("OmniaManager", "Ruta, por ejemplo /mnt/JUEGOS/Ports"); text: settings.manager.rootPath; onTextEdited: settings.manager.rootPath = text; color: settings.manager.ink; font.family: "Hanken Grotesk"; font.pixelSize: settings.manager.s * 14; background: Rectangle { radius: settings.manager.s * 10; color: settings.manager.surface2; border.color: rootInput.activeFocus ? "#45CFC9" : "#24FFFFFF" } }
                Rectangle { width: settings.manager.s * 40; height: settings.manager.s * 40; radius: settings.manager.s * 10; color: settings.manager.surface2; LucideIcon { anchors.centerIn: parent; width: settings.manager.s * 17; height: width; name: "folder-open"; color: settings.manager.muted } MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: libraryFolderDialog.open() } }
                Rectangle { width: settings.manager.s * 126; height: settings.manager.s * 40; radius: settings.manager.s * 10; color: settings.manager.accent; Text { anchors.centerIn: parent; text: qsTranslate("OmniaManager", "Añadir carpeta"); color: settings.manager.ink; font.family: "Hanken Grotesk"; font.pixelSize: settings.manager.s * 13; font.weight: Font.DemiBold } MouseArea { anchors.fill: parent; enabled: settings.manager.rootPath.trim().length > 0; cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor; onClicked: settings.manager.changeRoot("add", settings.manager.rootPath.trim()) } }
            }
        }
        Text { visible: settings.manager.settingsSection === "library" && settings.manager.libraryRoots.length === 0; text: qsTranslate("OmniaManager", "Aún no has añadido carpetas externas."); color: settings.manager.muted; font.family: "Hanken Grotesk"; font.pixelSize: settings.manager.s * 14 }
        Repeater {
            model: settings.manager.settingsSection === "library" ? settings.manager.libraryRoots : []
            delegate: Rectangle {
                id: rootEntry
                required property string modelData
                width: parent.width; height: settings.manager.s * 58; radius: settings.manager.s * 13; color: settings.manager.surface
                LucideIcon { x: settings.manager.s * 16; anchors.verticalCenter: parent.verticalCenter; width: settings.manager.s * 20; height: width; name: "folder-open"; color: "#66D5D0" }
                Text { anchors { left: parent.left; leftMargin: settings.manager.s * 48; right: removeRoot.left; verticalCenter: parent.verticalCenter } text: rootEntry.modelData; color: settings.manager.ink; font.family: "Hanken Grotesk"; font.pixelSize: settings.manager.s * 14; elide: Text.ElideMiddle }
                Rectangle { id: removeRoot; anchors { right: parent.right; verticalCenter: parent.verticalCenter; rightMargin: settings.manager.s * 12 } width: settings.manager.s * 90; height: settings.manager.s * 34; radius: height / 2; color: "#27343F"; Text { anchors.centerIn: parent; text: qsTranslate("OmniaManager", "Retirar"); color: settings.manager.muted; font.family: "Hanken Grotesk"; font.pixelSize: settings.manager.s * 12 } MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: settings.manager.changeRoot("remove", rootEntry.modelData) } }
            }
        }
        Text { visible: !!settings.manager.rootsMessage; text: settings.manager.rootsMessage; color: "#E8B86D"; font.family: "Hanken Grotesk"; font.pixelSize: settings.manager.s * 13; wrapMode: Text.WordWrap }
    }
    FolderDialog {
        id: libraryFolderDialog
        title: qsTranslate("OmniaManager", "Añadir carpeta de juegos")
        onAccepted: {
            const path = selectedFolder.toString().replace(/^file:\/\//, "")
            settings.manager.rootPath = decodeURIComponent(path)
        }
    }
}

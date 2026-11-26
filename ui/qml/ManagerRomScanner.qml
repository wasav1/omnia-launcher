pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls

/** Escáner de ROMs y selección explícita de sistema y emulador. */
Rectangle {
    id: scanner
    required property var manager
    anchors.fill: parent; visible: false; z: 11; color: "#A5000000"
    function open() { visible = true }
    MouseArea { anchors.fill: parent; onClicked: scanner.visible = false }
    Rectangle {
        anchors.centerIn: parent; width: Math.min(parent.width * 0.76, scanner.manager.s * 900); height: Math.min(parent.height * 0.82, scanner.manager.s * 680); radius: scanner.manager.s * 22; color: scanner.manager.surface; clip: true
        MouseArea { anchors.fill: parent; onClicked: function(mouse) { mouse.accepted = true } }
        Column {
            anchors.fill: parent; anchors.margins: scanner.manager.s * 22; spacing: scanner.manager.s * 12
            Row {
                width: parent.width; spacing: scanner.manager.s * 12
                Text { id: romDialogTitle; text: qsTranslate("OmniaManager", "ROMs y juegos de consola"); color: scanner.manager.ink; font.family: "Hanken Grotesk"; font.pixelSize: scanner.manager.s * 24; font.weight: Font.DemiBold }
                Item { width: parent.width - romDialogTitle.implicitWidth - closeRomDialog.width - scanner.manager.s * 24; height: 1 }
                Rectangle { id: closeRomDialog; width: scanner.manager.s * 38; height: scanner.manager.s * 38; radius: height / 2; color: scanner.manager.surface2; Text { anchors.centerIn: parent; text: "×"; color: scanner.manager.ink; font.pixelSize: scanner.manager.s * 23 } MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: scanner.visible = false } }
            }
            Text { width: parent.width; text: scanner.manager.romMessage; color: scanner.manager.muted; font.family: "Hanken Grotesk"; font.pixelSize: scanner.manager.s * 14; wrapMode: Text.WordWrap }
            ListView {
                width: parent.width; height: parent.height - scanner.manager.s * 86; spacing: scanner.manager.s * 8; clip: true; model: scanner.manager.romResults
                delegate: Rectangle {
                    id: romEntry
                    required property var modelData
                    width: ListView.view.width; height: scanner.manager.s * 82; radius: scanner.manager.s * 12; color: scanner.manager.surface2
                    property string selectedSystemId: romEntry.modelData.system
                    property var selectedSystemOption: romEntry.modelData.systemOptions.find(option => option.id === selectedSystemId) || romEntry.modelData.systemOptions[0]
                    property var activeCatalogMatch: scanner.manager.catalogMatchFor(romEntry.modelData, selectedSystemId)
                    property string proposedName: activeCatalogMatch ? activeCatalogMatch.name : romEntry.modelData.name
                    property string selectedEmulatorId: selectedSystemOption && selectedSystemOption.emulators.length ? selectedSystemOption.emulators[0].id : ""
                    Column { anchors { left: parent.left; verticalCenter: parent.verticalCenter; leftMargin: scanner.manager.s * 14 } width: parent.width * 0.25; spacing: scanner.manager.s * 3; Text { width: parent.width; text: romEntry.selectedSystemOption.name + " · " + romEntry.modelData.format.toUpperCase(); color: scanner.manager.muted; font.family: "Hanken Grotesk"; font.pixelSize: scanner.manager.s * 11; elide: Text.ElideRight } Text { width: parent.width; text: romEntry.modelData.internalTitle || romEntry.modelData.fileName; color: scanner.manager.ink; font.family: "Hanken Grotesk"; font.pixelSize: scanner.manager.s * 14; elide: Text.ElideRight } Text { width: parent.width; visible: !!romEntry.modelData.internalId || !!romEntry.modelData.region || !!romEntry.activeCatalogMatch; text: [romEntry.modelData.internalId, romEntry.modelData.region, romEntry.activeCatalogMatch ? "Omnia · " + romEntry.activeCatalogMatch.name : ""].filter(Boolean).join(" · "); color: romEntry.activeCatalogMatch ? scanner.manager.accent : scanner.manager.muted; font.family: "Hanken Grotesk"; font.pixelSize: scanner.manager.s * 10; elide: Text.ElideRight } }
                    TextField { id: romName; anchors { left: parent.left; leftMargin: parent.width * 0.27; verticalCenter: parent.verticalCenter } width: parent.width * 0.24; height: scanner.manager.s * 38; text: romEntry.proposedName; color: scanner.manager.ink; font.family: "Hanken Grotesk"; font.pixelSize: scanner.manager.s * 13; background: Rectangle { radius: scanner.manager.s * 9; color: "#111923" } }
                    ComboBox { id: systemChoice; anchors { left: romName.right; leftMargin: scanner.manager.s * 6; verticalCenter: parent.verticalCenter } width: parent.width * 0.18; height: scanner.manager.s * 38; visible: romEntry.modelData.systemOptions.length > 1; model: romEntry.modelData.systemOptions.map(option => option.name); currentIndex: Math.max(0, romEntry.modelData.systemOptions.findIndex(option => option.id === romEntry.selectedSystemId)); onActivated: { romEntry.selectedSystemId = romEntry.modelData.systemOptions[currentIndex].id; romEntry.selectedEmulatorId = romEntry.selectedSystemOption.emulators.length ? romEntry.selectedSystemOption.emulators[0].id : "" } }
                    ComboBox { id: emulatorChoice; anchors { left: romName.right; leftMargin: systemChoice.visible ? systemChoice.width + scanner.manager.s * 12 : scanner.manager.s * 8; verticalCenter: parent.verticalCenter } width: parent.width * 0.16; height: scanner.manager.s * 38; visible: romEntry.selectedSystemOption && romEntry.selectedSystemOption.emulators.length > 0; model: romEntry.selectedSystemOption ? romEntry.selectedSystemOption.emulators.map(e => e.label) : []; onActivated: romEntry.selectedEmulatorId = romEntry.selectedSystemOption.emulators[currentIndex].id }
                    Text { anchors { left: romName.right; leftMargin: systemChoice.visible ? systemChoice.width + scanner.manager.s * 12 : scanner.manager.s * 8; verticalCenter: parent.verticalCenter } width: parent.width * 0.16; visible: !romEntry.selectedSystemOption || romEntry.selectedSystemOption.emulators.length === 0; text: qsTranslate("OmniaManager", "Sin emulador: se elige al jugar"); color: scanner.manager.muted; font.family: "Hanken Grotesk"; font.pixelSize: scanner.manager.s * 10; wrapMode: Text.WordWrap }
                    Rectangle { anchors { right: parent.right; verticalCenter: parent.verticalCenter; rightMargin: scanner.manager.s * 10 } width: scanner.manager.s * 76; height: scanner.manager.s * 38; radius: height / 2; color: scanner.manager.accent; opacity: romName.text.trim().length > 0 && !scanner.manager.romMatching ? 1 : 0.45; Text { anchors.centerIn: parent; text: qsTranslate("OmniaManager", "Añadir"); color: scanner.manager.ink; font.family: "Hanken Grotesk"; font.pixelSize: scanner.manager.s * 13; font.weight: Font.DemiBold } MouseArea { anchors.fill: parent; enabled: romName.text.trim().length > 0 && !scanner.manager.romMatching; cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor; onClicked: scanner.manager.addScannedRom(romEntry.modelData, romName.text.trim(), romEntry.selectedSystemId, romEntry.selectedEmulatorId, romEntry.activeCatalogMatch ? romEntry.activeCatalogMatch.slug : "") } }
                }
                Text { visible: scanner.manager.romResults.length === 0 && !scanner.manager.romScanning; anchors.centerIn: parent; text: qsTranslate("OmniaManager", "No hay candidatos pendientes."); color: scanner.manager.muted; font.family: "Hanken Grotesk"; font.pixelSize: scanner.manager.s * 15 }
            }
        }
    }
    Keys.onEscapePressed: visible = false
}

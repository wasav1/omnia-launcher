pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls
import "Theme.js" as Theme

/** Panel central de la Biblioteca (rediseño D, fase 2): el Catálogo, antes «Explorar».
 *  Reúne los ports de Omnia y los juegos de tus tiendas en una cuadrícula de carátulas de
 *  tamaño fijo; solo cambia el número de columnas según el ancho disponible.
 *  Tiene su propio buscador: filtra al escribir y, con Enter, busca también en el catálogo
 *  en línea. Al elegir un juego que ya está en tu biblioteca emite `localGameChosen` para
 *  que la Biblioteca abra su ficha; el resto abre la ficha de instalación del gestor. */
GlassPanel {
    id: cat
    required property var manager
    required property var stores
    signal localGameChosen(var game)
    signal installedRequested()
    property bool showInstalledButton: false   // bajo 900 px, Instalados se abre desde aquí

    readonly property real pad: 18
    property alias text: searchField.text

    function normalize(text) {
        return String(text || "").toLowerCase().normalize("NFD").replace(/[̀-ͯ]/g, "")
    }
    readonly property var items: {
        const all = cat.stores && cat.stores.ready ? (cat.manager.exploreItems || []) : []
        const q = normalize(searchField.text.trim())
        if (!q) return all
        return all.filter(i => normalize(i.name + " " + (i.store || "") + " " + (i.platform || "")).includes(q))
    }
    readonly property var layout: Theme.posterLayout(width - 2 * pad)
    readonly property int columns: layout.columns

    function choose(entry) {
        const m = cat.manager
        if (entry.kind === "omnia") {
            const local = m.localMatch(entry.game)
            if (m.catalogLinkTargetId) m.linkCatalogGame(entry.game)
            else if (local) cat.localGameChosen(local)
            else m.openCatalogDetail(entry.game)
        } else if (entry.item.local) cat.localGameChosen(entry.item.local)
        else m.openStoreDetail(entry.item)
    }
    function contextMenu(entry) {
        const local = entry.item?.local || cat.manager.localMatch(entry.game)
        if (local) cat.manager.openGameMenu(local)
        else cat.manager.openOfferMenu(entry)
    }
    function focusSearch() { searchField.forceActiveFocus() }
    function searchOnline() {
        cat.manager.query = searchField.text.trim()
        cat.manager.loadOnline(1)
        grid.contentY = 0
    }

    // ---------------- encabezado
    Item {
        id: header
        anchors { left: parent.left; right: parent.right; top: parent.top; margins: cat.pad }
        height: Theme.size.control
        Row {
            anchors.verticalCenter: parent.verticalCenter
            spacing: 10
            Rectangle {
                visible: cat.showInstalledButton
                anchors.verticalCenter: parent.verticalCenter
                width: installedRow.implicitWidth + 20; height: 32; radius: Theme.radius.sm
                color: installedMa.containsMouse ? Theme.color.glassFillStrong : Theme.color.inset; border.color: Theme.color.glassBorder
                Row { id: installedRow; anchors.centerIn: parent; spacing: 6
                    LucideIcon { anchors.verticalCenter: parent.verticalCenter; width: 16; height: 16; name: "menu"; color: Theme.color.ink }
                    Text { anchors.verticalCenter: parent.verticalCenter; text: qsTr("Instalados"); color: Theme.color.ink; font.family: Theme.font.family; font.pixelSize: Theme.font.size.small; font.weight: Font.DemiBold } }
                MouseArea { id: installedMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: cat.installedRequested() }
            }
            Text { anchors.verticalCenter: parent.verticalCenter; text: qsTr("Catálogo"); color: Theme.color.ink; font.family: Theme.font.family; font.pixelSize: Theme.font.size.title + 3; font.weight: Font.Bold }
            Text { anchors.verticalCenter: parent.verticalCenter; text: cat.items.length === 1 ? qsTr("1 juego") : qsTr("%1 juegos").arg(cat.items.length); color: Theme.color.muted; font.family: Theme.font.family; font.pixelSize: Theme.font.size.small }
        }
        Row {
            anchors { right: parent.right; verticalCenter: parent.verticalCenter }
            spacing: 8
            ComboBox {
                id: sortControl
                width: 160; height: 32
                model: [qsTr("Año · recientes"), qsTr("Año · antiguos"), qsTr("Nombre · A–Z"), qsTr("Nombre · Z–A")]
                currentIndex: ["year-desc", "year-asc", "name-asc", "name-desc"].indexOf(cat.manager.exploreSort)
                onActivated: cat.manager.exploreSort = ["year-desc", "year-asc", "name-asc", "name-desc"][currentIndex]
                contentItem: Text { leftPadding: 12; rightPadding: 24; text: sortControl.displayText; color: Theme.color.ink; font.family: Theme.font.family; font.pixelSize: Theme.font.size.small; verticalAlignment: Text.AlignVCenter; elide: Text.ElideRight }
                background: Rectangle { radius: Theme.radius.sm; color: Theme.color.inset; border.color: sortControl.activeFocus ? Theme.color.accent : Theme.color.glassBorder }
            }
            Rectangle {
                id: accountsButton
                width: 32; height: 32; radius: Theme.radius.sm
                color: accountsMouse.containsMouse ? Theme.color.glassFillStrong : Theme.color.inset
                border.color: Theme.color.glassBorder
                LucideIcon { anchors.centerIn: parent; width: 16; height: 16; name: "key-round"; color: Theme.color.soft }
                ToolTip.visible: accountsMouse.containsMouse; ToolTip.text: qsTr("Cuentas de tiendas"); ToolTip.delay: 400
                MouseArea { id: accountsMouse; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: cat.manager.openStoreSettings() }
            }
        }
    }

    TextField {
        id: searchField
        anchors { left: parent.left; right: parent.right; top: header.bottom; leftMargin: cat.pad; rightMargin: cat.pad; topMargin: 12 }
        height: Theme.size.control
        leftPadding: 38
        placeholderText: cat.manager.catalogLinkTargetId ? qsTr("Buscar una ficha para vincular") : qsTr("Buscar en el catálogo · Enter busca en línea")
        placeholderTextColor: Theme.color.muted
        color: Theme.color.ink; font.family: Theme.font.family; font.pixelSize: Theme.font.size.body
        onAccepted: cat.searchOnline()
        onTextChanged: if (!text.trim() && cat.manager.query) cat.searchOnline()
        Keys.onEscapePressed: text = ""
        background: Rectangle {
            radius: Theme.radius.md; color: Theme.color.inset
            border.color: searchField.activeFocus ? Theme.color.accent : Theme.color.glassBorder
            LucideIcon { x: 12; anchors.verticalCenter: parent.verticalCenter; width: 16; height: 16; name: "search"; color: Theme.color.muted }
        }
    }

    Flow {
        id: sources
        anchors { left: parent.left; right: parent.right; top: searchField.bottom; leftMargin: cat.pad; rightMargin: cat.pad; topMargin: 10 }
        spacing: 6
        Repeater {
            model: cat.manager.exploreSources
            delegate: Rectangle {
                id: chip
                required property var modelData
                readonly property bool selected: cat.manager.exploreFilter === modelData.k
                height: Theme.size.chip + 2; radius: height / 2
                width: chipRow.implicitWidth + 22
                color: selected ? Theme.color.accentSoft : (chipMouse.containsMouse ? Theme.color.glassFill : "transparent")
                border.color: selected ? Theme.color.accent : Theme.color.glassBorder
                Row {
                    id: chipRow
                    anchors.centerIn: parent; spacing: 6
                    Image { visible: !!chip.modelData.logo; anchors.verticalCenter: parent.verticalCenter; width: 16; height: 16; source: chip.modelData.logo; sourceSize.width: 32; sourceSize.height: 32; fillMode: Image.PreserveAspectFit }
                    Text { anchors.verticalCenter: parent.verticalCenter; text: chip.modelData.label; color: chip.selected ? Theme.color.accentLight : Theme.color.soft; font.family: Theme.font.family; font.pixelSize: Theme.font.size.small; font.weight: Font.DemiBold }
                }
                MouseArea { id: chipMouse; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                    onClicked: { cat.manager.exploreFilter = chip.modelData.k; grid.contentY = 0 } }
            }
        }
    }

    Item {
        id: notice
        anchors { left: parent.left; right: parent.right; top: sources.bottom; leftMargin: cat.pad; rightMargin: cat.pad; topMargin: visible ? 8 : 0 }
        height: visible ? Math.max(warning.implicitHeight, cancelLink.visible ? 28 : 0) : 0
        visible: !!cat.manager.onlineWarning || !!cat.manager.catalogLinkTargetId
        Text {
            id: warning
            anchors { left: parent.left; right: cancelLink.visible ? cancelLink.left : parent.right; rightMargin: 8; verticalCenter: parent.verticalCenter }
            text: cat.manager.onlineWarning
            color: Theme.color.warning; font.family: Theme.font.family; font.pixelSize: Theme.font.size.small
            wrapMode: Text.WordWrap; maximumLineCount: 2; elide: Text.ElideRight
        }
        Rectangle {
            id: cancelLink
            visible: !!cat.manager.catalogLinkTargetId
            anchors { right: parent.right; verticalCenter: parent.verticalCenter }
            width: cancelText.implicitWidth + 24; height: 28; radius: Theme.radius.sm; color: Theme.color.inset; border.color: Theme.color.glassBorder
            Text { id: cancelText; anchors.centerIn: parent; text: qsTr("Cancelar vínculo"); color: Theme.color.ink; font.family: Theme.font.family; font.pixelSize: Theme.font.size.small }
            MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: cat.manager.cancelCatalogLink() }
        }
    }

    // ---------------- cuadrícula de carátulas (152 × 203 fijos)
    Flickable {
        id: grid
        anchors { left: parent.left; right: parent.right; top: notice.bottom; bottom: parent.bottom; topMargin: 12; bottomMargin: 2 }
        clip: true
        contentWidth: width
        contentHeight: gridBody.height + 24
        boundsBehavior: Flickable.StopAtBounds
        ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }
        onContentYChanged: if (contentY + height >= contentHeight - 600) cat.manager.loadNextOnline()

        Column {
            id: gridBody
            readonly property real gridWidth: cat.columns * cat.layout.width + (cat.columns - 1) * Theme.size.posterGap
            x: Math.max(cat.pad, (grid.width - gridWidth) / 2)
            y: 6
            width: gridWidth
            spacing: 14
            Grid {
                id: posters
                columns: cat.columns
                columnSpacing: Theme.size.posterGap
                rowSpacing: Theme.size.posterGap
                Repeater {
                    id: posterRepeater
                    model: cat.items
                    delegate: Item {
                        id: cell
                        required property var modelData
                        width: cat.layout.width; height: cat.layout.height
                        z: poster.hovered ? 1 : 0
                        ManagerPosterCard {
                            id: poster
                            anchors.fill: parent
                            viewport: grid
                            title: cell.modelData.name
                            artwork: cell.modelData.art
                            store: cell.modelData.store
                            sourceLogo: cell.modelData.logo
                            platform: cell.modelData.platform
                            info: cell.modelData.info
                            installed: cell.modelData.installed
                            highlightColor: Theme.color.accent
                            onActivated: cat.choose(cell.modelData)
                            onContextRequested: cat.contextMenu(cell.modelData)
                        }
                    }
                }
            }
            StoreLoading {
                width: parent.width
                visible: cat.stores ? cat.stores.loadingContent : false
                ink: Theme.color.muted
            }
            Text {
                width: parent.width
                visible: posterRepeater.count === 0 && !cat.manager.onlineBusy && !(cat.stores && cat.stores.loadingContent)
                text: searchField.text.trim() ? qsTr("Nada coincide. Pulsa Enter para buscar en línea.") : qsTr("No hay juegos para este filtro.")
                color: Theme.color.muted; font.family: Theme.font.family; font.pixelSize: Theme.font.size.body
                wrapMode: Text.WordWrap
            }
            Text {
                visible: cat.manager.onlineBusy
                text: qsTr("Cargando más juegos…")
                color: Theme.color.muted; font.family: Theme.font.family; font.pixelSize: Theme.font.size.small
            }
        }
    }
}

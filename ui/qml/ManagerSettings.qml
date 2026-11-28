pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls
import QtQuick.Dialogs
import "Theme.js" as Theme

/** Ajustes de Desktop (rediseño D, fase 3): menú de categorías a la izquierda y su contenido
 *  a la derecha, en paneles de cristal con tamaños fijos. Por ahora solo reúne los ajustes que ya
 *  existían (más el efecto cristal); Novedades y Panel rápido de Dux llegarán con sus fases.
 *  El gestor anfitrión conserva el estado (`settingsSection`, carpetas, cuentas de tiendas). */
Item {
    id: settings
    required property var manager
    required property var api
    required property var stores
    property Item backdrop: null
    property alias accountsContainer: accountHost
    signal chooseInstallFolder()
    visible: settings.manager.page === "settings"

    readonly property var categories: [
        { k: "general", icon: "settings", l: qsTr("General"), d: qsTr("Idioma y avisos de actualización de los ports.") },
        { k: "library", icon: "folder-open", l: qsTr("Biblioteca y carpetas"), d: qsTr("Dónde se instalan los juegos y qué carpetas revisa Omnia.") },
        { k: "stores", icon: "key-round", l: qsTr("Tiendas y cuentas"), d: qsTr("Conecta Steam, Epic, GOG y Amazon. Omnia nunca ve tus contraseñas.") },
        { k: "games", icon: "gamepad-2", l: qsTr("Juegos y rendimiento"), d: qsTr("Monitor de rendimiento sobre los juegos que lanzas desde Omnia.") },
        { k: "news", icon: "bell", l: qsTr("Novedades"), d: qsTr("Qué tiendas aparecen en el Inicio y en el panel rápido: ofertas, juegos gratis, lanzamientos y noticias.") },
        { k: "appearance", icon: "image", l: qsTr("Apariencia"), d: qsTr("Aspecto de la app de escritorio.") },
        { k: "bigmode", icon: "monitor", l: qsTr("Big Mode"), d: qsTr("Fondo, sonidos y bienvenida de la interfaz para mando.") },
        { k: "about", icon: "info", l: qsTr("Acerca de"), d: "" }
    ]
    readonly property var currentCategory: categories.find(c => c.k === settings.manager.settingsSection) || categories[0]
    readonly property string section: currentCategory.k

    function backdropRectOf(item) {
        if (!backdrop || !item) return Qt.rect(0, 0, 0, 0)
        void (item.x + item.y + item.width + item.height + settings.x + settings.y + settings.width + settings.height)
        const p = item.mapToItem(backdrop, 0, 0)
        return Qt.rect(p.x, p.y, item.width, item.height)
    }
    function saved(status, body) {
        if (status !== 200) settings.api.notify((body && body.error) || qsTr("No se pudo guardar el ajuste."))
    }

    // ---------------- controles comunes
    // Interruptor que siempre muestra el valor guardado (`value`): al tocarlo pide el cambio con
    // `changeRequested` y vuelve a seguir `value`, así un fallo al guardar no lo deja mintiendo.
    component SettingSwitch: Switch {
        id: sw
        property bool value: false
        signal changeRequested(bool enabled)
        checked: value
        onToggled: { const wanted = checked; checked = Qt.binding(() => sw.value); sw.changeRequested(wanted) }
        implicitWidth: 46; implicitHeight: 26
        padding: 0
        indicator: Rectangle {
            width: 46; height: 26; radius: 13
            color: sw.checked ? Theme.color.accent : Theme.color.inset
            border.color: sw.checked ? Theme.color.accent : Theme.color.glassBorderStrong
            opacity: sw.enabled ? 1 : 0.45
            Rectangle {
                x: sw.checked ? parent.width - width - 3 : 3
                anchors.verticalCenter: parent.verticalCenter
                width: 20; height: 20; radius: 10
                color: sw.checked ? Theme.color.accentInk : Theme.color.soft
                Behavior on x { NumberAnimation { duration: 120 } }
            }
        }
        contentItem: null
    }
    component PillButton: Rectangle {
        id: pill
        property string text: ""
        property string icon: ""
        property bool primary: false
        property bool danger: false
        signal clicked()
        implicitWidth: pillRow.implicitWidth + 28
        implicitHeight: Theme.size.control
        radius: Theme.radius.sm
        color: primary ? Theme.color.accent : (pillMa.containsMouse ? Theme.color.glassFillStrong : Theme.color.inset)
        border.color: primary ? "transparent" : Theme.color.glassBorder
        opacity: enabled ? 1 : 0.5
        Row {
            id: pillRow
            anchors.centerIn: parent; spacing: 7
            LucideIcon { visible: !!pill.icon; anchors.verticalCenter: parent.verticalCenter; width: 16; height: 16; name: pill.icon; color: pill.primary ? Theme.color.accentInk : Theme.color.ink }
            Text { visible: !!pill.text; anchors.verticalCenter: parent.verticalCenter; text: pill.text; font.family: Theme.font.family; font.pixelSize: Theme.font.size.body; font.weight: pill.primary ? Font.DemiBold : Font.Normal
                color: pill.primary ? Theme.color.accentInk : (pill.danger ? Theme.color.danger : Theme.color.ink) }
        }
        MouseArea { id: pillMa; anchors.fill: parent; enabled: pill.enabled; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: pill.clicked() }
    }

    // ---------------- menú de categorías
    GlassPanel {
        id: nav
        anchors { left: parent.left; top: parent.top; bottom: parent.bottom
                  leftMargin: Theme.size.pageMargin; topMargin: Theme.size.panelGap; bottomMargin: Theme.size.pageMargin }
        width: 260
        backdrop: settings.backdrop
        backdropRect: settings.backdropRectOf(nav)
        Text { x: 18; y: 16; text: qsTr("Ajustes"); color: Theme.color.ink; font.family: Theme.font.family; font.pixelSize: Theme.font.size.title + 3; font.weight: Font.Bold }
        Column {
            anchors { left: parent.left; right: parent.right; top: parent.top; topMargin: 58; leftMargin: 8; rightMargin: 8 }
            spacing: 2
            Repeater {
                model: settings.categories
                delegate: Rectangle {
                    id: navItem
                    required property var modelData
                    readonly property bool on: settings.section === modelData.k
                    width: parent.width; height: 44; radius: Theme.radius.sm
                    color: on ? Theme.color.accentSoft : (navMa.containsMouse ? Theme.color.glassFill : "transparent")
                    LucideIcon { x: 12; anchors.verticalCenter: parent.verticalCenter; width: 18; height: 18; name: navItem.modelData.icon; color: navItem.on ? Theme.color.accentLight : Theme.color.soft }
                    Text { anchors { left: parent.left; leftMargin: 42; right: parent.right; rightMargin: 10; verticalCenter: parent.verticalCenter }
                        text: navItem.modelData.l; elide: Text.ElideRight
                        color: navItem.on ? Theme.color.inkStrong : Theme.color.ink; font.family: Theme.font.family; font.pixelSize: Theme.font.size.body + 1; font.weight: navItem.on ? Font.DemiBold : Font.Normal }
                    MouseArea { id: navMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: settings.manager.settingsSection = navItem.modelData.k }
                }
            }
        }
    }

    // ---------------- contenido de la categoría
    GlassPanel {
        id: page
        anchors { left: nav.right; right: parent.right; top: nav.top; bottom: nav.bottom; leftMargin: Theme.size.panelGap; rightMargin: Theme.size.pageMargin }
        backdrop: settings.backdrop
        backdropRect: settings.backdropRectOf(page)
        readonly property real contentWidth: Math.min(width - 56, 760)

        Column {
            id: heading
            x: 28; y: 22
            width: page.contentWidth
            spacing: 4
            Text { text: settings.currentCategory.l; color: Theme.color.ink; font.family: Theme.font.family; font.pixelSize: Theme.font.size.heading; font.weight: Font.Bold }
            Text { visible: !!settings.currentCategory.d; width: parent.width; text: settings.currentCategory.d; color: Theme.color.muted; font.family: Theme.font.family; font.pixelSize: Theme.font.size.body; wrapMode: Text.WordWrap }
        }

        // Cuentas de tiendas: ManagerStores coloca aquí su lista de cuentas.
        ScrollView {
            visible: settings.manager.storeSettingsOpen
            anchors { left: parent.left; right: parent.right; top: heading.bottom; bottom: parent.bottom; leftMargin: 28; rightMargin: 16; topMargin: 16; bottomMargin: 12 }
            contentWidth: availableWidth
            clip: true
            Item {
                id: accountHost
                width: Math.min(parent.width, page.contentWidth)
                implicitHeight: settings.stores.accountsHeight
            }
        }

        ScrollView {
            id: scroll
            visible: settings.section !== "stores"
            anchors { left: parent.left; right: parent.right; top: heading.bottom; bottom: parent.bottom; leftMargin: 28; rightMargin: 16; topMargin: 12; bottomMargin: 12 }
            contentWidth: availableWidth
            clip: true
            ScrollBar.horizontal.policy: ScrollBar.AlwaysOff

            Column {
                id: body
                width: Math.min(scroll.availableWidth, page.contentWidth)
                spacing: 0

                // ---- General
                SettingRow {
                    visible: settings.section === "general"
                    title: qsTr("Idioma de Omnia")
                    description: qsTr("Se aplica a Desktop, Big Mode y el panel rápido.")
                    ComboBox {
                        id: languageBox
                        width: 200; height: 34
                        model: [qsTr("Español"), qsTr("English")]
                        currentIndex: settings.api.language === "en" ? 1 : 0
                        onActivated: index => settings.api.setLanguage(index === 1 ? "en" : "es", function(status, body) {
                            if (status === 200) settings.api.notify(qsTr("Idioma actualizado."))
                            else settings.saved(status, body)
                        })
                        contentItem: Text { leftPadding: 12; rightPadding: 26; text: languageBox.displayText; color: Theme.color.ink; font.family: Theme.font.family; font.pixelSize: Theme.font.size.body; verticalAlignment: Text.AlignVCenter }
                        background: Rectangle { radius: Theme.radius.sm; color: Theme.color.inset; border.color: languageBox.activeFocus ? Theme.color.accent : Theme.color.glassBorder }
                    }
                }
                SettingRow {
                    visible: settings.section === "general"
                    divider: false
                    title: qsTr("Buscar actualizaciones de ports")
                    description: qsTr("Avisa cuando un port instalado desde el catálogo tiene una versión nueva. Nunca se actualiza sin confirmar.")
                    SettingSwitch { value: settings.api.updateCheck; onChangeRequested: v => settings.api.setUpdateCheck(v, settings.saved) }
                }

                // ---- Biblioteca y carpetas
                SettingRow {
                    visible: settings.section === "library"
                    title: qsTr("Carpeta predeterminada de instalación")
                    description: settings.api.installRoot || qsTr("Sin configurar; elige una ubicación.")
                    PillButton { icon: "folder-open"; text: qsTr("Elegir carpeta"); onClicked: settings.chooseInstallFolder() }
                }
                SettingRow {
                    visible: settings.section === "library"
                    title: qsTr("Mostrar juegos ocultos")
                    description: qsTr("Incluye en Instalados los juegos que ocultaste. Solo durante esta sesión.")
                    SettingSwitch { value: settings.manager.showHiddenGames; onChangeRequested: v => settings.manager.showHiddenGames = v }
                }
                Column {
                    visible: settings.section === "library"
                    width: parent.width
                    topPadding: 18
                    spacing: 10
                    Text { text: qsTr("Carpetas de la biblioteca"); color: Theme.color.ink; font.family: Theme.font.family; font.pixelSize: Theme.font.size.bodyLarge; font.weight: Font.DemiBold }
                    Text { width: parent.width; text: qsTr("Añade tus carpetas de juegos y ROMs: Omnia las detecta solas, sin elegir emulador. Retirar una carpeta no elimina los archivos."); color: Theme.color.muted; font.family: Theme.font.family; font.pixelSize: Theme.font.size.small + 1; wrapMode: Text.WordWrap }
                    Row {
                        width: parent.width
                        spacing: 8
                        TextField {
                            id: rootInput
                            width: parent.width - browse.width - addRoot.width - 16; height: Theme.size.control
                            placeholderText: qsTr("Ruta, por ejemplo /mnt/JUEGOS/Ports")
                            placeholderTextColor: Theme.color.muted
                            text: settings.manager.rootPath
                            onTextEdited: settings.manager.rootPath = text
                            onAccepted: if (settings.manager.rootPath.trim()) settings.manager.changeRoot("add", settings.manager.rootPath.trim())
                            color: Theme.color.ink; font.family: Theme.font.family; font.pixelSize: Theme.font.size.body
                            background: Rectangle { radius: Theme.radius.sm; color: Theme.color.inset; border.color: rootInput.activeFocus ? Theme.color.accent : Theme.color.glassBorder }
                        }
                        PillButton { id: browse; icon: "folder-open"; implicitWidth: Theme.size.control; onClicked: libraryFolderDialog.open() }
                        PillButton { id: addRoot; primary: true; text: qsTr("Añadir carpeta"); enabled: settings.manager.rootPath.trim().length > 0
                            onClicked: settings.manager.changeRoot("add", settings.manager.rootPath.trim()) }
                    }
                    Text { visible: settings.manager.libraryRoots.length === 0; text: qsTr("Aún no has añadido carpetas externas."); color: Theme.color.muted; font.family: Theme.font.family; font.pixelSize: Theme.font.size.body }
                    Repeater {
                        model: settings.section === "library" ? settings.manager.libraryRoots : []
                        delegate: Rectangle {
                            id: rootEntry
                            required property string modelData
                            width: parent.width; height: 50; radius: Theme.radius.sm
                            color: Theme.color.inset; border.color: Theme.color.glassBorder
                            LucideIcon { x: 14; anchors.verticalCenter: parent.verticalCenter; width: 18; height: 18; name: "folder"; color: Theme.color.accentLight }
                            Text { anchors { left: parent.left; leftMargin: 44; right: removeRoot.left; rightMargin: 10; verticalCenter: parent.verticalCenter }
                                text: rootEntry.modelData; color: Theme.color.ink; font.family: Theme.font.family; font.pixelSize: Theme.font.size.body; elide: Text.ElideMiddle }
                            PillButton { id: removeRoot; anchors { right: parent.right; rightMargin: 8; verticalCenter: parent.verticalCenter }
                                implicitHeight: 32; text: qsTr("Retirar"); onClicked: settings.manager.changeRoot("remove", rootEntry.modelData) }
                        }
                    }
                    Text { visible: !!settings.manager.rootsMessage; width: parent.width; text: settings.manager.rootsMessage; color: Theme.color.warning; font.family: Theme.font.family; font.pixelSize: Theme.font.size.small + 1; wrapMode: Text.WordWrap }
                }

                // ---- Juegos y rendimiento
                SettingRow {
                    visible: settings.section === "games"
                    divider: false
                    title: qsTr("Monitor de rendimiento en los juegos")
                    description: settings.api.mangohudInstalled
                        ? qsTr("Muestra FPS, GPU, CPU, VRAM y RAM en una sola línea, con el estilo de Omnia, sobre los juegos que lanzas desde aquí.")
                        : qsTr("Necesita MangoHud: instálalo desde el gestor de paquetes.")
                    SettingSwitch {
                        value: settings.api.mangohud
                        enabled: settings.api.mangohudInstalled || settings.api.mangohud
                        onChangeRequested: v => settings.api.setMangohud(v, settings.saved)
                    }
                }

                // ---- Novedades
                Repeater {
                    model: settings.section === "news" ? [
                        { k: "steam", l: "Steam", d: qsTr("Ofertas, lanzamientos y noticias de tus juegos de Steam.") },
                        { k: "epic", l: "Epic Games", d: qsTr("Juegos gratis de la semana y los que vienen, y noticias de la tienda.") },
                        { k: "gog", l: "GOG", d: qsTr("Ofertas del catálogo y noticias de GOG.") },
                        { k: "amazon", l: "Amazon", d: qsTr("Noticias de Amazon Games.") },
                        { k: "omnia", l: "Omnia", d: qsTr("Ports nuevos del catálogo y actualizaciones de tus ports.") }
                    ] : []
                    delegate: SettingRow {
                        id: newsRow
                        required property var modelData
                        required property int index
                        title: modelData.l
                        description: modelData.d
                        divider: index < 4
                        SettingSwitch {
                            value: (settings.api.newsStores || []).indexOf(newsRow.modelData.k) >= 0
                            onChangeRequested: v => {
                                const now = (settings.api.newsStores || []).filter(s => s !== newsRow.modelData.k)
                                settings.api.setNewsStores(v ? now.concat([newsRow.modelData.k]) : now, settings.saved)
                            }
                        }
                    }
                }

                // ---- Apariencia
                SettingRow {
                    visible: settings.section === "appearance"
                    divider: false
                    title: qsTr("Efecto cristal")
                    description: qsTr("Desenfoca el fondo detrás de los paneles. Apagado, los paneles se ven casi opacos y la app usa menos GPU. Mientras un juego está abierto se apaga solo.")
                    SettingSwitch { value: settings.api.glassEffect; onChangeRequested: v => settings.api.setGlassEffect(v, settings.saved) }
                }

                // ---- Big Mode
                SettingRow {
                    visible: settings.section === "bigmode"
                    title: qsTr("Fondo animado")
                    description: qsTr("Constelación en el Inicio y ondas en la Biblioteca de Big Mode.")
                    SettingSwitch { value: settings.api.animatedBackground; onChangeRequested: v => settings.api.setAnimatedBackground(v, settings.saved) }
                }
                SettingRow {
                    visible: settings.section === "bigmode"
                    title: qsTr("Animación de bienvenida")
                    description: qsTr("Se reproduce al abrir Big Mode.")
                    SettingSwitch { value: settings.api.introEnabled; onChangeRequested: v => settings.api.setIntro(v, settings.saved) }
                }
                SettingRow {
                    visible: settings.section === "bigmode"
                    title: qsTr("Sonidos de la interfaz")
                    description: qsTr("Sonidos al moverte y elegir con el mando.")
                    SettingSwitch { value: settings.api.uiSounds; onChangeRequested: v => settings.api.setSounds({ enabled: v }, settings.saved) }
                }
                SettingRow {
                    visible: settings.section === "bigmode"
                    title: qsTr("Volumen de los sonidos")
                    description: settings.api.uiSounds ? "" : qsTr("Los sonidos están apagados.")
                    Row {
                        spacing: 10
                        Slider {
                            id: volume
                            anchors.verticalCenter: parent.verticalCenter
                            width: 180; height: 26
                            implicitHeight: 26
                            from: 0; to: 100; stepSize: 5
                            enabled: settings.api.uiSounds
                            value: settings.api.uiSoundVolume
                            onMoved: volumeSave.restart()
                            background: Rectangle {
                                x: volume.leftPadding; y: volume.topPadding + volume.availableHeight / 2 - height / 2
                                width: volume.availableWidth; height: 4; radius: 2; color: Theme.color.inset
                                Rectangle { width: volume.visualPosition * parent.width; height: parent.height; radius: 2; color: volume.enabled ? Theme.color.accent : Theme.color.muted }
                            }
                            handle: Rectangle {
                                x: volume.leftPadding + volume.visualPosition * (volume.availableWidth - width)
                                y: volume.topPadding + volume.availableHeight / 2 - height / 2
                                width: 18; height: 18; radius: 9
                                color: volume.pressed ? Theme.color.accentLight : Theme.color.ink
                                border.color: Theme.color.accent; border.width: 2
                            }
                        }
                        Text { anchors.verticalCenter: parent.verticalCenter; width: 40; text: Math.round(volume.value) + " %"; color: Theme.color.soft; font.family: Theme.font.numeric; font.pixelSize: Theme.font.size.bodyLarge; font.weight: Font.DemiBold }
                        Timer { id: volumeSave; interval: 300; onTriggered: settings.api.setSounds({ volume: Math.round(volume.value) }, settings.saved) }
                    }
                }
                SettingRow {
                    visible: settings.section === "bigmode" && settings.api.uiSoundPacks.length > 1
                    title: qsTr("Paquete de sonidos")
                    ComboBox {
                        id: packBox
                        width: 200; height: 34
                        model: settings.api.uiSoundPacks.map(p => p.label || p.id)
                        currentIndex: Math.max(0, settings.api.uiSoundPacks.findIndex(p => p.id === settings.api.uiSoundPack))
                        onActivated: index => settings.api.setSounds({ pack: settings.api.uiSoundPacks[index].id }, settings.saved)
                        contentItem: Text { leftPadding: 12; rightPadding: 26; text: packBox.displayText; color: Theme.color.ink; font.family: Theme.font.family; font.pixelSize: Theme.font.size.body; verticalAlignment: Text.AlignVCenter; elide: Text.ElideRight }
                        background: Rectangle { radius: Theme.radius.sm; color: Theme.color.inset; border.color: packBox.activeFocus ? Theme.color.accent : Theme.color.glassBorder }
                    }
                }
                SettingRow {
                    visible: settings.section === "bigmode"
                    divider: false
                    title: qsTr("Abrir Big Mode")
                    description: qsTr("A pantalla completa, para jugar con mando.")
                    PillButton { primary: true; icon: "gamepad-2"; text: qsTr("Abrir"); onClicked: settings.manager.openBigMode() }
                }

                // ---- Acerca de
                Row {
                    visible: settings.section === "about"
                    topPadding: 8
                    spacing: 20
                    Image { width: 72; height: 72; source: Qt.resolvedUrl("images/omnia-mark.svg"); sourceSize.height: 192; fillMode: Image.PreserveAspectFit }
                    Column {
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 5
                        Text { text: "Omnia Game Suite" + (settings.api.suiteUpdate && settings.api.suiteUpdate.current ? "  " + settings.api.suiteUpdate.current : "")
                            color: Theme.color.ink; font.family: Theme.font.family; font.pixelSize: Theme.font.size.heading - 2; font.weight: Font.DemiBold }
                        Text { text: qsTr("Biblioteca de juegos y Big Mode para Linux."); color: Theme.color.muted; font.family: Theme.font.family; font.pixelSize: Theme.font.size.body }
                        Text { width: body.width - 92; text: qsTr("Los juegos y sus archivos viven en este equipo; Omnia no incluye ni descarga ROMs."); color: Theme.color.muted; font.family: Theme.font.family; font.pixelSize: Theme.font.size.body; wrapMode: Text.WordWrap }
                    }
                }
            }
        }
    }

    FolderDialog {
        id: libraryFolderDialog
        title: qsTr("Añadir carpeta de juegos")
        onAccepted: {
            const path = selectedFolder.toString().replace(/^file:\/\//, "")
            settings.manager.rootPath = decodeURIComponent(path)
        }
    }
}

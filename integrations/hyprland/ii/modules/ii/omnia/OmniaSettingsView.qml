pragma ComponentBehavior: Bound

import qs.services
import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import QtQuick.Layouts
import Quickshell

/**
 * Ajustes de Omnia dentro del panel: grupos con título y tarjeta, filas con descripción y control,
 * interruptores y selectores segmentados.
 */
Flickable {
    id: view
    clip: true
    contentWidth: width
    contentHeight: body.implicitHeight
    boundsBehavior: Flickable.StopAtBounds
    interactive: contentHeight > height

    readonly property color ink: OmniaTheme.ink
    // en el panel ancho los ajustes no se estiran: columna centrada
    property bool reveal: false


    ColumnLayout {
        id: body
        width: Math.min(view.width, 560)
        x: (view.width - width) / 2
        spacing: 14

        // ================= Imágenes =================
        ColumnLayout {
            Layout.fillWidth: true
            spacing: 6
            StyledText {
                text: OmniaApi.tr("Imágenes", "Images")
                font.pixelSize: Appearance.font.pixelSize.normal
                font.weight: Font.Bold
                color: OmniaTheme.ink
            }
            Rectangle {
                Layout.fillWidth: true
                implicitHeight: artworkCol.implicitHeight + 28
                radius: 16
                color: OmniaTheme.card(OmniaSettings.blur)
                border.width: 1
                border.color: Qt.rgba(1, 1, 1, 0.08)
                ColumnLayout {
                    id: artworkCol
                    anchors { fill: parent; margins: 14 }
                    spacing: 6
                    StyledText {
                        Layout.fillWidth: true
                        text: OmniaApi.tr("Artwork gestionado por Omnia", "Artwork managed by Omnia")
                        font.weight: Font.DemiBold
                        color: OmniaTheme.ink
                    }
                    StyledText {
                        Layout.fillWidth: true
                        text: OmniaApi.tr("Las portadas, fondos y logos publicados se cargan desde omnia-backend. No necesitas una clave API de proveedor.", "Published covers, backgrounds, and logos come from omnia-backend. No provider API key is required.")
                        font.pixelSize: Appearance.font.pixelSize.smaller
                        color: OmniaTheme.inkDim
                        wrapMode: Text.Wrap
                    }
                }
            }
        }

        // ================= Activación =================
        ColumnLayout {
            Layout.fillWidth: true
            spacing: 6
            StyledText { text: OmniaApi.tr("Activación", "Activation"); font.pixelSize: Appearance.font.pixelSize.normal; font.weight: Font.Bold; color: OmniaTheme.ink }
            Rectangle {
                Layout.fillWidth: true
                implicitHeight: actCol.implicitHeight + 28
                radius: 16
                color: OmniaTheme.card(OmniaSettings.blur)
                border.width: 1
                border.color: Qt.rgba(1, 1, 1, 0.08)
                ColumnLayout {
                    id: actCol
                    anchors { fill: parent; margins: 14 }
                    spacing: 12

                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 6
                        StyledText { text: OmniaApi.tr("Abrir el panel desde", "Open the panel from"); font.weight: Font.DemiBold; color: OmniaTheme.ink }
                        OmniaSegmented {
                            Layout.fillWidth: true
                            options: [{ label: OmniaApi.tr("Barra superior", "Top bar"), value: "bar" }, { label: OmniaApi.tr("Borde de pantalla", "Screen edge"), value: "edge" }, { label: OmniaApi.tr("Ambos", "Both"), value: "both" }]
                            current: OmniaSettings.activation
                            onPicked: v => OmniaSettings.set("activation", v)
                        }
                    }
                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 6
                        visible: OmniaSettings.edgeEnabled
                        StyledText { text: OmniaApi.tr("Borde", "Edge"); font.weight: Font.DemiBold; color: OmniaTheme.ink }
                        OmniaSegmented {
                            Layout.fillWidth: true
                            options: [{ label: OmniaApi.tr("Izquierdo", "Left"), value: "left" }, { label: OmniaApi.tr("Derecho", "Right"), value: "right" }, { label: OmniaApi.tr("Superior", "Top"), value: "top" }, { label: OmniaApi.tr("Inferior", "Bottom"), value: "bottom" }]
                            current: OmniaSettings.edgeSide
                            onPicked: v => OmniaSettings.set("edgeSide", v)
                        }
                    }
                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 6
                        visible: OmniaSettings.edgeEnabled
                        StyledText { text: OmniaApi.tr("Posición en el borde", "Position at edge"); font.weight: Font.DemiBold; color: OmniaTheme.ink }
                        OmniaSegmented {
                            Layout.fillWidth: true
                            options: [{ label: OmniaApi.tr("Inicio", "Start"), value: "start" }, { label: OmniaApi.tr("Centro", "Center"), value: "center" }, { label: OmniaApi.tr("Fin", "End"), value: "end" }]
                            current: OmniaSettings.edgePosition
                            onPicked: v => OmniaSettings.set("edgePosition", v)
                        }
                    }
                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 6
                        visible: OmniaSettings.edgeEnabled
                        StyledText { text: OmniaApi.tr("Retraso al acercar el puntero", "Pointer activation delay"); font.weight: Font.DemiBold; color: OmniaTheme.ink }
                        OmniaSegmented {
                            Layout.fillWidth: true
                            options: [{ label: "150 ms", value: 150 }, { label: "300 ms", value: 300 }, { label: "500 ms", value: 500 }, { label: "800 ms", value: 800 }]
                            current: OmniaSettings.revealDelayMs
                            onPicked: v => OmniaSettings.set("revealDelayMs", v)
                        }
                    }
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 10
                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 2
                            StyledText { text: OmniaApi.tr("Desenfoque del escritorio", "Desktop blur"); font.weight: Font.DemiBold; color: OmniaTheme.ink }
                            StyledText {
                                Layout.fillWidth: true
                                text: OmniaApi.tr("Translucidez con desenfoque de Hyprland. Sin él, el panel es casi opaco.", "Translucency uses Hyprland blur. With blur disabled, the panel is nearly opaque.")
                                font.pixelSize: Appearance.font.pixelSize.smaller
                                color: OmniaTheme.inkDim
                                wrapMode: Text.Wrap
                            }
                        }
                        OmniaSwitch { checked: OmniaSettings.blur; onToggled: v => OmniaSettings.set("blur", v) }
                    }
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 10
                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 2
                            StyledText { text: OmniaApi.tr("Preguntar al conectar un mando", "Prompt when a controller connects"); font.weight: Font.DemiBold; color: OmniaTheme.ink }
                            StyledText {
                                Layout.fillWidth: true
                                text: OmniaApi.tr("Al conectar un mando aparece «¿Abrir Omnia?»: A abre Big Mode y B lo descarta.", "Connecting a controller shows an Open Omnia prompt. A opens Big Mode and B dismisses it.")
                                font.pixelSize: Appearance.font.pixelSize.smaller
                                color: OmniaTheme.inkDim
                                wrapMode: Text.Wrap
                            }
                        }
                        OmniaSwitch { checked: OmniaSettings.padPrompt; onToggled: v => OmniaSettings.set("padPrompt", v) }
                    }
                }
            }
        }

        StyledText {
            Layout.fillWidth: true
            Layout.bottomMargin: 4
            horizontalAlignment: Text.AlignHCenter
            text: OmniaApi.tr("Omnia · núcleo ", "Omnia · core ") + (OmniaApi.status === "error" ? OmniaApi.tr("desconectado", "disconnected") : OmniaApi.tr("conectado", "connected")) + OmniaApi.tr(" · ajustes en ~/.config/omnia", " · settings in ~/.config/omnia")
            font.pixelSize: Appearance.font.pixelSize.smaller
            color: OmniaTheme.inkDim
        }
    }
}

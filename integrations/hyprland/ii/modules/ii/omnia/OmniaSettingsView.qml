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
                text: "Imágenes"
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
                        text: "Artwork gestionado por Omnia"
                        font.weight: Font.DemiBold
                        color: OmniaTheme.ink
                    }
                    StyledText {
                        Layout.fillWidth: true
                        text: "Las portadas, fondos y logos publicados se cargan desde omnia-backend. No necesitas una clave API de proveedor."
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
            StyledText { text: "Activación"; font.pixelSize: Appearance.font.pixelSize.normal; font.weight: Font.Bold; color: OmniaTheme.ink }
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
                        StyledText { text: "Abrir el panel desde"; font.weight: Font.DemiBold; color: OmniaTheme.ink }
                        OmniaSegmented {
                            Layout.fillWidth: true
                            options: [{ label: "Barra superior", value: "bar" }, { label: "Borde de pantalla", value: "edge" }, { label: "Ambos", value: "both" }]
                            current: OmniaSettings.activation
                            onPicked: v => OmniaSettings.set("activation", v)
                        }
                    }
                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 6
                        visible: OmniaSettings.edgeEnabled
                        StyledText { text: "Borde"; font.weight: Font.DemiBold; color: OmniaTheme.ink }
                        OmniaSegmented {
                            Layout.fillWidth: true
                            options: [{ label: "Izquierdo", value: "left" }, { label: "Derecho", value: "right" }, { label: "Superior", value: "top" }, { label: "Inferior", value: "bottom" }]
                            current: OmniaSettings.edgeSide
                            onPicked: v => OmniaSettings.set("edgeSide", v)
                        }
                    }
                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 6
                        visible: OmniaSettings.edgeEnabled
                        StyledText { text: "Posición en el borde"; font.weight: Font.DemiBold; color: OmniaTheme.ink }
                        OmniaSegmented {
                            Layout.fillWidth: true
                            options: [{ label: "Inicio", value: "start" }, { label: "Centro", value: "center" }, { label: "Fin", value: "end" }]
                            current: OmniaSettings.edgePosition
                            onPicked: v => OmniaSettings.set("edgePosition", v)
                        }
                    }
                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 6
                        visible: OmniaSettings.edgeEnabled
                        StyledText { text: "Retraso al acercar el puntero"; font.weight: Font.DemiBold; color: OmniaTheme.ink }
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
                            StyledText { text: "Desenfoque del escritorio"; font.weight: Font.DemiBold; color: OmniaTheme.ink }
                            StyledText {
                                Layout.fillWidth: true
                                text: "Translucidez con desenfoque de Hyprland. Sin él, el panel es casi opaco."
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
                            StyledText { text: "Preguntar al conectar un mando"; font.weight: Font.DemiBold; color: OmniaTheme.ink }
                            StyledText {
                                Layout.fillWidth: true
                                text: "Al conectar un mando aparece «¿Abrir Omnia?»: A abre Big Mode y B lo descarta."
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
            text: "Omnia · núcleo " + (OmniaApi.status === "error" ? "desconectado" : "conectado") + " · ajustes en ~/.config/omnia"
            font.pixelSize: Appearance.font.pixelSize.smaller
            color: OmniaTheme.inkDim
        }
    }
}

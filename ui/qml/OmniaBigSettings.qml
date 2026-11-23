pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls

/** Ajustes de Big Mode: idioma, biblioteca local y conexión con los servicios públicos de Omnia. */
Item {
    id: set
    required property var host
    signal back()
    readonly property real s: set.host.s
    property string msg: ""

    Keys.onEscapePressed: back()
    Rectangle { anchors.fill: parent; color: set.host.base }
    Rectangle {
        id: backB
        x: set.s * 48; y: set.s * 30
        width: bRow.implicitWidth + set.s * 44; height: set.s * 54; radius: height / 2
        color: Qt.rgba(0.05, 0.08, 0.12, 0.70); border.width: 1; border.color: Qt.rgba(1, 1, 1, 0.26)
        Row {
            id: bRow; anchors.centerIn: parent; spacing: set.s * 10
            LucideIcon { width: set.s * 26; height: set.s * 26; name: "chevron-left"; color: set.host.ink; anchors.verticalCenter: parent.verticalCenter }
            Text { text: qsTr("Volver"); color: set.host.ink; font.family: set.host.uiFont; font.pixelSize: set.s * 24; anchors.verticalCenter: parent.verticalCenter }
        }
        MouseArea { anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: set.back() }
    }
    PadBattery {
        api: set.host.api; uiScale: set.s; uiFont: set.host.uiFont; ink: set.host.ink; muted: set.host.ink2
        anchors { right: parent.right; rightMargin: set.s * 48; verticalCenter: backB.verticalCenter }
    }
    Text { anchors { left: backB.right; leftMargin: set.s * 22; verticalCenter: backB.verticalCenter } text: qsTr("Ajustes"); color: set.host.ink; font.family: set.host.uiFont; font.pixelSize: set.s * 36; font.weight: Font.Medium }

    Column {
        anchors { left: parent.left; right: parent.right; top: backB.bottom; leftMargin: set.s * 48; rightMargin: set.s * 48; topMargin: set.s * 28 }
        spacing: set.s * 18
        Text { text: qsTr("Aplicación"); color: set.host.ink2; font.family: set.host.uiFont; font.pixelSize: set.s * 22; font.weight: Font.DemiBold }
        Rectangle {
            width: parent.width; height: set.s * 132; radius: set.s * 22
            color: Qt.rgba(0.082, 0.114, 0.153, 0.92); border.width: 1; border.color: Qt.rgba(1, 1, 1, 0.10)
            Column {
                anchors { left: parent.left; verticalCenter: parent.verticalCenter; leftMargin: set.s * 24 }
                Text { text: qsTr("Idioma"); color: set.host.ink; font.family: set.host.uiFont; font.pixelSize: set.s * 26; font.weight: Font.DemiBold }
                Text { text: qsTr("Los textos de Omnia se mostrarán en el idioma seleccionado."); color: set.host.ink2; font.family: set.host.uiFont; font.pixelSize: set.s * 19 }
            }
            ComboBox {
                anchors { right: parent.right; verticalCenter: parent.verticalCenter; rightMargin: set.s * 24 }
                width: set.s * 230; model: [qsTr("Español"), "English"]
                currentIndex: set.host.api.language === "en" ? 1 : 0
                onActivated: function(index) {
                    set.host.api.setLanguage(index === 1 ? "en" : "es", function(status, body) {
                        set.msg = status === 200 ? qsTr("Idioma guardado.") : ((body && body.error) || qsTr("No se pudo guardar el idioma."))
                    })
                }
            }
        }
        Text { visible: !!set.msg; text: set.msg; color: set.host.ink2; font.family: set.host.uiFont; font.pixelSize: set.s * 20 }

        Rectangle {
            width: parent.width; height: set.s * 132; radius: set.s * 22
            color: Qt.rgba(0.082, 0.114, 0.153, 0.92); border.width: 1; border.color: Qt.rgba(1, 1, 1, 0.10)
            Column {
                anchors { left: parent.left; verticalCenter: parent.verticalCenter; leftMargin: set.s * 24 }
                Text { text: qsTr("Fondo animado"); color: set.host.ink; font.family: set.host.uiFont; font.pixelSize: set.s * 26; font.weight: Font.DemiBold }
                Text { text: qsTr("Puntos y líneas con los colores del juego. Se detiene mientras juegas."); color: set.host.ink2; font.family: set.host.uiFont; font.pixelSize: set.s * 19 }
            }
            Switch {
                anchors { right: parent.right; verticalCenter: parent.verticalCenter; rightMargin: set.s * 24 }
                scale: set.s * 1.4
                checked: set.host.api.animatedBackground
                onToggled: set.host.api.setAnimatedBackground(checked, function(status, body) {
                    set.msg = status === 200 ? qsTr("Ajuste guardado.") : ((body && body.error) || qsTr("No se pudo guardar el ajuste."))
                })
            }
        }

        Text { text: qsTr("Biblioteca"); color: set.host.ink2; font.family: set.host.uiFont; font.pixelSize: set.s * 22; font.weight: Font.DemiBold }
        Rectangle {
            width: parent.width; height: set.s * 132; radius: set.s * 22
            color: Qt.rgba(0.082, 0.114, 0.153, 0.92); border.width: 1; border.color: Qt.rgba(1, 1, 1, 0.10)
            Column {
                anchors { left: parent.left; verticalCenter: parent.verticalCenter; leftMargin: set.s * 24 }
                Text { text: qsTr("Sincronizar juegos"); color: set.host.ink; font.family: set.host.uiFont; font.pixelSize: set.s * 26; font.weight: Font.DemiBold }
                Text { text: qsTr("El catálogo y las imágenes publicados se consultan desde Omnia Backend."); color: set.host.ink2; font.family: set.host.uiFont; font.pixelSize: set.s * 19 }
            }
            Rectangle {
                anchors { right: parent.right; verticalCenter: parent.verticalCenter; rightMargin: set.s * 24 }
                width: set.s * 200; height: set.s * 58; radius: height / 2; color: set.host.accent
                Text { anchors.centerIn: parent; text: qsTr("Buscar juegos"); color: set.host.ink; font.family: set.host.uiFont; font.pixelSize: set.s * 21 }
                MouseArea { anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: set.host.api.call("POST", "/library/refresh", function(status) { set.host.api.refresh(); set.host.api.notify(status === 200 ? qsTr("Biblioteca actualizada.") : qsTr("No se pudo actualizar la biblioteca.")) }) }
            }
        }
    }
}

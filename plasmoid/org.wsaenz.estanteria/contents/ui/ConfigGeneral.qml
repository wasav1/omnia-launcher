import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts
import org.kde.kirigami as Kirigami

Kirigami.FormLayout {
    id: page
    property alias cfg_clearance: clearance.value
    property alias cfg_film: film.value
    property alias cfg_blur: blur.value
    property alias cfg_pan: pan.checked
    property string cfg_helperUrl

    QQC2.SpinBox {
        id: clearance
        Kirigami.FormData.label: "Margen sobre el dock (px del escritorio):"
        from: 0
        to: 400
        stepSize: 4
    }
    QQC2.Slider {
        id: film
        Kirigami.FormData.label: "Película sobre el fondo (%):"
        from: 0
        to: 90
        stepSize: 5
    }
    QQC2.CheckBox {
        id: pan
        Kirigami.FormData.label: "Fondo en movimiento:"
        text: "Desplazar lentamente el fondo (consume más GPU)"
    }
    QQC2.Slider {
        id: blur
        Kirigami.FormData.label: "Desenfoque del fondo:"
        from: 0
        to: 64
        stepSize: 4
    }
    QQC2.Label {
        text: "Difumina los fondos de los juegos. 0 = nítidos."
        wrapMode: Text.WordWrap
        Layout.maximumWidth: Kirigami.Units.gridUnit * 24
        opacity: 0.7
    }
    QQC2.Label {
        text: "Oscurece y apaga los colores del fondo para que no se vea tan vivo. 0 = sin película."
        wrapMode: Text.WordWrap
        Layout.maximumWidth: Kirigami.Units.gridUnit * 24
        opacity: 0.7
    }
    QQC2.Label {
        text: "Es la distancia desde el borde inferior del widget hasta la base de las portadas. Súbela si tu dock crece."
        wrapMode: Text.WordWrap
        Layout.maximumWidth: Kirigami.Units.gridUnit * 24
        opacity: 0.7
    }
}

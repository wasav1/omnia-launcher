import QtQuick
import "Theme.js" as Theme

/** Fila de Ajustes (rediseño D): título y descripción a la izquierda, control a la derecha.
 *  El control va como hijo:  SettingRow { title: "…"; description: "…"; Switch { … } } */
Item {
    id: row
    property string title: ""
    property string description: ""
    property bool divider: true
    default property alias control: slot.data

    width: parent ? parent.width : 400
    implicitHeight: Math.max(64, texts.implicitHeight + 28, slot.childrenRect.height + 24)
    height: implicitHeight

    Column {
        id: texts
        anchors { left: parent.left; right: slot.left; rightMargin: 20; verticalCenter: parent.verticalCenter }
        spacing: 3
        Text { width: parent.width; text: row.title; color: Theme.color.ink; font.family: Theme.font.family; font.pixelSize: Theme.font.size.bodyLarge; font.weight: Font.DemiBold; wrapMode: Text.WordWrap }
        Text { visible: !!row.description; width: parent.width; text: row.description; color: Theme.color.muted; font.family: Theme.font.family; font.pixelSize: Theme.font.size.small + 1; wrapMode: Text.WordWrap; lineHeight: 1.1 }
    }
    Item {
        id: slot
        anchors { right: parent.right; verticalCenter: parent.verticalCenter }
        width: childrenRect.width
        height: childrenRect.height
    }
    Rectangle { visible: row.divider; anchors { left: parent.left; right: parent.right; bottom: parent.bottom } height: 1; color: Theme.color.glassBorder }
}

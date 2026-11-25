import QtQuick

Rectangle {
    id: track
    property real percent: 0
    property color ink: "#6ADCD6"
    height: 5
    radius: height / 2
    color: "#32FFFFFF"

    Rectangle {
        width: parent.width * Math.min(100, Math.max(0, track.percent)) / 100
        height: parent.height
        radius: height / 2
        color: track.ink
        Behavior on width { NumberAnimation { duration: 180 } }
    }
}

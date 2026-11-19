import QtQuick

LucideIcon {
    property string kind: "play"
    name: kind === "prev" ? "skip-back" : kind === "next" ? "skip-forward" : kind
    width: 24
    height: 24
    color: "#f3efe3"
}

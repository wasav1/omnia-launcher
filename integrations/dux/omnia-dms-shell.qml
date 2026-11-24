// Instancia separada que solo carga el panel rápido de Omnia bajo DUX.
import qs.modules.common
import qs.services
import qs.modules.ii.omnia
import QtQuick
import Quickshell

ShellRoot {
    Component.onCompleted: MaterialThemeLoader.reapplyTheme()
    OmniaEdge {}
}

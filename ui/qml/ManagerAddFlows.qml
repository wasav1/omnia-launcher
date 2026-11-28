pragma ComponentBehavior: Bound

import QtQuick

/** Asistente para añadir juegos e importación, con estado en el gestor anfitrión. */
Item {
    id: addFlows
    required property var manager
    required property var api

    Loader {
        anchors.fill: parent
        active: addFlows.manager.addWizardOpen || addFlows.manager.importPanelOpen
        sourceComponent: addFlows.manager.importPanelOpen ? importComponent : addGameComponent
    }
    Component {
        id: addGameComponent
        ManagerAddGame {
            manager: addFlows.manager
            api: addFlows.api
            onFinished: addFlows.manager.addWizardOpen = false
            onAdded: function(id) {
                addFlows.manager.addWizardOpen = false
                addFlows.api.refresh()
                addFlows.manager.openGameInLibrary({id: id})
                addFlows.api.notify(qsTranslate("OmniaManager", "Juego añadido a la biblioteca."))
            }
            onAddedMany: function(count) {
                addFlows.manager.addWizardOpen = false
                addFlows.api.refresh()
                addFlows.api.notify(qsTranslate("OmniaManager", "%1 juegos añadidos a la biblioteca.").arg(count))
            }
            onImportRequested: function(path) {
                addFlows.manager.importPath = path
                addFlows.manager.addWizardOpen = false
                addFlows.manager.importPanelOpen = true
            }
        }
    }
    Component {
        id: importComponent
        ImportPanel {
            api: addFlows.api
            path: addFlows.manager.importPath
            onFinished: addFlows.manager.importPanelOpen = false
            onImported: {
                addFlows.manager.importPanelOpen = false
                addFlows.api.refresh()
            }
        }
    }
}

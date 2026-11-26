pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls

/** Confirmaciones de actualización, desinstalación y retiro de biblioteca. */
Item {
    id: confirmations
    required property var manager
    required property var api
    required property var gameActions
    property var updateGame: null
    property string removeGameId: ""
    property var removePreview: null
    property string unlinkGameId: ""
    readonly property var removalGame: api.games.find(game => game.id === removeGameId)

    function updateFor(game) {
        if (!game || !game.updateAvailable) return
        updateGame = game
        updateDialog.open()
    }
    function askUninstallFor(game) {
        if (!game || !game.id) return
        const id = game.id
        removeGameId = id
        removePreview = null
        api.removalPreview(id, (status, body) => {
            if (removeGameId !== id) return
            if (status !== 200) { gameActions.removalResult(api, status, body); return }
            removePreview = body
            uninstallDialog.open()
        })
    }
    function unlinkGame(game) {
        if (!game || !game.id) return
        unlinkGameId = game.id
        unlinkGameDialog.open()
    }
    Dialog {
        id: updateDialog
        modal: true
        anchors.centerIn: parent
        title: qsTranslate("OmniaManager", "Actualizar port")
        standardButtons: Dialog.Yes | Dialog.Cancel
        Label {
            width: confirmations.manager.s * 460; wrapMode: Text.WordWrap
            text: confirmations.updateGame && confirmations.updateGame.updateAvailable
                  ? qsTranslate("OmniaManager", "%1: %2 → %3 (%4 MB, %5).\nSe verifica su SHA-256 y se superpone sobre la carpeta actual; tus partidas y los archivos que el port preparó se conservan. Algunos ports rehacen su preparación (compilar el juego, shaders) la primera vez que se abren tras actualizar. Cierra el juego antes de actualizar.")
                        .arg(confirmations.updateGame.name).arg(confirmations.updateGame.updateAvailable.current || "?").arg(confirmations.updateGame.updateAvailable.version)
                        .arg(Math.round((confirmations.updateGame.updateAvailable.sizeBytes || 0) / 1048576)).arg(confirmations.updateGame.updateAvailable.sourceName || "")
                  : ""
        }
        onAccepted: confirmations.api.updateInstallation(confirmations.updateGame.id, function(status, body) {
            if (status === 200) { confirmations.api.notify(qsTranslate("OmniaManager", "Actualización iniciada: %1").arg(confirmations.updateGame.name)); confirmations.manager.loadInstallations() }
            else confirmations.api.notify((body && body.error) || qsTranslate("OmniaManager", "No se pudo iniciar la actualización."))
        })
    }
    Dialog {
        id: uninstallDialog
        modal: true
        anchors.centerIn: Overlay.overlay
        implicitWidth: Math.max(1, Math.min(confirmations.manager.width - confirmations.manager.s * 28, confirmations.manager.s * 540))
        title: confirmations.removalGame ? qsTranslate("OmniaManager", "Desinstalar %1").arg(confirmations.removalGame.name) : qsTranslate("OmniaManager", "Desinstalar juego")
        standardButtons: Dialog.Yes | Dialog.Cancel
        onOpened: standardButton(Dialog.Cancel).forceActiveFocus()
        contentItem: Label { text: confirmations.gameActions.uninstallText(confirmations.removePreview); wrapMode: Text.Wrap; textFormat: Text.PlainText }
        onAccepted: confirmations.api.removeInstallation(confirmations.removeGameId, confirmations.removePreview.path, function(status, body) {
            if (status === 200) { confirmations.removeGameId = ""; confirmations.manager.loadInstallations(); confirmations.api.refresh() }
            confirmations.gameActions.removalResult(confirmations.api, status, body)
        })
    }
    Dialog {
        id: unlinkGameDialog
        modal: true
        title: qsTranslate("OmniaManager", "Quitar juego de Omnia")
        standardButtons: Dialog.Yes | Dialog.Cancel
        Label { text: qsTranslate("OmniaManager", "El juego dejará de aparecer en Omnia. Sus archivos no se borrarán del disco."); wrapMode: Text.WordWrap }
        onAccepted: confirmations.api.removeGame({id: confirmations.unlinkGameId}, function(status, body) {
            if (status === 200) { confirmations.unlinkGameId = ""; confirmations.api.refresh() }
            else confirmations.api.notify((body && body.error) || qsTranslate("OmniaManager", "No se pudo quitar el juego de Omnia."))
        })
    }
}

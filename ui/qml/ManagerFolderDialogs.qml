pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Dialogs

/** Selectores nativos de carpeta para ROMs y destino de instalación. */
Item {
    id: folderDialogs
    required property var manager
    required property var api

    function openRomFolder() { romFolderDialog.open() }
    function openInstallFolder() { installFolderDialog.open() }

    FolderDialog {
        id: romFolderDialog
        title: qsTranslate("OmniaManager", "Elige la carpeta donde buscar ROMs")
        onAccepted: folderDialogs.manager.scanRomFolder(decodeURIComponent(selectedFolder.toString().replace(/^file:\/\//, "")))
    }
    FolderDialog {
        id: installFolderDialog
        title: qsTranslate("OmniaManager", "Elige la carpeta predeterminada para instalar juegos")
        onAccepted: {
            const path = decodeURIComponent(selectedFolder.toString().replace(/^file:\/\//, ""))
            folderDialogs.api.setInstallRoot(path, function(status, body) {
                if (status === 200) folderDialogs.api.notify(qsTranslate("OmniaManager", "Carpeta de instalación guardada."))
                else folderDialogs.api.notify((body && body.error) || qsTranslate("OmniaManager", "No se pudo guardar la carpeta de instalación."))
            })
        }
    }
}

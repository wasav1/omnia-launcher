import QtQuick

QtObject {
    function entries(game) {
        if (!game) return []
        const actions = []
        if (!game.running) {
            if (game.portAvailable) actions.push({key: "port", label: qsTr("Instalar port"), icon: "download"})
            else actions.push({key: "play", label: qsTr("Jugar"), icon: "play"})
            if (game.updateAvailable) actions.push({key: "update", label: qsTr("Actualizar"), icon: "download"})
        }
        actions.push({key: "details", label: qsTr("Detalles"), icon: "info"},
                     {key: "fav", label: game.fav ? qsTr("Quitar de favoritos") : qsTr("Añadir a favoritos"), icon: "star"},
                     {key: "saves", label: qsTr("Abrir carpeta de partidas"), icon: "folder-open"},
                     {key: "art", label: qsTr("Cambiar arte"), icon: "image"},
                     {key: "hide", label: game.hidden ? qsTr("Mostrar en la biblioteca") : qsTr("Ocultar de la biblioteca"), icon: "eye-off"})
        if (game.installPath || game.folder)
            actions.push({key: "folder", label: qsTr("Abrir carpeta de instalación"), icon: "folder-open"})
        if ((game.canUninstall || game.installPackageId) && !game.running)
            actions.push({key: "uninstall", label: qsTr("Desinstalar juego"), icon: "trash-2"})
        if (game.canUnlink && !game.running)
            actions.push({key: "remove", label: qsTr("Quitar de la biblioteca"), icon: "eye-off"})
        return actions
    }

    function uninstallText(preview) {
        if (!preview || !preview.path) return ""
        const text = qsTr("Omnia borrará la carpeta %1 y su contenido, incluidas las partidas guardadas dentro de ella.").arg(preview.path)
        if (preview.client === "steam") return text + "\n\n" + qsTr("Cierra Steam antes de confirmar.")
        if (preview.client === "heroic") return text + "\n\n" + qsTr("Cierra Heroic antes de confirmar.")
        return text
    }

    function removalResult(api, status, body) {
        if (status !== 200) api.notify(body.error || qsTr("No se pudo desinstalar el juego."))
        else if (body.leftover) api.notify(qsTr("La instalación se retiró. Quedaron archivos en %1.").arg(body.leftover))
        else api.notify(qsTr("Juego desinstalado."))
    }
}

import QtQuick

QtObject {
    function storeOf(game) {
        if (game.storeSource) return game.storeSource
        if (game.src === "Steam") return "steam"
        const tag = String(game.sub || "").toLowerCase()
        return ["epic", "gog", "amazon"].find(store => tag.includes(store)) || ""
    }

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
        if (game.installPackageId && !game.running)
            actions.push({key: "uninstall", label: qsTr("Desinstalar juego"), icon: "trash-2"})
        else if (storeOf(game))
            actions.push({key: "external", label: qsTr("Gestionar en la tienda"), icon: "settings"})
        return actions
    }

    function openExternal(game) {
        if (storeOf(game) === "steam") Qt.openUrlExternally("steam://nav/library")
        else Qt.openUrlExternally("heroic://")
    }

    function uninstallText(path) {
        return path
            ? qsTr("Omnia borrará la carpeta %1 y su contenido, incluidas las partidas guardadas dentro de ella.").arg(path)
            : qsTr("Omnia borrará la carpeta de instalación y su contenido, incluidas las partidas guardadas dentro de ella.")
    }
}

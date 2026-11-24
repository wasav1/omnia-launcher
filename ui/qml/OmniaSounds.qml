pragma ComponentBehavior: Bound

import QtQuick
import QtQml.Models
import QtMultimedia

/** Sonidos de la interfaz de Big Mode. `play("move" | "confirm" | "back" | "menu" | "page" | "error" | "done" | "pad-on" | "pad-off" |
 *  "toggle" | "open" | "close")`. El paquete (carpeta sounds/<paquete>/) y el volumen vienen de los ajustes; con los sonidos apagados,
 *  con volumen 0 o con un juego en marcha (`muted`) no suena nada. */
Item {
    id: sfx
    required property var api
    property bool muted: false
    readonly property var names: ["move", "confirm", "back", "menu", "page", "error", "done", "pad-on", "pad-off", "toggle", "open", "close"]
    readonly property bool audible: sfx.api.uiSounds && !sfx.muted && sfx.api.uiSoundVolume > 0
    property var reg: ({})
    function play(name) {
        if (!sfx.audible) return
        const e = sfx.reg[name]
        if (e && e.status !== SoundEffect.Error) e.play()
    }
    Instantiator {
        model: sfx.names
        delegate: SoundEffect {
            required property string modelData
            source: Qt.resolvedUrl("sounds/" + sfx.api.uiSoundPack + "/" + modelData + ".wav")
            volume: sfx.api.uiSoundVolume / 100
        }
        onObjectAdded: function(index, object) { sfx.reg[sfx.names[index]] = object }
    }
}

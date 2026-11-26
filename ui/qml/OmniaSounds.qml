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
    property string openingSound: ""
    property var names: ["move", "confirm", "back", "menu", "page", "error", "done", "pad-on", "pad-off", "toggle", "open", "close"]
    readonly property bool audible: sfx.api.uiSounds && !sfx.muted && sfx.api.uiSoundVolume > 0
    property var reg: ({})
    property string pendingSound: ""
    signal soundFinished(string name)

    function playWhenReady(name) {
        sfx.pendingSound = name
        sfx.playPendingSound(sfx.reg[name])
    }

    function playPendingSound(effect) {
        if (!sfx.audible || !effect || effect.modelData !== sfx.pendingSound || effect.status !== SoundEffect.Ready)
            return
        sfx.pendingSound = ""
        effect.play()
    }
    function play(name) {
        if (!sfx.audible) return
        const e = sfx.reg[name]
        if (e && e.status !== SoundEffect.Error) e.play()
    }
    Instantiator {
        model: sfx.names
        delegate: SoundEffect {
            id: effect
            required property string modelData
            property bool openingPlayed: false
            function playOpeningSound() {
                if (openingPlayed || modelData !== sfx.openingSound || status !== SoundEffect.Ready || !sfx.audible)
                    return
                openingPlayed = true
                play()
            }
            onStatusChanged: {
                effect.playOpeningSound()
                sfx.playPendingSound(effect)
            }
            onPlayingChanged: if (!effect.playing) sfx.soundFinished(effect.modelData)
            Component.onCompleted: effect.playOpeningSound()
            source: Qt.resolvedUrl("sounds/" + sfx.api.uiSoundPack + "/" + modelData + ".wav")
            volume: sfx.api.uiSoundVolume / 100
        }
        onObjectAdded: function(index, object) {
            sfx.reg[sfx.names[index]] = object
            sfx.playPendingSound(object)
        }
    }
}

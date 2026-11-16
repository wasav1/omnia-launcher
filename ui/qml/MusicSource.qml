import QtQuick
import org.kde.plasma.private.mpris as Mpris

// Música real vía MPRIS (Spotify, Cider, Firefox, VLC...).
Item {
    id: m
    readonly property var player: model.currentPlayer
    readonly property bool available: player !== null && player !== undefined && String(player.track).length > 0
    readonly property bool playing: available && player.playbackStatus === Mpris.PlaybackStatus.Playing
    readonly property string track: available ? player.track : ""
    readonly property string artist: available ? player.artist : ""
    readonly property string sourceName: available ? String(player.identity || player.desktopEntry || "Reproductor").replace(/\.desktop$/i, "") : ""
    readonly property real length: available && Number.isFinite(Number(player.length)) && Number(player.length) > 0 ? Number(player.length) / 1000000 : 0
    readonly property real playbackRate: available && Number(player.rate) > 0 ? Number(player.rate) : 1
    // Posición propia: avanza con el reloj local cada 100 ms (fluida, segundo a segundo) y solo se corrige con el valor del
    // reproductor ante un salto real (cambio de pista, adelantar/atrasar). Antes se volvía a anclar justo antes de leerla y
    // el tiempo transcurrido valía siempre ~0: la barra solo avanzaba a saltos de ~2 s cuando el reproductor corregía.
    property real position: 0
    property real positionSampledAt: Date.now()
    property real trackChangedAt: Date.now()
    property int positionPollCount: 0

    function clampPos(v) { return length > 0 ? Math.min(length, Math.max(0, v)) : Math.max(0, v) }

    Mpris.Mpris2Model { id: model }

    function acceptRemotePosition() {
        if (!player) return
        const value = Number(player.position)
        if (!Number.isFinite(value) || value < 0) return
        const seconds = value / 1000000
        const now = Date.now()
        // Algunos clientes (sobre todo navegadores) devuelven 0 o una posición vieja: se ignoran. El valor remoto solo se
        // usa para saltos o búsquedas de verdad (más de 2 s de diferencia con la posición propia).
        if (now - trackChangedAt < 1200 && seconds > 2) return
        if (seconds === 0 && position > 1.25) return
        if (Math.abs(seconds - position) > 2.0) {
            position = clampPos(seconds)
            positionSampledAt = now
        }
    }

    function resetPosition() {
        position = 0
        positionSampledAt = Date.now()
        trackChangedAt = positionSampledAt
        if (player) player.updatePosition()
    }
    onPlayerChanged: resetPosition()

    Connections {
        target: m.player
        ignoreUnknownSignals: true
        function onPositionChanged() { m.acceptRemotePosition() }
        function onPlaybackStatusChanged() { if (m.player) m.player.updatePosition() }
        function onRateChanged() { if (m.player) m.player.updatePosition() }
        function onTrackChanged() { m.resetPosition() }
    }

    Timer {
        interval: 100; repeat: true; running: m.available; triggeredOnStart: true
        onTriggered: {
            const now = Date.now()
            if (m.playing) m.position = m.clampPos(m.position + (now - m.positionSampledAt) / 1000 * m.playbackRate)
            m.positionSampledAt = now
            if (m.player && (++m.positionPollCount % 10) === 0) m.player.updatePosition()      // consulta al reproductor cada ~1 s
        }
    }
    function playPause() { if (player) player.PlayPause() }
    function next() { if (player) player.Next() }
    function previous() { if (player) player.Previous() }
}

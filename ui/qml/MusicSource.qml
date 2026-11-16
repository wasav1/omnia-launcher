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
    property real positionAnchor: 0
    property real positionSampledAt: Date.now()
    property int positionPulse: 0
    property int positionPollCount: 0
    property real trackChangedAt: Date.now()
    readonly property real position: {
        positionPulse
        const elapsed = playing ? Math.max(0, (Date.now() - positionSampledAt) / 1000 * playbackRate) : 0
        const value = Math.max(0, positionAnchor + elapsed)
        return length > 0 ? Math.min(length, value) : value
    }

    Mpris.Mpris2Model { id: model }

    function acceptRemotePosition() {
        if (!player) return
        const value = Number(player.position)
        if (!Number.isFinite(value) || value < 0) return
        const seconds = value / 1000000
        const now = Date.now()
        const predicted = position
        // Some MPRIS clients (notably browser players) keep reporting zero or a stale
        // position. Ignore it; use remote values only for meaningful jumps/seeks.
        if (now - trackChangedAt < 1200 && seconds > 2) return
        if (seconds === 0 && predicted > 1.25) return
        if (Math.abs(seconds - predicted) > 1.25) {
            positionAnchor = seconds
            positionSampledAt = now
            positionPulse++
        }
    }

    onPlayerChanged: {
        positionAnchor = 0
        positionSampledAt = Date.now()
        trackChangedAt = positionSampledAt
        if (player) player.updatePosition()
    }

    Connections {
        target: m.player
        ignoreUnknownSignals: true
        function onPositionChanged() { m.acceptRemotePosition() }
        function onPlaybackStatusChanged() { if (m.player) m.player.updatePosition() }
        function onRateChanged() { if (m.player) m.player.updatePosition() }
        function onTrackChanged() {
            m.positionAnchor = 0
            m.positionSampledAt = Date.now()
            m.trackChangedAt = m.positionSampledAt
            if (m.player) m.player.updatePosition()
        }
    }

    Timer {
        interval: 250; repeat: true; running: m.available; triggeredOnStart: true
        onTriggered: {
            if (m.playing) {
                m.positionAnchor = m.position
                m.positionSampledAt = Date.now()
            }
            m.positionPulse++
            if (m.player && (++m.positionPollCount % 4) === 0) m.player.updatePosition()
        }
    }
    function playPause() { if (player) player.PlayPause() }
    function next() { if (player) player.Next() }
    function previous() { if (player) player.Previous() }
}

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
    readonly property real length: available ? Math.max(0, player.length) / 1000000 : 0
    property real position: 0
    Mpris.Mpris2Model { id: model }
    Timer {
        interval: 1000; repeat: true; running: m.available; triggeredOnStart: true
        onTriggered: { if (m.player) { m.player.updatePosition(); m.position = Math.max(0, m.player.position) / 1000000 } }
    }
    function playPause() { if (player) player.PlayPause() }
    function next() { if (player) player.Next() }
    function previous() { if (player) player.Previous() }
}

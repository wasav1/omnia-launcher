pragma Singleton
pragma ComponentBehavior: Bound

import qs.modules.common
import QtQuick
import Quickshell
import Quickshell.Io

/**
 * Fondo del escritorio: Omnia NO lo cambia por su cuenta. Solo lo hace a petición del usuario desde el menú «⋯»:
 * «Usar su fondo en el escritorio» y «Quitar fondo fijado». No hay rotación ni cambios automáticos.
 * Antes de fijar se guarda el fondo original en ~/.local/state/omnia/wallpaper-backup.json; quitar lo restaura.
 * Se escribe Config.options.background.wallpaperPath (lo dibuja ii); no se llama a switchwall.sh, así que no se
 * regeneran los colores de terminal ni de aplicaciones.
 */
Singleton {
    id: root

    readonly property string backupPath: (Quickshell.env("XDG_STATE_HOME") || (Quickshell.env("HOME") + "/.local/state")) + "/omnia/wallpaper-backup.json"
    readonly property string current: Config.ready ? (Config.options.background.wallpaperPath || "") : ""
    readonly property bool pinned: current.indexOf("/omnia/art/") >= 0          // el fondo actual es arte de Omnia

    function pathOf(url) {
        let p = String(url || "");
        if (p.startsWith("file://")) p = decodeURIComponent(p.slice(7));
        return p;
    }
    function isVideo(p) { return /\.(mp4|webm|mkv|avi|mov)$/i.test(p || ""); }

    function hasFondo(game) { return !!game && !!game.fondo; }
    function isPinnedTo(game) { return hasFondo(game) && current === pathOf(game.fondo); }
    // «Usar su fondo»: hay fondo, aún no es el fijado y el fondo original no es un vídeo (lo gestiona mpvpaper).
    function canPin(game) { return Config.ready && hasFondo(game) && !isPinnedTo(game) && !isVideo(current); }

    function pin(game) {
        if (!canPin(game)) return;
        if (!pinned) {
            Quickshell.execDetached(["bash", "-c", 'mkdir -p "$(dirname "$1")" && printf %s "$2" > "$1"', "_", root.backupPath,
                JSON.stringify({ wallpaperPath: current, thumbnailPath: Config.options.background.thumbnailPath })]);
        }
        Config.options.background.wallpaperPath = pathOf(game.fondo);
    }

    function unpin() {
        if (pinned) restore.running = true;
    }

    Process {
        id: restore
        command: ["cat", root.backupPath]
        stdout: StdioCollector { id: out }
        onExited: code => {
            if (code !== 0) return;
            let original = "";
            try { original = JSON.parse(out.text).wallpaperPath || ""; } catch (e) {}
            if (original) {
                Config.options.background.wallpaperPath = original;
                Quickshell.execDetached(["rm", "-f", root.backupPath]);
            }
        }
    }
}

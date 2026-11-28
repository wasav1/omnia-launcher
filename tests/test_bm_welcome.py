"""Bienvenida de Big Mode «Trazo que abre la barra» (propuesta G)."""
import os
import shutil
import subprocess
import tempfile
import unittest
from pathlib import Path

QML = Path(__file__).resolve().parents[1] / "ui/qml"
CHECKS_OK = 49


@unittest.skipUnless(shutil.which("qml6"), "Requiere qml6")
class WelcomeQml(unittest.TestCase):
    def test_logo_lands_on_the_header_logo_and_the_intro_ends(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            for f in QML.iterdir():
                if f.suffix in (".qml", ".js"):
                    shutil.copyfile(f, root / f.name)
            (root / "test.qml").write_text('''import QtQuick
import QtQuick.Window
Window {
    visible: true; width: 1920; height: 1080
    Item {
        id: host
        anchors.fill: parent
        property real s: 1
        property string uiFont: "Hanken Grotesk"
        property color ink: "#EEF4FB"
        property color ink2: "#A9BDD3"
        property bool focused: false
        property var api: QtObject {
            property real uiSoundVolume: 0
            property bool uiSounds: false
            property string userName: "Ana"
            property var games: [{ name: "x" }]
            property bool padOn: false
        }
        property Item headerBar: bar
        function lastFocus() { focused = true }
        Item { id: bar; x: 48; y: 22; width: 1832; height: 54 }
    }
    OmniaIntro { id: intro; anchors.fill: parent; host: host }
    function fail(msg) { console.error(msg); Qt.exit(1) }
    Component.onCompleted: {
        intro.start()
        intro.tt = 0.1
        if (!intro.active) return fail("start() must show the intro")
        intro.tt = 7.0
        const logo = intro.children[intro.children.length - 1]
        if (Math.abs(logo.x - 48) > 0.5 || Math.abs(logo.y - 27) > 0.5 || Math.abs(logo.width - 44) > 0.5)
            return fail("the logo must land on the header logo: " + logo.x + "," + logo.y + " " + logo.width)
        intro.tt = intro.total + 0.05
        if (intro.active || !host.focused) return fail("the intro must end by itself and give focus back")
        intro.start(); intro.skip()
        if (!intro.closing) return fail("skip() starts the fade out")
        Qt.exit(CHECKS_OK)
    }
}
'''.replace("CHECKS_OK", str(CHECKS_OK)))
            env = dict(os.environ, QT_QPA_PLATFORM="offscreen", QT_FORCE_STDERR_LOGGING="1", MANGOHUD="0", DISABLE_MANGOHUD="1")
            result = subprocess.run(["qml6", str(root / "test.qml")], check=False, env=env, capture_output=True, text=True, timeout=30)
            self.assertEqual(result.returncode, CHECKS_OK, result.stdout + result.stderr)


if __name__ == "__main__":
    unittest.main()

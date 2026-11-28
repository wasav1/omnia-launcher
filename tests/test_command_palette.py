"""Fase 1 del rediseño D: paleta de comandos (Ctrl K) y barra superior de Desktop."""
import os
import shutil
import subprocess
import tempfile
import unittest
from pathlib import Path

REPO = Path(__file__).resolve().parents[1]
QML = REPO / 'ui/qml'
CHECKS_OK = 44


class TopBarSource(unittest.TestCase):
    def test_manager_uses_top_bar_without_sidebar(self):
        text = (QML / 'OmniaManager.qml').read_text()
        self.assertIn('GlassPanel {\n        id: topbar', text)
        self.assertNotIn('navWidth', text)
        self.assertNotIn('topbar.right', text)
        for page in ('"home"', '"library"', '"installs"', '"stats"', '"settings"'):
            self.assertIn('key: ' + page, text)
        # Desde la fase 2 el Catálogo vive dentro de Biblioteca.
        self.assertNotIn('key: "catalog"', text)
        self.assertIn('sequence: "Ctrl+K"', text)

    def test_top_bar_reorganizes_at_fixed_breakpoints(self):
        theme = (QML / 'Theme.js').read_text()
        self.assertIn('commandField: 1280', theme)
        self.assertIn('navIcons: 1040', theme)


@unittest.skipUnless(shutil.which('qml6'), 'Requiere qml6 para cargar la paleta')
class CommandPaletteQml(unittest.TestCase):
    def test_filters_games_and_runs_the_selected_action(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            for name in ('Theme.js', 'GlassPanel.qml', 'FrostedSurface.qml', 'CommandPalette.qml', 'LucideIcon.qml'):
                shutil.copyfile(QML / name, root / name)
            (root / 'test.qml').write_text('''import QtQuick
import QtQuick.Window
Window {
    visible: true; width: 1440; height: 900
    QtObject {
        id: fake
        property string launched: ""
        property string opened: ""
        property string page: ""
        function launch(g) { launched = g.name }
        function openGameInLibrary(g) { opened = g.name }
        function selectPage(k) { page = k }
        function openBigMode() { page = "bigmode" }
        function libraryAction(a) { page = "add" }
    }
    CommandPalette {
        id: cmd
        manager: fake
        games: [{name: "Red Dead Redemption 2", source: "steam"}, {name: "Detroit: Become Human"}, {name: "Pokémon Legends"}]
    }
    function fail(msg) { console.error(msg); Qt.exit(1) }
    Component.onCompleted: {
        cmd.show()
        if (!cmd.open) return fail("show() must open the palette")
        cmd.text = "red"
        if (cmd.results.length !== 2 + 0) return fail("red -> " + JSON.stringify(cmd.results.map(r => r.kind + ":" + r.label)))
        if (cmd.results[0].kind !== "Jugar" || cmd.results[1].kind !== "Ficha") return fail("order " + cmd.results[0].kind)
        cmd.runCurrent()
        if (fake.launched !== "Red Dead Redemption 2") return fail("launch " + fake.launched)
        if (cmd.open) return fail("running an action must close the palette")
        cmd.show()
        cmd.text = "pokemon"
        if (cmd.results.length < 2 || cmd.results[0].label !== "Pokémon Legends") return fail("accents ignored")
        cmd.current = 1; cmd.runCurrent()
        if (fake.opened !== "Pokémon Legends") return fail("open detail " + fake.opened)
        cmd.show()
        cmd.text = "ajustes"
        cmd.runCurrent()
        if (fake.page !== "settings") return fail("navigate " + fake.page)
        Qt.exit(CHECKS_OK)
    }
}
'''.replace('CHECKS_OK', str(CHECKS_OK)))
            env = dict(os.environ, QT_QPA_PLATFORM='offscreen', QT_FORCE_STDERR_LOGGING='1', QT_LOGGING_TO_CONSOLE='1',
                       MANGOHUD='0', DISABLE_MANGOHUD='1')
            result = subprocess.run(['qml6', str(root / 'test.qml')], check=False, env=env,
                                    capture_output=True, text=True, timeout=20)
            self.assertEqual(result.returncode, CHECKS_OK, result.stdout + result.stderr)


if __name__ == '__main__':
    unittest.main()

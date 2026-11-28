"""Fase 0 del rediseño D: tema central (Theme.js) y panel de cristal (GlassPanel)."""
import os
import shutil
import subprocess
import tempfile
import unittest
from pathlib import Path

REPO = Path(__file__).resolve().parents[1]
QML = REPO / 'ui/qml'
CHECKS_OK = 43


class ThemeTokens(unittest.TestCase):
    def test_fixed_sizes_match_the_approved_layout(self):
        text = (QML / 'Theme.js').read_text()
        self.assertTrue(text.startswith('.pragma library'))
        for token in ('panelInstalled: 300', 'panelCatalog: 688', 'panelDetail: 380',
                      'posterWidth: 152', 'posterHeight: 203', 'threePanels: 1360', 'compact: 900'):
            self.assertIn(token, text)

    def test_theme_does_not_scale_with_the_window(self):
        text = (QML / 'Theme.js').read_text()
        self.assertNotIn('Screen.', text)
        self.assertNotIn('devicePixelRatio', text)


@unittest.skipUnless(shutil.which('qml6'), 'Requiere qml6 para cargar los componentes')
class GlassPanelQml(unittest.TestCase):
    def test_layout_math_and_glass_modes(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            for name in ('Theme.js', 'GlassPanel.qml', 'FrostedSurface.qml'):
                shutil.copyfile(QML / name, root / name)
            (root / 'test.qml').write_text('''import QtQuick
import QtQuick.Window
import "Theme.js" as Theme
Window {
    visible: true; width: 1440; height: 900
    color: Theme.color.background
    Rectangle { id: art; anchors.fill: parent; color: "#7A1712" }
    GlassPanel { id: withBackdrop; x: 40; y: 40; width: 380; height: 300; backdrop: art; strong: true }
    GlassPanel { id: noBackdrop; x: 440; y: 40; width: 380; height: 300 }
    GlassPanel { id: glassOff; x: 840; y: 40; width: 380; height: 300; backdrop: art; glass: false
        Text { id: child; text: "Ficha"; color: Theme.color.ink }
    }
    function fail(msg) { console.error(msg); Qt.exit(1) }
    Component.onCompleted: {
        if (Theme.catalogWidth(1440, true) !== 688) return fail("catalog open " + Theme.catalogWidth(1440, true))
        if (Theme.catalogWidth(1440, false) !== 1084) return fail("catalog closed " + Theme.catalogWidth(1440, false))
        if (Theme.catalogWidth(1100, true) !== 744) return fail("catalog floating detail " + Theme.catalogWidth(1100, true))
        if (Theme.posterColumns(688 - 36) !== 4) return fail("columns open " + Theme.posterColumns(652))
        if (Theme.posterColumns(1084 - 36) !== 6) return fail("columns closed " + Theme.posterColumns(1048))
        if (!withBackdrop.sampling) return fail("glass with backdrop should sample")
        if (noBackdrop.sampling) return fail("glass without backdrop must not sample")
        if (glassOff.sampling) return fail("glass disabled must not sample")
        if (child.parent.parent !== glassOff) return fail("content must live inside the panel")
        if (withBackdrop.radius !== Theme.radius.xl) return fail("default radius")
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

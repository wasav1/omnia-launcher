"""Prueba QML real: el widget desplazado no altera la superficie del monitor."""
import os
import shutil
import subprocess
import tempfile
import unittest
from pathlib import Path

REPO = Path(__file__).resolve().parents[1]


@unittest.skipUnless(shutil.which('qml6'), 'Requiere qml6 para probar geometría Qt')
class DesktopSurface(unittest.TestCase):
    def test_resizes_with_each_window_and_ignores_widget_offset(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            shutil.copyfile(REPO / 'ui/qml/DesktopSurface.qml', root / 'DesktopSurface.qml')
            (root / 'test.qml').write_text('''import QtQuick
import QtQuick.Window
Window {
    id: first
    visible: true; width: 1920; height: 1080
    Window { id: second; visible: true; width: 1280; height: 720 }
    Item {
        x: -14; y: 91; width: 1920; height: 1024
        DesktopSurface { id: surface; viewport: first.contentItem }
    }
    property int stage: 0
    Timer {
        interval: 30; running: true; repeat: true
        onTriggered: {
            var target = first.stage < 2 ? first : second;
            if (surface.x !== 0 || surface.y !== 0 || surface.width !== target.width || surface.height !== target.height) {
                console.error("Incorrect geometry", surface.x, surface.y, surface.width, surface.height);
                Qt.exit(1); return;
            }
            if (first.stage === 0) { first.width = 2560; first.height = 1440; }
            else if (first.stage === 1) { surface.viewport = second.contentItem; }
            else if (first.stage === 2) { second.width = 1536; second.height = 864; }
            else { console.log("geometry-ok"); Qt.quit(); }
            first.stage++;
        }
    }
}
''')
            env = dict(os.environ, QT_QPA_PLATFORM='offscreen', QT_QUICK_BACKEND='software', QT_FORCE_STDERR_LOGGING='1', QT_LOGGING_TO_CONSOLE='1')
            result = subprocess.run(['qml6', str(root / 'test.qml')], check=False, env=env, capture_output=True, text=True, timeout=15)
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
            self.assertIn('geometry-ok', result.stdout + result.stderr)

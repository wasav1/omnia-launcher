"""Fase 3 del rediseño D: Ajustes de Desktop como menú de categorías."""
import os
import shutil
import subprocess
import tempfile
import unittest
from pathlib import Path

REPO = Path(__file__).resolve().parents[1]
QML = REPO / 'ui/qml'
CHECKS_OK = 46


class SettingsSource(unittest.TestCase):
    def test_categories_and_glass_wiring(self):
        text = (QML / 'ManagerSettings.qml').read_text()
        for key in ('"general"', '"library"', '"stores"', '"games"', '"appearance"', '"bigmode"', '"about"'):
            self.assertIn('k: ' + key, text)
        self.assertIn('settings.api.setGlassEffect(v, settings.saved)', text)
        self.assertIn('checked = Qt.binding(() => sw.value)', text)
        manager = (QML / 'OmniaManager.qml').read_text()
        self.assertIn('readonly property bool glassActive: api.glassEffect && !gameRunning', manager)
        self.assertEqual(manager.count('backdrop: manager.glassBackdrop'), 3)
        self.assertNotIn('backdrop: ambient', manager)


@unittest.skipUnless(shutil.which('qml6'), 'Requiere qml6 para cargar Ajustes')
class SettingsQml(unittest.TestCase):
    def test_sections_and_switches(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            for f in QML.iterdir():
                if f.suffix in ('.qml', '.js'):
                    shutil.copyfile(f, root / f.name)
            (root / 'test.qml').write_text('''import QtQuick
import QtQuick.Window
Window {
    visible: true; width: 1440; height: 900
    QtObject {
        id: fakeManager
        property string page: "settings"
        property string settingsSection: "general"
        readonly property bool storeSettingsOpen: settingsSection === "stores"
        property bool showHiddenGames: false
        property var libraryRoots: ["/mnt/JUEGOS"]
        property string rootPath: ""
        property string rootsMessage: ""
        function changeRoot(a, p) {}
        function openBigMode() {}
    }
    QtObject {
        id: fakeApi
        property string language: "es"
        property bool updateCheck: true
        property string installRoot: ""
        property bool mangohud: false
        property bool mangohudInstalled: true
        property bool glassEffect: true
        property bool animatedBackground: true
        property bool introEnabled: true
        property bool uiSounds: true
        property int uiSoundVolume: 70
        property string uiSoundPack: "omnia"
        property var uiSoundPacks: [{ id: "omnia", label: "Omnia" }]
        property var suiteUpdate: ({ current: "0.4.0" })
        property bool glassCall: false
        function setGlassEffect(v, done) { glassEffect = v; glassCall = true; if (done) done(200, {}) }
        function notify(t) {}
    }
    QtObject { id: fakeStores; property real accountsHeight: 100 }
    ManagerSettings {
        id: settings
        anchors.fill: parent
        manager: fakeManager
        api: fakeApi
        stores: fakeStores
    }
    function fail(msg) { console.error(msg); Qt.exit(1) }
    Component.onCompleted: {
        if (settings.categories.length !== 7) return fail("categories " + settings.categories.length)
        if (settings.currentCategory.l !== "General") return fail("default section")
        fakeManager.settingsSection = "appearance"
        if (settings.section !== "appearance") return fail("section " + settings.section)
        fakeApi.setGlassEffect(false, settings.saved)
        if (fakeApi.glassEffect || !fakeApi.glassCall) return fail("glass toggle")
        fakeManager.settingsSection = "desconocida"
        if (settings.section !== "general") return fail("unknown section must fall back to General")
        Qt.exit(CHECKS_OK)
    }
}
'''.replace('CHECKS_OK', str(CHECKS_OK)))
            env = dict(os.environ, QT_QPA_PLATFORM='offscreen', QT_FORCE_STDERR_LOGGING='1', QT_LOGGING_TO_CONSOLE='1',
                       MANGOHUD='0', DISABLE_MANGOHUD='1')
            result = subprocess.run(['qml6', str(root / 'test.qml')], check=False, env=env,
                                    capture_output=True, text=True, timeout=30)
            self.assertEqual(result.returncode, CHECKS_OK, result.stdout + result.stderr)


if __name__ == '__main__':
    unittest.main()

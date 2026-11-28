"""Fase 5a del rediseño D: barra de Big Mode y Menú rápido (botón Guía)."""
import os
import shutil
import subprocess
import tempfile
import unittest
from pathlib import Path

REPO = Path(__file__).resolve().parents[1]
QML = REPO / 'ui/qml'
CHECKS_OK = 47


class BigModeBarSource(unittest.TestCase):
    def test_tabs_and_guide_button(self):
        lib = (QML / 'OmniaLibrary.qml').read_text()
        self.assertIn('label:qsTr("Catálogo")', lib)
        self.assertIn('{key:"downloads", label:qsTr("Descargas")}', lib)
        self.assertIn('if (k === "START" && !lib.exitConfirmOpen && !api.covered', lib)   # Start, no el botón Guía
        self.assertIn('else if (i === menuIndex) quickMenu.show()', lib)
        header = (QML / 'OmniaBigHeader.qml').read_text()
        self.assertNotIn('id: gearBtn', header)
        self.assertNotIn('id: powerBtn', header)
        self.assertIn('id: menuBtn', header)
        self.assertIn('backdrop: head.host.glassBackdrop', header)


@unittest.skipUnless(shutil.which('qml6'), 'Requiere qml6 para cargar el Menú rápido')
class QuickMenuQml(unittest.TestCase):
    def test_pad_navigation_volume_and_shutdown_confirmation(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            for f in QML.iterdir():
                if f.suffix in ('.qml', '.js'):
                    shutil.copyfile(f, root / f.name)
            (root / 'test.qml').write_text('''import QtQuick
import QtQuick.Window
Window {
    visible: true; width: 1920; height: 1080
    QtObject {
        id: fakeApi
        property bool padOn: true
        property string padName: "Mando Xbox"
        property var padBattery: ({ level: 72 })
        property bool hudVisible: true
        property int fpsLimit: 0
        readonly property var fpsLimits: [0, 30, 40, 45, 60]
        property var powerProfile: ({ available: true, profiles: ["power-saver", "balanced", "performance"], current: "balanced" })
        function loadPower() {}
        function fpsLabel(v) { return v > 0 ? v + " FPS" : "Sin límite" }
        function profileLabel(k) { return k }
        function setPerformance(c, done) { if (c.hud_visible !== undefined) hudVisible = c.hud_visible; if (c.fps_limit !== undefined) fpsLimit = c.fps_limit; done(200, {}) }
        function setPowerProfile(p, done) { powerProfile = { available: true, profiles: powerProfile.profiles, current: p }; done(200, {}) }
        property int level: 40
        property bool mute: false
        property string powered: ""
        function setAudioLevel(target, changes, done) {
            if (changes.volume !== undefined) level = changes.volume
            if (changes.muted !== undefined) mute = changes.muted
            done(200, { volume: level, muted: mute })
        }
        function power(a) { powered = a }
        function notify(t) {}
    }
    Item {
        id: fakeHost
        property var api: fakeApi
        property real s: 1
        property string uiFont: "Hanken Grotesk"
        property string clockLabel: "2:41 a. m."
    }
    property bool settingsAsked: false
    OmniaQuickMenu {
        id: menu
        host: fakeHost
        onSettingsRequested: settingsAsked = true
    }
    function fail(msg) { console.error(msg); Qt.exit(1) }
    Component.onCompleted: {
        if (menu.pad("A")) return fail("closed menu must not take keys")
        menu.show()
        if (!menu.open || menu.volume !== 40) return fail("show reads the volume: " + menu.volume)
        menu.pad("r"); menu.pad("r")
        if (fakeApi.level !== 50 || menu.volume !== 50) return fail("right raises volume by 5: " + fakeApi.level)
        menu.pad("A")
        if (!fakeApi.mute || !menu.muted) return fail("A on volume toggles mute")
        menu.pad("d"); menu.pad("r")
        if (fakeApi.powerProfile.current !== "performance") return fail("right on the profile goes up: " + fakeApi.powerProfile.current)
        menu.pad("r")
        if (fakeApi.powerProfile.current !== "performance") return fail("the profile stops at the last one")
        menu.pad("A")
        if (fakeApi.powerProfile.current !== "power-saver") return fail("A cycles the profile")
        menu.pad("d"); menu.pad("r"); menu.pad("r"); menu.pad("r")
        if (fakeApi.fpsLimit !== 45) return fail("fps steps: " + fakeApi.fpsLimit)
        menu.pad("l")
        if (fakeApi.fpsLimit !== 40) return fail("left lowers the limit: " + fakeApi.fpsLimit)
        menu.pad("d"); menu.pad("l")
        if (fakeApi.hudVisible) return fail("left on HUD hides it")
        menu.current = 0
        menu.pad("u")
        if (menu.current !== menu.items.length - 1) return fail("up from the top wraps to the last item")
        menu.pad("A")
        if (fakeApi.powered !== "" || !menu.confirmShutdown) return fail("shutdown needs a second press")
        menu.pad("u")
        if (menu.confirmShutdown) return fail("moving away cancels the shutdown confirmation")
        menu.current = 4; menu.pad("A")
        if (!settingsAsked || menu.open) return fail("settings closes the menu and asks the host")
        menu.show(); menu.current = menu.items.length - 1; menu.pad("A"); menu.pad("A")
        if (fakeApi.powered !== "shutdown" || menu.open) return fail("second press powers off: " + fakeApi.powered)
        menu.show(); menu.pad("START")
        if (menu.open) return fail("Start closes the menu")
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

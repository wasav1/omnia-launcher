"""Fase 5c del rediseño D: Inicio de Big Mode con las novedades de las tiendas."""
import os
import shutil
import subprocess
import tempfile
import unittest
from pathlib import Path

QML = Path(__file__).resolve().parents[1] / 'ui/qml'
CHECKS_OK = 48


class HomeDealsSource(unittest.TestCase):
    def test_pad_wiring(self):
        lib = (QML / 'OmniaLibrary.qml').read_text()
        self.assertIn('else if (k === "LB") home.nav("tabprev")', lib)
        self.assertIn('else if (k === "RB") home.nav("tabnext")', lib)
        home = (QML / 'OmniaHome.qml').read_text()
        self.assertIn('"/stores/deals?lang="', home)


@unittest.skipUnless(shutil.which('qml6'), 'Requiere qml6')
class HomeDealsQml(unittest.TestCase):
    def test_sections_navigation_and_store_filter(self):
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
        property string language: "es"
        property bool padOn: false
        property string opened: ""
        property var games: []
        function call(method, path, done) {
            if (path.indexOf("/stores/news") === 0) { done(200, { items: [] }); return }
            if (path.indexOf("/stores/deals") === 0) done(200, { loading: false, items: [
                { source: "steam", kind: "deal", title: "Cyberpunk", url: "https://store.steampowered.com/app/1/", discount: 70, price: "$ 1", endsAt: 0 },
                { source: "gog", kind: "deal", title: "Heroes 3", url: "https://www.gog.com/x", discount: 76, price: "US$ 0,99" },
                { source: "epic", kind: "free", title: "Bread and Fred", url: "https://store.epicgames.com/x", endsAt: 0 },
                { source: "steam", kind: "release", title: "Nuevo", url: "https://store.steampowered.com/app/2/" }
            ] })
        }
        function catalogGames(o, done) { done(200, { items: [] }) }
    }
    OmniaHome {
        id: home
        anchors.fill: parent
        api: fakeApi
        uiScale: 0.8
    }
    function fail(msg) { console.error(msg); Qt.exit(1) }
    Component.onCompleted: {
        home.loadDeals()
        const keys = home.dealSections.map(s => s.key + ":" + s.items.length).join(",")
        if (keys !== "free:1,deal:2,release:1") return fail("sections " + keys)
        // el destacado usa las mismas novedades que Desktop: primero el juego gratis
        if (!home.currentFeatured || home.currentFeatured.title !== "Bread and Fred") return fail("featured " + JSON.stringify(home.currentFeatured))
        home.zone = "hero"
        home.nav("right")
        if (home.zone !== "library") return fail("without a recent game, right from the hero goes to Library: " + home.zone)
        home.nav("right")
        if (home.zone !== "catalog") return fail("right from Library goes to Catalog")
        home.nav("down")
        if (home.zone !== "deals" || home.sectionIndex !== 0) return fail("down from the tiles goes to the deals: " + home.zone)
        home.nav("down")
        if (home.sectionIndex !== 1 || home.itemIndex !== 0) return fail("down crosses to the next section: " + home.sectionIndex + "/" + home.itemIndex)
        home.nav("right")
        if (home.focusedDeal.title !== "Heroes 3") return fail("focused " + JSON.stringify(home.focusedDeal))
        home.nav("right")
        if (home.itemIndex !== 1) return fail("stays on the last card")
        home.nav("up"); home.nav("up")
        if (home.zone !== "hero") return fail("up from the first row goes back to the hero: " + home.zone)
        home.nav("tabnext")
        if (home.storeFilter !== "steam") return fail("RB changes the store: " + home.storeFilter)
        if (home.dealSections.map(s => s.key).join(",") !== "deal,release") return fail("steam filter " + home.dealSections.map(s => s.key))
        home.nav("tabprev"); home.nav("tabprev")
        if (home.storeFilter !== "omnia") return fail("LB wraps around: " + home.storeFilter)
        if (home.dealColumns < 2 || home.dealColumns > 5) return fail("columns " + home.dealColumns)
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

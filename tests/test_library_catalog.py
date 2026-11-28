"""Fase 2 del rediseño D: Biblioteca + Catálogo en tres paneles de ancho fijo."""
import os
import shutil
import subprocess
import tempfile
import unittest
from pathlib import Path

REPO = Path(__file__).resolve().parents[1]
QML = REPO / 'ui/qml'
CHECKS_OK = 45


class LibraryLayoutSource(unittest.TestCase):
    def test_library_has_three_fixed_panels(self):
        text = (QML / 'ManagerLibrary.qml').read_text()
        self.assertIn('width: Theme.size.panelInstalled', text)
        self.assertIn('width: Theme.catalogWidth(ml.width, ml.detailShown)', text)
        self.assertIn('width: Theme.size.panelDetail', text)
        self.assertIn('placeholderText: qsTr("Buscar en instalados")', text)
        # La ficha se oculta hasta elegir un juego y flota bajo el punto de reorganización.
        self.assertIn('readonly property bool detailShown: detailOpen && current !== null', text)
        self.assertIn('width < Theme.breakpoint.threePanels', text)
        self.assertNotIn('installedGrid', text)
        self.assertNotIn('ml.s *', text)

    def test_explore_page_is_gone_and_catalog_routes_to_library(self):
        self.assertFalse((QML / 'ManagerExplore.qml').exists())
        manager = (QML / 'OmniaManager.qml').read_text()
        self.assertNotIn('ManagerExplore', manager)
        self.assertIn('const toCatalog = key === "catalog" || key === "stores"', manager)
        self.assertIn('page = "library"', manager)


@unittest.skipUnless(shutil.which('qml6'), 'Requiere qml6 para cargar el Catálogo')
class CatalogPanelQml(unittest.TestCase):
    def test_columns_filter_and_actions(self):
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
        id: fake
        property string query: ""
        property int loads: 0
        property string exploreFilter: "all"
        property string exploreSort: "year-desc"
        property string catalogLinkTargetId: ""
        property string onlineWarning: ""
        property bool onlineBusy: false
        property string opened: ""
        readonly property var exploreSources: [{ k: "all", label: "Todas", logo: "" }]
        readonly property var exploreItems: [
            { kind: "omnia", game: { name: "Zelda Port" }, name: "Zelda Port", art: "", store: "Omnia", logo: "", platform: "PC", info: "", installed: false },
            { kind: "omnia", game: { name: "Mario Port" }, name: "Mario Port", art: "", store: "Omnia", logo: "", platform: "PC", info: "", installed: true },
            { kind: "store", item: { local: null }, name: "Hades", art: "", store: "Steam", logo: "", platform: "PC", info: "", installed: false },
            { kind: "store", item: { local: { id: "rdr2", name: "Red Dead" } }, name: "Red Dead Redemption 2", art: "", store: "Steam", logo: "", platform: "PC", info: "", installed: true }
        ]
        function localMatch(g) { return g.name === "Mario Port" ? { id: "mario" } : null }
        function openCatalogDetail(g) { opened = "catalog:" + g.name }
        function openStoreDetail(i) { opened = "store" }
        function linkCatalogGame(g) { opened = "link:" + g.name }
        function loadOnline(p) { loads++ }
        function loadNextOnline() {}
        function openStoreSettings() {}
        function openGameMenu(g) {}
        function openOfferMenu(o) {}
        function cancelCatalogLink() {}
    }
    QtObject { id: stores; property bool ready: true; property bool loadingContent: false }
    property string chosen: ""
    CatalogPanel {
        id: cat
        width: 688; height: 700
        manager: fake
        stores: stores
        onLocalGameChosen: game => chosen = game.id
    }
    function fail(msg) { console.error(msg); Qt.exit(1) }
    Component.onCompleted: {
        if (cat.columns !== 4) return fail("688 px -> 4 columns, got " + cat.columns)
        cat.width = 1084
        if (cat.columns !== 6) return fail("1084 px -> 6 columns, got " + cat.columns)
        if (cat.items.length !== 4) return fail("items " + cat.items.length)
        cat.text = "red DEAD"
        if (cat.items.length !== 1) return fail("filter " + cat.items.length)
        cat.choose(cat.items[0])
        if (chosen !== "rdr2") return fail("local store game must open the library detail")
        cat.text = "port"
        cat.choose(cat.items[1])
        if (chosen !== "mario") return fail("local Omnia port must open the library detail: " + chosen)
        cat.choose(cat.items[0])
        if (fake.opened !== "catalog:Zelda Port") return fail("catalog detail " + fake.opened)
        cat.searchOnline()
        if (fake.query !== "port" || fake.loads !== 1) return fail("online search " + fake.query + " " + fake.loads)
        cat.text = ""
        if (fake.query !== "" || fake.loads !== 2) return fail("clearing must reset the online search")
        fake.catalogLinkTargetId = "abc"
        cat.choose(cat.items[0])
        if (fake.opened !== "link:Zelda Port") return fail("link mode " + fake.opened)
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

"""Fase 5b del rediseño D: Descargas con la barra, ficha con pestañas y Catálogo de Big Mode."""
import unittest
from pathlib import Path

QML = Path(__file__).resolve().parents[1] / 'ui/qml'


class BigMode5bSource(unittest.TestCase):
    def test_downloads_show_the_top_bar_without_the_footer(self):
        lib = (QML / 'OmniaLibrary.qml').read_text()
        self.assertIn('|| page === "downloads"', lib)
        self.assertIn('readonly property bool footerVisible: mainNavVisible && page !== "downloads"', lib)
        self.assertIn('mainNavIndex = page === "downloads" ? 3', lib)
        downloads = (QML / 'OmniaDownloads.qml').read_text()
        self.assertIn('readonly property bool withBar: dl.host.mainNavVisible === true', downloads)
        self.assertIn('visible: !dl.withBar', downloads)

    def test_details_tabs_and_favorite(self):
        details = (QML / 'OmniaGameDetails.qml').read_text()
        self.assertIn('model: [qsTr("Resumen"), qsTr("Partidas"), qsTr("Actividad")]', details)
        self.assertNotIn('qsTr("Descripción")', details)
        self.assertIn('const row = ["play", "fav", "more"]', details)
        self.assertIn('id: favB', details)

    def test_catalog_name(self):
        store = (QML / 'OmniaBigStore.qml').read_text()
        self.assertIn('text: qsTr("Catálogo")', store)
        self.assertNotIn('qsTr("Tienda")', store)


if __name__ == '__main__':
    unittest.main()

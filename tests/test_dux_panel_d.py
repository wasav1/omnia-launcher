"""Fase 6 del rediseño D: panel rápido de Dux con pestañas y descarga activa."""
import json
import unittest
from pathlib import Path

PANEL = Path(__file__).resolve().parents[1] / 'integrations/dux/omnia-panel'


class DuxPanelSource(unittest.TestCase):
    def test_tabs_news_and_downloads(self):
        text = (PANEL / 'OmniaPanel.qml').read_text()
        for tab in ('k: "recent"', 'k: "fav"', 'k: "news"'):
            self.assertIn(tab, text)
        self.assertIn('"/stores/news?lang="', text)
        self.assertIn('"/installations"', text)
        self.assertIn('readonly property var featured: library.find(g => g.id === selectedId) ?? pinned', text)
        self.assertIn('root.openApp("", "--downloads")', text)
        self.assertIn('Quickshell.execDetached(["omnia-ui", "--window"])', text)
        # el panel sigue sin depender de ii y usa los colores de Omnia
        self.assertNotIn('import qs.ii', text)
        self.assertIn('readonly property color accent: "#4DA3FF"', text)

    def test_plugin_manifest(self):
        manifest = json.loads((PANEL / 'plugin.json').read_text())
        self.assertEqual(manifest['id'], 'omniaPanel')
        self.assertEqual(manifest['version'], '3.1.0')


if __name__ == '__main__':
    unittest.main()

"""Desktop usa su propio menú contextual y la versión de escritorio de «Cambiar arte», sin el turquesa anterior."""
import unittest
from pathlib import Path

QML = Path(__file__).resolve().parents[1] / "ui/qml"


class DesktopIdentity(unittest.TestCase):
    def test_context_menu_opens_at_the_pointer(self):
        manager = (QML / "OmniaManager.qml").read_text()
        self.assertIn("DesktopContextMenu {", manager)
        self.assertNotIn("OmniaContextMenu {", manager)
        self.assertEqual(manager.count("desktopMenu.show(pointer.point.position)"), 2)

    def test_art_editor_runs_in_desktop_mode(self):
        manager = (QML / "OmniaManager.qml").read_text()
        self.assertIn("desktop: true", manager)
        editor = (QML / "OmniaArtEditor.qml").read_text()
        self.assertIn("readonly property real s: ed.host.s * (ed.desktop ? 0.72 : 1)", editor)
        self.assertIn("id: deskButtons", editor)

    def test_no_old_turquoise_in_desktop(self):
        for f in list(QML.glob("Manager*.qml")) + [QML / "OmniaManager.qml"]:
            text = f.read_text().upper()
            for old in ("#45CFC9", "#16434E", "#72E0DA", "#66D5D0", "#70E0D9", "#6CE2DC", '"#167E87"'):
                self.assertNotIn(old, text, f.name)


if __name__ == "__main__":
    unittest.main()

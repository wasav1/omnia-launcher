"""Big Mode: navegación coherente con mando (Start, Select, B y ↑) y colores del tema."""
import re
import unittest
from pathlib import Path

QML = Path(__file__).resolve().parents[1] / "ui/qml"


class BigModeNavigation(unittest.TestCase):
    def test_start_opens_the_quick_menu_and_guide_does_not(self):
        lib = (QML / "OmniaLibrary.qml").read_text()
        self.assertIn('if (k === "START" && !lib.exitConfirmOpen', lib)
        self.assertNotIn('k === "MODE"', lib)
        self.assertNotIn('"START"', (QML / "OmniaAllGames.qml").read_text())
        self.assertNotIn('key === "START"', (QML / "OmniaBigStore.qml").read_text())

    def test_back_follows_the_history(self):
        lib = (QML / "OmniaLibrary.qml").read_text()
        self.assertIn("function backSection()", lib)
        for opener in ("openLibrary", "openHome", "openStore", "openAll"):
            body = re.search(r"function " + opener + r"\(\)[^\n]*", lib).group(0)
            self.assertIn("remember(", body, opener)
        self.assertIn('if (key === "B") { host.back(); return }', (QML / "OmniaBigStore.qml").read_text())

    def test_up_from_the_first_row_reaches_the_bar(self):
        self.assertIn('if (dir === "up") { home.headerRequested(); return }', (QML / "OmniaHome.qml").read_text())
        self.assertIn("onTopReached: lib.searchFocus = true", (QML / "OmniaLibrary.qml").read_text())
        self.assertIn("dl.host.focusMainNav()", (QML / "OmniaDownloads.qml").read_text())

    def test_game_art_only_on_the_shelf(self):
        self.assertIn('opacity: lib.page === "library" ? 1 : 0', (QML / "OmniaLibrary.qml").read_text())

    def test_store_accounts_use_one_row_each(self):
        text = (QML / "OmniaBigSettings.qml").read_text()
        self.assertNotIn('label:qsTr("Conectar %1 en el navegador")', text)
        self.assertIn('text: qsTr("En el navegador")', text)

    def test_old_green_theme_is_gone_from_shared_modals(self):
        for name in ("Modal.qml", "AddGame.qml", "Browser.qml", "OptionList.qml", "ImportPanel.qml", "SavesPanel.qml"):
            text = (QML / name).read_text().lower()
            for old in ("#f4efd8", "#c9bf8a", "#a89f74", "#8c8560", "0.06, 0.14, 0.11"):
                self.assertNotIn(old, text, name)


if __name__ == "__main__":
    unittest.main()

"""Las cadenas de la interfaz QML tienen traducción al inglés (ui/qml/i18n/qml_en_US.ts)."""
import re
import shutil
import subprocess
import tempfile
import unittest
from pathlib import Path

REPO = Path(__file__).resolve().parents[1]
TS = REPO / "ui/qml/i18n/qml_en_US.ts"


class EnglishTranslation(unittest.TestCase):
    def test_no_unfinished_or_empty_translations(self):
        text = TS.read_text(encoding="utf-8")
        self.assertNotIn('type="unfinished"', text)
        self.assertIsNone(re.search(r"<translation>\s*</translation>", text))

    @unittest.skipUnless(shutil.which("lupdate6"), "Requiere lupdate6")
    def test_every_qml_string_is_in_the_ts_file(self):
        with tempfile.TemporaryDirectory() as tmp:
            copy = Path(tmp) / "qml_en_US.ts"
            shutil.copyfile(TS, copy)
            out = subprocess.run(["lupdate6", "-no-obsolete", "-locations", "none", str(REPO / "ui/qml"), "-ts", str(copy)],
                                 capture_output=True, text=True, timeout=120).stdout
            match = re.search(r"\((\d+) new", out)
            self.assertIsNotNone(match, out)
            self.assertEqual(match.group(1), "0", "Hay textos nuevos sin pasar por lupdate6:\n" + out)


if __name__ == "__main__":
    unittest.main()

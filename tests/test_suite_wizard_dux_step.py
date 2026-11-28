import re
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
WIZARD = ROOT / "packaging/suite/wizard.cpp"
TRANSLATION = ROOT / "packaging/suite/wizard_en_US.ts"

STEP = ("Último paso para el panel rápido: en Ajustes de Dux → Complementos, "
        "activa «Panel de Omnia». Después, en Widgets de la barra → Agregar widget, "
        "añade «Panel de Omnia».")


def source_strings(text):
    """Une los literales de C++ contiguos ("a" "b" → "ab") para comparar el texto final."""
    return re.sub(r'"\s*\n\s*"', "", text)


class SuiteWizardDuxStepTest(unittest.TestCase):
    def test_final_page_explains_how_to_add_the_panel(self):
        text = source_strings(WIZARD.read_text())
        self.assertIn(STEP, text)
        self.assertIn('QObject::tr("Abrir Ajustes de Dux")', text)
        self.assertIn('{"ipc", "call", "settings", "focusOrToggle"}', text)

    def test_step_is_shown_only_when_dux_was_chosen(self):
        text = WIZARD.read_text()
        self.assertIn("const bool showDux = dux && dux->isChecked();", text)
        self.assertIn("duxStep->setVisible(showDux);", text)
        self.assertIn("duxSettings->setVisible(showDux);", text)

    def test_english_translation_keeps_the_plugin_name(self):
        text = TRANSLATION.read_text()
        self.assertIn(f"<source>{STEP}</source>", text)
        self.assertIn("<source>Abrir Ajustes de Dux</source>", text)
        self.assertIn("<translation>Open Dux Settings</translation>", text)
        self.assertIn("enable “Panel de Omnia”", text)


if __name__ == "__main__":
    unittest.main()

"""Las ventanas completas (Big Mode y Desktop) cargan sin errores de QML.

Las pruebas por componente no detectan, por ejemplo, una propiedad asignada dos veces en `OmniaLibrary`:
aquí se carga cada ventana sin pantalla durante unos segundos y se buscan los errores de carga."""
import os
import shutil
import subprocess
import tempfile
import unittest
from pathlib import Path

QML = Path(__file__).resolve().parents[1] / "ui/qml"
FATAL = ("failed to load component", "Did not load any objects", "unavailable", "is not a type",
         "Property value set multiple times", "Cannot assign to non-existent property", "Expected token")


@unittest.skipUnless(shutil.which("qml6"), "Requiere qml6")
class WindowsLoad(unittest.TestCase):
    def check(self, name):
        with tempfile.TemporaryDirectory() as tmp:
            token = Path(tmp) / "token"
            token.write_text("prueba")
            env = dict(os.environ, QT_QPA_PLATFORM="offscreen", QT_FORCE_STDERR_LOGGING="1", MANGOHUD="0", DISABLE_MANGOHUD="1")
            try:
                out = subprocess.run(["qml6", str(QML / name), "--", "--token", str(token), "--port", "1"],
                                     capture_output=True, text=True, timeout=8, env=env)
                log = out.stdout + out.stderr
            except subprocess.TimeoutExpired as exc:        # sigue abierta: cargó bien
                log = (exc.stdout or b"").decode(errors="replace") + (exc.stderr or b"").decode(errors="replace")
        bad = [line for line in log.splitlines() if any(f in line for f in FATAL)]
        self.assertEqual(bad, [], "\n".join(bad))

    def test_big_mode_window(self):
        self.check("main-window.qml")

    def test_desktop_window(self):
        self.check("manager-window.qml")


if __name__ == "__main__":
    unittest.main()

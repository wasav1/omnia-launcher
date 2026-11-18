import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


class QmlImportScope(unittest.TestCase):
    def test_plasma_imports_token_provider_relatively(self):
        for file in (ROOT / 'plasma/wallpapers/org.omnia.launcher/contents/ui/main.qml',
                     ROOT / 'plasma/applets/org.omnia.desktop/contents/ui/main.qml'):
            self.assertIn('import "../../../../../omnia/ui/session" as OmniaSession', file.read_text())

    def test_plugin_installs_beside_shared_qml(self):
        cmake = (ROOT / 'plasma/tokenprovider/CMakeLists.txt').read_text()
        installer = (ROOT / 'packaging/universal/install.sh').read_text()
        self.assertIn('DESTINATION session', cmake)
        self.assertIn('CMAKE_INSTALL_PREFIX="$DATA/omnia/ui"', installer)
        self.assertNotIn('configure-qml.sh', installer)

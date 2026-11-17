import os
from pathlib import Path
import subprocess
import tempfile
import unittest

SCRIPT = Path(__file__).resolve().parents[1] / 'packaging/universal/configure-qml.sh'


class QmlEnvironment(unittest.TestCase):
    def test_publishes_plugin_path_preserves_other_imports_and_does_not_duplicate(self):
        with tempfile.TemporaryDirectory() as tmp:
            home = Path(tmp)
            binary = home / 'bin'; binary.mkdir()
            qml = str(home / '.local/lib/qt6/qml')
            mock = binary / 'systemctl'
            mock.write_text('#!/bin/sh\n'
                            'if [ "$2" = show-environment ]; then\n'
                            ' printf "QML_IMPORT_PATH=%s:/other/qml\\n" "$HOME/.local/lib/qt6/qml"\n'
                            'else\n'
                            ' printf "%s\\n" "$3" > "$HOME/published"\n'
                            'fi\n')
            mock.chmod(0o755)
            env = dict(os.environ, HOME=tmp, PATH=str(binary) + ':' + os.environ['PATH'])
            subprocess.run(['bash', str(SCRIPT)], env=env, check=True)
            self.assertEqual((home / 'published').read_text().strip(), 'QML_IMPORT_PATH=' + qml + ':/other/qml')
            self.assertIn('${HOME}/.local/lib/qt6/qml', (home / '.config/environment.d/60-omnia-qml.conf').read_text())

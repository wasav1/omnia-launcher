"""Ejecuta la GUI Qt real contra un backend ficticio, sin secretos ni cambios de sesión."""
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

REPO = Path(__file__).resolve().parents[1]


@unittest.skipUnless(shutil.which('cmake') and shutil.which('c++'), 'Requiere Qt Widgets y compilador')
class InstallerRetry(unittest.TestCase):
    def test_failed_install_keeps_key_for_retry_and_success_clears_it(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            (root / 'backend.py').write_text('''import json, pathlib, sys
root = pathlib.Path(__file__).parent
if sys.argv[1] == '--inspect':
    print(json.dumps({'volumes':[{'label':'Test','path':'/test','uuid':'test'}]}))
elif sys.argv[1] == '--install':
    data = json.load(sys.stdin)
    file = root / 'attempts.json'
    attempts = json.loads(file.read_text()) if file.exists() else []
    attempts.append(data.get('steamgriddb_key'))
    file.write_text(json.dumps(attempts))
    sys.exit(1 if len(attempts) == 1 else 0)
''')
            (root / 'test.cpp').write_text('''#define main omnia_application_main
#include "''' + (REPO / 'packaging/universal/gui/main.cpp').as_posix() + '''"
#undef main
int main(int argc, char **argv) {
    QApplication app(argc, argv);
    Installer wizard(QString::fromLocal8Bit(argv[1]), false);
    QLineEdit *key = nullptr;
    for (auto field : wizard.findChildren<QLineEdit*>())
        if (field->echoMode() == QLineEdit::Password) key = field;
    if (!key) return 10;
    key->setText("example-test-key");
    for (auto box : wizard.findChildren<QCheckBox*>())
        if (box->text().startsWith("He leído")) box->setChecked(true);
    int stage = 0;
    QTimer poll;
    QObject::connect(&poll, &QTimer::timeout, [&] {
        if (!wizard.button(QWizard::FinishButton)->isEnabled()) return;
        if (stage == 0) {
            if (key->text() != "example-test-key") { app.exit(11); return; }
            stage = 1;
            wizard.accept();
        } else {
            app.exit(key->text().isEmpty() ? 0 : 12);
        }
    });
    QTimer::singleShot(10000, &app, [&] { app.exit(13); });
    wizard.accept();
    poll.start(20);
    return app.exec();
}
''')
            (root / 'CMakeLists.txt').write_text('''cmake_minimum_required(VERSION 3.21)
project(omnia-retry-test LANGUAGES CXX)
find_package(Qt6 REQUIRED COMPONENTS Widgets)
add_executable(retry test.cpp)
target_compile_features(retry PRIVATE cxx_std_17)
target_link_libraries(retry PRIVATE Qt6::Widgets)
''')
            for command in (['cmake', '-S', str(root), '-B', str(root / 'build')],
                            ['cmake', '--build', str(root / 'build'), '--parallel', '2']):
                built = subprocess.run(command, capture_output=True, text=True, timeout=120)
                self.assertEqual(built.returncode, 0, built.stdout + built.stderr)
            env = dict(os.environ, QT_QPA_PLATFORM='offscreen', QT_FORCE_STDERR_LOGGING='1')
            result = subprocess.run([str(root / 'build/retry'), str(root / 'backend.py')], env=env, capture_output=True, text=True, timeout=15)
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
            self.assertEqual(json.loads((root / 'attempts.json').read_text()), ['example-test-key', 'example-test-key'])

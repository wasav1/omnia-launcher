"""El preflight no permite instalar si faltan dependencias del paquete nativo."""
import importlib.util
import os
import shutil
from pathlib import Path
import subprocess
import tempfile
import unittest

REPO = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location('dependency_build', REPO / 'packaging/distros/build.py')
build = importlib.util.module_from_spec(spec)
spec.loader.exec_module(build)


class InstallerDependencies(unittest.TestCase):
    @unittest.skipUnless(shutil.which('bsdtar'), 'libarchive (bsdtar) no instalado')
    def test_archive_declares_complete_dependency_contract_and_carries_it(self):
        with tempfile.TemporaryDirectory() as tmp:
            tmp = Path(tmp)
            root = tmp / 'root'; root.mkdir()
            work = tmp / 'work'; work.mkdir()
            out = tmp / 'out'; out.mkdir()
            build.stage(root)
            package = build.arch(root, out, work)
            metadata = subprocess.check_output(['bsdtar', '-xOf', str(package), '.PKGINFO'], text=True)
            declared = [line.removeprefix('depend = ') for line in metadata.splitlines() if line.startswith('depend = ')]
            self.assertEqual(declared, build.PROFILES['arch']['depends'])
            payload = root / 'usr/share' / build.NAME
            self.assertTrue((payload / 'packaging/distros/profiles.json').is_file())
            self.assertTrue((payload / 'packaging/universal/check-dependencies.sh').is_file())
            for package in ('make', 'cmake', 'qt6-tools', 'libpulse', 'libksysguard', 'python-gobject'):
                self.assertIn(package, declared)

    @unittest.skipUnless(Path('/etc/arch-release').exists(), 'Preflight Arch')
    def test_missing_runtime_module_blocks_check_and_cancel_blocks_install(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            for name, body in {
                'pacman': 'printf "libksysguard\\n"; exit 127',
                'kdialog': 'exit 1',
                'pkexec': f'touch "{root}/unexpected-install"; exit 1',
            }.items():
                script = root / name
                script.write_text('#!/bin/sh\n' + body + '\n')
                script.chmod(0o755)
            env = dict(os.environ, PATH=str(root) + ':' + os.environ['PATH'])
            for mode in ('--check', '--ensure'):
                result = subprocess.run(['bash', str(REPO / 'packaging/universal/check-dependencies.sh'), mode], env=env, capture_output=True, text=True)
                self.assertNotEqual(result.returncode, 0)
                self.assertIn('libksysguard', result.stderr)
            self.assertFalse((root / 'unexpected-install').exists())

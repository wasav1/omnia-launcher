import importlib.util
import io
from pathlib import Path
import subprocess
import shutil
import tarfile
import tempfile
import unittest

spec=importlib.util.spec_from_file_location('distribution_build',Path(__file__).resolve().parents[1]/'packaging/distros/build.py')
build=importlib.util.module_from_spec(spec);spec.loader.exec_module(build)


class DistributionPackages(unittest.TestCase):
    def test_pkginfo_separa_version_y_revision(self):
        fields = dict(line.split(' = ', 1) for line in build.arch_pkginfo(123).splitlines() if ' = ' in line)
        self.assertEqual(fields['pkgver'], build.VERSION)
        self.assertEqual(fields['pkgrel'], build.RELEASE)
        self.assertNotIn('-', fields['pkgver'])

    def test_payload_contains_sources_and_launcher_but_no_host_binary(self):
        with tempfile.TemporaryDirectory() as tmp:
            root=Path(tmp);build.stage(root)
            app=root/'usr/share'/build.NAME
            self.assertTrue((app/'packaging/universal/gui/main.cpp').is_file())
            self.assertTrue((app/'packaging/universal/candidate_import.py').is_file())
            self.assertTrue((root/'usr/bin/omnia-desktop-suite-install').stat().st_mode&0o111)
            self.assertFalse((app/'omnia-installer').exists())
            self.assertFalse(any(p.name=='out' for p in root.rglob('*')))
            for p in root.rglob('*'):
                if p.is_file():
                    with p.open('rb') as f:self.assertNotEqual(f.read(4),b'\x7fELF',str(p))

    @unittest.skipUnless(shutil.which('ar'), 'binutils (ar) no instalado')
    def test_debian_archive_metadata_and_no_automatic_user_changes(self):
        with tempfile.TemporaryDirectory() as tmp:
            tmp=Path(tmp);root=tmp/'stage';root.mkdir();work=tmp/'work';work.mkdir();out=tmp/'out';out.mkdir();build.stage(root)
            package=build.deb(root,out,work)
            self.assertEqual(subprocess.check_output(['ar','p',str(package),'debian-binary']),b'2.0\n')
            data=subprocess.check_output(['ar','p',str(package),'control.tar.gz'])
            with tarfile.open(fileobj=io.BytesIO(data),mode='r:gz') as archive:
                self.assertEqual(archive.getnames(),['control'])
                control=archive.extractfile('control').read().decode()
                self.assertIn('plasma-workspace (>= 4:6.0)',control)
                self.assertIn('Architecture: all',control)

    def test_rpm_profiles_use_their_own_package_names(self):
        self.assertIn('plasma-workspace >= 6.0',build.PROFILES['fedora']['depends'])
        self.assertIn('plasma6-workspace >= 6.0',build.PROFILES['opensuse']['depends'])
        self.assertNotIn('qt6-qtbase-devel >= 6.6',build.PROFILES['opensuse']['depends'])

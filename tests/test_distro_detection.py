import os
import subprocess
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
HELPER = ROOT / 'packaging/universal/distro.sh'


def run_distro(env=None, files=None):
    """Ejecuta el helper en un sandbox con /etc y /run/host simulados."""
    script = r'''
set -eu
. "$1"
omnia_distro_detect
printf '%s|%s|%s|%s|%s|%s\n' "$OMNIA_DISTRO_ID" "$OMNIA_DISTRO_LIKE" \
  "$OMNIA_OSTREE" "$(omnia_distro_profile)" "$(omnia_package_manager)" \
  "$(omnia_is_bazzite && echo yes || echo no)"
'''
    with tempfile.TemporaryDirectory() as tmp:
        base = Path(tmp)
        (base / 'etc').mkdir()
        (base / 'run').mkdir()
        (base / 'os-release').write_text('ID=freedesktop\n')
        (base / 'etc/os-release').write_text('ID=freedesktop\n')
        for path, content in (files or {}).items():
            target = base / path
            target.parent.mkdir(parents=True, exist_ok=True)
            target.write_text(content)
        sandbox_env = {
            'PATH': '/usr/bin:/bin',
            'HOME': str(base),
            'FAKE_BASE': str(base),
            **(env or {}),
        }
        # El helper lee rutas absolutas: se montan según FAKE_BASE mediante un
        # pequeño wrapper que reescribe las rutas en el código cargado.
        wrapped = HELPER.read_text()
        wrapped = wrapped.replace('/run/host/os-release', '${FAKE_BASE}/run/host/os-release')
        wrapped = wrapped.replace('/etc/os-release', '${FAKE_BASE}/etc/os-release')
        wrapped = wrapped.replace('/usr/lib/os-release', '${FAKE_BASE}/usr/lib/os-release')
        wrapped = wrapped.replace('/run/ostree-booted', '${FAKE_BASE}/run/ostree-booted')
        wrapped = wrapped.replace('/run/host/ostree-booted', '${FAKE_BASE}/run/host/ostree-booted')
        (base / 'distro.sh').write_text(wrapped)
        return subprocess.check_output(
            ['bash', '-c', script, 'bash', str(base / 'distro.sh')],
            env=sandbox_env, text=True,
        ).strip()


class DistroDetection(unittest.TestCase):
    def test_bazzite_from_flatpak_host(self):
        release = 'NAME="Bazzite"\nID=bazzite\nID_LIKE="fedora"\nPRETTY_NAME="Bazzite"\nOSTREE_VERSION=45\n'
        result = run_distro(env={'FLATPAK_ID': 'org.some.App'},
                            files={'run/host/os-release': release})
        self.assertEqual(result, 'bazzite|fedora|1|fedora|rpm-ostree|yes')

    def test_flatpak_uses_host_os_release(self):
        host = 'NAME="CachyOS Linux"\nID=cachyos\nID_LIKE=arch\n'
        runtime = 'NAME="Freedesktop SDK"\nID=org.freedesktop.platform\n'
        result = run_distro(env={'FLATPAK_ID': 'org.some.App'},
                            files={'run/host/os-release': host, 'etc/os-release': runtime})
        self.assertEqual(result, 'cachyos|arch|0|arch||no')

    def test_bazzite_without_ostree_marker(self):
        release = 'NAME="Bazzite"\nID=bazzite\nID_LIKE="fedora"\n'
        result = run_distro(files={'etc/os-release': release})
        self.assertEqual(result.split('|')[2:], ['1', 'fedora', 'rpm-ostree', 'yes'])

    def test_cachyos_regular(self):
        release = 'NAME="CachyOS Linux"\nID=cachyos\nID_LIKE=arch\n'
        result = run_distro(files={'etc/os-release': release})
        self.assertEqual(result.split('|')[2:], ['0', 'arch', '', 'no'])

    def test_fedora_ostree_without_bazzite_id(self):
        release = 'NAME="Fedora Kinoite"\nID=fedora\nID_LIKE=fedora\nOSTREE_VERSION=45\n'
        result = run_distro(files={'etc/os-release': release})
        self.assertEqual(result.split('|')[2:], ['1', 'fedora', 'rpm-ostree', 'no'])


class CheckDependenciesScript(unittest.TestCase):
    """Ejecuta el script real con un gestor de paquetes simulado."""

    def _run(self, os_release, shim_name, shim_body):
        with tempfile.TemporaryDirectory() as tmp:
            base = Path(tmp)
            release = base / 'os-release'
            release.write_text(os_release)
            shim = base / shim_name
            shim.write_text(shim_body)
            shim.chmod(0o755)
            env = {
                'PATH': f'{base}:' + os.environ.get('PATH', '/usr/bin:/bin'),
                'HOME': str(base),
                'OMNIA_OS_RELEASE': str(release),
            }
            return subprocess.run(
                ['bash', str(ROOT / 'packaging/universal/check-dependencies.sh'), '--check'], check=False,
                capture_output=True, text=True, env=env,
            )

    def test_fedora_lists_missing_without_failing_the_check(self):
        release = 'NAME="Bazzite"\nID=bazzite\nID_LIKE=fedora\nOSTREE_VERSION=45\n'
        rpm = '''#!/bin/sh
[ "$1" = "-q" ] || exit 2
case " bash systemd python3 plasma-workspace " in
  *" $2 "*) echo "$2-0"; exit 0 ;;
esac
echo "package $2 is not installed" >&2
exit 1
'''
        result = self._run(release, 'rpm', rpm)
        self.assertEqual(result.returncode, 1)
        self.assertIn('qt6-qttools', result.stderr)
        self.assertIn('cmake', result.stderr)
        self.assertNotIn('no se pudieron comprobar', result.stderr)

    def test_fedora_ok_when_everything_is_installed(self):
        release = 'NAME="Bazzite"\nID=bazzite\nID_LIKE=fedora\n'
        rpm = '#!/bin/sh\nexit 0\n'
        result = self._run(release, 'rpm', rpm)
        self.assertEqual(result.returncode, 0)
        self.assertNotIn('faltan dependencias', result.stderr)

    def test_fedora_accepts_provider_with_another_package_name(self):
        # Bazzite cubre "mangohud" con "terra-mangohud": el nombre exacto no
        # existe, pero el paquete base sí provee la capacidad.
        release = 'NAME="Bazzite"\nID=bazzite\nID_LIKE=fedora\n'
        rpm = '''#!/bin/sh
[ "$1" = "-q" ] || exit 2
if [ "$2" = "--whatprovides" ]; then
  [ "$3" = "mangohud" ] && { echo "terra-mangohud-0.8.4"; exit 0; }
  exit 1
fi
[ "$2" = "mangohud" ] && exit 1
exit 0
'''
        result = self._run(release, 'rpm', rpm)
        self.assertEqual(result.returncode, 0)
        self.assertNotIn('faltan dependencias', result.stderr)

    def test_arch_uses_pacman_missing_list(self):
        release = 'NAME="CachyOS Linux"\nID=cachyos\nID_LIKE=arch\n'
        pacman = '''#!/bin/sh
[ "$1" = "-T" ] || exit 0
shift
for p in "$@"; do echo "$p"; done
exit 127
'''
        result = self._run(release, 'pacman', pacman)
        self.assertEqual(result.returncode, 1)
        self.assertIn('qt6-declarative', result.stderr)
        self.assertNotIn('no se pudieron comprobar', result.stderr)

    def test_debian_comprueba_modulos_qml_y_muestra_el_que_falta(self):
        release = 'NAME="Debian GNU/Linux"\nID=debian\n'
        dpkg = '''#!/bin/sh
[ "$1" = "-W" ] || exit 2
case "$*" in *qml6-module-qtquick-shapes*) exit 1 ;; esac
echo 'install ok installed'
'''
        result = self._run(release, 'dpkg-query', dpkg)
        self.assertEqual(result.returncode, 1)
        self.assertIn('qml6-module-qtquick-shapes', result.stderr)

    def test_opensuse_comprueba_imports_criticos(self):
        release = 'NAME="openSUSE Tumbleweed"\nID=opensuse-tumbleweed\n'
        rpm = '''#!/bin/sh
[ "$1" = "-q" ] || exit 2
[ "$2" = "libksysguard6-imports" ] && exit 1
exit 0
'''
        result = self._run(release, 'rpm', rpm)
        self.assertEqual(result.returncode, 1)
        self.assertIn('libksysguard6-imports', result.stderr)


if __name__ == '__main__':
    unittest.main()

#!/usr/bin/env python3
"""AppImage del asistente con Qt local; compilación dirigida a CachyOS/x86-64."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import tempfile

from build import REPO, VERSION, RELEASE, NAME, stage

# Los controladores gráficos y la libc pertenecen al sistema anfitrión.
HOST_LIBS = ('libc.so.', 'libm.so.', 'libdl.so.', 'libpthread.so.', 'librt.so.',
             'libresolv.so.', 'libutil.so.', 'ld-linux', 'libGL.so.', 'libGLX.so.',
             'libOpenGL.so.', 'libGLdispatch.so.', 'libEGL.so.', 'libvulkan.so.',
             'libdrm.so.', 'libgbm.so.')


def libraries(binary):
    output=subprocess.check_output(['ldd',str(binary)],text=True)
    if 'not found' in output: raise RuntimeError('Dependencia no resuelta de '+str(binary))
    for line in output.splitlines():
        match=re.search(r'=> (/\S+)',line)
        if match:
            file=Path(match.group(1))
            if not file.name.startswith(HOST_LIBS): yield file


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--appimagetool',type=Path,required=True)
    parser.add_argument('--runtime',type=Path,required=True)
    parser.add_argument('--output',type=Path,default=REPO/'packaging/distros/out')
    args=parser.parse_args();out=args.output.resolve();out.mkdir(parents=True,exist_ok=True)
    tool=args.appimagetool.resolve();runtime=args.runtime.resolve()
    if os.uname().machine!='x86_64': parser.error('Este constructor es para x86-64.')
    icon=REPO/'assets/branding/omnia-icon-bluegray.png'
    if not icon.is_file(): parser.error('Falta el icono circular azul grisáceo.')
    with tempfile.TemporaryDirectory(prefix='omnia-appimage-') as tmp:
        work=Path(tmp);app=work/'Omnia.AppDir';app.mkdir();stage(app)
        subprocess.run(['cmake','-S',str(REPO/'packaging/universal/gui'),'-B',str(work/'gui'),'-DCMAKE_BUILD_TYPE=Release'],check=True)
        subprocess.run(['cmake','--build',str(work/'gui'),'--parallel','2'],check=True)
        binary=app/'usr/bin/omnia-installer';shutil.copy2(work/'gui/omnia-installer',binary)
        plugins=Path(subprocess.check_output(['qmake6','-query','QT_INSTALL_PLUGINS'],text=True).strip())
        selected=[]
        for folder,names in {'platforms':['libqxcb.so','libqwayland.so','libqwayland-egl.so','libqwayland-generic.so','libqoffscreen.so','libqminimal.so'],
                             'imageformats':['libqjpeg.so','libqico.so','libqsvg.so'],
                             'iconengines':['libqsvgicon.so']}.items():
            selected += [plugins/folder/name for name in names if (plugins/folder/name).is_file()]
        for folder in ('wayland-shell-integration','wayland-graphics-integration-client','wayland-decoration-client','xcbglintegrations'):
            selected += list((plugins/folder).glob('*.so'))
        bundled=set()
        library_dir=app/'usr/lib';library_dir.mkdir(parents=True,exist_ok=True)
        for source in [binary]+selected:
            for library in libraries(source):
                if library.name not in bundled:
                    shutil.copy2(library,library_dir/library.name);bundled.add(library.name)
        for plugin in selected:
            target=app/'usr/plugins'/plugin.relative_to(plugins);target.parent.mkdir(parents=True,exist_ok=True);shutil.copy2(plugin,target)
        for package in ('qt6-base','qt6-wayland','qt6-svg'):
            license_dir=Path('/usr/share/licenses')/package
            if license_dir.is_dir(): shutil.copytree(license_dir,app/'usr/share/licenses'/package,dirs_exist_ok=True)
        # Los paquetes Qt de Debian y Ubuntu guardan sus avisos en /usr/share/doc.
        debian_docs = Path('/usr/share/doc')
        for pattern in ('libqt6*/copyright', 'qt6-wayland*/copyright', 'qt6-qpa-plugins*/copyright'):
            for notice in debian_docs.glob(pattern):
                target_notice = app / 'usr/share/licenses' / notice.parent.name / 'copyright'
                target_notice.parent.mkdir(parents=True, exist_ok=True)
                shutil.copyfile(notice, target_notice)
        (app/'usr/share/omnia-bundled-libraries.txt').write_text('\n'.join(sorted(bundled))+'\n')
        shutil.copy2(icon,app/'omnia.png');(app/'.DirIcon').symlink_to('omnia.png')
        (app/'omnia.desktop').write_text('[Desktop Entry]\nType=Application\nName=Omnia — Instalador\nExec=omnia-installer\nIcon=omnia\nTerminal=false\nCategories=Game;\n')
        (app/'AppRun').write_text('''#!/usr/bin/env bash
set -euo pipefail
APPDIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
for variable in LD_LIBRARY_PATH LD_PRELOAD QT_PLUGIN_PATH QT_QPA_PLATFORM_PLUGIN_PATH QT_QPA_PLATFORMTHEME QT_STYLE_OVERRIDE; do
  if [[ -v "$variable" ]]; then
    export "OMNIA_HOST_$variable=${!variable}" "OMNIA_HOST_SET_$variable=1"
  else
    export "OMNIA_HOST_SET_$variable=0"
  fi
done
export OMNIA_APPIMAGE_BUNDLE=1
export LD_LIBRARY_PATH="$APPDIR/usr/lib"
export QT_PLUGIN_PATH="$APPDIR/usr/plugins"
export QT_QPA_PLATFORM_PLUGIN_PATH="$APPDIR/usr/plugins/platforms"
unset LD_PRELOAD QT_QPA_PLATFORMTHEME QT_STYLE_OVERRIDE
exec "$APPDIR/usr/bin/omnia-installer" "$APPDIR/usr/share/omnia-desktop-suite-installer/packaging/universal/installer_backend.py" "$@"
''');(app/'AppRun').chmod(0o755)
        target=out/f'Omnia-Installer-{VERSION}-{RELEASE}-x86_64.AppImage'
        subprocess.run([str(tool),'--appimage-extract-and-run','--no-appstream','--runtime-file',str(runtime),str(app),str(target)],env={**os.environ,'ARCH':'x86_64'},check=True)
        target.chmod(0o755)
    manifest={'file':target.name,'version':VERSION,'revision':RELEASE,'architecture':'x86_64',
              'target':'CachyOS / Bazzite / KDE Plasma 6; Qt bundled for the graphical assistant',
              'host_glibc':os.confstr('CS_GNU_LIBC_VERSION'),
              'appimagetool_sha256':hashlib.sha256(tool.read_bytes()).hexdigest(),
              'runtime_sha256':hashlib.sha256(runtime.read_bytes()).hexdigest()}
    (out/(target.name+'.json')).write_text(json.dumps(manifest,indent=2)+'\n')
    (out/(target.name+'.sha256')).write_text(hashlib.sha256(target.read_bytes()).hexdigest()+'  '+target.name+'\n')
    print(target)

if __name__=='__main__':main()

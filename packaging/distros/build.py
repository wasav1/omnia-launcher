#!/usr/bin/env python3
"""Paquetes del asistente con fuentes: no distribuyen ELF ligado al Qt del host."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import tarfile
import tempfile
import time
import tomllib

REPO = Path(__file__).resolve().parents[2]
PROFILES = json.loads((REPO / 'packaging/distros/profiles.json').read_text())
NAME = 'omnia-desktop-suite-installer'
VERSION = tomllib.loads((REPO / 'pyproject.toml').read_text())['project']['version']
RELEASE = os.environ.get('OMNIA_PKGREL', '1')
if not RELEASE.isdigit():
    raise ValueError('OMNIA_PKGREL debe ser un entero positivo')


def source_files():
    for base in ('core', 'ui', 'plasma', 'kwin', 'assets', 'packaging/universal', 'packaging/systemd', 'packaging/xdg'):
        for file in sorted((REPO / base).rglob('*')):
            if file.is_file() and not file.is_symlink() and not any(p in {'out', '__pycache__'} for p in file.relative_to(REPO).parts) and file.suffix != '.pyc':
                yield file
    yield REPO / 'packaging/distros/profiles.json'
    yield REPO / 'pyproject.toml'
    yield REPO / 'LICENSE'
    yield REPO / 'docs/INSTALADORES.md'
    yield REPO / 'docs/MangoHud.conf'


def stage(root):
    source = root / 'usr/share' / NAME
    for file in source_files():
        dest = source / file.relative_to(REPO)
        dest.parent.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(file, dest)
        dest.chmod(0o755 if file.suffix == '.sh' else 0o644)
    (source / 'packaging/universal/release.json').write_text(json.dumps({'label': f'{VERSION}-{RELEASE}'}) + '\n')
    shutil.copyfile(REPO / 'docs/INSTALADORES.md', source / 'README.md')
    for src, dest in [('packaging/distros/omnia-desktop-suite-install', 'usr/bin/omnia-desktop-suite-install'),
                      ('packaging/xdg/org.omnia.installer.desktop', 'usr/share/applications/org.omnia.installer.desktop'),
                      ('packaging/xdg/org.omnia.uninstall.desktop', 'usr/share/applications/org.omnia.uninstall.desktop'),
                      ('assets/branding/omnia-logo.svg', 'usr/share/icons/hicolor/scalable/apps/org.omnia.installer.svg'),
                      ('assets/branding/omnia-uninstall-icon.svg', 'usr/share/icons/hicolor/scalable/apps/org.omnia.uninstall.svg')]:
        target=root/dest;target.parent.mkdir(parents=True,exist_ok=True);shutil.copyfile(REPO/src,target)
        target.chmod(0o755 if dest.startswith('usr/bin') else 0o644)
        if dest.endswith('org.omnia.uninstall.desktop'):
            target.write_text(target.read_text().replace('Exec=omnia-uninstall', 'Exec=omnia-desktop-suite-install --uninstall'))


def tar_tree(root, output, prefix=''):
    with tarfile.open(output, 'w:gz' if str(output).endswith('.gz') else 'w') as archive:
        for file in sorted(root.rglob('*')):
            info = archive.gettarinfo(str(file), arcname=str(Path(prefix) / file.relative_to(root)))
            info.uid=info.gid=0; info.uname=info.gname='root';info.mtime=0
            if file.is_file():
                with file.open('rb') as stream: archive.addfile(info,stream)
            else: archive.addfile(info)


def deb(root,out,work):
    metadata=work/'control';metadata.mkdir()
    size=sum(p.stat().st_size for p in root.rglob('*') if p.is_file())//1024
    (metadata/'control').write_text(f'''Package: {NAME}
Version: {VERSION}-{RELEASE}
Architecture: all
Maintainer: wasav1 <wichmann.saenz@outlook.com>
Section: games
Priority: optional
Installed-Size: {size}
Depends: {PROFILES['debian']['depends']}
Homepage: https://github.com/wasav1/omnia-launcher
Description: Asistente grafico de Omnia Desktop Suite para KDE Plasma 6
 Instala el asistente con fuentes. Abre Omnia desde el menu de aplicaciones
 para compilar los componentes Qt locales y configurar el escritorio del usuario.
 No inicia sesiones ni modifica escritorios durante la instalacion del paquete.
''')
    (work/'debian-binary').write_bytes(b'2.0\n')
    tar_tree(metadata,work/'control.tar.gz');tar_tree(root,work/'data.tar.gz')
    target=out/f'{NAME}_{VERSION}-{RELEASE}_all.deb'
    subprocess.run(['ar','rcD',str(target),'debian-binary','control.tar.gz','data.tar.gz'],cwd=work,check=True)
    return target


def arch(root,out,work):
    dest=work/'arch';shutil.copytree(root,dest)
    size=sum(p.stat().st_size for p in root.rglob('*') if p.is_file())
    (dest/'.PKGINFO').write_text(arch_pkginfo(size))
    tar_tree(dest,work/'arch.tar')
    target=out/f'{NAME}-{VERSION}-{RELEASE}-any.pkg.tar.zst'
    subprocess.run(['zstd','-q','-f',str(work/'arch.tar'),'-o',str(target)],check=True)
    return target


def arch_pkginfo(size):
    fields=[f'pkgname = {NAME}',f'pkgbase = {NAME}',f'pkgver = {VERSION}',f'pkgrel = {RELEASE}',
            'pkgdesc = Asistente grafico de Omnia Desktop Suite para KDE Plasma 6',
            'url = https://github.com/wasav1/omnia-launcher',f'builddate = {int(time.time())}',
            'packager = wasav1',f'size = {size}','arch = any','license = GPL-3.0-or-later']
    fields += ['depend = ' + p for p in PROFILES['arch']['depends']]
    return '\n'.join(fields) + '\n'


def rpm(root,out,work,flavor,rpmbuild):
    top=work/flavor
    for folder in ['SOURCES','SPECS','BUILD','RPMS','SRPMS','BUILDROOT']:(top/folder).mkdir(parents=True)
    tar_tree(root,top/'SOURCES/payload.tar.gz','payload')
    deps='\n'.join('Requires: '+d for d in PROFILES[flavor]['depends'])
    text=f'''%global _rpmformat 4
%global _binary_payload w9.gzdio
%global __os_install_post %{{nil}}
%global debug_package %{{nil}}
Name: {NAME}
Version: {VERSION}
Release: {RELEASE}.{flavor}
Summary: Omnia Desktop Suite graphical installer for KDE Plasma 6
License: GPL-3.0-or-later
URL: https://github.com/wasav1/omnia-launcher
Source0: payload.tar.gz
BuildArch: noarch
AutoReqProv: no
{deps}

%description
Installs the graphical assistant and sources. Launch Omnia from the application
menu to compile matching Qt components and configure the current user's desktop.
The package does not restart Plasma or change user data during installation.

%prep
%setup -q -n payload

%build

%install
mkdir -p %{{buildroot}}
cp -a usr %{{buildroot}}/

%files
/usr/bin/omnia-desktop-suite-install
/usr/share/{NAME}
/usr/share/applications/org.omnia.installer.desktop
/usr/share/applications/org.omnia.uninstall.desktop
/usr/share/icons/hicolor/scalable/apps/org.omnia.installer.svg
/usr/share/icons/hicolor/scalable/apps/org.omnia.uninstall.svg
'''
    spec=top/'SPECS/omnia.spec';spec.write_text(text)
    subprocess.run([rpmbuild,'--define',f'_topdir {top}','--define',f'_tmppath {top}', '--define', f'_dbpath {top}/rpmdb','--define','_buildhost omnia-builder','--nodeps','-bb',str(spec)],check=True)
    artifacts=list((top/'RPMS').rglob('*.rpm'))
    if len(artifacts)!=1:raise RuntimeError('RPM no generado')
    target=out/artifacts[0].name;shutil.copyfile(artifacts[0],target)
    return target


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--formats',default='deb,arch,fedora,opensuse,run,source')
    parser.add_argument('--output',type=Path,default=Path(os.environ.get('OMNIA_BUILD_DIR', Path.home()/'.cache/omnia-build')))
    parser.add_argument('--rpmbuild',default=shutil.which('rpmbuild'))
    args=parser.parse_args();formats=args.formats.split(',');out=args.output.resolve();out.mkdir(parents=True,exist_ok=True)
    if any(f in formats for f in ('fedora','opensuse')) and not args.rpmbuild:
        parser.error('Falta rpmbuild. Instala las herramientas RPM o pasa --rpmbuild /ruta/rpmbuild.')
    artifacts=[]
    with tempfile.TemporaryDirectory(prefix='omnia-distributions-') as temporary:
        work=Path(temporary);root=work/'stage';root.mkdir();stage(root)
        for flavor in formats:
            if flavor=='deb':artifacts.append(deb(root,out,work))
            elif flavor=='arch':artifacts.append(arch(root,out,work))
            elif flavor in ('fedora','opensuse'):artifacts.append(rpm(root,out,work,flavor,args.rpmbuild))
            elif flavor=='run':
                target=out/f'Omnia-Desktop-Suite-{VERSION}-source.run'
                subprocess.run(['bash',str(REPO/'packaging/universal/build-run.sh'),'--source-only',str(target)],check=True);artifacts.append(target)
            elif flavor=='source':
                target=out/f'{NAME}-{VERSION}-sources.tar.gz';tar_tree(root/'usr/share'/NAME,target,NAME);artifacts.append(target)
            else:parser.error('Formato desconocido: '+flavor)
    for artifact in artifacts:print(artifact)
    checksums=''.join(hashlib.sha256(p.read_bytes()).hexdigest()+'  '+p.name+'\n' for p in artifacts)
    (out/'SHA256SUMS').write_text(checksums)
    (out/'manifest.json').write_text(json.dumps({'version':VERSION,'artifacts':[p.name for p in artifacts],
        'requires':'Plasma 6, Qt >= 6.6, Python >= 3.11, systemd user session',
        'tested_installation':['CachyOS (universal .run existing workflow)'],
        'target_distro_installation':'Pending; package format and payload checks only'},indent=2)+'\n')

if __name__=='__main__':main()

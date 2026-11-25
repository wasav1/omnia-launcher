"""Identificación conservadora de ports locales. Nunca ejecuta archivos ni descarga datos."""
import re
from pathlib import Path

CATALOG = {
    # Se registran los puntos de inicio del juego; el wrapper de Longshot es el
    # lanzador canónico del build y por eso tiene prioridad sobre bin/longshot.
    'longshot': {'game': 'The Legend of Zelda: Ocarina of Time', 'port': 'Longshot', 'platform': 'sw2', 'folders': ('longshot',), 'executables': ('longshot',)},
    'hookshot': {'game': 'The Legend of Zelda: Ocarina of Time', 'port': 'Hookshot', 'platform': 'sw2', 'folders': ('hookshot',), 'executables': ('hookshot',)},
    'nx2navi': {'game': 'The Legend of Zelda: Ocarina of Time', 'port': 'NX2navi', 'platform': 'sw2', 'folders': ('nx2navi',), 'executables': ('ocarina',)},
    'savagewind': {'game': 'The Legend of Zelda: Breath of the Wild', 'port': 'Savage Wind', 'platform': 'sw1', 'folders': ('savagewind',), 'executables': ('savagewind',)},
    'totkrecomp': {'game': 'The Legend of Zelda: Tears of the Kingdom', 'port': 'TOTK Recomp', 'platform': 'sw1', 'folders': ('totkrecomp',), 'executables': ('totk',)},
}


def normalize(value):
    return re.sub(r'[^a-z0-9]', '', value.lower())


def identify(path):
    """Nombre de ejecutable + contexto de instalación; una carpeta sola no basta."""
    file = Path(path)
    low = file.name.lower()
    if any(word in low for word in ('launcher', 'builder', 'setup', 'updater', '_xlate', 'crash', 'uninstall')):
        return None
    ancestors = list(file.parents)[:5]
    stem = file.stem.lower() if file.suffix.lower() in ('.exe', '.appimage', '.sh') else low
    for template, record in CATALOG.items():
        folder = next((p for p in ancestors if normalize(p.name) in record['folders']), None)
        matches = stem in record['executables']
        if template == 'nx2navi' and file.suffix.lower() == '.sh':
            try:
                with file.open(errors='replace') as source:
                    content = source.read(4096)
                matches = 'ocarina' in content and (file.parent / 'ocarina').is_file()
            except OSError:
                pass
        if template == 'savagewind' and file.suffix.lower() == '.appimage':
            matches = bool(re.match(r'^savage[_-]?wind(?:[-_].*)?$', stem))
        if matches and folder:
            # Un wrapper guarda partidas junto al ejecutable real, no junto al shell arbitrario.
            install = file.parent.parent if file.parent.name == 'bin' else file.parent
            launcher_priority = 0
            if template == 'longshot':
                try:
                    with file.open(errors='replace') as source:
                        prefix = source.read(4096)
                    if prefix.startswith('#!/bin/sh') and 'builder_line()' in prefix and '--launch "$HERE"' in prefix:
                        launcher_priority = 1
                except OSError:
                    pass
            if template == 'nx2navi' and file.suffix.lower() == '.sh':
                launcher_priority = 1
            return {**record, 'template': template, 'group': str(folder), 'install': str(install),
                    'launcher_priority': launcher_priority}
    return None


def version_key(path):
    """Prioriza versiones numeradas; el usuario confirma la selección propuesta."""
    versions = re.findall(r'(?:^|[/_-])v?(\d+)\.(\d+)\.(\d+)(?:[-.]?(rc|alpha|beta)[.-]?(\d+))?', str(path), re.IGNORECASE)
    if not versions:
        return (-1, -1, -1, -1, -1)
    major, minor, patch, stage, number = versions[-1]
    return (int(major), int(minor), int(patch), {'alpha': 0, 'beta': 1, 'rc': 2, '': 3}[stage.lower()], int(number or 0))

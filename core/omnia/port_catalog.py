"""Identificación conservadora de ports locales. Nunca ejecuta archivos ni descarga datos."""
from pathlib import Path
import re

CATALOG = {
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
        if template == 'savagewind' and file.suffix.lower() == '.appimage':
            matches = bool(re.match(r'^savage[_-]?wind(?:[-_].*)?$', stem))
        if template == 'nx2navi' and low == 'play.sh' and folder:
            try:
                matches = bool(re.search(r'exec\s+\./ocarina(?:\s|$)', file.read_text()[:4096])) and (file.parent / 'ocarina').is_file()
            except (OSError, UnicodeError):
                matches = False
        if matches and folder:
            # Un wrapper guarda partidas junto al ejecutable real, no junto al shell arbitrario.
            install = file.parent.parent if file.parent.name == 'bin' else file.parent
            return {**record, 'template': template, 'group': str(folder), 'install': str(install)}
    return None


def version_key(path):
    """Prioriza versiones numeradas; el usuario confirma la selección propuesta."""
    versions = re.findall(r'(?:^|[/_-])v?(\d+)\.(\d+)\.(\d+)(?:[-.]?(rc|alpha|beta)[.-]?(\d+))?', str(path), re.I)
    if not versions:
        return (-1, -1, -1, -1, -1)
    major, minor, patch, stage, number = versions[-1]
    return (int(major), int(minor), int(patch), {'alpha': 0, 'beta': 1, 'rc': 2, '': 3}[stage.lower()], int(number or 0))

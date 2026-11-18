"""Prepara solo los candidatos confirmados. Nunca lanza binarios durante la importación."""
import os
import shutil
import re
from pathlib import Path
import tempfile
from omnia import manual, templates, port_catalog
from omnia.store import Store


def requirements(selected):
    """Requisitos de los archivos seleccionados, recalculados antes de guardar."""
    selected = [item for item in selected if not item.get('unlink')]
    missing = []
    n64 = [item for item in selected if item.get('kind') == 'rom' and item.get('emulator') == 'gopher64']
    invalid_n64 = [item for item in n64 if Path(str(item.get('file', ''))).suffix.lower() not in {'.z64', '.n64', '.v64'}]
    if invalid_n64:
        missing.append({'component': 'Emulador compatible', 'message': 'Gopher64 es para Nintendo 64 (.z64, .n64, .v64). Selecciona un emulador compatible con las otras ROMs marcadas.'})
    needs_n64 = bool(n64) and not invalid_n64
    if needs_n64:
        try:
            templates.gopher64_install()
        except templates.TemplateError:
            missing.append({'component': 'Gopher64', 'message': 'Instala Gopher64 para importar las ROMs de N64 seleccionadas. En Arch/CachyOS: paquete AUR gopher64 o gopher64-bin; también se admite su Flatpak.'})
    if any(Path(str(item.get('file', ''))).suffix.lower() == '.exe' and item.get('kind') != 'rom'
           and not templates.bedrock_on_linux_appimage(str(item.get('file', ''))) for item in selected) and not shutil.which('umu-run'):
        missing.append({'component': 'UMU Launcher', 'message': 'Instala umu-launcher para los ejecutables Windows seleccionados. En Arch/CachyOS está disponible desde el gestor de paquetes.'})
    for item in selected:
        if item.get('kind') == 'rom' and item.get('emulator') not in ('gopher64', ''):
            emulator = str(item['emulator'])
            if not os.path.isabs(emulator) or not os.path.isfile(emulator) or not os.access(emulator, os.X_OK):
                missing.append({'component': 'Emulador', 'message': 'Instala y selecciona un emulador ejecutable para ' + str(item.get('name', 'la ROM')) + '.'})
    return missing


def prepare(games, selected, roots):
    try:
        return _prepare(games, selected, roots)
    except (manual.ManualError, templates.TemplateError) as error:
        raise ValueError(str(error)) from None


def _prepare(games, selected, roots):
    missing = requirements(selected)
    if missing:
        raise ValueError('\n'.join(item['message'] for item in missing))
    roots = [os.path.realpath(p) for p in roots]
    known = {os.path.realpath(p.get('check', '')) for g in games for p in g.get('ports', []) if p.get('check')}
    added = 0
    with tempfile.TemporaryDirectory(prefix='omnia-candidates-') as directory:
        staging = Store(Path(directory)); staging.set_games(games)
        for item in selected:
            path = os.path.realpath(str(item.get('file', '')))
            if not os.path.isfile(path) or not any(path == r or path.startswith(r.rstrip('/') + '/') for r in roots):
                raise ValueError('Un candidato no existe o está fuera de las rutas seleccionadas.')
            if path in known:
                continue
            name = str(item.get('name', '')).strip()
            if not name or len(name) > 80:
                raise ValueError('Revisa el nombre del candidato (hasta 80 caracteres).')
            if item.get('kind') == 'rom':
                emulator = str(item.get('emulator', ''))
                if emulator == 'gopher64':
                    manual.add_game(staging, {'name': name, 'template': 'gopher64', 'rom': path}, roots)
                else:
                    if not os.path.isabs(emulator) or not os.path.isfile(emulator) or not os.access(emulator, os.X_OK):
                        raise ValueError('Selecciona un emulador ejecutable para cada ROM marcada.')
                    gid = 'manual-' + manual.slug(name)
                    base=gid; index=2
                    while staging.find_game(gid):
                        gid=base+'-'+str(index); index+=1
                    entry={'id':gid,'name':name,'platform':'pc','src':'Manual','sub':'Emulador',
                           'art':{'slug':gid,'sgdb':name},'ports':[{'id':gid+'-main','name':'Emulador',
                           'launch':[emulator,path],'check':path,'proc':os.path.basename(emulator)}]}
                    staging.set_games(staging.games()+[entry])
            else:
                if item.get('template') == 'bedrock-on-linux':
                    manual.add_game(staging, {'name': name, 'exe': path, 'template': 'bedrock-on-linux'}, roots)
                    known.add(path); added += 1
                    continue
                record = port_catalog.identify(path)
                if record:
                    windows = Path(path).suffix.lower() == '.exe'
                    data = {'name': name, 'exe': path, 'kind': 'windows' if windows else 'port'}
                    if not windows: data['template'] = record['template']
                    entry = manual.add_game(staging, data, roots)
                    key = record['platform'] + ':' + port_catalog.normalize(record['game'])
                    entry.update(platform=record['platform'], sub='Port recompilado', catalog_game=key)
                    entry['art']['sgdb'] = record['game']
                    port = entry['ports'][0]
                    port.update(name=record['port'], template=record['template'], chips=['Port recompilado'])
                    if record['template'] == 'nx2navi' and Path(path).suffix.lower() == '.sh':
                        port['proc'] = 'ocarina'
                    rows = staging.games()
                    rows = [entry if g['id'] == entry['id'] else g for g in rows]
                    def same_game(game):
                        if game.get('catalog_game') == key: return True
                        if game.get('auto'): return False
                        for old in game.get('ports', []):
                            identified = port_catalog.identify(old.get('check', ''))
                            if identified and identified['platform'] + ':' + port_catalog.normalize(identified['game']) == key:
                                return True
                        return False
                    same = next((g for g in rows if g['id'] != entry['id'] and same_game(g)), None)
                    if same:
                        same = dict(same)
                        same.update(catalog_game=key, platform=record['platform'], sub='Port recompilado')
                        same['art'] = {**same.get('art', {}), 'sgdb': record['game']}
                        if re.fullmatch(r'v?\d+\.\d+\.\d+.*', same.get('name', ''), re.I): same['name'] = name
                        port['id'] = same['id'] + '-' + record['template'] + '-' + str(len(same['ports']) + 1)
                        same['ports'] = same['ports'] + [port]
                        rows = [same if g['id'] == same['id'] else g for g in rows if g['id'] != entry['id']]
                    staging.set_games(rows)
                else:
                    manual.add_game(staging, {'name':name,'kind':'windows' if Path(path).suffix.lower()=='.exe' else 'native','exe':path}, roots)
            known.add(path); added+=1
        return staging.games(), added

"""Prepara solo los candidatos confirmados. Nunca lanza binarios durante la importación."""
import os
from pathlib import Path
import tempfile
from omnia import manual, templates
from omnia.store import Store


def prepare(games, selected, roots):
    try:
        return _prepare(games, selected, roots)
    except (manual.ManualError, templates.TemplateError) as error:
        raise ValueError(str(error)) from None


def _prepare(games, selected, roots):
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
                manual.add_game(staging, {'name':name,'kind':'windows' if Path(path).suffix.lower()=='.exe' else 'native','exe':path}, roots)
            known.add(path); added+=1
        return staging.games(), added

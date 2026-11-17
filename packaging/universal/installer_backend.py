#!/usr/bin/env python3
"""Backend del asistente: sin contraseñas; secretos por stdin, nunca argv."""
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import urllib.request
import urllib.error
import socket

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / 'core'))
sys.path.insert(0, str(Path(__file__).resolve().parent))
from omnia import paths, library_paths
from omnia.store import load_json, write_json_atomic
from route_inspection import effective_roots, inspect_route
from candidate_import import prepare, requirements


def volumes():
    data = json.loads(subprocess.check_output(['lsblk', '-J', '-b', '-o', 'NAME,LABEL,UUID,MODEL,SIZE,FSTYPE,MOUNTPOINTS'], text=True))
    result, seen = [], set()
    def visit(nodes, model=''):
        for n in nodes:
            model_now = (n.get('model') or model).strip()
            mounts = [p for p in n.get('mountpoints', []) if p and p.startswith('/') and Path(p).is_dir()]
            ident = n.get('uuid') or n['name']
            if mounts and n.get('fstype') not in ('swap', 'vfat') and ident not in seen:
                seen.add(ident)
                mount = min(mounts, key=len)
                label = n.get('label') or f"{model_now or 'Disco'} · {n['name']}"
                result.append({'label': label, 'uuid': n.get('uuid') or '', 'path': mount, 'device': n['name'], 'fs': n.get('fstype'), 'size': n.get('size', 0)})
            visit(n.get('children', []), model_now)
    visit(data['blockdevices'])
    return result


def configure(data, consent=True):
    config_file = paths.config_dir() / 'config.json'
    cfg = load_json(config_file, {})
    games = load_json(paths.config_dir() / 'library.json', {}).get('games', [])
    old_roots = effective_roots(cfg, games)
    roots = list(dict.fromkeys(str(Path(p).expanduser().resolve()) for p in data.get('external_roots', [])))
    if any((not Path(p).is_dir() or not os.access(p, os.R_OK | os.X_OK)) and p not in old_roots for p in roots):
        raise ValueError('Una carpeta elegida no existe o no es accesible.')
    disk = data.get('monitor_disk', {})
    matches = [v for v in volumes() if v['path'] == disk.get('path') and v['uuid'] == disk.get('uuid', '')]
    if not matches:
        if not consent and disk == cfg.get('monitor_disk', {}):
            matches = [disk]
        else:
            raise ValueError('El volumen seleccionado ya no está montado. Vuelve a seleccionarlo.')
    excluded = library_paths.update_excluded({**cfg, "external_roots": old_roots}, roots)
    prepared, added = prepare(games, data.get('selected_candidates', []), roots)
    cfg.update(external_roots=roots, excluded_external_roots=excluded, monitor_disk=matches[0])
    write_json_atomic(config_file, cfg)
    key = data.get('steamgriddb_key', '').strip()
    if data.get('clear_key'):
        (paths.config_dir() / 'steamgriddb.key').unlink(missing_ok=True)
    elif key:
        write_secret(paths.config_dir() / 'steamgriddb.key', key)
    if added:
        library = load_json(paths.config_dir() / 'library.json', {})
        library['games'] = prepared
        write_json_atomic(paths.config_dir() / 'library.json', library)
    if consent:
        write_json_atomic(paths.config_dir() / 'installer-consent.json', {'accepted': True, 'notice_version': 1})
    return added


def write_secret(path, text):
    path.parent.mkdir(parents=True, exist_ok=True)
    fd, name = tempfile.mkstemp(dir=path.parent, prefix='.omnia-key-')
    try:
        with os.fdopen(fd, 'w') as f:
            f.write(text + '\n')
        os.replace(name, path)
    finally:
        if os.path.exists(name): os.unlink(name)


def validate_key(key, opener=None):
    """La misma identidad HTTP del cliente de arte; nunca incluye la clave en errores."""
    if not key:
        return 'Introduce una clave para validarla.', 1
    opener = opener or urllib.request.urlopen
    try:
        req = urllib.request.Request('https://www.steamgriddb.com/api/v2/games/id/1',
                                     headers={'Authorization': 'Bearer ' + key, 'User-Agent': 'omnia'})
        with opener(req, timeout=15) as response:
            body = json.loads(response.read(1024 * 1024))
            if response.status == 200 and body.get('success') is True:
                return '✓ Clave válida. SteamGridDB confirmó el acceso.', 0
        return 'SteamGridDB no confirmó el acceso. Intenta de nuevo más tarde.', 1
    except urllib.error.HTTPError as error:
        messages = {
            401: 'SteamGridDB rechazó la clave. Revisa que la hayas copiado completa.',
            403: 'SteamGridDB bloqueó la solicitud (403). No se pudo confirmar si la clave es válida.',
            429: 'SteamGridDB recibió demasiadas solicitudes. Espera y vuelve a intentar.',
        }
        return messages.get(error.code, f'SteamGridDB respondió con un error HTTP {error.code}. Intenta más tarde.'), 1
    except (TimeoutError, socket.timeout):
        return 'SteamGridDB tardó demasiado en responder. No se ha validado la clave.', 1
    except urllib.error.URLError:
        return 'No se pudo conectar con SteamGridDB. Revisa la conexión y vuelve a intentar.', 1
    except (ValueError, OSError):
        return 'No se pudo interpretar la respuesta de SteamGridDB. Intenta más tarde.', 1


def logo_path():
    candidates = [ROOT / 'assets/branding/omnia-icon-bluegray.png', ROOT / 'assets/branding/omnia-logo.png', paths.data_dir() / 'assets/branding/omnia-logo.png',
                  Path('/usr/share/omnia/assets/branding/omnia-logo.png')]
    return str(next((p for p in candidates if p.is_file()), candidates[0]))


def main():
    mode = sys.argv[1]
    if mode == '--inspect':
        from omnia.games.steam import SteamDetector, steam_roots, library_dirs
        cfg = load_json(paths.config_dir() / 'config.json', {})
        games = load_json(paths.config_dir() / 'library.json', {}).get('games', [])
        roots = effective_roots(cfg, games)
        print(json.dumps({'volumes': volumes(), 'config': cfg, 'steam_count': len(SteamDetector().detect()),
                          'steam_libraries': [str(p.parent) for r in steam_roots() for p in library_dirs(r)],
                          'logo': logo_path(),
                          'installed': (paths.config_dir() / 'library.json').exists() or (paths.data_dir() / 'installer/omnia-installer').exists(),
                          'linked_roots': roots,
                          'key_exists': (paths.config_dir() / 'steamgriddb.key').exists()}))
    elif mode == '--uninstall-plan':
        from omnia.uninstall import plan
        print(json.dumps(plan()))
    elif mode == '--uninstall':
        data = json.load(sys.stdin)
        if data.get('accepted') is not True:
            raise ValueError('Debes confirmar la eliminación de los datos de Omnia.')
        from omnia.uninstall import uninstall
        print(uninstall(remove_package=data.get('remove_package') is True))
    elif mode == '--check-candidates':
        data = json.load(sys.stdin)
        missing = requirements(data.get('selected_candidates', []))
        print(json.dumps({'missing': missing, 'ready': not missing}))
    elif mode == '--inspect-route':
        data = json.load(sys.stdin)
        games = load_json(paths.config_dir() / 'library.json', {}).get('games', [])
        print(json.dumps(inspect_route(str(data.get('path', '')), games)))
    elif mode == '--validate-saved-key':
        file = paths.config_dir() / 'steamgriddb.key'
        message, status = validate_key(file.read_text().strip() if file.exists() else '')
        print(message)
        return status
    elif mode == '--validate-key':
        key = sys.stdin.read().strip()
        message, status = validate_key(key)
        print(message)
        return status
    elif mode == '--save-settings':
        data = json.load(sys.stdin)
        stopped = subprocess.run(['systemctl', '--user', 'stop', 'omnia.service'], capture_output=True)
        if stopped.returncode:
            print('No se pudo detener el núcleo para guardar con seguridad. No se cambiaron los ajustes.')
            return 1
        try:
            added = configure(data, consent=False)
        finally:
            restart = subprocess.run(['systemctl', '--user', 'start', 'omnia.service'], capture_output=True)
        if restart.returncode:
            print('Ajustes guardados. No se pudo iniciar el servicio; ejecuta systemctl --user start omnia.service.')
            return 2
        print(f'Ajustes guardados. {added} juegos agregados. La biblioteca se actualizará automáticamente.')
    elif mode == '--configure':
        configure(json.loads(Path(sys.argv[2]).read_text()))
    elif mode == '--install':
        data = json.load(sys.stdin)
        if data.get('accepted') is not True:
            raise ValueError('Debes aceptar la información de instalación.')
        fd, name = tempfile.mkstemp(prefix='omnia-settings-', suffix='.json')
        try:
            with os.fdopen(fd, 'w') as f: json.dump(data, f)
            env = {**os.environ, 'OMNIA_SETTINGS': name}
            return subprocess.call(['bash', str(ROOT / 'packaging/universal/install.sh'), '--cli'], env=env)
        finally:
            os.unlink(name)
    return 0

if __name__ == '__main__':
    try:
        sys.exit(main())
    except (ValueError, RuntimeError) as error:
        print(str(error), file=sys.stderr)
        sys.exit(1)
    except Exception:
        print('No se pudo completar la configuración. Revisa las carpetas y el disco seleccionado.', file=sys.stderr)
        sys.exit(1)

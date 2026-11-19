#!/usr/bin/env python3
"""Backend del asistente: sin contraseñas; secretos por stdin, nunca argv."""
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import urllib.request
import urllib.error
import socket
import stat

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / 'core'))
sys.path.insert(0, str(Path(__file__).resolve().parent))
from omnia import paths, library_paths
from omnia.themes import THEMES, normalize_theme
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


def set_session_autostart(enabled):
    entry = Path.home() / '.config/autostart/omnia-maintain.desktop'
    if not enabled:
        entry.unlink(missing_ok=True)
        return
    command = str(Path.home() / '.local/bin/omnia-maintain')
    entry.parent.mkdir(parents=True, exist_ok=True)
    entry.write_text('[Desktop Entry]\nType=Application\nName=Omnia: restaurar escritorio\n'
                     'Comment=Aplicar el fondo y el widget de Omnia al iniciar Plasma\n'
                     f'Exec="{command}"\nIcon=org.omnia.menu\nTerminal=false\nX-KDE-autostart-phase=2\n')


def configure(data, consent=True):
    config_file = paths.config_dir() / 'config.json'
    # La actualización de una instalación existente solo puede guardar una
    # clave que el asistente ya validó. No consulta discos ni toca la biblioteca.
    if data.get('update_only') is True:
        cfg = load_json(config_file, {})
        if 'mangohud_enabled' not in cfg:
            cfg['mangohud_enabled'] = True
        cfg.setdefault('keep_omnia_session', True)
        if 'theme' in data:
            cfg['theme'] = normalize_theme(data.get('theme'))
        set_session_autostart(cfg['keep_omnia_session'])
        key = data.get('steamgriddb_key', '').strip()
        if key:
            write_secret(paths.config_dir() / 'steamgriddb.key', key)
        write_json_atomic(config_file, cfg)
        return 0
    cfg = load_json(config_file, {})
    cfg['theme'] = normalize_theme(data.get('theme', cfg.get('theme')))
    cfg['mangohud_enabled'] = bool(data.get('mangohud_enabled', cfg.get('mangohud_enabled', True)))
    games = load_json(paths.config_dir() / 'library.json', {}).get('games', [])
    old_roots = effective_roots(cfg, games)
    roots = list(dict.fromkeys(str(Path(p).expanduser().resolve()) for p in data.get('external_roots', [])))
    if any((not Path(p).is_dir() or not os.access(p, os.R_OK | os.X_OK)) and p not in old_roots for p in roots):
        raise ValueError('Una carpeta elegida no existe o no es accesible.')
    requested = data.get('monitor_disks')
    if requested is None:
        old = data.get('monitor_disk', cfg.get('monitor_disk', {}))
        requested = [old] if old else cfg.get('monitor_disks', [])
    if not isinstance(requested, list) or any(not isinstance(x, dict) for x in requested):
        raise ValueError('La selección de discos no es válida.')
    available = volumes(); matches = []
    saved_volumes = cfg.get('monitor_disks')
    if saved_volumes is None and cfg.get('monitor_disk'):
        saved_volumes = [cfg['monitor_disk']]
    for disk in requested:
        match = next((v for v in available if v['path'] == disk.get('path') and v['uuid'] == disk.get('uuid', '')), None)
        if match:
            matches.append(match)
        elif not consent and disk in saved_volumes:
            matches.append(disk)
        else:
            raise ValueError('Uno de los volúmenes seleccionados ya no está montado. Vuelve a seleccionarlo.')
    excluded = library_paths.update_excluded({**cfg, "external_roots": old_roots}, roots)
    selected = data.get('selected_candidates', [])
    if not isinstance(selected, list):
        raise ValueError('La selección de juegos no es válida.')
    unlink = [x for x in selected if isinstance(x, dict) and x.get('unlink') is True]
    additions = [x for x in selected if not (isinstance(x, dict) and x.get('unlink') is True)]
    prepared, added = prepare(games, additions, roots)
    unlinked = 0
    for item in unlink:
        path = os.path.realpath(str(item.get('file', '')))
        if not os.path.isfile(path) or not any(path == root or path.startswith(root.rstrip('/') + '/') for root in roots):
            raise ValueError('No se puede desvincular un juego fuera de las rutas seleccionadas.')
        removed = False
        updated = []
        for game in prepared:
            if game.get('auto'):
                updated.append(game); continue
            ports = game.get('ports', [])
            kept = [port for port in ports if os.path.realpath(os.path.expanduser(port.get('check') or (port.get('launch') or [''])[0])) != path]
            if len(kept) != len(ports):
                removed = True
                if kept:
                    game = {**game, 'ports': kept}
                    updated.append(game)
            else:
                updated.append(game)
        if not removed:
            raise ValueError('El juego ya no está vinculado o no pertenece a esta carpeta.')
        prepared = updated
        unlinked += 1
    notification_position = str(data.get('notification_position', cfg.get('notification_position', 'bottom-right')))
    if notification_position not in {'bottom-right', 'bottom-left', 'top-right', 'top-left'}:
        notification_position = 'bottom-right'
    cfg.update(external_roots=roots, excluded_external_roots=excluded, monitor_disks=matches,
               monitor_disk=matches[0] if matches else {}, notification_position=notification_position)
    if 'keep_omnia_session' in data:
        cfg['keep_omnia_session'] = bool(data['keep_omnia_session'])
        set_session_autostart(cfg['keep_omnia_session'])
    write_json_atomic(config_file, cfg)
    key = data.get('steamgriddb_key', '').strip()
    if data.get('clear_key'):
        (paths.config_dir() / 'steamgriddb.key').unlink(missing_ok=True)
    elif key:
        write_secret(paths.config_dir() / 'steamgriddb.key', key)
    if added or unlinked:
        library = load_json(paths.config_dir() / 'library.json', {})
        library['games'] = prepared
        write_json_atomic(paths.config_dir() / 'library.json', library)
    if consent:
        write_json_atomic(paths.config_dir() / 'installer-consent.json', {'accepted': True, 'notice_version': 1})
    return {'added': added, 'unlinked': unlinked}


def write_secret(path, text):
    path.parent.mkdir(parents=True, exist_ok=True)
    fd, name = tempfile.mkstemp(dir=path.parent, prefix='.omnia-key-')
    try:
        with os.fdopen(fd, 'w') as f:
            f.write(text + '\n')
        os.replace(name, path)
    finally:
        if os.path.exists(name): os.unlink(name)


def read_settings_file(name):
    """Lee solo un JSON regular, pequeño y propiedad del usuario actual."""
    fd = os.open(name, os.O_RDONLY | getattr(os, 'O_NOFOLLOW', 0))
    try:
        st = os.fstat(fd)
        if not stat.S_ISREG(st.st_mode) or st.st_uid != os.getuid() or st.st_size > 1024 * 1024:
            raise ValueError('El archivo de configuración no es válido.')
        with os.fdopen(fd, 'r', encoding='utf-8', closefd=False) as stream:
            payload = stream.read(1024 * 1024 + 1)
        if len(payload) > 1024 * 1024:
            raise ValueError('El archivo de configuración supera el tamaño permitido.')
        return json.loads(payload)
    finally:
        os.close(fd)


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


def release_label(path):
    value = load_json(path, {})
    label = value.get('label') if isinstance(value, dict) else None
    return label if isinstance(label, str) and label else None


def main():
    mode = sys.argv[1]
    if mode == '--inspect':
        from omnia.games.steam import SteamDetector, steam_roots, library_dirs
        cfg = load_json(paths.config_dir() / 'config.json', {})
        games = load_json(paths.config_dir() / 'library.json', {}).get('games', [])
        roots = effective_roots(cfg, games)
        print(json.dumps({'volumes': volumes(), 'config': cfg, 'steam_count': len(SteamDetector().detect()),
                          'themes': THEMES,
                          'steam_libraries': [str(p.parent) for r in steam_roots() for p in library_dirs(r)],
                          'logo': logo_path(),
                          'installed_version': release_label(paths.data_dir() / 'installer/release.json'),
                          'available_version': release_label(Path(__file__).parent / 'release.json'),
                          'installed': (paths.config_dir() / 'library.json').exists() or (paths.data_dir() / 'installer/omnia-installer').exists(),
                          'linked_roots': roots,
                          'mangohud_available': shutil.which('mangohud') is not None,
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
            changes = configure(data, consent=False)
        finally:
            restart = subprocess.run(['systemctl', '--user', 'start', 'omnia.service'], capture_output=True)
        if restart.returncode:
            print('Ajustes guardados. No se pudo iniciar el servicio; ejecuta systemctl --user start omnia.service.')
            return 2
        print(f"Ajustes guardados. {changes.get('added', 0)} juegos vinculados y {changes.get('unlinked', 0)} desvinculados. La biblioteca se actualizará automáticamente.")
    elif mode == '--configure':
        configure(read_settings_file(sys.argv[2]))
    elif mode == '--install':
        data = json.load(sys.stdin)
        if data.get('accepted') is not True:
            raise ValueError('Debes aceptar la información de instalación.')
        fd, name = tempfile.mkstemp(prefix='omnia-settings-', suffix='.json')
        try:
            with os.fdopen(fd, 'w') as f: json.dump(data, f)
            env = {**os.environ, 'OMNIA_SETTINGS': name}
            install_args = ['--cli']
            if data.get('update_only') is True:
                install_args.append('--update')
            return subprocess.call(['bash', str(ROOT / 'packaging/universal/install.sh'), *install_args], env=env)
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

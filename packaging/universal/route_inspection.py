"""Lectura limitada de rutas y migración de bibliotecas antiguas. No ejecuta archivos."""
import os
import time
from pathlib import Path
from omnia import library_paths, port_catalog, templates


def location(port):
    path = port.get('check') or port.get('cwd') or ''
    return os.path.realpath(os.path.expanduser(path)) if path else ''


def inside(path, root):
    return path == root or path.startswith(root.rstrip('/') + '/')


def effective_roots(config, games):
    roots = list(dict.fromkeys(os.path.realpath(os.path.expanduser(p)) for p in config.get('external_roots', [])))
    for game in games:
        if game.get('auto'):
            continue
        for port in game.get('ports', []):
            path = location(port)
            if not path or not library_paths.port_visible(game, port, config):
                continue
            if not inside(path, str(Path.home())) and path.startswith(('/usr/', '/bin/', '/opt/omnia')):
                continue
            folder = path if os.path.isdir(path) else str(Path(path).parent)
            if folder != '/' and not any(inside(folder, root) for root in roots):
                roots.append(folder)
    return roots


def inspect_route(path, games, max_files=25000, max_seconds=3):
    root = os.path.realpath(os.path.expanduser(path))
    linked = set()
    for game in games:
        if not game.get('auto') and any(inside(location(p), root) for p in game.get('ports', []) if location(p)):
            linked.add(game['id'])
    out = {'path': root, 'linked': len(linked), 'available': False, 'candidates': 0, 'partial': False, 'items': []}
    if not os.path.isdir(root) or not os.access(root, os.R_OK | os.X_OK):
        out['message'] = 'No disponible o sin permiso'
        return out
    out['available'] = True
    deadline, visited, candidates = time.monotonic() + max_seconds, 0, {}
    linked_files = {location(p) for g in games for p in g.get('ports', []) if location(p)}
    def finish():
        # Agrupa versiones y bin/ por port; conserva todos los lanzadores válidos para revisión.
        grouped = {}
        for candidate in candidates.values():
            bedrock_exe = next((file for file in candidate['files'] if templates.bedrock_on_linux_appimage(file)), None)
            if bedrock_exe:
                game_root = next(p for p in Path(bedrock_exe).parents if p.name == 'Minecraft')
                grouped[('bedrock-on-linux', str(game_root))] = {
                    'path': str(game_root), 'root': root, 'name': 'Minecraft Bedrock', 'kind': 'port',
                    'template': 'bedrock-on-linux', 'platform': 'pc', 'port_name': 'BedrockOnLinux',
                    'game_key': 'pc:minecraft bedrock', 'files': [bedrock_exe],
                    'linked_files': [bedrock_exe] if bedrock_exe in linked_files else [],
                    'linked': bedrock_exe in linked_files, 'suggested_file': bedrock_exe}
                continue
            for file in candidate['files']:
                if templates.bedrock_on_linux_appimage(file):
                    continue
                record = port_catalog.identify(file)
                if record:
                    key = ('port', record['template'], record['group'])
                    entry = grouped.setdefault(key, {'path': record['group'], 'root': root, 'name': record['game'],
                        'kind': 'port', 'template': record['template'], 'platform': record['platform'],
                        'port_name': record['port'], 'game_key': record['platform'] + ':' + port_catalog.normalize(record['game']), 'files': [], 'linked_files': [], 'linked': False})
                    if file not in entry['files']: entry['files'].append(file)
                    if file in linked_files and file not in entry['linked_files']: entry['linked_files'].append(file)
                    entry['linked'] |= file in linked_files
                else:
                    key = ('candidate', candidate['path'])
                    entry = grouped.setdefault(key, {**candidate, 'files': [], 'linked_files': []})
                    if file not in entry['files']: entry['files'].append(file)
                    if file in linked_files and file not in entry['linked_files']: entry['linked_files'].append(file)
        for candidate in grouped.values():
            if candidate['kind'] == 'port':
                new_files = [p for p in candidate['files'] if p not in linked_files]
                candidate['linked'] = not new_files
                if new_files: candidate['files'] = new_files
                else: candidate['files'] = candidate['linked_files']
                candidate['files'].sort(key=lambda p: (port_catalog.version_key(p),
                    (port_catalog.identify(p) or {}).get('launcher_priority', 0)), reverse=True)
                candidate['suggested_file'] = candidate['files'][0]
            elif candidate.get('linked') and candidate.get('linked_files'):
                candidate['files'] = candidate['linked_files']
            if candidate['kind'] == 'rom' and Path(candidate['files'][0]).suffix.lower() in {'.n64', '.z64', '.v64'}:
                candidate['suggested_emulator'] = 'gopher64'
        bedrock_roots = [c['path'] for c in grouped.values() if c.get('template') == 'bedrock-on-linux']
        grouped = {k:c for k,c in grouped.items() if c.get('files') and
                   (c.get('template') == 'bedrock-on-linux' or not any(inside(c['path'], p) for p in bedrock_roots))}
        port_roots = [c['path'] for c in grouped.values() if c['kind'] == 'port']
        grouped = {k:c for k,c in grouped.items() if c['kind'] != 'executable' or not any(inside(c['path'], p) for p in port_roots)}
        candidates.clear(); candidates.update(grouped)
        out['candidates'] = len(candidates)
        out['items'] = sorted(candidates.values(), key=lambda c: c['name'].casefold())
        return out
    roms = {'.z64', '.v64', '.n64', '.nes', '.sfc', '.smc', '.gba', '.gbc', '.gb', '.nds', '.3ds', '.nsp', '.xci', '.chd', '.iso', '.cue'}
    executables = {'.exe', '.appimage', '.sh'}
    ignored = {'node_modules', '__pycache__', '.git', 'steamapps', '_Partidas', 'drive_c', 'compatdata', 'shadercache'}
    def fail(_error): out['partial'] = True
    for folder, dirs, files in os.walk(root, followlinks=False, onerror=fail):
        if time.monotonic() > deadline:
            out['partial'] = True
            break
        dirs[:] = [d for d in dirs if not d.startswith('.') and d not in ignored and not os.path.islink(os.path.join(folder, d))]
        if len(Path(folder).relative_to(root).parts) >= 8:
            if dirs: out['partial'] = True
            dirs[:] = []
        for name in files:
            visited += 1
            if visited > max_files or time.monotonic() > deadline:
                out['partial'] = True
                return finish()
            file = Path(folder) / name
            if file.is_symlink() or name.startswith('.'):
                continue
            suffix = file.suffix.lower()
            low = name.lower()
            if any(word in low for word in ('unins', 'uninstall', 'crashreport', 'vcredist', 'dxsetup', 'setup', 'updater', '_xlate', 'launcher', 'builder', 'crashhandler')):
                continue
            if suffix in roms:
                candidates[str(file)] = {'path': str(file), 'root': root, 'name': file.stem,
                                         'kind': 'rom', 'files': [str(file)], 'linked': str(file) in linked_files}
            elif suffix in executables or (not suffix and os.access(file, os.X_OK)):
                entry = candidates.setdefault(str(file.parent), {'path': str(file.parent), 'root': root,
                    'name': file.parent.name, 'kind': 'executable', 'files': [], 'linked': False})
                if len(entry['files']) < 40: entry['files'].append(str(file))
                else: out['partial'] = True
                entry['linked'] = entry['linked'] or str(file) in linked_files
            if len(candidates) >= 1000:
                out['partial'] = True
                return finish()
    return finish()

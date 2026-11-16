"""Lectura limitada de rutas y migración de bibliotecas antiguas. No ejecuta archivos."""
import os
import time
from pathlib import Path
from omnia import library_paths


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
            if any(word in low for word in ('unins', 'uninstall', 'crashreport', 'vcredist', 'dxsetup', 'setup', 'updater')):
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

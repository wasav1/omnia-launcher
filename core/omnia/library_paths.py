"""Exclusión reversible de ports de carpetas retiradas, sin borrar archivos ni historial."""
import os


def _real(path):
    return os.path.realpath(os.path.expanduser(path))


def _within(path, root):
    return path == root or path.startswith(root.rstrip('/') + '/')


def update_excluded(old, roots):
    active = {_real(p) for p in roots}
    excluded = {_real(p) for p in old.get('excluded_external_roots', [])}
    excluded.update(_real(p) for p in old.get('external_roots', []) if _real(p) not in active)
    return sorted(excluded - active)


def port_visible(game, port, config):
    # Steam/Heroic/Lutris administran sus bibliotecas independientemente de las carpetas externas.
    if game.get('auto'):
        return True
    location = port.get('check') or port.get('cwd')
    if not location or not os.path.isabs(os.path.expanduser(location)):
        return True
    location = _real(location)
    active = [len(_real(p)) for p in config.get('external_roots', []) if _within(location, _real(p))]
    excluded = [len(_real(p)) for p in config.get('excluded_external_roots', []) if _within(location, _real(p))]
    return not excluded or max(active, default=-1) >= max(excluded)

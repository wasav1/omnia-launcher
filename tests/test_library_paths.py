import threading
import unittest

from omnia.library_paths import port_visible, update_excluded


class RemovedRoots(unittest.TestCase):
    def test_removed_root_excludes_existing_ports(self):
        cfg = {'external_roots': ['/games/other'], 'excluded_external_roots': ['/games/ports']}
        self.assertFalse(port_visible({}, {'check': '/games/ports/zelda/longshot'}, cfg))
        self.assertTrue(port_visible({}, {'check': '/games/ports-extra/game'}, cfg))
        self.assertTrue(port_visible({}, {'check': '/games/other/game'}, cfg))

    def test_automatic_platforms_remain_independent(self):
        cfg = {'excluded_external_roots': ['/games']}
        self.assertTrue(port_visible({'auto': 'steam'}, {'check': '/games/Steam/appmanifest.acf'}, cfg))

    def test_readding_parent_does_not_override_removed_subfolder(self):
        cfg = {'external_roots': ['/games'], 'excluded_external_roots': ['/games/private']}
        self.assertFalse(port_visible({}, {'check': '/games/private/game'}, cfg))

    def test_readding_subfolder_restores_its_games(self):
        cfg = {'external_roots': ['/games/ports/keep'], 'excluded_external_roots': ['/games/ports']}
        self.assertTrue(port_visible({}, {'check': '/games/ports/keep/game'}, cfg))
        self.assertFalse(port_visible({}, {'check': '/games/ports/other/game'}, cfg))

    def test_exclusions_survive_reinstall_and_clear_on_readd(self):
        removed = update_excluded({'external_roots': ['/games/ports']}, [])
        self.assertEqual(removed, ['/games/ports'])
        self.assertEqual(update_excluded({'external_roots': [], 'excluded_external_roots': removed}, []), removed)
        self.assertEqual(update_excluded({'excluded_external_roots': removed}, ['/games/ports']), [])


class CatalogIntegration(unittest.TestCase):
    def test_removed_path_is_filtered_after_reload_and_readd_restores(self):
        import tempfile
        from pathlib import Path

        from omnia.api import Api, ApiError
        from omnia.store import Store, write_json_atomic
        with tempfile.TemporaryDirectory() as tmp:
            folder = Path(tmp) / 'ports'
            folder.mkdir()
            exe = folder / 'game'
            exe.touch()
            store = Store(Path(tmp) / 'config')
            game = {'id': 'manual-demo', 'name': 'Demo', 'ports': [{'id': 'main', 'name': 'Port', 'check': str(exe), 'launch': [str(exe)]}]}
            store.set_games([game])
            api = Api.__new__(Api)
            api.store, api.sessions = store, None
            api._installation_actions = threading.Lock()
            api.scan_fn = list
            api._is_running = lambda *args: False
            api._art = lambda *args: {}
            write_json_atomic(store.dir / 'config.json', {'external_roots': [], 'excluded_external_roots': [str(folder)]})
            self.assertEqual(api.library({})['games'], [])
            with self.assertRaises(ApiError):
                api.launch({'id': 'manual-demo', 'port': 'main'})
            self.assertEqual(len(Store(store.dir).games()), 1)
            write_json_atomic(store.dir / 'config.json', {'external_roots': [str(folder)], 'excluded_external_roots': []})
            self.assertEqual(api.library({})['games'][0]['id'], 'manual-demo')
            self.assertTrue(exe.exists())

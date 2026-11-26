import importlib.util
import json
import os
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

spec = importlib.util.spec_from_file_location('installer_backend', Path(__file__).resolve().parents[1] / 'packaging/universal/installer_backend.py')
installer = importlib.util.module_from_spec(spec)
spec.loader.exec_module(installer)


class InstallerSettings(unittest.TestCase):
    def test_preserves_existing_config_values(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            (root / 'config.json').write_text('{"refresh_secs": 42}')
            volume = {'path': tmp, 'uuid': 'sample', 'label': 'PRUEBA'}
            with patch.object(installer.paths, 'config_dir', return_value=root), patch.object(installer, 'volumes', return_value=[volume]):
                installer.configure({'external_roots': [tmp, tmp], 'monitor_disk': volume})
            cfg = json.loads((root / 'config.json').read_text())
            self.assertEqual(cfg['refresh_secs'], 42)
            self.assertEqual(cfg['external_roots'], [tmp])
            self.assertEqual(cfg['excluded_external_roots'], [])

    def test_missing_volume_does_not_change_config(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            with patch.object(installer.paths, 'config_dir', return_value=root), patch.object(installer, 'volumes', return_value=[]), self.assertRaises(ValueError):
                installer.configure({'monitor_disk': {'path': tmp, 'uuid': 'disconnected'}})
            self.assertFalse((root / 'config.json').exists())


class SettingsRouteRemoval(unittest.TestCase):
    def test_removal_updates_catalog_policy_and_preserves_library(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            removed = root / 'ports'
            removed.mkdir()
            (root / 'config.json').write_text(json.dumps({'external_roots': [str(removed)]}))
            (root / 'library.json').write_text('{"games":[{"id":"manual-example"}]}')
            volume = {'path': tmp, 'uuid': 'sample', 'label': 'PRUEBA'}
            with patch.object(installer.paths, 'config_dir', return_value=root), patch.object(installer, 'volumes', return_value=[volume]):
                installer.configure({'external_roots': [], 'monitor_disk': volume}, consent=False)
            cfg = json.loads((root / 'config.json').read_text())
            self.assertEqual(cfg['excluded_external_roots'], [str(removed)])
            self.assertEqual(json.loads((root / 'library.json').read_text())['games'][0]['id'], 'manual-example')
            self.assertTrue(removed.exists())

    def test_settings_preserve_disconnected_monitor(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            volume = {'path': '/not/mounted', 'uuid': 'sample', 'label': 'PRUEBA'}
            (root / 'config.json').write_text(json.dumps({'monitor_disk': volume}))
            with patch.object(installer.paths, 'config_dir', return_value=root), patch.object(installer, 'volumes', return_value=[]):
                installer.configure({'monitor_disk': volume}, consent=False)
            self.assertEqual(json.loads((root / 'config.json').read_text())['monitor_disk'], volume)


class ExistingInstallation(unittest.TestCase):
    def test_legacy_routes_are_recovered_and_removal_excludes_them(self):
        from route_inspection import effective_roots
        with tempfile.TemporaryDirectory() as tmp:
            root=Path(tmp);folder=root/'ports';folder.mkdir();exe=folder/'game.sh';exe.touch()
            games=[{'id':'manual-old','ports':[{'check':str(exe)}]}]
            self.assertEqual(effective_roots({},games),[str(folder)])
            (root/'library.json').write_text(json.dumps({'games':games}))
            volume={'path':tmp,'uuid':'sample','label':'PRUEBA'}
            with patch.object(installer.paths,'config_dir',return_value=root),patch.object(installer,'volumes',return_value=[volume]):
                installer.configure({'external_roots':[],'monitor_disk':volume},consent=False)
            self.assertEqual(json.loads((root/'config.json').read_text())['excluded_external_roots'],[str(folder)])
            self.assertEqual(effective_roots({'excluded_external_roots':[str(folder)]},games),[])

    def test_scan_counts_linked_games_and_candidates_without_running_them(self):
        from route_inspection import inspect_route
        with tempfile.TemporaryDirectory() as tmp:
            root=Path(tmp)
            (root/'example.z64').touch()
            port=root/'port';port.mkdir()
            (port/'game.exe').touch();(port/'launcher.sh').touch();(port/'uninstall.exe').touch()
            games=[{'id':'manual-a','ports':[{'check':str(root/'example.z64')},{'check':str(port/'game.exe')}]}]
            result=inspect_route(tmp,games)
            self.assertEqual(result['linked'],1)
            self.assertEqual(result['candidates'],2)
            self.assertFalse(result['partial'])
            self.assertTrue(result['available'])

    def test_missing_route_keeps_linked_count(self):
        from route_inspection import inspect_route
        with tempfile.TemporaryDirectory() as tmp:
            missing=str(Path(tmp)/'missing')
            result=inspect_route(missing,[{'id':'manual-offline','ports':[{'check':missing+'/game'}]}])
            self.assertEqual(result['linked'],1)
            self.assertFalse(result['available'])

    def test_bounded_scan_reports_partial_result(self):
        from route_inspection import inspect_route
        with tempfile.TemporaryDirectory() as tmp:
            for i in range(3):(Path(tmp)/f'{i}.z64').touch()
            result=inspect_route(tmp,[],max_files=1)
            self.assertTrue(result['partial'])
            self.assertEqual(result['candidates'],1)


class ReviewedCandidates(unittest.TestCase):
    def test_only_checked_candidates_are_imported_and_repeated_paths_do_not_duplicate(self):
        from candidate_import import prepare
        with tempfile.TemporaryDirectory() as tmp:
            root=Path(tmp); first=root/'first.sh'; second=root/'second.sh'
            first.touch();second.touch();first.chmod(0o755);second.chmod(0o755)
            choice={'file':str(first),'name':'Chosen','kind':'executable'}
            games,count=prepare([], [choice], [tmp])
            self.assertEqual(count,1)
            self.assertEqual(games[0]['ports'][0]['check'],str(first))
            again,count=prepare(games,[choice],[tmp])
            self.assertEqual(count,0)
            self.assertEqual(len(again),1)

    def test_bad_selection_is_rejected_before_configuration_changes(self):
        with tempfile.TemporaryDirectory() as tmp:
            root=Path(tmp);exe=root/'game.sh';exe.touch();exe.chmod(0o755)
            volume={'path':tmp,'uuid':'sample','label':'PRUEBA'}
            data={'external_roots':[tmp],'monitor_disk':volume,'selected_candidates':[
                {'file':str(exe),'name':'Valid','kind':'executable'},
                {'file':str(root/'missing.sh'),'name':'Missing','kind':'executable'}]}
            with patch.object(installer.paths,'config_dir',return_value=root),patch.object(installer,'volumes',return_value=[volume]), self.assertRaises(ValueError):
                installer.configure(data)
            self.assertFalse((root/'library.json').exists())
            self.assertFalse((root/'config.json').exists())

    def test_candidate_outside_selected_roots_is_rejected(self):
        from candidate_import import prepare
        with tempfile.TemporaryDirectory() as tmp:
            root=Path(tmp);exe=root/'game';exe.touch();exe.chmod(0o755)
            with self.assertRaises(ValueError):
                prepare([],[{'file':str(exe),'name':'Demo','kind':'executable'}],[str(root/'other')])

    def test_no_selection_adds_nothing(self):
        from candidate_import import prepare
        self.assertEqual(prepare([],[],[]),([],0))

import json
import tempfile
import unittest
from pathlib import Path
from types import SimpleNamespace
from unittest.mock import Mock, patch

from omnia import uninstall


class UninstallSafety(unittest.TestCase):
    def test_cleanup_preserves_games_saves_and_unknown_data(self):
        with tempfile.TemporaryDirectory() as tmp:
            home=Path(tmp)
            game=home/'Juegos/PC/Game/game';game.parent.mkdir(parents=True);game.write_text('game')
            save=home/'Juegos/Partidas/slot.sav';save.parent.mkdir(parents=True);save.write_text('save')
            extra=home/'.local/share/omnia/my-game/data';extra.parent.mkdir(parents=True);extra.write_text('keep')
            config=home/'.config/omnia';config.mkdir(parents=True)
            (config/'steamgriddb.key').write_text('example-test-key')
            (config/'library.json').write_text(json.dumps({'games':[{'ports':[{'check':str(game),'saves':{'files':[str(save)]}}]}]}))
            for file in [home/'.local/share/omnia/art/game/image.png',home/'.local/bin/omnia-core']:
                file.parent.mkdir(parents=True,exist_ok=True);file.write_text('owned')
            items=uninstall.owned_paths(home)
            uninstall.validate_paths(items,config)
            uninstall.remove_paths(items)
            self.assertEqual(game.read_text(),'game')
            self.assertEqual(save.read_text(),'save')
            self.assertEqual(extra.read_text(),'keep')
            self.assertFalse(config.exists())
            self.assertFalse((home/'.local/bin/omnia-core').exists())

    def test_symlink_target_is_never_removed(self):
        with tempfile.TemporaryDirectory() as tmp:
            home=Path(tmp)
            games=home/'Games';games.mkdir();(games/'save.sav').write_text('keep')
            link=home/'.local/share/omnia/ui';link.parent.mkdir(parents=True);link.symlink_to(games,target_is_directory=True)
            uninstall.validate_paths([link],home/'.config/omnia')
            uninstall.remove_paths([link])
            self.assertFalse(link.is_symlink())
            self.assertEqual((games/'save.sav').read_text(),'keep')

    def test_symlink_parent_blocks_cleanup(self):
        with tempfile.TemporaryDirectory() as tmp:
            home=Path(tmp);games=home/'Games';games.mkdir();(games/'ui').mkdir()
            redirect=home/'omnia';redirect.symlink_to(games,target_is_directory=True)
            with self.assertRaisesRegex(ValueError,'enlace'):
                uninstall.validate_paths([redirect/'ui'],home/'.config/omnia')
            self.assertTrue((games/'ui').exists())

    def test_symlinked_home_from_ostree_is_allowed(self):
        # Fedora Atomic/Bazzite: /home -> /var/home hace que todo el home cuelgue de
        # un enlace; no debe impedir la desinstalación normal.
        with tempfile.TemporaryDirectory() as tmp:
            real=Path(tmp)/'var/home/user';real.mkdir(parents=True)
            linked=Path(tmp)/'home/user';linked.parent.mkdir(parents=True)
            linked.symlink_to(real,target_is_directory=True)
            config=linked/'.config/omnia';config.mkdir(parents=True)
            with patch.object(Path,'home',return_value=linked):
                uninstall.validate_paths([config],config)
            self.assertTrue(config.exists())

    def test_game_stored_in_omnia_directory_blocks_cleanup(self):
        with tempfile.TemporaryDirectory() as tmp:
            home=Path(tmp);config=home/'.config/omnia';config.mkdir(parents=True)
            owned=home/'.local/share/omnia/ui';owned.mkdir(parents=True)
            game=owned/'game';game.write_text('keep')
            (config/'library.json').write_text(json.dumps({'games':[{'ports':[{'check':str(game)}]}]}))
            with self.assertRaisesRegex(ValueError,'juegos o partidas'):
                uninstall.validate_paths(uninstall.owned_paths(home),config)
            self.assertEqual(game.read_text(),'keep')

    def test_save_override_inside_own_directory_blocks_cleanup(self):
        with tempfile.TemporaryDirectory() as tmp:
            home=Path(tmp);config=home/'.config/omnia';config.mkdir(parents=True)
            art=home/'.local/share/omnia/art';art.mkdir(parents=True)
            (config/'state.json').write_text(json.dumps({'saves':{'game':{'spec':{'dirs':[str(art/'saves')]}}}}))
            with self.assertRaisesRegex(ValueError,'juegos o partidas'):
                uninstall.validate_paths(uninstall.owned_paths(home),config)

    def test_desktop_script_removes_only_owned_widgets_and_preserves_panels(self):
        script=uninstall.detach_script({},'file:///home/test/Desktop')
        self.assertIn('org.omnia.desktop',script)
        self.assertIn('ids.indexOf(widgets[j].type)>=0',script)
        self.assertIn('org.kde.image',script)
        self.assertNotIn('panels()',script)
        self.assertNotIn('loadSerializedLayout',script)

    def test_capture_does_not_overwrite_original_desktop_on_update(self):
        with tempfile.TemporaryDirectory() as tmp:
            config=Path(tmp)
            first={'1':{'id':'1','wallpaper':'org.kde.image','url':'file:///original'}}
            (config/'desktop-before-omnia.json').write_text(json.dumps(first))
            with patch.object(uninstall.paths,'config_dir',return_value=config),patch.object(uninstall,'qdbus',return_value=json.dumps([{'id':'1','wallpaper':'org.omnia.launcher','url':'file:///empty'}])):
                uninstall.capture_desktop()
            self.assertEqual(json.loads((config/'desktop-before-omnia.json').read_text()),first)


class UninstallFlow(unittest.TestCase):
    def test_mocked_flow_removes_only_planned_files(self):
        with tempfile.TemporaryDirectory() as tmp:
            home=Path(tmp);config=home/'.config/omnia';config.mkdir(parents=True)
            (config/'state.json').write_text('{}')
            game=home/'Juegos/Game/game';game.parent.mkdir(parents=True);game.write_text('keep')
            runtime=home/'runtime/omnia';runtime.mkdir(parents=True);(runtime/'token').write_text('test-token')
            backend=Mock();backend.plugin_enabled.return_value=False
            calls=[]
            def run(argv,**kwargs):
                calls.append(argv)
                return SimpleNamespace(returncode=3 if 'is-active' in argv else 0,stdout='QML_IMPORT_PATH='+str(home/'.local/lib/qt6/qml')+':/shared/qml\n')
            with patch.object(Path,'home',return_value=home),patch.object(uninstall.os,'geteuid',return_value=1000),patch.object(uninstall.paths,'config_dir',return_value=config),patch.object(uninstall.paths,'cache_dir',return_value=home/'.cache/omnia'),patch.object(uninstall.paths,'runtime_dir',return_value=runtime),patch.object(uninstall,'owned_paths',return_value=[config]),patch.object(uninstall.setup,'KdeBackend',return_value=backend),patch.object(uninstall,'qdbus',return_value='done'),patch.object(uninstall.subprocess,'run',side_effect=run),patch('omnia.gamemode.Freezer.resume',return_value=0):
                message=uninstall.uninstall()
            self.assertIn('se conservaron',message)
            self.assertFalse(config.exists())
            self.assertEqual(game.read_text(),'keep')
            self.assertIn(['systemctl','--user','set-environment','QML_IMPORT_PATH=/shared/qml'],calls)
            self.assertFalse(any('pkexec' in command for command in calls))

    def test_desktop_failure_keeps_files(self):
        with tempfile.TemporaryDirectory() as tmp:
            config=Path(tmp)/'omnia';config.mkdir();(config/'state.json').write_text('{}')
            backend=Mock();backend.plugin_enabled.return_value=False
            with patch.object(uninstall.os,'geteuid',return_value=1000),patch.object(uninstall.paths,'config_dir',return_value=config),patch.object(uninstall,'owned_paths',return_value=[config]),patch.object(uninstall.setup,'KdeBackend',return_value=backend),patch.object(uninstall,'qdbus',side_effect=RuntimeError('Plasma no disponible')), self.assertRaisesRegex(RuntimeError,'Plasma'):
                uninstall.uninstall()
            self.assertTrue((config/'state.json').exists())

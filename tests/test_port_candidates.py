import sys
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

from omnia import port_catalog, templates

UNIVERSAL=Path(__file__).resolve().parents[1]/'packaging/universal'
sys.path.insert(0,str(UNIVERSAL))
from candidate_import import prepare, requirements
from route_inspection import inspect_route


def executable(file, content='#!/bin/sh\nexit 0\n'):
    file.parent.mkdir(parents=True,exist_ok=True)
    file.write_text(content);file.chmod(0o755)
    return str(file)


class PortCandidates(unittest.TestCase):
    def test_names_platforms_versions_and_tools(self):
        with tempfile.TemporaryDirectory() as tmp:
            root=Path(tmp)
            old=executable(root/'Longshot/v3.0.0-rc.3/longshot')
            new=executable(root/'Longshot/v3.0.0-rc.6/bin/longshot')
            executable(root/'Longshot/LongshotLauncher.AppImage')
            executable(root/'Longshot/v3.0.0-rc.6/bin/longshot_xlate')
            executable(root/'TOTK-Recomp/v0.4.0/totk')
            executable(root/'TOTK-Recomp/v0.4.0/totk_xlate')
            executable(root/'Savage-Wind/Savage_Wind-0.5.3-alpha.5-x86_64.AppImage')
            scan=inspect_route(tmp,[])
            self.assertEqual(scan['candidates'],3)
            by={c['template']:c for c in scan['items']}
            self.assertEqual(by['longshot']['name'],'The Legend of Zelda: Ocarina of Time')
            self.assertEqual(by['longshot']['platform'],'sw2')
            self.assertEqual(by['longshot']['files'],[new,old])
            self.assertEqual(by['longshot']['suggested_file'],new)
            self.assertEqual(by['totkrecomp']['platform'],'sw1')
            self.assertEqual(len(by['savagewind']['files']),1)

    def test_folder_name_alone_does_not_recognize_unknown_binary(self):
        with tempfile.TemporaryDirectory() as tmp:
            file=executable(Path(tmp)/'Longshot/unknown-game')
            self.assertIsNone(port_catalog.identify(file))
            self.assertEqual(inspect_route(tmp,[])['items'][0]['kind'],'executable')

    def test_nx2navi_proposes_wrapper_and_tracks_actual_game(self):
        with tempfile.TemporaryDirectory() as tmp:
            root=Path(tmp)/'NX2navi'
            executable(root/'ocarina')
            wrapper=executable(root/'play.sh','#!/bin/sh\ncd "$(dirname "$0")"\nexec ./ocarina "$@"\n')
            scan=inspect_route(tmp,[])
            self.assertEqual(scan['candidates'],1)
            self.assertEqual(scan['items'][0]['suggested_file'],wrapper)
            games,_count=prepare([], [{'file':wrapper,'name':scan['items'][0]['name'],'kind':'port'}],[tmp])
            self.assertEqual(games[0]['ports'][0]['proc'],'ocarina')
            self.assertEqual(games[0]['ports'][0]['name'],'NX2navi')
            self.assertEqual(games[0]['platform'],'sw2')

    def test_two_ports_are_one_game_and_reimport_is_idempotent(self):
        with tempfile.TemporaryDirectory() as tmp:
            first=executable(Path(tmp)/'Longshot/v3.0.0/longshot')
            second=executable(Path(tmp)/'Hookshot/v2.1.0/hookshot')
            selected=[{'file':p,'name':'Mi Ocarina','kind':'port'} for p in (first,second)]
            games,_count=prepare([],selected,[tmp])
            self.assertEqual(len(games),1)
            self.assertEqual(games[0]['name'],'Mi Ocarina')
            self.assertEqual(len(games[0]['ports']),2)
            self.assertEqual(games[0]['art']['sgdb'],'The Legend of Zelda: Ocarina of Time')
            self.assertEqual({p['name'] for p in games[0]['ports']},{'Longshot','Hookshot'})
            self.assertTrue(games[0]['ports'][0]['saves'])
            again,added=prepare(games,selected,[tmp])
            self.assertEqual(again,games)
            self.assertEqual(added,0)

    def test_known_file_marks_port_as_already_linked(self):
        with tempfile.TemporaryDirectory() as tmp:
            file=executable(Path(tmp)/'Longshot/v3.0.0/longshot')
            scan=inspect_route(tmp,[{'id':'existing','ports':[{'check':file}]}])
            self.assertTrue(scan['items'][0]['linked'])

    def test_new_version_is_available_when_old_version_is_linked(self):
        with tempfile.TemporaryDirectory() as tmp:
            old=executable(Path(tmp)/'Longshot/v3.0.0-rc.3/longshot')
            new=executable(Path(tmp)/'Longshot/v3.0.0-rc.6/longshot')
            previous=[{'id':'keep-me','name':'v3.0.0-rc.3','ports':[{'id':'old-port','check':old,'launch':[old]}]}]
            scan=inspect_route(tmp,previous)
            self.assertFalse(scan['items'][0]['linked'])
            self.assertEqual(scan['items'][0]['files'],[new])
            games,_count=prepare(previous,[{'file':new,'name':scan['items'][0]['name'],'kind':'port'}],[tmp])
            self.assertEqual(len(games),1)
            self.assertEqual(games[0]['id'],'keep-me')
            self.assertEqual(games[0]['name'],'The Legend of Zelda: Ocarina of Time')
            self.assertEqual(len(games[0]['ports']),2)

    def test_n64_emulator_proposal(self):
        with tempfile.TemporaryDirectory() as tmp:
            (Path(tmp)/'Mario.z64').touch()
            self.assertEqual(inspect_route(tmp,[])['items'][0]['suggested_emulator'],'gopher64')


class MissingComponents(unittest.TestCase):
    def test_missing_gopher64_has_actionable_message(self):
        choice={'kind':'rom','file':'/game.n64','emulator':'gopher64'}
        with patch('candidate_import.templates.gopher64_install',side_effect=templates.TemplateError('missing')):
            missing=requirements([choice])
        self.assertEqual(missing[0]['component'],'Gopher64')
        self.assertIn('Instala Gopher64',missing[0]['message'])

    def test_flatpak_gopher64_satisfies_check(self):
        with patch('candidate_import.templates.gopher64_install',return_value={'argv':['flatpak','run','g64']}):
            self.assertEqual(requirements([{'kind':'rom','file':'/game.z64','emulator':'gopher64'}]),[])

    def test_missing_windows_runtime_is_reported_before_import(self):
        with patch('candidate_import.shutil.which',return_value=None):
            missing=requirements([{'kind':'port','file':'/Longshot/longshot.exe'}])
        self.assertEqual(missing[0]['component'],'UMU Launcher')

    def test_n64_emulator_is_not_accepted_for_switch_rom(self):
        missing=requirements([{'kind':'rom','file':'/game.xci','emulator':'gopher64'}])
        self.assertEqual(missing[0]['component'],'Emulador compatible')

    def test_invalid_custom_emulator_is_reported(self):
        missing=requirements([{'kind':'rom','file':'/game.iso','emulator':'/nonexistent/emulator','name':'Game'}])
        self.assertEqual(missing[0]['component'],'Emulador')

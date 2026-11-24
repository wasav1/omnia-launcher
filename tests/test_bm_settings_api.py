import json
import shutil
import tempfile
import unittest
from pathlib import Path
from unittest import mock

from omnia import security, sounds
from omnia.api import Api, ApiError
from omnia.store import Store

from tests.test_audio_out import FakeIO
from tests.test_pad_settings import reader_with_pad


class BmSettingsApiTests(unittest.TestCase):
    def setUp(self):
        self.tmp = Path(tempfile.mkdtemp())
        self.addCleanup(shutil.rmtree, self.tmp, True)
        import os
        env = mock.patch.dict(os.environ, {"XDG_DATA_HOME": str(self.tmp / "data"), "XDG_CONFIG_HOME": str(self.tmp / "cfg")})
        env.start()
        self.addCleanup(env.stop)
        self.api = Api(Store(self.tmp / "cfg"), security.new_token(self.tmp / "run"), [], scan_fn=list, fs_roots=[self.tmp])
        self.api.serve()
        self.addCleanup(self.api.stop)
        packs = mock.patch("omnia.api.sounds.packs", return_value=[{"id": "omnia", "label": "Omnia"}, {"id": "kenney", "label": "Kenney"}])
        packs.start()
        self.addCleanup(packs.stop)

    def config(self):
        return json.loads((self.api.store.dir / "config.json").read_text())

    def test_settings_expose_the_new_values_with_defaults(self):
        data = self.api.settings({})
        self.assertEqual((data["ui_sounds"], data["ui_sound_volume"], data["ui_sound_pack"], data["intro_enabled"]), (True, 70, "omnia", True))
        self.assertEqual([p["id"] for p in data["ui_sound_packs"]], ["omnia", "kenney"])
        self.assertTrue(isinstance(data["user_name"], str))

    def test_sounds_setting_validates_and_persists(self):
        self.assertEqual(self.api.settings_sounds({"_body": {"enabled": False, "volume": 40, "pack": "kenney"}})["ui_sound_pack"], "kenney")
        cfg = self.config()
        self.assertEqual((cfg["ui_sounds"], cfg["ui_sound_volume"], cfg["ui_sound_pack"]), (False, 40, "kenney"))
        for bad in ({}, {"enabled": "si"}, {"volume": 101}, {"volume": -1}, {"volume": True}, {"volume": 50.5}, {"pack": "../../etc"}, {"pack": "nope"}):
            with self.assertRaises(ApiError, msg=str(bad)):
                self.api.settings_sounds({"_body": bad})

    def test_an_unknown_saved_pack_falls_back_to_omnia(self):
        self.api._update_config(ui_sound_pack="borrado")
        self.assertEqual(self.api.settings({})["ui_sound_pack"], "omnia")

    def test_the_greeting_name_belongs_to_each_system_user(self):
        import pwd
        from types import SimpleNamespace
        cases = (("Ana María López,,,", "ana", "Ana"), ("", "carlos", "carlos"), ("Zoë", "zoe", "Zoë"), ("  ", "root", "root"))
        for gecos, login, expected in cases:
            entry = SimpleNamespace(pw_gecos=gecos, pw_name=login)
            with mock.patch.object(pwd, "getpwuid", return_value=entry):
                self.assertEqual(self.api.settings({})["user_name"], expected, (gecos, login))
        with mock.patch.object(pwd, "getpwuid", side_effect=KeyError("sin usuario")), mock.patch.dict("os.environ", {"USER": "invitada"}):
            self.assertEqual(self.api.settings({})["user_name"], "invitada")

    def test_a_chosen_display_name_wins_and_is_sanitized(self):
        import pwd
        from types import SimpleNamespace
        with mock.patch.object(pwd, "getpwuid", return_value=SimpleNamespace(pw_gecos="Wichmann", pw_name="wsaenz")):
            self.assertEqual(self.api.settings_profile({"_body": {"display_name": "  Sofi  <b>Pro</b>  "}})["user_name"], "Sofi bPro/b")
            self.assertEqual(self.api.settings({})["display_name"], "Sofi bPro/b")
            self.assertEqual(self.api.settings_profile({"_body": {"display_name": ""}})["user_name"], "Wichmann")   # vacío: vuelve al del sistema
            self.assertEqual(self.api.settings_profile({"_body": {"display_name": "x" * 80}})["display_name"], "x" * 24)
        with self.assertRaises(ApiError):
            self.api.settings_profile({"_body": {"display_name": 5}})

    def test_intro_setting(self):
        self.assertEqual(self.api.settings_intro({"_body": {"enabled": False}}), {"ok": True, "intro_enabled": False})
        self.assertFalse(self.api.settings({})["intro_enabled"])
        with self.assertRaises(ApiError):
            self.api.settings_intro({"_body": {"enabled": 1}})

    def test_audio_devices_and_level(self):
        self.api.pactl_run = FakeIO()
        data = self.api.audio_devices({})
        self.assertEqual((data["output"]["volume"], data["output"]["muted"], data["input"]["volume"], data["input"]["muted"]), (63, False, 80, True))
        self.assertEqual([i["source"] for i in data["input"]["items"]], ["alsa_input.usb-Mic", "alsa_input.pci.analog"])
        self.assertTrue(self.api.audio_level({"_body": {"target": "output", "volume": 55, "muted": False}})["ok"])
        for bad in ({"target": "otra"}, {"target": "output", "volume": 999}, {"target": "input", "muted": "si"}):
            with self.assertRaises(ApiError, msg=str(bad)):
                self.api.audio_level({"_body": bad})
        with self.assertRaises(ApiError):
            self.api.audio_input_set({"_body": {"source": "inventado"}})

    def test_pads_settings_persist_apply_and_validate(self):
        reader, dev = reader_with_pad()
        self.api.pad_reader = reader
        pad_id = self.api.pads({})["pads"][0]["id"]
        out = self.api.pads_settings({"_body": {"id": pad_id, "nickname": "  Sofá <b>  ", "family": "ps", "deadzone": 0.25, "haptics": True}})
        self.assertEqual((out["pad"]["nickname"], out["pad"]["family"], out["pad"]["deadzone"], out["pad"]["haptics"]), ("Sofá b", "ps", 0.25, True))
        self.assertEqual(self.config()["pads"]["aa:bb"]["family"], "ps")
        self.api.pads_settings({"_body": {"id": pad_id, "family": "auto"}})
        self.assertEqual(self.api.pads({})["pads"][0]["family"], "xbox")                  # «auto» vuelve a la familia detectada
        for bad in ({"id": pad_id}, {"id": pad_id, "family": "atari"}, {"id": pad_id, "deadzone": 0.9}, {"id": pad_id, "deadzone": True},
                    {"id": pad_id, "haptics": "si"}, {"id": "/dev/input/event0", "family": "ps"}):
            with self.assertRaises(ApiError, msg=str(bad)):
                self.api.pads_settings({"_body": bad})

    def test_pads_rumble_validates_and_reports_unsupported_pads(self):
        reader, dev = reader_with_pad()
        self.api.pad_reader = reader
        calls = []
        reader.haptic = lambda *a: calls.append(a)
        self.assertTrue(self.api.pads_rumble({"_body": {"id": dev.path, "strong": 5, "weak": -2, "ms": 99999}})["ok"])
        self.assertEqual(calls, [(dev.path, 1.0, 0.0, 1500)])                                 # valores acotados
        reader.haptic = mock.Mock(side_effect=OSError("sin FF"))
        with self.assertRaises(ApiError) as ctx:
            self.api.pads_rumble({"_body": {"id": dev.path}})
        self.assertEqual(ctx.exception.code, 409)
        with self.assertRaises(ApiError):
            self.api.pads_rumble({"_body": {"id": "/etc/passwd"}})


class SoundPackTests(unittest.TestCase):
    def test_lists_only_complete_packs_with_omnia_first(self):
        base = Path(tempfile.mkdtemp())
        self.addCleanup(shutil.rmtree, base, True)
        for pack, files in (("zeta", ["move.wav", "confirm.wav"]), ("omnia", ["move.wav", "confirm.wav", "back.wav"]), ("roto", ["move.wav"])):
            (base / pack).mkdir()
            for f in files:
                (base / pack / f).write_bytes(b"RIFF")
        self.assertEqual([p["id"] for p in sounds.packs([base])], ["omnia", "zeta"])


if __name__ == "__main__":
    unittest.main()


class DiscordApiTests(BmSettingsApiTests):
    def test_discord_settings_validate_and_persist(self):
        self.assertEqual(self.api.discord_status({})["enabled"], False)
        out = self.api.settings_discord({"_body": {"enabled": True, "app_id": " 1234567890123456789 "}})
        self.assertEqual((out["enabled"], out["app_id"], out["app_id_set"]), (True, "1234567890123456789", False))
        cfg = self.config()
        self.assertEqual((cfg["discord_enabled"], cfg["discord_app_id"]), (True, "1234567890123456789"))
        self.assertEqual(self.api.discord_settings()["enabled"], True)
        for bad in ({}, {"enabled": "si"}, {"app_id": "abc"}, {"app_id": 5}, {"app_id": "1" * 30}):
            with self.assertRaises(ApiError, msg=str(bad)):
                self.api.settings_discord({"_body": bad})
        self.assertEqual(self.api.settings_discord({"_body": {"app_id": ""}})["app_id"], "")

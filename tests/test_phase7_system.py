"""Fase 7 del rediseño D: límite de FPS y HUD en MangoHud, perfil de energía y Ubisoft desde Lutris."""
import shutil
import sqlite3
import subprocess
import tempfile
import unittest
from pathlib import Path
from unittest import mock

from omnia import mangohud, power_profile, security
from omnia.api import Api, ApiError
from omnia.games import ubisoft_lutris
from omnia.games.lutris import LutrisDetector
from omnia.store import Store

GUID = "8c8d9b22-498c-45e6-80da-7cd22787c9b3"
LIST_OUTPUT = """  performance:
    CpuDriver:\tintel_pstate
    Degraded:   no

* balanced:
    CpuDriver:\tintel_pstate

  power-saver:
    CpuDriver:\tintel_pstate
"""


class Temp(unittest.TestCase):
    def setUp(self):
        self.tmp = Path(tempfile.mkdtemp())
        self.addCleanup(shutil.rmtree, self.tmp, True)


class MangoHudOptions(Temp):
    def test_limit_and_hidden_hud_are_written(self):
        text = mangohud.render(font="", hardware={}, options={"fps_limit": 45, "hud_visible": False})
        self.assertTrue(text.startswith(mangohud.MARKER))
        for line in ("fps_limit=45,0", "fps_limit_method=late", "toggle_fps_limit=Shift_L+F1", "no_display"):
            self.assertIn("\n" + line + "\n", text)
        plain = mangohud.render(font="", hardware={}, options={"fps_limit": 0, "hud_visible": True})
        self.assertNotIn("fps_limit=", plain.replace("toggle_fps_limit", ""))
        self.assertNotIn("no_display", plain)

    def test_options_come_from_config_and_survive_regeneration(self):
        (self.tmp / "config.json").write_text('{"fps_limit": 45, "hud_visible": false}')
        self.assertEqual(mangohud.options_from(self.tmp), {"fps_limit": 45, "hud_visible": False})
        path = mangohud.ensure(self.tmp)
        self.assertIn("fps_limit=45,0", path.read_text())
        (self.tmp / "config.json").write_text('{"fps_limit": 33}')               # valor no permitido → sin límite
        self.assertEqual(mangohud.options_from(self.tmp)["fps_limit"], 0)

    def test_user_owned_file_is_never_rewritten(self):
        (self.tmp / "MangoHud.conf").write_text("fps_limit=30\n")
        (self.tmp / "config.json").write_text('{"fps_limit": 60}')
        mangohud.ensure(self.tmp)
        self.assertEqual((self.tmp / "MangoHud.conf").read_text(), "fps_limit=30\n")


class PowerProfile(Temp):
    def test_parse_and_status(self):
        self.assertEqual(power_profile.parse_list(LIST_OUTPUT), (["power-saver", "balanced", "performance"], "balanced"))
        run = mock.Mock(return_value=subprocess.CompletedProcess([], 0, LIST_OUTPUT, ""))
        with mock.patch.object(power_profile.shutil, "which", return_value="/usr/bin/powerprofilesctl"):
            self.assertEqual(power_profile.status(run)["current"], "balanced")
            power_profile.set_profile("performance", run)
            self.assertEqual(run.call_args_list[-2].args[0], ["/usr/bin/powerprofilesctl", "set", "performance"])
            with self.assertRaises(power_profile.PowerProfileError):
                power_profile.set_profile("turbo", run)

    def test_without_the_daemon(self):
        with mock.patch.object(power_profile.shutil, "which", return_value=None):
            out = power_profile.status()
        self.assertFalse(out["available"])
        self.assertIn("power-profiles-daemon", out["error"])

    def test_cpu_cap(self):
        base = self.tmp / "devices/system/cpu/cpu0/cpufreq"
        base.mkdir(parents=True)
        (base / "cpuinfo_max_freq").write_text("4500000\n")
        (base / "scaling_max_freq").write_text("2800000\n")
        self.assertEqual(power_profile.cpu_cap(str(self.tmp)), {"limit_mhz": 2800, "max_mhz": 4500, "capped": True})
        (base / "scaling_max_freq").write_text("4500000\n")
        self.assertFalse(power_profile.cpu_cap(str(self.tmp))["capped"])


def write_prefix(root, product="2688", folder="WATCH_DOGS2"):
    root.mkdir(parents=True, exist_ok=True)
    (root / "system.reg").write_text(
        "WINE REGISTRY Version 2\n\n"
        f"[Software\\\\Wow6432Node\\\\Ubisoft\\\\Launcher\\\\Installs\\\\{product}] 1795845748\n"
        "#time=1dd7efe0c749786\n"
        f"\"InstallDir\"=\"C:/Program Files (x86)/Ubisoft/Ubisoft Game Launcher/games/{folder}/\"\n\n"
        "[Software\\\\Wine] 1\n\"Version\"=\"win10\"\n")


def write_yml(path, prefix, args):
    path.write_text("game:\n"
                    f"  args: {args}\n"
                    "  exe: drive_c/Program Files (x86)/Ubisoft/Ubisoft Game Launcher/UbisoftConnect.exe\n"
                    f"  prefix: {prefix}\n"
                    "game_slug: watch_dogs-2\n"
                    "script:\n  game:\n"
                    f"    args: uplay://launch/{GUID}\n"
                    "service: ubisoft\n")


class Ubisoft(Temp):
    def test_finds_product_and_fixes_only_the_game_block(self):
        prefix = self.tmp / "prefix"
        write_prefix(prefix)
        self.assertEqual(ubisoft_lutris.installs(prefix), {"2688": "WATCH_DOGS2"})
        yml = self.tmp / "wd2.yml"
        write_yml(yml, prefix, f"uplay://launch/{GUID}/0")
        self.assertEqual(ubisoft_lutris.check(yml, "WATCH_DOGS® 2", "watch_dogs-2"), {"productId": "2688", "guid": GUID})
        backup = ubisoft_lutris.apply(yml, "2688")
        text = yml.read_text()
        self.assertIn("  args: uplay://launch/2688/0\n", text)
        self.assertIn(f"    args: uplay://launch/{GUID}\n", text)          # el script del instalador queda igual
        self.assertIn(GUID + "/0", backup.read_text())
        self.assertEqual(ubisoft_lutris.check(yml, "WATCH_DOGS® 2"), {})
        with self.assertRaises(ValueError):
            ubisoft_lutris.apply(yml, "2688")

    def test_no_guess_when_several_games_do_not_match(self):
        prefix = self.tmp / "prefix"
        write_prefix(prefix)
        reg = prefix / "system.reg"
        reg.write_text(reg.read_text() + "[Software\\\\Wow6432Node\\\\Ubisoft\\\\Launcher\\\\Installs\\\\109] 1\n"
                       "\"InstallDir\"=\"C:/Ubisoft/games/Far Cry 3/\"\n")
        self.assertEqual(ubisoft_lutris.product_for("Otro juego", "otro", prefix), "")
        self.assertEqual(ubisoft_lutris.product_for("Far Cry® 3", "far-cry-3", prefix), "109")

    def test_detector_and_api(self):
        home = self.tmp / "home"
        data = home / ".local/share/lutris"
        (data / "games").mkdir(parents=True)
        prefix = self.tmp / "prefix"
        write_prefix(prefix)
        game_dir = self.tmp / "game"
        game_dir.mkdir()
        write_yml(data / "games" / "wd2-1.yml", prefix, f"uplay://launch/{GUID}")
        con = sqlite3.connect(data / "pga.db")
        con.execute("CREATE TABLE games (id INTEGER, name TEXT, slug TEXT, runner TEXT, directory TEXT, configpath TEXT, installed INTEGER)")
        con.execute("INSERT INTO games VALUES (7, 'WATCH_DOGS® 2', 'watch_dogs-2-ubisoft', 'wine', ?, 'wd2-1', 1)", (str(game_dir),))
        con.commit(); con.close()
        detector = LutrisDetector(home=home, db=data / "pga.db")
        games = detector.detect()
        self.assertEqual(games[0]["ubisoftFix"], {"productId": "2688", "configpath": "wd2-1"})
        store = Store(self.tmp / "cfg")
        store.set_games(games)
        api = Api(store, security.new_token(self.tmp / "run"), [detector], scan_fn=lambda: [])
        out = api.game_ubisoft_fix({"id": "lutris-7"})
        self.assertEqual(out["productId"], "2688")
        self.assertIn("uplay://launch/2688/0", (data / "games" / "wd2-1.yml").read_text())
        self.assertNotIn("ubisoftFix", store.games()[0])
        with self.assertRaises(ApiError):
            api.game_ubisoft_fix({"id": "lutris-7"})


class Settings(Temp):
    def setUp(self):
        super().setUp()
        self.api = Api(Store(self.tmp / "cfg"), security.new_token(self.tmp / "run"), [], scan_fn=lambda: [])

    def test_performance_settings(self):
        self.assertEqual((self.api.settings({})["fps_limit"], self.api.settings({})["hud_visible"]), (0, True))
        out = self.api.settings_performance({"_body": {"fps_limit": 45, "hud_visible": False}})
        self.assertEqual((out["fps_limit"], out["hud_visible"], out["managed"]), (45, False, True))
        self.assertIn("fps_limit=45,0", (self.tmp / "cfg" / "MangoHud.conf").read_text())
        for body in ({}, {"fps_limit": 33}, {"fps_limit": "45"}, {"fps_limit": True}, {"hud_visible": "no"}):
            with self.assertRaises(ApiError):
                self.api.settings_performance({"_body": body})

    def test_power_routes(self):
        self.api.power_run = mock.Mock(return_value=subprocess.CompletedProcess([], 0, LIST_OUTPUT, ""))
        with mock.patch.object(power_profile.shutil, "which", return_value="/usr/bin/powerprofilesctl"):
            self.assertEqual(self.api.system_power({})["profile"]["current"], "balanced")
            with self.assertRaises(ApiError):
                self.api.settings_power_profile({"_body": {"profile": "turbo"}})
        for route in ("/settings/performance", "/settings/power-profile", "/system/power", "/game/ubisoft-fix"):
            self.assertIn(route, self.api.routes)


if __name__ == "__main__":
    unittest.main()

import os
import shutil
import tempfile
import unittest
from pathlib import Path

from omnia import system


def put(root, rel, text):
    p = Path(root, rel)
    p.parent.mkdir(parents=True, exist_ok=True)
    p.write_text(text)


class SystemTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.mkdtemp()
        self.addCleanup(shutil.rmtree, self.tmp, True)

    def test_short_cpu_names(self):
        self.assertEqual(system.short_cpu_name("Intel(R) Core(TM) i5-10300H CPU @ 2.50GHz"), "i5-10300H")
        self.assertEqual(system.short_cpu_name("AMD Ryzen 7 5800X 8-Core Processor"), "Ryzen 7 5800X")
        self.assertEqual(system.short_cpu_name("Algún CPU raro"), "Algún raro")

    def test_cpu_model_and_average_frequency(self):
        put(self.tmp, "proc/cpuinfo", "processor\t: 0\nmodel name\t: Intel(R) Core(TM) i5-10300H CPU @ 2.50GHz\n")
        put(self.tmp, "sys/devices/system/cpu/cpu0/cpufreq/scaling_cur_freq", "4000000")
        put(self.tmp, "sys/devices/system/cpu/cpu1/cpufreq/scaling_cur_freq", "2000000")
        r = system.cpu(self.tmp + "/proc", self.tmp + "/sys")
        self.assertEqual(r, {"model": "i5-10300H", "ghz": 3.0})

    def test_cpu_without_data_is_empty(self):
        self.assertEqual(system.cpu(self.tmp + "/proc", self.tmp + "/sys"), {})

    def test_battery_and_ac(self):
        put(self.tmp, "sys/class/power_supply/BAT0/capacity", "87")
        put(self.tmp, "sys/class/power_supply/BAT0/status", "Charging")
        put(self.tmp, "sys/class/power_supply/AC0/online", "1")
        r = system.battery(self.tmp + "/sys")
        self.assertEqual(r, {"bat": {"pct": 87, "status": "Charging"}, "ac": True})

    def test_desktop_without_battery(self):
        self.assertEqual(system.battery(self.tmp + "/sys"), {"ac": False})

    def test_fs_type_uses_longest_mount(self):
        games = os.path.join(self.tmp, "Juegos")
        os.makedirs(games)
        real = os.path.realpath(self.tmp)
        put(self.tmp, "proc/mounts", f"/dev/a / ext4 rw 0 0\n/dev/b {real}/Juegos btrfs rw 0 0\n")
        self.assertEqual(system.fs_type(games, self.tmp + "/proc"), "btrfs")

    def test_games_dir_prefers_configured_then_juegos(self):
        os.makedirs(os.path.join(self.tmp, "Juegos"))
        os.makedirs(os.path.join(self.tmp, "Otro"))
        self.assertEqual(system.games_dir(self.tmp), os.path.join(self.tmp, "Juegos"))
        self.assertEqual(system.games_dir(self.tmp, os.path.join(self.tmp, "Otro")), os.path.join(self.tmp, "Otro"))
        self.assertEqual(system.games_dir(os.path.join(self.tmp, "vacío")), os.path.join(self.tmp, "vacío"))

    def test_disk_reports_used_and_total(self):
        d = system.disk(self.tmp)
        self.assertGreater(d["total"], 0)
        self.assertLessEqual(d["used"], d["total"])


if __name__ == "__main__":
    unittest.main()

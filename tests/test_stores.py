import json
import subprocess
import tempfile
import unittest
from pathlib import Path

from omnia.stores import registry
from omnia.stores.base import StoreError
from omnia.stores.epic import Epic, clean_code

CODE = "a" * 32


class FakeRun:
    def __init__(self):
        self.calls = []
        self.logged = False

    def __call__(self, cmd, **kw):
        self.calls.append((cmd, kw["env"].get("LEGENDARY_CONFIG_PATH")))
        sub = cmd[1]
        out = ""
        if sub == "status":
            out = json.dumps({"account": "Ana" if self.logged else "<not logged in>", "games_available": 2})
        elif sub == "auth" and "--code" in cmd:
            self.logged = cmd[-1] == CODE
            return subprocess.CompletedProcess(cmd, 0 if self.logged else 1, "", "")
        elif sub == "auth":
            self.logged = False
        elif sub == "list":
            out = "INFO log\n" + json.dumps([
                {"app_name": "b", "app_title": "Zeta", "metadata": {"keyImages": [{"type": "DieselGameBoxTall", "url": "https://x/y.jpg"}]}},
                {"app_name": "a", "app_title": "alfa", "metadata": {}}, {"title": "sin id"}])
        elif sub == "list-installed":
            out = json.dumps([{"app_name": "a"}])
        return subprocess.CompletedProcess(cmd, 0, out, "")


class EpicTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.run_ = FakeRun()
        self.epic = Epic(Path(self.tmp.name), runner=self.run_, tool="/bin/legendary")

    def test_clean_code(self):
        self.assertEqual(clean_code('{"redirectUrl":"x","authorizationCode":"%s","sid":null}' % CODE), CODE)
        self.assertEqual(clean_code(' "%s" ' % CODE), CODE)
        for bad in ("", "corto", "a b" * 20, "../../x" * 6):
            with self.assertRaises(StoreError):
                clean_code(bad)

    def test_login_flow_uses_private_config_dir(self):
        self.assertFalse(self.epic.status()["logged_in"])
        st = self.epic.login(CODE)
        self.assertTrue(st["logged_in"])
        self.assertEqual(st["account"], "Ana")
        self.assertTrue(all(c[1] == str(Path(self.tmp.name) / "legendary") for c in self.run_.calls))
        self.assertEqual((Path(self.tmp.name) / "legendary").stat().st_mode & 0o777, 0o700)
        self.assertFalse(self.epic.logout()["logged_in"])

    def test_rejected_code(self):
        with self.assertRaises(StoreError):
            self.epic.login("b" * 32)

    def test_library_sorted_with_installed_flag(self):
        lib = self.epic.library()
        self.assertEqual([g["title"] for g in lib], ["alfa", "Zeta"])
        self.assertEqual([g["installed"] for g in lib], [True, False])
        self.assertEqual(lib[1]["art"], "https://x/y.jpg")

    def test_missing_tool(self):
        e = Epic(Path(self.tmp.name), tool=None)
        e.tool = lambda: None
        self.assertFalse(e.status()["available"])
        with self.assertRaises(StoreError):
            e.library()

    def test_registry(self):
        self.assertEqual(list(registry.build(Path(self.tmp.name))), ["epic", "gog", "amazon", "steam"])


if __name__ == "__main__":
    unittest.main()

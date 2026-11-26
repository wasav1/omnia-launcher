import importlib.machinery
import importlib.util
import os
import shutil
import stat
import tempfile
import types
import unittest
from pathlib import Path
from unittest import mock

SCRIPT = Path(__file__).resolve().parents[1] / "integrations/hyprland/omnia-hyprland"


def load():
    loader = importlib.machinery.SourceFileLoader("omnia_hyprland", str(SCRIPT))
    spec = importlib.util.spec_from_loader("omnia_hyprland", loader)
    mod = importlib.util.module_from_spec(spec)
    loader.exec_module(mod)
    return mod


def args(**kw):
    return types.SimpleNamespace(**{"skip_key": False, "key_file": None, **kw})


class LibraryCommand(unittest.TestCase):
    def setUp(self):
        self.tmp = Path(tempfile.mkdtemp())
        self.addCleanup(shutil.rmtree, self.tmp, True)
        env = mock.patch.dict(os.environ, {"XDG_CONFIG_HOME": str(self.tmp)})
        env.start(); self.addCleanup(env.stop)
        self.m = load()

    def test_writes_repo_script_when_omnia_ui_missing_and_keeps_user_value(self):
        with mock.patch.object(self.m.shutil, "which", return_value=None):
            cfg = self.m.ensure_library_command()
            self.assertEqual(cfg, self.tmp / "omnia/hyprland.json")
            import json
            cmd = json.loads(cfg.read_text())["libraryCommand"]
            self.assertTrue(cmd[0].endswith("ui/omnia-ui") and cmd[1] == "--window")
            self.assertIsNone(self.m.ensure_library_command())          # no pisa un valor existente
            cfg.write_text('{"libraryCommand": ["mio"]}')
            self.assertIsNone(self.m.ensure_library_command())
            self.assertIn("mio", cfg.read_text())

    def test_nothing_when_omnia_ui_in_path(self):
        with mock.patch.object(self.m.shutil, "which", return_value="/usr/bin/omnia-ui"):
            self.assertIsNone(self.m.ensure_library_command())
        self.assertFalse((self.tmp / "omnia/hyprland.json").exists())


if __name__ == "__main__":
    unittest.main()

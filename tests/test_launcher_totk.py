import os
import shutil
import tempfile
import unittest
from pathlib import Path
from unittest import mock

from omnia import launcher


class TotkPlayTests(unittest.TestCase):
    def setUp(self):
        self.tmp = Path(tempfile.mkdtemp())
        self.addCleanup(shutil.rmtree, self.tmp, True)
        self.root = self.tmp / "totk-pc-recomp"
        (self.root / "installer").mkdir(parents=True)
        (self.root / "installer/gui.py").write_text("")
        self.apprun = self.root / "AppRun"
        self.apprun.write_text("#!/bin/sh\n")
        self.apprun.chmod(0o755)
        self.dest = self.root / "recompToK"
        self.dest.mkdir()
        state = self.tmp / "state/totk-recomp"
        state.mkdir(parents=True)
        (state / "setup.json").write_text('{"dest": "%s"}' % self.dest)
        env = mock.patch.dict(os.environ, {"XDG_STATE_HOME": str(self.tmp / "state")})
        env.start()
        self.addCleanup(env.stop)

    def build(self, marker=True):
        exe = self.dest / "totk"
        exe.write_text("#!/bin/sh\n")
        exe.chmod(0o755)
        if marker:
            (self.dest / "totk-install.json").write_text("{}")
        return exe

    def test_runs_the_game_when_it_is_built(self):
        exe = self.build()
        self.assertEqual(launcher._totk_play([str(self.apprun)], str(self.root)), ([str(exe)], str(self.dest)))

    def test_keeps_the_setup_window_until_the_build_finishes(self):
        self.build(marker=False)
        argv = [str(self.apprun)]
        self.assertEqual(launcher._totk_play(argv, str(self.root)), (argv, str(self.root)))

    def test_other_apprun_folders_are_untouched(self):
        (self.root / "installer/gui.py").unlink()
        self.build()
        argv = [str(self.apprun)]
        self.assertEqual(launcher._totk_play(argv, "x"), (argv, "x"))

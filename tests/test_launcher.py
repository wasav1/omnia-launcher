import os
import tempfile
import unittest
from pathlib import Path
from unittest import mock

from omnia import launcher


class LongshotLaunch(unittest.TestCase):
    def setUp(self):
        self.tmp = Path(tempfile.mkdtemp())
        self.addCleanup(__import__("shutil").rmtree, self.tmp, True)
        self.game = self.tmp / "Longshot" / "rc"
        self.game.mkdir(parents=True)
        self.wrapper = self.game / "longshot"
        self.wrapper.write_text("#!/bin/sh\n")
        self.builder = self.tmp / "Longshot Launcher.AppImage"
        self.builder.write_text("AppImage fixture\n")
        self.builder.chmod(0o755)
        (self.game / "longshot_version.txt").write_text(f"version=v3.0.0-rc.7\nbuilder={self.builder}\n")

    def test_wrapper_usa_play_para_iniciar_el_juego_sin_abrir_el_launcher(self):
        argv = launcher._longshot_play([str(self.wrapper)], str(self.game))
        self.assertEqual(argv, [str(self.builder), "--play", str(self.game)])

    def test_wrapper_sin_builder_conserva_el_lanzamiento_original(self):
        marker = self.game / "longshot_version.txt"
        marker.unlink()
        argv = [str(self.wrapper)]
        self.assertEqual(launcher._longshot_play(argv, str(self.game)), argv)

    def test_fuerza_extraccion_appimage_bajo_la_proteccion_del_servicio(self):
        with mock.patch.dict(os.environ, {"APPIMAGE_EXTRACT_AND_RUN": "0"}), \
             mock.patch.object(launcher.shutil, "which", return_value=None), \
             mock.patch.object(launcher.subprocess, "Popen") as popen:
            launcher.launch({"launch": [str(self.builder)]}, "test-game")
        self.assertEqual(popen.call_args.kwargs["env"]["APPIMAGE_EXTRACT_AND_RUN"], "1")


if __name__ == "__main__":
    unittest.main()

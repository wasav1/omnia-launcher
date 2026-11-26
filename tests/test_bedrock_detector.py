import os
import tempfile
import unittest
from pathlib import Path

from omnia.games.bedrock import BedrockDetector
from omnia.games import registry


def appimage(folder: Path, name: str, executable: bool = True) -> Path:
    path = folder / name
    path.write_bytes(b"\x7fELF")
    path.chmod(0o755 if executable else 0o644)
    return path


class FakeStore:
    def __init__(self, games=()):
        self._games = list(games)
        self.dir = Path(tempfile.mkdtemp())

    def games(self):
        return self._games


class BedrockDetectorTests(unittest.TestCase):
    def setUp(self):
        self.tmp = Path(tempfile.mkdtemp())

    def detect(self, store=None, folders=None):
        return BedrockDetector(store, folders_fn=lambda: folders if folders is not None else [str(self.tmp)]).detect()

    def test_detects_appimage_and_builds_launch(self):
        path = appimage(self.tmp, "BedrockOnLinux-2.3.1-x86_64.AppImage")
        games = self.detect()
        self.assertEqual(len(games), 1)
        game = games[0]
        self.assertEqual((game["id"], game["name"], game["platform"], game["auto"]), ("bedrock-on-linux", "Minecraft Bedrock", "pc", "bedrock"))
        port = game["ports"][0]
        self.assertEqual(port["launch"], [str(path), "play"])
        self.assertEqual((port["check"], port["proc"], port["cwd"]), (str(path), "Minecraft.Windows.exe", str(self.tmp)))

    def test_ignores_non_executable_and_other_files(self):
        appimage(self.tmp, "BedrockOnLinux-2.3.1-x86_64.AppImage", executable=False)
        appimage(self.tmp, "Otra-App-1.0-x86_64.AppImage")
        appimage(self.tmp, "BedrockOnLinux-notes.txt")
        self.assertEqual(self.detect(), [])

    def test_picks_newest_version_and_scans_one_level_down(self):
        appimage(self.tmp, "BedrockOnLinux-2.3.1-x86_64.AppImage")
        sub = self.tmp / "tools"
        sub.mkdir()
        newer = appimage(sub, "BedrockOnLinux-2.10.0-x86_64.AppImage")
        deep = sub / "a" / "b"
        deep.mkdir(parents=True)
        appimage(deep, "BedrockOnLinux-9.0.0-x86_64.AppImage")           # demasiado profundo: no se mira
        game = self.detect()[0]
        self.assertEqual(game["ports"][0]["launch"][0], str(newer))
        self.assertEqual(game["ports"][0]["s"], "BedrockOnLinux 2.10.0")

    def test_manual_entry_for_same_appimage_is_not_duplicated(self):
        path = appimage(self.tmp, "BedrockOnLinux-2.3.1-x86_64.AppImage")
        manual = {"id": "manual-minecraft", "name": "Minecraft", "ports": [{"launch": [str(path), "play"], "check": str(path)}]}
        self.assertEqual(self.detect(FakeStore([manual])), [])

    def test_manual_entry_launching_the_appimage_directly_is_not_duplicated(self):
        path = appimage(self.tmp, "BedrockOnLinux-2.3.1-x86_64.AppImage")
        manual = {"id": "manual-minecraft", "name": "Minecraft", "ports": [{"launch": [str(path), "play"], "check": "/otra/ruta"}]}
        self.assertEqual(self.detect(FakeStore([manual])), [])

    def test_no_folders_or_missing_folder(self):
        self.assertEqual(self.detect(folders=[]), [])
        self.assertEqual(self.detect(folders=[str(self.tmp / "no-existe")]), [])

    def test_registered_by_default(self):
        names = [d.name for d in registry.default_detectors(FakeStore())]
        self.assertIn("bedrock", names)

    def test_still_installed_only_while_file_exists(self):
        path = appimage(self.tmp, "BedrockOnLinux-2.3.1-x86_64.AppImage")
        detector = BedrockDetector(folders_fn=lambda: [str(self.tmp)])
        game = detector.detect()[0]
        self.assertTrue(detector.is_installed(game, game["ports"][0]))
        os.remove(path)
        self.assertFalse(detector.is_installed(game, game["ports"][0]))


if __name__ == "__main__":
    unittest.main()

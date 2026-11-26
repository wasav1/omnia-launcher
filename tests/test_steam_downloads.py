import tempfile
import unittest
from pathlib import Path

from omnia.games.steam import download_jobs


class SteamDownloadsTests(unittest.TestCase):
    def test_active_transfer_reports_progress_and_ignores_stale_completed_bytes(self):
        with tempfile.TemporaryDirectory() as temp:
            home = Path(temp)
            root = home / ".local/share/Steam/steamapps"
            root.mkdir(parents=True)
            for appid, flags, done in ((100, 1048582, 50), (200, 4, 100)):
                (root / f"appmanifest_{appid}.acf").write_text(f'''"AppState" {{
                     "appid" "{appid}" "name" "Example {appid}" "StateFlags" "{flags}"
                     "BytesToDownload" "100" "BytesDownloaded" "{done}"
                 }}''')
            job, = download_jobs(home)
        self.assertEqual(job["id"], "steam-transfer-100")
        self.assertTrue(job["external"])
        self.assertEqual(job["status"], "downloading")
        self.assertEqual(job["progress"], 50)

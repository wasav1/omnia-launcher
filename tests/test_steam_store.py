import io
import json
import tempfile
import unittest
import urllib.error
from pathlib import Path

from omnia.stores.base import StoreError
from omnia.stores.steam import Steam, fetch_owned, parse_capture

SID = "76561198273393717"
TOKEN = "eyJ" + "a" * 60 + "." + "b" * 30 + "." + "c" * 30


class Resp:
    def __init__(self, data):
        self.data = json.dumps(data).encode()

    def __enter__(self):
        return self

    def __exit__(self, *a):
        return False

    def read(self, n=-1):
        return self.data


def good_opener(req, timeout=0):
    assert req.full_url.startswith("https://api.steampowered.com/IPlayerService/GetOwnedGames/v1/?")
    assert "access_token=" + TOKEN in req.full_url and "steamid=" + SID in req.full_url
    return Resp({"response": {"game_count": 3, "games": [{"appid": 620, "name": "Portal 2"}, {"appid": 10, "name": "Counter-Strike"}, {"appid": "x"}]}})


def env(**kw):
    return json.dumps({"steamid": SID, "name": "Alex", "token": TOKEN, **kw})


class SteamTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.steam = Steam(Path(self.tmp.name), opener=good_opener)

    def test_login_library_logout_and_token_not_stored(self):
        self.assertFalse(self.steam.status()["logged_in"])
        st = self.steam.login(env())
        self.assertEqual((st["logged_in"], st["account"], st["games"]), (True, "Alex", 2))
        self.assertEqual(self.steam.file.stat().st_mode & 0o777, 0o600)
        self.assertNotIn(TOKEN, self.steam.file.read_text())
        lib = self.steam.library()
        self.assertEqual([g["title"] for g in lib], ["Counter-Strike", "Portal 2"])
        self.assertTrue(lib[0]["art"].endswith("/10/library_600x900.jpg"))
        self.assertFalse(self.steam.logout()["logged_in"])
        with self.assertRaises(StoreError):
            self.steam.library()

    def test_bad_captures(self):
        for raw in ("", "no json", "[]", env(steamid="123"), env(token="corto"), env(token="x y" * 30), json.dumps({}), None):
            with self.assertRaises(StoreError, msg=str(raw)[:30]):
                parse_capture(raw, good_opener)

    def test_api_errors(self):
        def denied(req, timeout=0):
            raise urllib.error.HTTPError(req.full_url, 401, "no", {}, io.BytesIO())

        def down(req, timeout=0):
            raise urllib.error.URLError("sin red")
        with self.assertRaises(StoreError) as cm:
            fetch_owned(SID, TOKEN, denied)
        self.assertIn("401", str(cm.exception))
        self.assertNotIn(TOKEN, str(cm.exception))
        with self.assertRaises(StoreError):
            fetch_owned(SID, TOKEN, down)
        self.assertEqual(fetch_owned(SID, TOKEN, lambda r, timeout=0: Resp({"response": {}})), [])


if __name__ == "__main__":
    unittest.main()

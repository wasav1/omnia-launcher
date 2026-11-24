import json
import tempfile
import unittest
from pathlib import Path

from omnia.stores.base import StoreError
from omnia.stores.steam import Steam, parse_games_xml

XML = """<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<gamesList><steamID64>76561198273393717</steamID64><steamID><![CDATA[Alex]]></steamID><games>
<game><appID>10</appID><name><![CDATA[Counter-Strike]]></name></game>
<game><appID>620</appID><name><![CDATA[Portal 2]]></name></game>
<game><appID>x</appID><name>malo</name></game></games></gamesList>"""


class SteamTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.steam = Steam(Path(self.tmp.name))

    def test_parse(self):
        d = parse_games_xml(XML)
        self.assertEqual((d["steamid"], d["name"]), ("76561198273393717", "Alex"))
        self.assertEqual([g["id"] for g in d["games"]], ["10", "620"])

    def test_rejects_bad_input(self):
        for bad in ("", "no es xml", "<response><error><![CDATA[x]]></error></response>", "<gamesList><steamID64>12</steamID64></gamesList>",
                    '<!DOCTYPE a [<!ENTITY x "y">]><gamesList/>', "<a>" + "x" * 9_000_000, None):
            with self.assertRaises(StoreError, msg=str(bad)[:30]):
                parse_games_xml(bad)

    def test_login_library_logout(self):
        self.assertFalse(self.steam.status()["logged_in"])
        st = self.steam.login(XML)
        self.assertEqual((st["logged_in"], st["account"], st["games"]), (True, "Alex", 2))
        self.assertEqual(self.steam.file.stat().st_mode & 0o777, 0o600)
        lib = self.steam.library()
        self.assertEqual([g["title"] for g in lib], ["Counter-Strike", "Portal 2"])
        self.assertTrue(lib[0]["art"].endswith("/10/library_600x900.jpg"))
        self.assertFalse(self.steam.logout()["logged_in"])
        with self.assertRaises(StoreError):
            self.steam.library()


if __name__ == "__main__":
    unittest.main()

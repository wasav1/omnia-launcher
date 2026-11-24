import shutil
import tempfile
import unittest
from pathlib import Path

from omnia import security
from omnia.api import Api, ApiError
from omnia.store import Store

from tests.test_stores import CODE, FakeRun


class StoresApiTests(unittest.TestCase):
    def setUp(self):
        self.tmp = Path(tempfile.mkdtemp())
        self.addCleanup(shutil.rmtree, self.tmp, True)
        self.api = Api(Store(self.tmp / "cfg"), security.new_token(self.tmp / "run"), [], scan_fn=list, fs_roots=[self.tmp])
        self.api.store_runner = FakeRun()
        import omnia.stores.epic as epic
        self._tool = epic.find_tool
        epic.find_tool = lambda name: "/bin/legendary"
        self.addCleanup(setattr, epic, "find_tool", self._tool)

    def test_list_login_logout_library(self):
        self.assertEqual(self.api.stores_list({})["stores"][0]["logged_in"], False)
        self.assertTrue(self.api.stores_login_url({"store": "epic"})["url"].startswith("https://www.epicgames.com/"))
        self.assertEqual(self.api.stores_login({"_body": {"store": "epic", "code": CODE}})["store"]["account"], "Ana")
        self.assertEqual(len(self.api.stores_library({"store": "epic"})["games"]), 2)
        self.assertFalse(self.api.stores_logout({"_body": {"store": "epic"}})["store"]["logged_in"])

    def test_errors(self):
        for q in ({}, {"store": "nope"}, {"store": ["epic"]}, {"store": "../x"}):
            with self.assertRaises(ApiError) as cm:
                self.api.stores_login_url(q)
            self.assertEqual(cm.exception.code, 404)
        with self.assertRaises(ApiError) as cm:
            self.api.stores_login({"_body": {"store": "epic", "code": "mal"}})
        self.assertEqual(cm.exception.code, 400)


if __name__ == "__main__":
    unittest.main()

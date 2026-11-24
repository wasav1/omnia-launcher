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


class StoreInstallApiTests(unittest.TestCase):
    def setUp(self):
        self.tmp = Path(tempfile.mkdtemp())
        self.addCleanup(shutil.rmtree, self.tmp, True)
        self.api = Api(Store(self.tmp / "cfg"), security.new_token(self.tmp / "run"), [], scan_fn=list, fs_roots=[self.tmp])
        self.api.store_runner = FakeRun()
        import omnia.stores.epic as epic
        self._tool = epic.find_tool
        epic.find_tool = lambda name: "/bin/legendary"
        self.addCleanup(setattr, epic, "find_tool", self._tool)

    def test_snapshot_merges_store_jobs_and_routes_actions(self):
        mgr = self.api._store_installs()
        mgr._jobs["j1"] = {"id": "j1", "kind": "store", "store": "epic", "gameId": "a", "name": "X", "status": "failed", "progress": 3, "error": "x"}
        snap = self.api.installations_snapshot({})
        self.assertIn("j1", [j["id"] for j in snap["jobs"]])
        with self.assertRaises(ApiError) as cm:
            self.api.installation_retry({"_body": {"jobId": "j1"}})
        self.assertEqual(cm.exception.code, 409)
        self.assertEqual(self.api.installation_dismiss({"_body": {"jobId": "j1"}})["dismissed"], 1)
        self.assertEqual(mgr.jobs(), [])

    def test_install_validation(self):
        for body in ({}, {"store": "nope"}, {"store": 5}):
            with self.assertRaises(ApiError) as cm:
                self.api.stores_install({"_body": body})
            self.assertEqual(cm.exception.code, 404)
        with self.assertRaises(ApiError) as cm:
            self.api.stores_install({"_body": {"store": "epic", "id": "A", "title": "t", "destination": str(self.tmp)}})
        self.assertEqual(cm.exception.code, 400)               # sin sesión de Epic

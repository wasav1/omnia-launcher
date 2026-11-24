import shutil
import tempfile
import unittest
from pathlib import Path

from omnia import security
from omnia.api import Api, ApiError
from omnia.store import Store


class InstallationApiTests(unittest.TestCase):
    def setUp(self):
        self.tmp = Path(tempfile.mkdtemp())
        self.addCleanup(shutil.rmtree, self.tmp, True)
        import os
        from unittest import mock
        env = mock.patch.dict(os.environ, {"XDG_DATA_HOME": str(self.tmp / "data"), "XDG_CONFIG_HOME": str(self.tmp / "cfg")})
        env.start()
        self.addCleanup(env.stop)
        self.api = Api(Store(self.tmp / "cfg"), security.new_token(self.tmp / "run"), [], scan_fn=list, fs_roots=[self.tmp])
        self.api.serve()
        self.addCleanup(self.api.stop)
        manager = self.api.package_installs
        manager._jobs = {"a": {"id": "a", "status": "failed", "name": "A", "error": "x"}, "b": {"id": "b", "status": "downloading", "name": "B"},
                         "c": {"id": "c", "status": "interrupted", "name": "C"}, "d": {"id": "d", "status": "completed", "name": "D"}}

    def test_dismiss_one_and_all_failed_but_never_a_running_job(self):
        self.assertEqual(self.api.installation_dismiss({"_body": {"jobId": "a"}}), {"ok": True, "dismissed": 1})
        with self.assertRaises(ApiError):
            self.api.installation_dismiss({"_body": {"jobId": "b"}})              # en curso: no se descarta
        self.assertEqual(self.api.installation_dismiss({"_body": {"all": True}})["dismissed"], 1)   # solo quedaba «c»
        self.assertEqual(sorted(j["id"] for j in self.api.package_installs.snapshot()["jobs"]), ["b"])        # «d» (completado) ya caducó

    def test_retry_rejects_running_or_unknown_jobs(self):
        for body in ({"jobId": "b"}, {"jobId": "zz"}, {}):
            with self.assertRaises(ApiError):
                self.api.installation_retry({"_body": body})


class MangoHudSettingTests(InstallationApiTests):
    def test_toggle_requires_a_boolean_and_an_installed_mangohud(self):
        from unittest import mock
        with self.assertRaises(ApiError):
            self.api.settings_mangohud({"_body": {"enabled": "si"}})
        with mock.patch("omnia.api.shutil.which", return_value=None):
            with self.assertRaises(ApiError):
                self.api.settings_mangohud({"_body": {"enabled": True}})
            self.assertTrue(self.api.settings_mangohud({"_body": {"enabled": False}})["ok"])
        with mock.patch("omnia.api.shutil.which", return_value="/usr/bin/mangohud"):
            self.assertEqual(self.api.settings_mangohud({"_body": {"enabled": True}}), {"ok": True, "mangohud": True})
            self.assertTrue(self.api.settings({})["mangohud"])
            env = self.api._mangohud_env()
        self.assertEqual(env["MANGOHUD_CONFIGFILE"], str(self.api.store.dir / "MangoHud.conf"))
        self.assertTrue((self.api.store.dir / "MangoHud.conf").read_text().startswith("# omnia-generado"))


if __name__ == "__main__":
    unittest.main()

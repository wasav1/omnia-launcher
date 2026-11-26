import shutil
import tempfile
import threading
import time
import unittest
from pathlib import Path
from unittest import mock

from omnia.store import Store
from omnia.stores.base import StoreError
from omnia.stores.installer import StoreInstalls, check_destination, parse_line


class FakeProc:
    def __init__(self, lines, code=0, hold=None):
        self.stdout = iter(l + "\n" for l in lines)
        self.code, self.pid, self.hold = code, 999999, hold

    def wait(self):
        if self.hold:
            self.hold.wait(3)
        return self.code


class FakeStore:
    id, short = "epic", "Epic"

    def __init__(self, exe=None, logged=True):
        self.exe, self.logged = exe, logged

    def status(self):
        return {"available": True, "logged_in": self.logged}

    def install_command(self, gid, folder):
        return ["legendary", "install", gid, folder], {"X": "1"}

    def find_executable(self, gid, folder):
        if not self.exe:
            raise StoreError("no encontró el ejecutable")
        return self.exe


def wait_for(mgr, pred, secs=3):
    end = time.time() + secs
    while time.time() < end:
        jobs = mgr.jobs()
        if jobs and pred(jobs[0]):
            return jobs[0]
        time.sleep(0.02)
    raise AssertionError(mgr.jobs())


class ParseTests(unittest.TestCase):
    def test_parse_line(self):
        self.assertEqual(parse_line("[DLManager] INFO: = Progress: 12.34% (123/1000), Running for 00:00:10, ETA: 00:01:05")["progress"], 12.34)
        self.assertEqual(parse_line("[DLManager] INFO: = Progress: 12.34% (1/2), ETA: 00:01:05")["eta"], "00:01:05")
        self.assertEqual(parse_line(" - Download\t- 12.3 MiB/s (raw)")["speed"], "12.3 MiB/s")
        self.assertEqual(parse_line("Progress: 55.5 12/24 , Running for: 00:00:01")["progress"], 55.5)
        self.assertEqual(parse_line("hola"), {})
        self.assertNotIn("progress", parse_line("Progress: 250%"))

    def test_destination(self):
        with tempfile.TemporaryDirectory() as d:
            self.assertEqual(check_destination(d), str(Path(d).resolve()))
        for bad in ("", "relativa", "/", "/usr", "/usr/lib", "/etc", str(Path.home()), "/no/existe"):
            with self.assertRaises(StoreError, msg=bad):
                check_destination(bad)


class InstallTests(unittest.TestCase):
    def setUp(self):
        self.tmp = Path(tempfile.mkdtemp())
        self.addCleanup(shutil.rmtree, self.tmp, True)
        self.dest = self.tmp / "Juegos"
        self.dest.mkdir()
        self.exe = self.tmp / "game.exe"
        self.exe.write_bytes(b"MZ")
        self.store = Store(self.tmp / "cfg")

    def mgr(self, proc, store=None):
        return StoreInstalls({"epic": store or FakeStore(str(self.exe))}, self.store, lambda: [self.tmp], popen=lambda *a, **k: proc, which=lambda n: "/x/" + n)

    def test_success_registers_game_in_library(self):
        m = self.mgr(FakeProc(["Progress: 40.0% (1/2) ETA: 00:00:30", "- Download - 5.0 MiB/s", "fin"]))
        job = m.start("epic", "Abc123", "Juego Uno", str(self.dest))
        done = wait_for(m, lambda j: j["status"] == "completed")
        self.assertEqual((done["progress"], done["name"], done["id"]), (100, "Juego Uno", job["id"]))
        games = self.store.games()
        self.assertEqual(len(games), 1)
        g = games[0]
        self.assertEqual((g["sub"], g["store_id"], g.get("auto")), ("PC · Epic", {"store": "epic", "id": "Abc123"}, None))
        self.assertIn("umu-run", g["ports"][0]["launch"])
        self.assertTrue(done["destination"].endswith("juego-uno"))

    def test_failure_exit_code_and_missing_exe(self):
        m = self.mgr(FakeProc(["boom"], code=3))
        m.start("epic", "A", "Falla", str(self.dest))
        j = wait_for(m, lambda j: j["status"] == "failed")
        self.assertIn("código 3", j["error"])
        self.assertEqual(self.store.games(), [])
        m2 = self.mgr(FakeProc(["ok"]), FakeStore(None))
        m2.start("epic", "B", "SinExe", str(self.dest))
        self.assertIn("ejecutable", wait_for(m2, lambda j: j["status"] == "failed")["error"])

    def test_cancel_and_dismiss(self):
        hold = threading.Event()
        m = self.mgr(FakeProc(["Progress: 1.0%"], code=1, hold=hold))
        job = m.start("epic", "C", "Cancela", str(self.dest))
        wait_for(m, lambda j: j["status"] == "downloading")
        with mock.patch("omnia.stores.installer.os.killpg"):
            self.assertTrue(m.cancel(job["id"]))
        hold.set()
        wait_for(m, lambda j: j["status"] == "cancelled")
        self.assertFalse(m.cancel(job["id"]))
        self.assertEqual(m.dismiss(job["id"]), 1)
        self.assertEqual(m.jobs(), [])

    def test_validation(self):
        m = self.mgr(FakeProc(["x"]))
        for args in (("nope", "A", "t", str(self.dest)), ("epic", "../x", "t", str(self.dest)), ("epic", "A", "t", "/usr")):
            with self.assertRaises(StoreError, msg=str(args)):
                m.start(*args)
        out = StoreInstalls({"epic": FakeStore(logged=False)}, self.store, lambda: [], which=lambda n: "/x")
        with self.assertRaises(StoreError):
            out.start("epic", "A", "t", str(self.dest))
        nou = StoreInstalls({"epic": FakeStore()}, self.store, lambda: [], which=lambda n: None)
        with self.assertRaises(StoreError):
            nou.start("epic", "A", "t", str(self.dest))

    def test_second_install_of_same_game_is_refused(self):
        hold = threading.Event()
        m = self.mgr(FakeProc(["x"], hold=hold))
        m.start("epic", "D", "Doble", str(self.dest))
        with self.assertRaises(StoreError):
            m.start("epic", "D", "Doble", str(self.dest))
        hold.set()


if __name__ == "__main__":
    unittest.main()

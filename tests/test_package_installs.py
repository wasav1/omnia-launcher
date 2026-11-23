import hashlib
import io
import os
import shutil
import tarfile
import tempfile
import time
import unittest
import zipfile
from pathlib import Path
from unittest import mock

from omnia import online_catalog, package_installs
from omnia.package_installs import PackageInstallManager
from omnia.store import Store


class FakeResponse(io.BytesIO):
    def __init__(self, data, url):
        super().__init__(data)
        self.headers = {"Content-Length": str(len(data))}
        self._url = url

    def geturl(self):
        return self._url

    def __enter__(self):
        return self

    def __exit__(self, *a):
        return False


class FakeOpener:
    def __init__(self, data):
        self.data = data

    def open(self, request, timeout=0):
        return FakeResponse(self.data, request.full_url)


def make_zip(files: dict) -> bytes:
    buf = io.BytesIO()
    with zipfile.ZipFile(buf, "w") as z:
        for name, data in files.items():
            info = zipfile.ZipInfo(name)
            info.external_attr = 0o755 << 16
            z.writestr(info, data)
    return buf.getvalue()


def make_targz(files: dict) -> bytes:
    buf = io.BytesIO()
    with tarfile.open(fileobj=buf, mode="w:gz") as t:
        for name, data in files.items():
            info = tarfile.TarInfo(name)
            info.size = len(data)
            info.mode = 0o755
            t.addfile(info, io.BytesIO(data))
    return buf.getvalue()


class InstallFlowTests(unittest.TestCase):
    def setUp(self):
        self.tmp = Path(tempfile.mkdtemp())
        self.addCleanup(shutil.rmtree, self.tmp, True)
        self.dest = self.tmp / "Juegos"
        self.dest.mkdir()
        env = mock.patch.dict(os.environ, {"XDG_DATA_HOME": str(self.tmp / "data"), "XDG_CONFIG_HOME": str(self.tmp / "cfg")})
        env.start()
        self.addCleanup(env.stop)
        self.store = Store(self.tmp / "cfg")
        self.manager = PackageInstallManager(self.store, lambda: [str(self.tmp)])
        self.addCleanup(self.manager.shutdown)
        patcher = mock.patch.object(package_installs, "_public_addresses", return_value=[])
        patcher.start()
        self.addCleanup(patcher.stop)

    def manifest(self, data: bytes, fmt: str, entrypoint: str, **extra):
        return {"id": "00000000-0000-4000-8000-000000000001", "title": "Port de prueba (Linux)", "version": "v1.0", "platformSlug": "pc",
                "sourceUrl": "https://github.com/o/mi-port/releases/download/v1.0/port", "sourceName": "GitHub: o/mi-port",
                "licenseName": "MIT", "archiveFormat": fmt, "sizeBytes": len(data), "sha256": hashlib.sha256(data).hexdigest(),
                "installSubdir": "", "entrypoint": entrypoint, **extra}

    def run_install(self, data, manifest, ficha=None):
        ficha = ficha or {"data": {"name": "Mario Kart World", "platforms": [{"slug": "switch2"}]}}
        with mock.patch.object(online_catalog, "install_package", return_value=manifest), \
                mock.patch.object(package_installs, "_safe_package_opener", return_value=FakeOpener(data)), \
                mock.patch.object(online_catalog, "game_detail", return_value=ficha):
            job = self.manager.start("mario-kart-world", manifest["id"], str(self.dest))
            deadline = time.time() + 10
            while time.time() < deadline:
                state = next(j for j in self.manager.snapshot()["jobs"] if j["id"] == job["id"])
                if state["status"] in {"completed", "failed", "cancelled"}:
                    return state
                time.sleep(0.05)
        self.fail("la instalación no terminó")

    def test_appimage_is_installed_as_the_executable(self):
        data = b"\x7fELF-appimage" * 100
        state = self.run_install(data, self.manifest(data, "appimage", "mkw.AppImage", setup={"start": {"program": ["mkw.AppImage"]}}))
        self.assertEqual(state["status"], "completed", state.get("error"))
        game = self.store.find_game(state["gameId"])
        self.assertEqual((game["name"], game["platform"], game["catalogSlug"]), ("Mario Kart World", "sw2", "mario-kart-world"))
        self.assertEqual(game["variant"], "mi-port")
        exe = Path(game["ports"][0]["launch"][-1])
        self.assertEqual(exe.read_bytes(), data)
        self.assertTrue(os.access(exe, os.X_OK))

    def test_zip_with_a_single_inner_tarball_is_unwrapped(self):
        inner = make_targz({"Zelda64Recompiled": b"binary", "assets/a.txt": b"x"})
        data = make_zip({"Zelda64Recompiled.tar.gz": inner})
        state = self.run_install(data, self.manifest(data, "zip", "Zelda64Recompiled"),
                                 ficha={"data": {"name": "Zelda: Majora's Mask", "platforms": [{"slug": "n64"}]}})
        self.assertEqual(state["status"], "completed", state.get("error"))
        game = self.store.find_game(state["gameId"])
        self.assertEqual(game["platform"], "n64")
        exe = Path(game["ports"][0]["launch"][-1])
        self.assertEqual(exe.name, "Zelda64Recompiled")
        self.assertTrue((exe.parent / "assets/a.txt").is_file())
        self.assertFalse(list(exe.parent.glob("*.tar.gz")))

    def test_plain_zip_still_works(self):
        data = make_zip({"juego": b"bin", "datos/x.dat": b"1"})
        state = self.run_install(data, self.manifest(data, "zip", "juego"), ficha={"data": {}})
        self.assertEqual(state["status"], "completed", state.get("error"))
        self.assertEqual(self.store.find_game(state["gameId"])["name"], "Port de prueba (Linux)")     # sin ficha: título del paquete

    def test_a_wrong_checksum_is_discarded_without_a_game(self):
        data = b"contenido" * 50
        manifest = self.manifest(data, "appimage", "x.AppImage", sha256="0" * 64)
        state = self.run_install(data, manifest)
        self.assertEqual(state["status"], "failed")
        self.assertEqual(self.store.games(), [])
        self.assertEqual([p.name for p in self.dest.iterdir()], [])                             # sin carpeta a medias


if __name__ == "__main__":
    unittest.main()


class PublicHTTPSHandlerCompat(unittest.TestCase):
    def test_https_open_does_not_need_private_handler_attributes(self):
        from unittest import mock
        from omnia import package_installs as pi
        handler = pi._PublicHTTPSHandler()
        with mock.patch.object(handler, "do_open", return_value="ok") as do_open:
            self.assertEqual(handler.https_open(object()), "ok")
        self.assertIs(do_open.call_args.kwargs["context"], handler._context)
        self.assertTrue(handler._context.check_hostname)


class PickUpdateTests(unittest.TestCase):
    rows = [{"id": "a", "createdAt": "2026-01-01", "archiveFormat": "zip"},
            {"id": "b", "createdAt": "2026-03-01", "archiveFormat": "zip"},
            {"id": "c", "createdAt": "2026-05-01", "archiveFormat": "appimage"}]

    def test_newest_of_the_same_format_wins(self):
        self.assertEqual(package_installs.pick_update(self.rows, "a", "zip")["id"], "b")

    def test_no_update_when_already_newest_or_alone(self):
        self.assertIsNone(package_installs.pick_update(self.rows, "b", "zip"))
        self.assertIsNone(package_installs.pick_update(self.rows[:1], "a", "zip"))

    def test_retired_package_is_replaced_by_the_newest_of_its_format(self):
        self.assertEqual(package_installs.pick_update(self.rows, "gone", "zip")["id"], "b")

    def test_format_is_taken_from_the_installed_row_when_unknown(self):
        self.assertEqual(package_installs.pick_update(self.rows, "a")["id"], "b")


class UpdateFlowTests(InstallFlowTests):
    def run_update(self, game_id, data, manifest, running=False):
        listing = {"items": [manifest], "offline": False}
        with mock.patch.object(online_catalog, "list_install_packages", return_value=listing), \
                mock.patch.object(package_installs, "_safe_package_opener", return_value=FakeOpener(data)):
            job = self.manager.start_update(game_id, lambda gid: running)
            deadline = time.time() + 10
            while time.time() < deadline:
                state = next(j for j in self.manager.snapshot()["jobs"] if j["id"] == job["id"])
                if state["status"] in {"completed", "failed", "cancelled"}:
                    return state
                time.sleep(0.05)
        self.fail("la actualización no terminó")

    def install_v1(self):
        data = make_zip({"juego-1": b"v1", "datos/x.dat": b"1", "licencia.txt": b"MIT"})
        state = self.run_install(data, self.manifest(data, "zip", "juego-1", createdAt="2026-01-01"))
        self.assertEqual(state["status"], "completed", state.get("error"))
        return state["gameId"], Path(self.store.find_game(state["gameId"])["installPath"])

    def v2(self, files=None):
        data = make_zip(files or {"juego-2": b"v2", "datos/x.dat": b"2"})
        return data, self.manifest(data, "zip", "juego-2", id="00000000-0000-4000-8000-000000000002", version="v2.0",
                                   createdAt="2026-06-01")

    def test_update_overlays_keeps_user_data_and_repoints_the_game(self):
        game_id, folder = self.install_v1()
        (folder / "Longshot").mkdir()
        (folder / "Longshot/construido.bin").write_bytes(b"datos del usuario")
        data, manifest = self.v2()
        state = self.run_update(game_id, data, manifest)
        self.assertEqual(state["status"], "completed", state.get("error"))
        self.assertEqual((folder / "datos/x.dat").read_bytes(), b"2")
        self.assertEqual((folder / "Longshot/construido.bin").read_bytes(), b"datos del usuario")
        self.assertEqual((folder / "licencia.txt").read_bytes(), b"MIT")                  # lo que el paquete nuevo no trae se conserva
        self.assertFalse((folder / "juego-1").exists())                                     # el ejecutable anterior se retira
        self.assertFalse((folder / package_installs.PREVIOUS_DIR).exists())
        game = self.store.find_game(game_id)
        self.assertEqual((game["installVersion"], game["installPackageId"]), ("v2.0", manifest["id"]))
        self.assertEqual(game["ports"][0]["launch"][-1], str(folder / "juego-2"))
        self.assertEqual(game["ports"][0]["proc"], "juego-2")
        (record,) = self.manager.installed()
        self.assertEqual((record["packageId"], record["entrypoint"], record["publishedAt"]), (manifest["id"], str(folder / "juego-2"), "2026-06-01"))
        self.assertEqual(len(self.store.games()), 1)

    def test_failed_overlay_restores_the_previous_version(self):
        game_id, folder = self.install_v1()
        data, manifest = self.v2({"datos/x.dat": b"2", "datos/y.dat": b"3", "juego-2": b"v2"})
        real_move = shutil.move
        calls = []

        def flaky(src, dst, *a, **k):
            calls.append(dst)
            if len(calls) == 3:
                raise OSError("disco lleno")
            return real_move(src, dst, *a, **k)
        with mock.patch.object(package_installs.shutil, "move", side_effect=flaky):
            state = self.run_update(game_id, data, manifest)
        self.assertEqual(state["status"], "failed")
        self.assertEqual((folder / "datos/x.dat").read_bytes(), b"1")
        self.assertEqual((folder / "juego-1").read_bytes(), b"v1")
        self.assertFalse((folder / "datos/y.dat").exists())
        self.assertFalse((folder / package_installs.PREVIOUS_DIR).exists())
        self.assertEqual(self.store.find_game(game_id)["installVersion"], "v1.0")

    def test_update_is_refused_while_the_game_runs_or_without_a_newer_package(self):
        game_id, _ = self.install_v1()
        data, manifest = self.v2()
        with self.assertRaises(package_installs.PackageInstallError):
            self.run_update(game_id, data, manifest, running=True)
        older = {**manifest, "createdAt": "2025-01-01"}
        with self.assertRaises(package_installs.PackageInstallError):
            self.run_update(game_id, data, older)

    def test_overlay_rejects_symlinks_in_the_installed_folder(self):
        game_id, folder = self.install_v1()
        outside = self.tmp / "fuera"
        outside.mkdir()
        shutil.rmtree(folder / "datos")
        (folder / "datos").symlink_to(outside)
        data, manifest = self.v2()
        state = self.run_update(game_id, data, manifest)
        self.assertEqual(state["status"], "failed")
        self.assertEqual(list(outside.iterdir()), [])

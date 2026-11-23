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

import json
import os
import shutil
import socket
import tempfile
import threading
import time
import unittest
import urllib.request
from pathlib import Path
from unittest import mock

from omnia import service
from omnia.games.base import Detector


class Falso(Detector):
    name = "falso"

    def __init__(self, juegos=None, falla=False):
        self.juegos, self.falla = juegos or [], falla

    def detect(self):
        if self.falla:
            raise RuntimeError("detector roto")
        return self.juegos


def juego(i, existe):
    return {"id": "f-%d" % i, "name": "Juego %d" % i, "auto": "falso",
            "ports": [{"id": "f-%d-m" % i, "name": "X", "launch": ["x"], "check": existe}]}


def puerto_libre():
    with socket.socket() as s:
        s.bind(("127.0.0.1", 0))
        return s.getsockname()[1]


class Servicio(unittest.TestCase):
    def setUp(self):
        self.tmp = Path(tempfile.mkdtemp())
        self.addCleanup(shutil.rmtree, self.tmp, True)
        env = {"XDG_CONFIG_HOME": str(self.tmp / "cfg"), "XDG_DATA_HOME": str(self.tmp / "data"),
               "XDG_RUNTIME_DIR": str(self.tmp / "run"),
               "OMNIA_DBUS_NAME": "org.omnia.Test%d" % os.getpid()}      # no choca con el omnia-core de la sesión
        p = mock.patch.dict(os.environ, env)
        p.start()
        self.addCleanup(p.stop)
        self.port, self.stop = puerto_libre(), threading.Event()
        self.rc = []

    def arrancar(self, dets, refresh=5):
        t = threading.Thread(target=lambda: self.rc.append(service.main(
            ["--port", str(self.port), "--refresh", str(refresh)], detectors=dets, stop=self.stop)))
        t.start()
        self.addCleanup(t.join, 5)
        self.addCleanup(self.stop.set)
        for _ in range(100):
            try:
                self.get("/health", auth=False)
                return t
            except OSError:
                time.sleep(0.05)
        self.fail("el servicio no arrancó")

    def get(self, path, auth=True):
        r = urllib.request.Request("http://127.0.0.1:%d%s" % (self.port, path))
        if auth:
            r.add_header("Authorization", "Bearer " + (self.tmp / "run/omnia/token").read_text())
        with urllib.request.urlopen(r, timeout=5) as resp:
            return json.load(resp)

    def test_arranca_sirve_y_se_apaga_limpio(self):
        existe = str(self.tmp)
        t = self.arrancar([Falso([juego(1, existe)])])
        self.assertEqual([g["name"] for g in self.get("/library")["games"]], ["Juego 1"])
        self.assertEqual((self.tmp / "run/omnia/token").stat().st_mode & 0o777, 0o600)
        self.stop.set()
        t.join(5)
        self.assertEqual(self.rc, [0])
        self.assertFalse((self.tmp / "run/omnia/token").exists())      # no deja el token a la vista

    def test_detector_roto_no_tumba_el_servicio(self):
        self.arrancar([Falso(falla=True)])
        self.assertEqual(self.get("/library")["games"], [])

    def test_puerto_ocupado_falla_con_error_claro(self):
        with socket.socket() as s:
            s.bind(("127.0.0.1", self.port))
            s.listen()
            self.assertEqual(service.main(["--port", str(self.port)], detectors=[], stop=self.stop), 1)


if __name__ == "__main__":
    unittest.main()

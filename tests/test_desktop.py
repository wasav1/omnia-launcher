import json
import os
import shutil
import subprocess
import tempfile
import time
import unittest
import urllib.request
from pathlib import Path

from omnia import security
from omnia.api import Api
from omnia.dbus import DesktopService
from omnia.events import EventBus
from omnia.store import Store


class Estado(unittest.TestCase):
    def test_el_bus_incluye_el_estado_y_despierta_la_espera(self):
        bus = EventBus()
        self.assertEqual(bus.snapshot(0)["shelfActive"], True)               # por defecto: el mando funciona
        bus.set_desktop(False, True)
        s = bus.snapshot(0)
        self.assertEqual((s["shelfActive"], s["covered"]), (False, True))

    def test_api_desktop_publica_el_estado_y_silencia_el_mando(self):
        tmp = Path(tempfile.mkdtemp())
        self.addCleanup(shutil.rmtree, tmp, True)
        token = security.new_token(tmp / "run")
        api = Api(Store(tmp / "cfg"), token, [], scan_fn=list)
        api.serve()
        self.addCleanup(api.stop)

        def call(path, method="GET"):
            r = urllib.request.Request(f'http://127.0.0.1:{api.port:d}{path}', method=method, data=b"{}" if method == "POST" else None,
                                       headers={"Authorization": "Bearer " + token})
            return json.load(urllib.request.urlopen(r, timeout=5))

        call("/desktop?visible=0&covered=1", "POST")
        s = call("/events?since=-1")
        self.assertEqual((s["shelfActive"], s["covered"]), (False, True))
        call("/emit?k=A", "POST")
        self.assertEqual(call("/events?since=-1")["seq"], 0)                 # no actúa con una ventana encima
        call("/desktop?visible=1&covered=0", "POST")
        call("/emit?k=A", "POST")
        self.assertEqual(call("/events?since=-1")["seq"], 1)


def hay_bus():
    try:
        import gi  # noqa: F401
        return bool(os.environ.get("DBUS_SESSION_BUS_ADDRESS") or os.path.exists(f'/run/user/{os.getuid():d}/bus'))
    except ImportError:
        return False


@unittest.skipUnless(hay_bus(), "sin bus de sesión D-Bus o sin PyGObject")
class DBus(unittest.TestCase):
    def test_setdesktop_llega_al_callback(self):
        got = []
        name = f'org.omnia.TestA{os.getpid():d}'
        svc = DesktopService(lambda a, c: got.append((a, c)), name=name)
        self.assertTrue(svc.start())
        self.addCleanup(svc.stop)
        for args, expect in ((("true", "false"), (True, False)), (("false", "true"), (False, True))):
            subprocess.run(["busctl", "--user", "call", name, "/org/omnia/Core", "org.omnia.Core", "SetDesktop", "bb", *args],
                           check=True, capture_output=True, timeout=10)
            t0 = time.time()
            while len(got) < (1 if expect == (True, False) else 2) and time.time() < t0 + 5:
                time.sleep(0.05)
        self.assertEqual(got, [(True, False), (False, True)])

    def test_togglemenu_llega_al_callback(self):
        n = []
        name = f'org.omnia.TestC{os.getpid():d}'
        svc = DesktopService(lambda a, c: None, on_menu=lambda: n.append(1), name=name)
        self.assertTrue(svc.start())
        self.addCleanup(svc.stop)
        subprocess.run(["busctl", "--user", "call", name, "/org/omnia/Core", "org.omnia.Core", "ToggleMenu"],
                       check=True, capture_output=True, timeout=10)
        self.assertEqual(n, [1])

    def test_nombre_ocupado_no_rompe(self):
        name = f'org.omnia.TestB{os.getpid():d}'
        a, b = DesktopService(lambda *x: None, name=name), DesktopService(lambda *x: None, name=name)
        self.assertTrue(a.start())
        self.addCleanup(a.stop)
        self.assertFalse(b.start())                                           # ya hay otra instancia: se avisa y se sigue


if __name__ == "__main__":
    unittest.main()

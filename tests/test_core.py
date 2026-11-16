import json
import os
import shutil
import tempfile
import unittest
import urllib.error
import urllib.request
from pathlib import Path
from unittest import mock

from omnia import paths, procs, security
from omnia.api import Api
from omnia.games.refresh import refresh
from omnia.games.steam import SteamDetector
from omnia.games.vdf import parse_vdf
from omnia.store import Store


def make_steam(home: Path, games: dict):
    """games: appid -> (nombre, StateFlags, ¿existe la carpeta?)"""
    lib = home / ".local/share/Steam/steamapps"
    (lib / "common").mkdir(parents=True)
    for appid, (name, flags, exists) in games.items():
        (lib / f"appmanifest_{appid}.acf").write_text(
            '"AppState"\n{\n\t"appid"\t\t"%s"\n\t"name"\t\t"%s"\n\t"StateFlags"\t\t"%d"\n\t"installdir"\t\t"%s"\n}\n'
            % (appid, name, flags, name))
        if exists:
            (lib / "common" / name).mkdir()


class Paths(unittest.TestCase):
    def test_xdg_y_sin_rutas_fijas(self):
        with mock.patch.dict(os.environ, {"XDG_CONFIG_HOME": "/x/cfg", "XDG_DATA_HOME": "/x/data"}):
            self.assertEqual(paths.config_dir(), Path("/x/cfg/omnia"))
            self.assertEqual(paths.data_dir(), Path("/x/data/omnia"))

    def test_xdg_relativo_se_ignora(self):
        with mock.patch.dict(os.environ, {"XDG_CONFIG_HOME": "relativa"}):
            self.assertEqual(paths.config_dir(), Path("~/.config/omnia").expanduser())


class Vdf(unittest.TestCase):
    def test_anidado(self):
        d = parse_vdf('"a" { "b" "1" "c" { "d" "2" } }')
        self.assertEqual(d, {"a": {"b": "1", "c": {"d": "2"}}})


class Steam(unittest.TestCase):
    def setUp(self):
        self.home = Path(tempfile.mkdtemp())
        self.addCleanup(shutil.rmtree, self.home, True)

    def test_solo_instalados_de_verdad(self):
        make_steam(self.home, {"10": ("Juego Bueno", 4, True), "20": ("Descargando", 1026, True),
                               "30": ("Carpeta Borrada", 4, False), "1493710": ("Proton Experimental", 4, True)})
        ids = [g["id"] for g in SteamDetector(self.home).detect()]
        self.assertEqual(ids, ["steam-10"])

    def test_lanzamiento_correcto(self):
        make_steam(self.home, {"10": ("Juego Bueno", 4, True)})
        p = SteamDetector(self.home).detect()[0]["ports"][0]
        self.assertEqual(p["launch"], ["steam", "steam://rungameid/10"])


class EnEjecucion(unittest.TestCase):
    REAPER = "/x/steamrt64/reaper SteamLaunch AppId=%s -- /x/proton waitforexitandrun /x/Juego.exe"

    def setUp(self):
        self.det = SteamDetector(Path("/nada"))
        self.g = {"id": "steam-10"}

    def test_steam_por_appid(self):
        self.assertTrue(self.det.is_running(self.g, {}, [self.REAPER % 10]))

    def test_appid_parecido_no_cuenta(self):       # AppId=100 no es el juego 10
        self.assertFalse(self.det.is_running(self.g, {}, [self.REAPER % 100]))

    def test_sin_reaper_no_cuenta(self):
        self.assertFalse(self.det.is_running(self.g, {}, ["steam steam://rungameid/10 SteamLaunch AppId=10 "]))

    def test_proc_generico(self):
        from omnia.games.base import Detector
        self.assertTrue(Detector().is_running({}, {"proc": "juego.exe"}, ["wine /a/juego.exe"]))
        self.assertFalse(Detector().is_running({}, {"proc": ""}, ["wine /a/juego.exe"]))

    def test_escaner_real_ve_este_proceso(self):
        self.assertTrue(any("unittest" in c or "python" in c for c in procs.scan()))


class Refresh(unittest.TestCase):
    def setUp(self):
        self.home = Path(tempfile.mkdtemp())
        self.store = Store(self.home / "cfg")
        self.addCleanup(shutil.rmtree, self.home, True)

    def test_desinstalar_lo_quita_y_manual_se_conserva(self):
        make_steam(self.home, {"10": ("Uno", 4, True), "11": ("Dos", 4, True)})
        self.store.set_games([{"id": "manual", "name": "Mio", "ports": []}])
        det = [SteamDetector(self.home)]
        self.assertEqual(refresh(self.store, det)["added"], 2)
        shutil.rmtree(self.home / ".local/share/Steam/steamapps/common/Dos")
        r = refresh(self.store, det)
        self.assertEqual(r["removed"], 1)
        self.assertEqual(sorted(g["id"] for g in self.store.games()), ["manual", "steam-10"])

    def test_conserva_ajustes_del_usuario(self):
        make_steam(self.home, {"10": ("Uno", 4, True)})
        det = [SteamDetector(self.home)]
        refresh(self.store, det)
        gs = self.store.games()
        gs[0]["art"]["portada"] = 3
        self.store.set_games(gs)
        refresh(self.store, det)
        self.assertEqual(self.store.games()[0]["art"]["portada"], 3)


class ApiSeguridad(unittest.TestCase):
    def setUp(self):
        self.tmp = Path(tempfile.mkdtemp())
        self.addCleanup(shutil.rmtree, self.tmp, True)
        make_steam(self.tmp, {"10": ("Uno", 4, True)})
        self.store = Store(self.tmp / "cfg")
        self.token = security.new_token(self.tmp / "run")
        self.launched = []
        self.api = Api(self.store, self.token, [SteamDetector(self.tmp)], launch_fn=lambda p, g: self.launched.append(g))
        self.api.serve()
        self.addCleanup(self.api.stop)
        self.base = "http://127.0.0.1:%d" % self.api.port

    def call(self, path, method="GET", token=True, host=None):
        req = urllib.request.Request(self.base + path, method=method, data=b"{}" if method == "POST" else None)
        if token:
            req.add_header("Authorization", "Bearer " + self.token)
        if host:
            req.add_header("Host", host)
        try:
            with urllib.request.urlopen(req, timeout=5) as r:
                return r.status, json.load(r)
        except urllib.error.HTTPError as e:
            return e.code, json.load(e)

    def test_token_con_permisos_0600(self):
        self.assertEqual((self.tmp / "run/token").stat().st_mode & 0o777, 0o600)

    def test_sin_token_401(self):
        self.assertEqual(self.call("/library", token=False)[0], 401)
        self.assertEqual(self.call("/launch?id=steam-10", "POST", token=False)[0], 401)

    def test_token_incorrecto_401(self):
        self.token = "falso"
        self.assertEqual(self.call("/library")[0], 401)

    def test_host_ajeno_403(self):
        self.assertEqual(self.call("/health", host="evil.example:%d" % self.api.port)[0], 403)

    def test_acciones_solo_por_post(self):
        self.call("/library/refresh", "POST")
        self.assertEqual(self.call("/launch?id=steam-10")[0], 405)
        self.assertEqual(self.launched, [])

    def test_preflight_cors_rechazado(self):
        self.assertEqual(self.call("/launch", "OPTIONS", token=False)[0], 405)

    def test_lanzar_flujo_normal(self):
        self.call("/library/refresh", "POST")
        self.assertEqual([g["id"] for g in self.call("/library")[1]["games"]], ["steam-10"])
        self.assertEqual(self.call("/launch?id=steam-10", "POST")[0], 200)
        self.assertEqual(self.launched, ["steam-10"])

    def test_running_y_no_relanzar(self):
        self.api.scan_fn = lambda: [EnEjecucion.REAPER % 10]
        self.call("/library/refresh", "POST")
        self.assertTrue(self.call("/library")[1]["games"][0]["running"])
        self.assertEqual(self.call("/launch?id=steam-10", "POST")[0], 409)
        self.assertEqual(self.launched, [])

    def test_energia_solo_post_y_solo_acciones_conocidas(self):
        ejecutadas = []
        self.api.power_spawn = lambda cmd, **kw: ejecutadas.append(cmd)
        self.assertEqual(self.call("/power?a=lock")[0], 405)                       # nunca por GET
        self.assertEqual(self.call("/power?a=lock", "POST", token=False)[0], 401)
        self.assertEqual(self.call("/power?a=format-c", "POST")[0], 400)
        self.assertEqual(ejecutadas, [])
        self.assertEqual(self.call("/power?a=lock", "POST")[0], 200)
        self.assertEqual(ejecutadas, [["loginctl", "lock-session"]])

    def test_sistema_devuelve_cpu_disco_y_bateria(self):
        st, body = self.call("/system")
        self.assertEqual(st, 200)
        self.assertIn("cpu", body)
        self.assertIn("ac", body)
        self.assertEqual(self.call("/system", token=False)[0], 401)

    def test_no_se_puede_inyectar_comando(self):
        self.call("/library/refresh", "POST")
        req = urllib.request.Request(self.base + "/launch", method="POST",
                                     data=json.dumps({"id": "steam-10", "launch": ["rm", "-rf", "/"]}).encode())
        req.add_header("Authorization", "Bearer " + self.token)
        urllib.request.urlopen(req, timeout=5).read()
        self.assertEqual(self.launched, ["steam-10"])     # solo el id: el comando sale de la biblioteca


if __name__ == "__main__":
    unittest.main()

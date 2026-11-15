import json
import os
import shutil
import signal
import subprocess
import tempfile
import time
import unittest
from pathlib import Path

from omnia import gamemode
from omnia.gamemode import Freezer, GameMode, proc_info, settings


def espera(cond, t=3.0):
    end = time.time() + t
    while time.time() < end:
        if cond():
            return True
        time.sleep(0.05)
    return False


class Procesos(unittest.TestCase):
    """Con procesos de verdad: copias de `sleep` con el nombre de un cliente de descargas."""

    def setUp(self):
        self.tmp = Path(tempfile.mkdtemp())
        self.addCleanup(shutil.rmtree, self.tmp, True)
        self.procs = []
        self.addCleanup(self.limpia)
        self.fz = Freezer(self.tmp / "gm.json")

    def limpia(self):
        for p in self.procs:
            try:
                p.send_signal(signal.SIGCONT)
                p.kill()
                p.wait(3)
            except Exception:
                pass

    def lanza(self, nombre):
        exe = self.tmp / nombre
        shutil.copy("/usr/bin/sleep", exe)
        p = subprocess.Popen([str(exe), "300"])
        self.procs.append(p)
        self.assertTrue(espera(lambda: (proc_info(p.pid) or ("",))[0] == nombre[:15]))
        return p

    def estado(self, p):
        return proc_info(p.pid)[1]

    def test_congela_por_nombre_exacto_y_reanuda(self):
        a, otro = self.lanza("aria2c"), self.lanza("aria2c-no")
        frozen = self.fz.freeze(["aria2c"])
        self.assertEqual([pid for pid, _ in frozen], [a.pid])
        self.assertTrue(espera(lambda: self.estado(a) == "T"))
        self.assertNotEqual(self.estado(otro), "T")                       # nombre parecido: no se toca
        self.assertEqual(self.fz.resume(), 1)
        self.assertTrue(espera(lambda: self.estado(a) != "T"))
        self.assertFalse(self.fz.state_file.exists())

    def test_no_toca_lo_que_ya_estaba_detenido(self):
        a = self.lanza("qbittorrent")
        os.kill(a.pid, signal.SIGSTOP)
        self.assertTrue(espera(lambda: self.estado(a) == "T"))
        self.assertEqual(self.fz.freeze(["qbittorrent"]), [])             # lo paró el usuario: no es nuestro
        self.assertEqual(self.fz.resume(), 0)
        self.assertEqual(self.estado(a), "T")

    def test_recupera_tras_una_caida(self):
        a = self.lanza("aria2c")
        self.fz.freeze(["aria2c"])
        self.assertTrue(espera(lambda: self.estado(a) == "T"))
        nuevo = Freezer(self.fz.state_file)                               # otro arranque del servicio, mismo archivo
        self.assertEqual(nuevo.resume(), 1)
        self.assertTrue(espera(lambda: self.estado(a) != "T"))

    def test_pid_reutilizado_no_se_reanuda(self):
        a = self.lanza("aria2c")
        self.fz.freeze(["aria2c"])
        estado = json.loads(self.fz.state_file.read_text())
        estado["frozen"][0][1] += 12345                                   # otra «hora de arranque»: otro proceso con ese pid
        self.fz.state_file.write_text(json.dumps(estado))
        os.kill(a.pid, signal.SIGSTOP)
        self.assertEqual(self.fz.resume(), 0)
        self.assertEqual(self.estado(a), "T")                             # no se envió SIGCONT

    def test_sin_nombres_no_hace_nada(self):
        self.assertEqual(self.fz.freeze([]), [])
        self.assertFalse(self.fz.state_file.exists())

    def test_proc_info_con_nombres_raros(self):
        d = self.tmp / "proc" / "42"
        d.mkdir(parents=True)
        (d / "stat").write_text("42 (mi (app) raro) S 1 1 1 0 -1 0 0 0 0 0 0 0 0 0 20 0 1 0 777 0 0 0\n")
        self.assertEqual(proc_info(42, str(self.tmp / "proc")), ("mi (app) raro", "S", 777))


class FakeFreezer:
    def __init__(self, n=2):
        self.n, self.calls = n, []
        self.state_file = Path("/nada")

    def freeze(self, names, extra=None):
        self.calls.append(("freeze", list(names)))
        return [(i, i) for i in range(self.n)]

    def resume(self):
        self.calls.append(("resume",))
        return self.n


class FakePower:
    def __init__(self, ok=True):
        self.ok, self.calls = ok, []

    def hold(self, profile):
        self.calls.append(("hold", profile))
        return self.ok

    def release(self):
        self.calls.append(("release",))


class Maquina(unittest.TestCase):
    def make(self, cfg=None, **kw):
        self.fz, self.pw = FakeFreezer(**kw), FakePower()
        return GameMode(cfg or {}, self.fz, self.pw, say=lambda *a: None)

    def test_entra_tras_dos_sondeos_y_sale_tras_tres(self):
        m = self.make()
        self.assertFalse(m.update(["Juego"]))                              # un solo sondeo: puede ser un lanzador
        self.assertTrue(m.update(["Juego"]))
        self.assertTrue(m.active)
        self.assertEqual(self.pw.calls, [("hold", "performance")])
        self.assertFalse(m.update([]))
        self.assertFalse(m.update([]))
        self.assertTrue(m.active)                                          # aún no: el juego pudo reiniciarse
        self.assertTrue(m.update([]))
        self.assertFalse(m.active)
        self.assertEqual(self.pw.calls[-1], ("release",))
        self.assertIn(("resume",), self.fz.calls)

    def test_un_reinicio_breve_del_juego_no_apaga_el_modo(self):
        m = self.make()
        m.update(["J"]); m.update(["J"])
        m.update([]); m.update([])
        m.update(["J"])                                                    # volvió antes del tercer sondeo
        m.update([]); m.update([])
        self.assertTrue(m.active)

    def test_desactivado_por_configuracion(self):
        m = self.make({"game_mode": {"enabled": False}})
        for _ in range(5):
            m.update(["J"])
        self.assertFalse(m.active)
        self.assertEqual((self.fz.calls, self.pw.calls), ([], []))

    def test_lista_y_perfil_configurables(self):
        m = self.make({"game_mode": {"freeze": ["miapp"], "profile": "balanced"}})
        m.update(["J"]); m.update(["J"])
        self.assertEqual(self.fz.calls[0], ("freeze", ["miapp"]))
        self.assertEqual(self.pw.calls[0], ("hold", "balanced"))

    def test_sin_perfil_disponible_sigue_congelando(self):
        m = self.make()
        self.pw.ok = False
        m.update(["J"]); m.update(["J"])
        self.assertTrue(m.active)
        self.assertEqual(m.status()["profile"], "")                        # no miente: no se retuvo ningún perfil
        self.assertEqual(m.status()["frozen"], 2)

    def test_shutdown_suelta_todo(self):
        m = self.make()
        m.update(["J"]); m.update(["J"])
        m.shutdown()
        self.assertFalse(m.active)
        self.assertEqual(self.pw.calls[-1], ("release",))

    def test_fallo_al_congelar_reanuda_y_sigue(self):
        m = self.make()
        def roto(names, extra=None):
            raise RuntimeError("boom")
        m.freezer.freeze = roto
        m.update(["J"]); m.update(["J"])
        self.assertIn(("resume",), self.fz.calls)                          # lo parcial se deshace
        self.assertEqual(self.pw.calls[0], ("hold", "performance"))

    def test_configuracion_invalida_cae_a_los_valores_por_defecto(self):
        s = settings({"game_mode": {"freeze": "no-es-una-lista", "profile": "x", "otra": 1}})
        self.assertEqual(s["freeze"], gamemode.DEFAULTS["freeze"])
        self.assertNotIn("otra", s)


class ConApi(unittest.TestCase):
    def test_running_games_ignora_la_nube(self):
        from omnia.api import Api
        from omnia.store import Store
        tmp = Path(tempfile.mkdtemp())
        self.addCleanup(shutil.rmtree, tmp, True)
        st = Store(tmp / "cfg")
        port = lambda n: {"id": n, "name": "x", "launch": ["x"], "check": str(tmp), "proc": n}
        st.set_games([{"id": "local", "name": "Local", "ports": [port("local.exe")]},
                      {"id": "nube", "name": "Nube", "cloud": True, "ports": [port("geforcenow")]},
                      {"id": "parado", "name": "Parado", "ports": [port("parado.exe")]}])
        api = Api(st, "t", [], scan_fn=lambda: ["wine /x/local.exe", "geforcenow --run"])
        self.addCleanup(api.httpd.server_close)
        self.assertEqual(api.running_games(), ["Local"])


if __name__ == "__main__":
    unittest.main()

import json
import shutil
import tempfile
import unittest
import urllib.request
from pathlib import Path

from omnia import security, sessions
from omnia.api import Api
from omnia.sessions import Sessions
from omnia.store import Store


class Reloj:
    def __init__(self, t=1_000_000):
        self.t = t

    def __call__(self):
        return self.t

    def avanza(self, s):
        self.t += s


class Historial(unittest.TestCase):
    def setUp(self):
        self.tmp = Path(tempfile.mkdtemp())
        self.addCleanup(shutil.rmtree, self.tmp, True)
        self.store = Store(self.tmp)
        self.r = Reloj()
        self.s = Sessions(self.store, now=self.r, say=lambda *a: None)

    def tick(self, running, n=1, dt=2):
        out = False
        for _ in range(n):
            out = self.s.update(running) or out
            self.r.avanza(dt)
        return out

    def juega(self, secs, gid="g", name="Juego"):
        """Una partida de `secs` segundos y su cierre completo (3 sondeos sin el juego)."""
        for _ in range(secs // 2):
            self.s.update({gid: name})
            self.r.avanza(2)
        self.tick({}, 3)

    def test_la_sesion_dura_hasta_la_ultima_vez_visto(self):
        self.juega(60)
        st = self.store.state
        self.assertEqual(st["sessions"]["g"]["count"], 1)
        self.assertTrue(58 <= st["sessions"]["g"]["total_secs"] <= 62)     # no incluye los 6 s de ausencia
        self.assertEqual(st["last_played"]["g"], st["sessions"]["g"]["last_ended"])
        self.assertEqual(st["history"][-1]["name"], "Juego")

    def test_un_parpadeo_no_cuenta(self):
        self.tick({"g": "J"}, 1)                                           # visto una sola vez
        self.tick({}, 5)
        self.assertEqual(self.store.state["sessions"], {})
        self.assertEqual(self.s.active, {})

    def test_menos_de_10_segundos_no_cuenta(self):
        self.tick({"g": "J"}, 3, dt=2)                                     # ~4 s de juego
        self.tick({}, 3)
        self.assertEqual(self.store.state["sessions"], {})

    def test_un_reinicio_breve_sigue_siendo_la_misma_sesion(self):
        self.tick({"g": "J"}, 10)
        self.tick({}, 2)                                                   # desaparece 4 s…
        self.tick({"g": "J"}, 10)                                          # …y vuelve
        self.tick({}, 3)
        self.assertEqual(self.store.state["sessions"]["g"]["count"], 1)

    def test_dos_partidas_suman(self):
        self.juega(60)
        self.r.avanza(600)
        self.juega(120)
        s = self.store.state["sessions"]["g"]
        self.assertEqual(s["count"], 2)
        self.assertTrue(175 <= s["total_secs"] <= 185)
        self.assertEqual(len(self.store.state["history"]), 2)

    def test_snapshot_mientras_se_juega(self):
        self.tick({"g": "J"}, 20)                                          # ~40 s en curso
        a = self.s.snapshot("g")
        self.assertTrue(a["playingSince"] > 0)
        self.assertTrue(36 <= a["totalSecs"] <= 44)
        self.assertEqual(a["plays"], 1)
        self.assertEqual(a["lastPlayed"], int(self.r()))                   # jugando ahora = ahora mismo

    def test_snapshot_de_un_juego_nunca_jugado(self):
        self.assertEqual(self.s.snapshot("nada"), {"lastPlayed": 0, "totalSecs": 0, "plays": 0, "playingSince": 0})

    def test_juegos_independientes(self):
        for _ in range(15):
            self.s.update({"a": "A", "b": "B"})
            self.r.avanza(2)
        for _ in range(15):
            self.s.update({"b": "B"})                                      # a se cierra, b sigue
            self.r.avanza(2)
        self.tick({}, 3)
        st = self.store.state["sessions"]
        self.assertTrue(st["b"]["total_secs"] > st["a"]["total_secs"] > 20)

    def test_shutdown_cierra_la_sesion_en_curso(self):
        self.tick({"g": "J"}, 20)
        self.s.shutdown()
        self.assertEqual(self.store.state["sessions"]["g"]["count"], 1)
        self.assertEqual(self.store.state["active_sessions"], {})
        self.assertEqual(Store(self.tmp).state["sessions"]["g"]["count"], 1)  # y quedó en disco

    def test_recupera_la_sesion_tras_una_caida(self):
        self.tick({"g": "J"}, 40)                                          # ~80 s: ya se anotó en active_sessions (cada 30 s)
        self.assertIn("g", Store(self.tmp).state["active_sessions"])
        # el servicio muere (no hay shutdown) y arranca otro con el mismo state.json
        nuevo = Sessions(Store(self.tmp), now=self.r, say=lambda *a: None)
        self.r.avanza(5000)                                                # mucho después: no debe contar este tiempo
        self.assertEqual(nuevo.recover(), 1)
        st = Store(self.tmp).state
        self.assertEqual(st["sessions"]["g"]["count"], 1)
        self.assertTrue(st["sessions"]["g"]["total_secs"] < 200)           # hasta la última vez visto, no hasta ahora
        self.assertEqual(st["active_sessions"], {})

    def test_el_historial_tiene_tope(self):
        with self.store.lock:
            self.store.state["history"] = [{"id": "x", "name": "x", "start": 0, "end": 1, "secs": 1}] * sessions.HISTORY_MAX
        self.juega(30)
        self.assertEqual(len(self.store.state["history"]), sessions.HISTORY_MAX)
        self.assertEqual(self.store.state["history"][-1]["id"], "g")


class Almacen(unittest.TestCase):
    def test_dos_instancias_no_comparten_el_estado_por_defecto(self):
        a, b = Path(tempfile.mkdtemp()), Path(tempfile.mkdtemp())
        self.addCleanup(shutil.rmtree, a, True)
        self.addCleanup(shutil.rmtree, b, True)
        Store(a).state["sessions"]["x"] = {"count": 9}
        self.assertEqual(Store(b).state["sessions"], {})                   # antes se filtraba entre instancias


class ApiHistorial(unittest.TestCase):
    def test_library_trae_el_historial_y_ordena_por_ultimo_jugado(self):
        tmp = Path(tempfile.mkdtemp())
        self.addCleanup(shutil.rmtree, tmp, True)
        store = Store(tmp / "cfg")
        port = {"id": "p", "name": "x", "launch": ["x"], "check": str(tmp)}
        store.set_games([{"id": "a", "name": "Alfa", "ports": [dict(port)]}, {"id": "b", "name": "Beta", "ports": [dict(port)]},
                         {"id": "c", "name": "Ceta", "ports": [dict(port)]}])
        r = Reloj()
        ses = Sessions(store, now=r, say=lambda *a: None)
        for gid, t in (("a", 100), ("c", 5000)):                           # c se jugó más tarde que a; b nunca
            store.state.setdefault("last_played", {})[gid] = t
            store.state.setdefault("sessions", {})[gid] = {"total_secs": 600, "count": 2}
        token = security.new_token(tmp / "run")
        api = Api(store, token, [], scan_fn=list)
        api.sessions = ses
        api.serve()
        self.addCleanup(api.stop)
        req = urllib.request.Request(f'http://127.0.0.1:{api.port:d}/library', headers={"Authorization": "Bearer " + token})
        games = json.load(urllib.request.urlopen(req, timeout=5))["games"]
        self.assertEqual([g["id"] for g in games], ["c", "a", "b"])        # último jugado primero; el nunca jugado, al final
        self.assertEqual((games[0]["totalSecs"], games[0]["plays"], games[0]["lastPlayed"]), (600, 2, 5000))
        self.assertEqual(games[2]["plays"], 0)


if __name__ == "__main__":
    unittest.main()

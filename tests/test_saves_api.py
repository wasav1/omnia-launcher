import json
import shutil
import tempfile
import unittest
import urllib.error
import urllib.request
from pathlib import Path

from omnia import security
from omnia.api import Api
from omnia.store import Store


class ApiPartidas(unittest.TestCase):
    def setUp(self):
        self.tmp = Path(tempfile.mkdtemp())
        self.addCleanup(shutil.rmtree, self.tmp, True)
        self.home = self.tmp / "home"                                   # «el home» y único lugar permitido para el explorador
        (self.home / "Juegos").mkdir(parents=True)
        self.saves_dir = self.home / "Juegos/MiPort/saves"
        (self.saves_dir / "perfil").mkdir(parents=True)
        (self.saves_dir / "perfil/slot0.sav").write_text("PARTIDA-1")
        self.store = Store(self.tmp / "cfg")
        port = {"id": "p", "name": "Port", "launch": ["x"], "check": str(self.tmp)}
        self.store.set_games([{"id": "mio", "name": "Mi Port", "ports": [port]}, {"id": "otro", "name": "Otro", "ports": [dict(port)]}])
        self.token = security.new_token(self.tmp / "run")
        self.opened = []
        self.api = Api(self.store, self.token, [], scan_fn=list, fs_roots=[self.home],
                       open_fn=self.opened.append, backup_root=str(self.home / "Juegos/_Partidas"))
        self.api.serve()
        self.addCleanup(self.api.stop)

    def call(self, path, method="GET", body=None, token=True):
        data = json.dumps(body).encode() if body is not None else (b"{}" if method == "POST" else None)
        r = urllib.request.Request(f'http://127.0.0.1:{self.api.port:d}{path}', method=method, data=data)
        if token:
            r.add_header("Authorization", "Bearer " + self.token)
        try:
            with urllib.request.urlopen(r, timeout=5) as x:
                return x.status, json.load(x)
        except urllib.error.HTTPError as e:
            return e.code, json.load(e)

    def config(self, gid="mio", **kw):
        return self.call("/saves/config?id=" + gid, "POST", {"dirs": [str(self.saves_dir)], **kw})

    # --- explorador
    def test_explorador_lista_dentro_del_home_y_exige_token(self):
        c, d = self.call("/fs/list?path=" + str(self.home / "Juegos"))
        self.assertEqual((c, [x["name"] for x in d["dirs"]]), (200, ["MiPort"]))
        self.assertEqual(self.call("/fs/list", token=False)[0], 401)

    def test_explorador_no_sale_del_home(self):
        for p in ("/etc", "/", str(self.home / "..")):
            self.assertEqual(self.call("/fs/list?path=" + p)[0], 403, p)

    def test_explorador_con_archivos_y_filtro(self):
        (self.home / "Juegos/rom.z64").write_text("x"); (self.home / "Juegos/notas.txt").write_text("y")
        d = self.call("/fs/list?path=%s&files=1&ext=z64,.n64" % (self.home / "Juegos"))[1]
        self.assertEqual([f["name"] for f in d["files"]], ["rom.z64"])

    # --- configuración
    def test_sin_configurar_y_luego_configurada(self):
        self.assertFalse(self.call("/saves?id=mio")[1]["configured"])
        self.assertEqual(self.config()[0], 200)
        info = self.call("/saves?id=mio")[1]
        self.assertTrue(info["configured"])
        self.assertEqual([x["name"] for x in info["slots"]], ["saves"])                  # la carpeta elegida, con su nombre
        self.assertTrue(info["backupDir"].endswith("/_Partidas/Mi-Port"))               # carpeta por defecto: por juego

    def test_configuracion_rechaza_rutas_fuera_del_home(self):
        for bad in ("/etc", "/root/.ssh", str(self.home / "../fuera"), "/"):
            c, _d = self.call("/saves/config?id=mio", "POST", {"dirs": [bad]})
            self.assertEqual(c, 403, bad)
        self.assertEqual(self.call("/saves/config?id=mio", "POST", {"dirs": [str(self.saves_dir)], "backup_dir": "/etc"})[0], 403)
        self.assertEqual(self.call("/saves/config?id=mio", "POST", {"glob": "/etc/*"})[0], 403)

    def test_configuracion_con_cuerpo_invalido(self):
        self.assertEqual(self.call("/saves/config?id=mio", "POST", {"dirs": "no-es-lista"})[0], 400)
        self.assertEqual(self.call("/saves/config?id=mio", "POST", {"dirs": [1, 2]})[0], 400)
        self.assertEqual(self.call("/saves/config?id=nada", "POST", {"dirs": []})[0], 404)

    def test_la_configuracion_va_por_juego(self):
        self.config("mio")
        self.assertFalse(self.call("/saves?id=otro")[1]["configured"])

    def test_la_configuracion_sobrevive_a_regenerar_la_biblioteca(self):
        self.config()
        self.store.set_games([{"id": "mio", "name": "Mi Port", "ports": [{"id": "p", "name": "Port", "launch": ["x"], "check": str(self.tmp)}]}])
        self.assertTrue(self.call("/saves?id=mio")[1]["configured"])                    # no depende de lo que traiga la biblioteca

    def test_la_configuracion_se_guarda_en_disco(self):
        self.config()
        self.assertIn("mio", Store(self.tmp / "cfg").state["saves"])

    # --- respaldar y restaurar
    def test_respaldo_y_restauracion_completos(self):
        self.config()
        c, r = self.call("/saves/backup?id=mio", "POST")
        self.assertEqual(c, 200)
        (self.saves_dir / "perfil/slot0.sav").write_text("CORROMPIDA")
        info = self.call("/saves?id=mio")[1]
        self.assertEqual([b["name"] for b in info["backups"]], [r["file"]])
        self.assertTrue(info["backups"][0]["restorable"])
        self.assertGreater(info["lastBackup"], 0)
        c, out = self.call("/saves/restore?id=mio&file=" + r["file"], "POST")
        self.assertEqual((c, out["restored"]), (200, 1))
        self.assertEqual((self.saves_dir / "perfil/slot0.sav").read_text(), "PARTIDA-1")
        self.assertTrue(out["safety"])

    def test_respaldar_sin_partidas(self):
        self.assertEqual(self.call("/saves/backup?id=mio", "POST")[0], 409)

    def test_restaurar_solo_acepta_nombres_de_respaldo(self):
        self.config()
        self.call("/saves/backup?id=mio", "POST")
        for bad in ("../../etc/passwd", "/etc/passwd", ".oculto.tar.gz", "x.zip", "a/b.tar.gz", ""):
            self.assertEqual(self.call("/saves/restore?id=mio&file=" + bad, "POST")[0], 400, bad)
        self.assertEqual(self.call("/saves/restore?id=mio&file=no-existe.tar.gz", "POST")[0], 404)

    def test_no_se_restaura_el_respaldo_de_otro_juego(self):
        self.config("mio")
        r = self.call("/saves/backup?id=mio", "POST")[1]
        self.config("otro")                                                             # «otro» tiene su propia carpeta de respaldos
        self.assertEqual(self.call("/saves/restore?id=otro&file=" + r["file"], "POST")[0], 404)

    def test_acciones_solo_por_post_y_con_token(self):
        self.config()
        self.assertEqual(self.call("/saves/backup?id=mio")[0], 405)
        self.assertEqual(self.call("/saves/backup?id=mio", "POST", token=False)[0], 401)
        self.assertEqual(self.call("/saves/config?id=mio", "POST", {"dirs": []}, token=False)[0], 401)

    def test_abrir_la_carpeta(self):
        self.assertEqual(self.call("/saves/open?id=mio", "POST")[0], 404)
        self.config()
        self.assertEqual(self.call("/saves/open?id=mio", "POST")[0], 200)
        self.assertEqual(len(self.opened), 1)
        self.assertEqual(self.opened[0], str(self.saves_dir))


if __name__ == "__main__":
    unittest.main()


class ApiActividadCarpeta(ApiPartidas):
    """Reutiliza el montaje de ApiPartidas (juegos «mio» y «otro» con puertos en self.tmp)."""

    def test_activity_lists_newest_first_and_only_that_game(self):
        self.store.state["history"] = [
            {"id": "mio", "name": "Mi Port", "start": 100, "end": 200, "secs": 100},
            {"id": "otro", "name": "Otro", "start": 150, "end": 250, "secs": 100},
            {"id": "mio", "name": "Mi Port", "start": 300, "end": 460, "secs": 160}]
        self.store.state["sessions"] = {"mio": {"total_secs": 260, "count": 2, "last_secs": 160}}
        code, d = self.call("/game/activity?id=mio")
        self.assertEqual(code, 200)
        self.assertEqual([s["secs"] for s in d["sessions"]], [160, 100])
        self.assertEqual((d["plays"], d["lastSecs"]), (2, 160))
        self.assertEqual(self.call("/game/activity?id=nope")[0], 404)
        self.assertEqual(self.call("/game/activity?id=mio", token=False)[0], 401)

    def test_library_reports_existing_folder_only(self):
        rows = {g["id"]: g for g in self.call("/library")[1]["games"]}
        self.assertEqual(rows["mio"]["folder"], str(self.tmp.resolve()))      # el check del puerto es una carpeta real
        self.store.set_games([{"id": "x", "name": "X", "ports": [{"id": "p", "name": "P", "launch": ["x"], "check": str(self.tmp / "no-existe/exe")}]}])
        self.api.store.revision += 1
        self.assertEqual(self.call("/library")[1]["games"], [])             # sin instalar no aparece

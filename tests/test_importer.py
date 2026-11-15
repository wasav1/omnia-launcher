import json
import shutil
import tempfile
import unittest
import urllib.error
import urllib.request
from pathlib import Path

from omnia import importer, security
from omnia.api import Api
from omnia.store import Store


def port(pid, exe, **kw):
    return {"id": pid, "name": pid.title(), "launch": [exe] if exe else [], "check": exe, **kw}


class Plan(unittest.TestCase):
    def setUp(self):
        self.tmp = Path(tempfile.mkdtemp())
        self.addCleanup(shutil.rmtree, self.tmp, True)
        self.home = str(self.tmp / "home")
        self.exists = lambda p: p.startswith(self.home) and "falta" not in p
        self.legacy = {"games": [
            {"id": "ocarina", "name": "Ocarina", "platform": "sw2", "art": {"sgdb": "Zelda OoT"}, "ports": [
                port("longshot", "/var/home/wsaenz/Juegos/Longshot/longshot", cwd="/var/home/wsaenz/Juegos/Longshot",
                     saves={"glob": "~/.local/share/longshot/save/*/slot_*"}, backup_dir="/var/home/wsaenz/Juegos/Partidas/L"),
                port("nx2navi", "/var/home/wsaenz/Juegos/NX/nx2navi")]},
            {"id": "n64-mk", "name": "Mario Kart 64", "platform": "n64", "ports": [
                {"id": "mk-g64", "name": "Gopher64", "launch": ["flatpak", "run", "io.github.gopher64.gopher64", "--fullscreen", "/var/home/wsaenz/Juegos/N64/mk.z64"],
                 "check": "/var/home/wsaenz/Juegos/N64/mk.z64", "saves": {"files": ["/var/home/wsaenz/.var/app/io.github.gopher64.gopher64/data/gopher64/saves/*-AAA.*"]}}]},
            {"id": "majora", "name": "Majora", "platform": "n64", "ports": [port("g64", "/home/wsaenz/Juegos/N64/mj.z64"), {"id": "recomp", "name": "Recomp"}]},
            {"id": "roto", "name": "Sin archivo", "platform": "pc", "ports": [port("x", "/var/home/wsaenz/Juegos/falta/x")]},
            {"id": "pc-steam-1", "name": "Un Steam", "auto": "pc", "src": "Steam", "ports": [port("s", "/x")]},
            {"id": "pc-heroic-a", "name": "Un Heroic", "auto": "pc", "src": "Heroic", "ports": [port("h", "/x")]},
            {"id": "pc-hydra-a", "name": "Un Hydra", "auto": "pc", "src": "Hydra", "ports": [port("y", "/x")]},
            {"id": "gfn-x", "name": "Nube", "src": "GeForce NOW", "ports": [port("g", "/x")]},
        ]}

    def plan(self, current=(), g64=False):
        return importer.plan(self.legacy, list(current), new_home=self.home, user="wsaenz", exists=self.exists, gopher64=g64)

    def by(self, p):
        return {i["name"]: i for i in p["items"]}

    def test_cada_grupo_con_su_motivo(self):
        b = self.by(self.plan())
        self.assertEqual(b["Mario Kart 64"]["status"], "new")
        self.assertIn("Steam sola", b["Un Steam"]["reason"])
        self.assertIn("Heroic", b["Un Heroic"]["reason"])
        self.assertIn("Hydra", b["Un Hydra"]["reason"])
        self.assertIn("GeForce NOW", b["Nube"]["reason"])
        self.assertIn("no tiene lanzador", b["Majora · Recomp"]["reason"])
        self.assertTrue(b["Sin archivo · X"]["reason"].startswith("ya no existe") if "Sin archivo · X" in b else b["Sin archivo"]["reason"].startswith("ya no existe"))

    def test_un_juego_con_varios_ports_se_separa(self):
        b = self.by(self.plan())
        self.assertEqual({k for k in b if k.startswith("Ocarina")}, {"Ocarina · Longshot", "Ocarina · Nx2Navi"})
        self.assertEqual(b["Ocarina · Longshot"]["id"], "manual-ocarina-longshot")
        self.assertEqual(b["Majora"]["id"], "manual-majora")                           # un solo port importable: sin sufijo

    def test_rutas_convertidas_y_partidas_conservadas(self):
        e = self.by(self.plan())["Ocarina · Longshot"]["entry"]
        p = e["ports"][0]
        self.assertEqual(p["launch"], [self.home + "/Juegos/Longshot/longshot"])
        self.assertEqual(p["cwd"], self.home + "/Juegos/Longshot")
        self.assertEqual(p["saves"]["glob"], self.home + "/.local/share/longshot/save/*/slot_*")       # «~» → el home actual
        self.assertEqual(p["backup_dir"], self.home + "/Juegos/Partidas/L")                            # la carpeta de respaldos, como estaba
        self.assertNotIn("auto", e)
        self.assertEqual(e["art"], {"slug": "manual-ocarina-longshot", "sgdb": "Zelda OoT"})
        self.assertEqual(e["src"], "Nintendo Switch 2")

    def test_argumentos_con_ruta_antigua_en_medio(self):
        mp = importer.make_mapper("/home/nuevo", "wsaenz")
        self.assertEqual(mp(["env", "WINEPREFIX=/var/home/wsaenz/P", "/home/wsaenz/x", "/otro/home/wsaenz/y", "/var/home/wsaenzX/z"]),
                         ["env", "WINEPREFIX=/home/nuevo/P", "/home/nuevo/x", "/otro/home/wsaenz/y", "/var/home/wsaenzX/z"])
        self.assertEqual(mp("~/a"), "/home/nuevo/a")

    def test_aviso_si_falta_gopher64(self):
        self.assertTrue(any("no está instalado" in w for w in self.plan(g64=False)["warnings"]))

    def test_con_gopher64_nativo_se_adapta_el_comando_y_las_partidas(self):
        nativo = {"argv": ["gopher64"], "saves": self.home + "/.local/share/gopher64/saves"}
        p = self.plan(g64=nativo)
        e = self.by(p)["Mario Kart 64"]["entry"]["ports"][0]
        self.assertEqual(e["launch"], ["gopher64", "--fullscreen", self.home + "/Juegos/N64/mk.z64"])
        self.assertEqual(e["saves"]["files"], [self.home + "/.local/share/gopher64/saves/*-AAA.*"])     # la carpeta nativa, no la del Flatpak
        self.assertTrue(any("nativo" in w for w in p["warnings"]))
        self.assertFalse(any("no está instalado" in w for w in p["warnings"]))

    def test_con_gopher64_flatpak_no_se_toca_nada(self):
        flat = {"argv": ["flatpak", "run", "io.github.gopher64.gopher64"], "saves": self.home + "/.var/app/io.github.gopher64.gopher64/data/gopher64/saves"}
        e = self.by(self.plan(g64=flat))["Mario Kart 64"]["entry"]["ports"][0]
        self.assertEqual(e["launch"][:3], ["flatpak", "run", "io.github.gopher64.gopher64"])
        self.assertIn(".var/app/io.github.gopher64.gopher64/data/gopher64/saves", e["saves"]["files"][0])

    def test_lo_que_no_es_gopher64_no_se_adapta(self):
        nativo = {"argv": ["gopher64"], "saves": "/x"}
        e = self.by(self.plan(g64=nativo))["Ocarina · Longshot"]["entry"]["ports"][0]
        self.assertEqual(e["launch"], [self.home + "/Juegos/Longshot/longshot"])

    def test_lo_ya_importado_se_marca_y_no_se_repite(self):
        p = self.plan(current=[{"id": "manual-n64-mk"}])
        self.assertEqual(self.by(p)["Mario Kart 64"]["status"], "existing")
        self.assertEqual(p["summary"]["existing"], 1)

    def test_el_orden_pone_lo_nuevo_primero(self):
        statuses = [i["status"] for i in self.plan()["items"]]
        self.assertEqual(statuses, sorted(statuses, key=["new", "existing", "skip"].index))

    def test_find_y_load(self):
        self.assertEqual(importer.find_legacy("wsaenz", exists=lambda p: p.startswith("/mnt/bazzite/home/wsaenz")),
                         [{"path": "/mnt/bazzite/home/wsaenz/.config/estanteria/library.json", "label": "Disco de Bazzite"}])
        f = self.tmp / "library.json"
        f.write_text(json.dumps(self.legacy))
        self.assertEqual(len(importer.load(f)["games"]), 8)
        for nombre, contenido in (("otra.json", "{}"), ("library.json", "no es json")):
            g = self.tmp / "x" / nombre
            g.parent.mkdir(exist_ok=True)
            g.write_text(contenido)
            with self.assertRaises(importer.ImportError_):
                importer.load(g)
        (self.tmp / "y").mkdir()
        (self.tmp / "y/library.json").write_text('{"games": "no es lista"}')
        with self.assertRaises(importer.ImportError_):
            importer.load(self.tmp / "y/library.json")


class Aplicar(unittest.TestCase):
    def setUp(self):
        self.tmp = Path(tempfile.mkdtemp())
        self.addCleanup(shutil.rmtree, self.tmp, True)
        self.store = Store(self.tmp / "cfg")
        self.store.set_games([{"id": "steam-1", "name": "S", "auto": "steam", "ports": []}])
        exe = self.tmp / "juego"
        exe.write_text("x")
        self.legacy = {"games": [{"id": "a", "name": "A", "platform": "pc", "ports": [{"id": "p", "name": "P", "launch": [str(exe)], "check": str(exe)}]},
                                 {"id": "b", "name": "B", "platform": "pc", "ports": [{"id": "p", "name": "P", "launch": [str(exe)], "check": str(exe)}]}]}

    def plan(self):
        return importer.plan(self.legacy, self.store.games(), new_home=str(self.tmp), user="nadie", gopher64=False)

    def test_aplica_solo_lo_nuevo_y_respeta_lo_demas(self):
        self.assertEqual(sorted(importer.apply(self.store, self.plan())), ["manual-a", "manual-b"])
        self.assertEqual(sorted(g["id"] for g in self.store.games()), ["manual-a", "manual-b", "steam-1"])    # lo detectado, intacto

    def test_es_idempotente(self):
        importer.apply(self.store, self.plan())
        self.assertEqual(importer.apply(self.store, self.plan()), [])
        self.assertEqual(len(self.store.games()), 3)

    def test_solo_los_ids_elegidos(self):
        self.assertEqual(importer.apply(self.store, self.plan(), ids=["manual-b"]), ["manual-b"])
        self.assertEqual(sorted(g["id"] for g in self.store.games()), ["manual-b", "steam-1"])

    def test_un_id_inventado_no_inyecta_nada(self):
        self.assertEqual(importer.apply(self.store, self.plan(), ids=["manual-no-existe", "steam-1"]), [])


class ApiImportar(unittest.TestCase):
    def setUp(self):
        self.tmp = Path(tempfile.mkdtemp())
        self.addCleanup(shutil.rmtree, self.tmp, True)
        exe = self.tmp / "juego"
        exe.write_text("x")
        self.lib = self.tmp / "viejo" / "library.json"
        self.lib.parent.mkdir()
        self.lib.write_text(json.dumps({"games": [{"id": "a", "name": "A", "platform": "pc",
                            "ports": [{"id": "p", "name": "P", "launch": [str(exe)], "check": str(exe)}]}]}))
        self.store = Store(self.tmp / "cfg")
        self.token = security.new_token(self.tmp / "run")
        self.api = Api(self.store, self.token, [], scan_fn=lambda: [], fs_roots=[self.tmp])
        self.api.serve()
        self.addCleanup(self.api.stop)

    def call(self, path, method="GET", body=None, token=True):
        data = json.dumps(body).encode() if body is not None else (b"{}" if method == "POST" else None)
        r = urllib.request.Request("http://127.0.0.1:%d%s" % (self.api.port, path), method=method, data=data)
        if token:
            r.add_header("Authorization", "Bearer " + self.token)
        try:
            with urllib.request.urlopen(r, timeout=5) as x:
                return x.status, json.load(x)
        except urllib.error.HTTPError as e:
            return e.code, json.load(e)

    def test_la_vista_previa_no_escribe_nada(self):
        c, d = self.call("/import/preview?path=" + str(self.lib))
        self.assertEqual((c, d["summary"]["new"]), (200, 1))
        self.assertNotIn("entry", d["items"][0])                       # no se exponen las entradas completas
        self.assertEqual(self.store.games(), [])

    def test_aplicar_y_repetir(self):
        c, d = self.call("/import/apply?path=" + str(self.lib), "POST")
        self.assertEqual((c, d["added"]), (200, ["manual-a"]))
        self.assertEqual(self.call("/import/apply?path=" + str(self.lib), "POST")[1]["count"], 0)
        self.assertEqual([g["id"] for g in self.store.games()], ["manual-a"])

    def test_aplicar_con_ids(self):
        self.assertEqual(self.call("/import/apply?path=" + str(self.lib), "POST", {"ids": ["otro"]})[1]["added"], [])
        self.assertEqual(self.call("/import/apply?path=" + str(self.lib), "POST", {"ids": "malo"})[0], 400)

    def test_rutas_fuera_de_las_permitidas_y_otros_archivos(self):
        self.assertEqual(self.call("/import/preview?path=/etc/passwd")[0], 403)
        self.assertEqual(self.call("/import/preview?path=")[0], 403)
        otro = self.tmp / "config.json"
        otro.write_text("{}")
        self.assertEqual(self.call("/import/preview?path=" + str(otro))[0], 400)
        self.assertEqual(self.call("/import/apply?path=/etc/passwd", "POST")[0], 403)

    def test_token_y_metodo(self):
        self.assertEqual(self.call("/import/preview?path=" + str(self.lib), token=False)[0], 401)
        self.assertEqual(self.call("/import/apply?path=" + str(self.lib))[0], 405)

    def test_find(self):
        self.assertIsInstance(self.call("/import/find")[1]["candidates"], list)


if __name__ == "__main__":
    unittest.main()

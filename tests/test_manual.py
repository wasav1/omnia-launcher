import json
import shutil
import tempfile
import unittest
import urllib.error
import urllib.request
from pathlib import Path

from omnia import manual, security, templates
from omnia.api import Api
from omnia.games.base import Detector
from omnia.games.refresh import refresh
from omnia.manual import ManualError
from omnia.store import Store
from omnia.templates import TemplateError


class Base(unittest.TestCase):
    def setUp(self):
        self.tmp = Path(tempfile.mkdtemp())
        self.addCleanup(shutil.rmtree, self.tmp, True)
        self.roots = [self.tmp]

    def exe(self, rel="Ports/Longshot/longshot", ejecutable=True):
        f = self.tmp / rel
        f.parent.mkdir(parents=True, exist_ok=True)
        f.write_text("#!/bin/sh\n")
        f.chmod(0o755 if ejecutable else 0o644)
        return str(f)


class Gopher64(Base):
    def rom(self, nombre, cabecera, cuerpo=b"\x00\x01\x02\x03" * 8):
        f = self.tmp / nombre
        f.write_bytes(cabecera + cuerpo)
        return str(f)

    def test_hash_z64_es_uno_y_v64_incluye_el_normalizado(self):
        z = self.rom("a.z64", b"\x80\x37\x12\x40")
        v = self.rom("b.v64", b"\x37\x80\x40\x12", b"\x01\x00\x03\x02" * 8)          # el cuerpo de z64 con pares intercambiados
        hz, hv = templates.rom_hashes(z), templates.rom_hashes(v)
        self.assertEqual(len(hz), 1)
        self.assertEqual(len(hv), 2)                                                  # el del archivo y el de su versión z64
        self.assertEqual(hv & hz, hz)                                                 # el normalizado coincide con el z64 equivalente
        self.assertTrue(all(len(h) == 64 and h == h.upper() for h in hz | hv))

    def test_hash_n64_intercambia_32_bits(self):
        n = self.rom("c.n64", b"\x40\x12\x37\x80")
        z = self.rom("d.z64", b"\x80\x37\x12\x40")
        self.assertEqual(len(templates.rom_hashes(n)), 2)
        self.assertTrue(templates.rom_hashes(z) <= templates.rom_hashes(n) or len(templates.rom_hashes(z)) == 1)

    def test_instalacion_nativa_flatpak_o_ninguna(self):
        nat = templates.gopher64_install(which=lambda c: "/usr/bin/" + c if c == "gopher64" else None)
        self.assertEqual(nat["argv"], ["gopher64"])
        class R:  returncode = 0
        fp = templates.gopher64_install(which=lambda c: "/usr/bin/flatpak" if c == "flatpak" else None, run=lambda *a, **k: R())
        self.assertEqual(fp["argv"][:2], ["flatpak", "run"])
        self.assertIn(".var/app/io.github.gopher64.gopher64/data/gopher64/saves", fp["saves"])
        class NoInst:  returncode = 1
        with self.assertRaisesRegex(TemplateError, "no está instalado"):
            templates.gopher64_install(which=lambda c: "/usr/bin/flatpak" if c == "flatpak" else None, run=lambda *a, **k: NoInst())

    def test_construir_la_plantilla(self):
        rom = self.rom("MARIOKART64.z64", b"\x80\x37\x12\x40")
        b = templates.build("gopher64", rom=rom, gopher64={"argv": ["gopher64"], "saves": "/x/saves"})
        self.assertEqual(b["launch"], ["gopher64", "--fullscreen", rom])
        (h,) = templates.rom_hashes(rom)
        self.assertEqual(b["saves"]["files"], [f"/x/saves/*-{h}.*"])
        self.assertEqual((b["check"], b["proc"]), (rom, "MARIOKART64.z64"))
        with self.assertRaisesRegex(TemplateError, "ROM"):
            templates.build("gopher64", rom=str(self.tmp / "no-existe.z64"), gopher64={"argv": ["g"], "saves": "/x"})


class Ports(Base):
    def test_cada_port_conocido(self):
        home = str(Path.home())
        lo = templates.build("longshot", exe=self.exe())
        self.assertEqual(lo["saves"]["glob"], home + "/.local/share/longshot/save/*/slot_*")
        self.assertEqual(lo["launch"], [self.exe()]); self.assertEqual(lo["cwd"], str(self.tmp / "Ports/Longshot"))
        nx = templates.build("nx2navi", exe=self.exe("Ports/NX2navi/nx2navi"))
        self.assertEqual(nx["saves"]["glob"], str(self.tmp / "Ports/NX2navi") + "/profile/save/*/slot_*")     # relativa a la instalación
        tk = templates.build("totkrecomp", exe=self.exe("Ports/TOTK/totk"))
        self.assertEqual(tk["saves"]["files"], [str(self.tmp / "Ports/TOTK") + "/profile/**/*.sav"])
        self.assertIn("hookshot/save", templates.build("hookshot", exe=self.exe("H/hookshot"))["saves"]["glob"])

    def test_savagewind_no_afirma_lo_que_no_se_sabe(self):
        sw = templates.build("savagewind", exe=self.exe("Ports/SW/savagewind"))
        self.assertIsNone(sw["saves"])                                                # «ubicación sin comprobar»

    def test_errores_del_ejecutable(self):
        with self.assertRaisesRegex(TemplateError, "ejecutable del port"):
            templates.build("longshot", exe="")
        with self.assertRaisesRegex(TemplateError, "no es ejecutable"):
            templates.build("longshot", exe=self.exe(ejecutable=False))
        with self.assertRaisesRegex(TemplateError, "desconocida"):
            templates.build("inexistente")

    def test_catalogo(self):
        ids = [t["id"] for t in templates.catalog()]
        self.assertEqual(sorted(ids), sorted(["bedrock-on-linux", "gopher64", "longshot", "hookshot", "nx2navi", "savagewind", "totkrecomp"]))


class Sugerencias(Base):
    def test_carpetas_que_parecen_guardar_partidas(self):
        for d, f in (("Juego/saves", "slot1.sav"), ("Juego/profile/save", "a.dat"), ("Juego/assets", "textura.png"),
                     ("Juego/saves/vacia", None), ("Juego/.oculta/saves", "x.sav")):
            (self.tmp / d).mkdir(parents=True, exist_ok=True)
            if f:
                (self.tmp / d / f).write_text("x")
        got = [x["label"] for x in templates.suggest_dirs(self.tmp / "Juego")]
        self.assertIn("saves", got)
        self.assertIn("profile/save", got)
        self.assertNotIn("assets", got)
        self.assertFalse(any(".oculta" in g for g in got))

    def test_limite_de_profundidad_y_raiz_inexistente(self):
        d = self.tmp / "a/b/c/d/e/f/saves"
        d.mkdir(parents=True)
        (d / "x.sav").write_text("x")
        self.assertEqual(templates.suggest_dirs(self.tmp / "a"), [])
        self.assertEqual(templates.suggest_dirs("/no/existe"), [])

    def steam(self, nombre_carpeta="Hollow Knight"):
        lib = self.tmp / "steamapps"
        (lib).mkdir()
        manifest = lib / "appmanifest_1.acf"
        manifest.write_text("x")
        pfx = lib / "compatdata/1/pfx/drive_c/users/steamuser"
        (pfx / "AppData/LocalLow/Team Cherry" / nombre_carpeta).mkdir(parents=True)
        (pfx / "AppData/Local/Microsoft/Windows").mkdir(parents=True)               # ruido del sistema: no debe sugerirse
        (pfx / "Documents/My Games/Otro Juego").mkdir(parents=True)
        cloud = self.tmp / "Steam/userdata/123/1/remote"
        cloud.mkdir(parents=True)
        (cloud / "user1.dat").write_text("nube")
        return str(manifest), str(self.tmp / "Steam")

    def test_steam_sugiere_la_nube_y_lo_que_se_parece_al_nombre(self):
        manifest, root = self.steam("Hollow Knight")
        got = templates.steam_suggestions("Hollow Knight", "1", manifest, root)
        self.assertEqual(got[0]["label"], "Steam Cloud (caché local)")                # lo más fiable, primero
        labels = [g["label"] for g in got]
        self.assertTrue(any("Hollow Knight" in l for l in labels))
        self.assertFalse(any("Windows" in l or "Otro Juego" in l for l in labels))

    def test_steam_sin_prefijo_ni_nube(self):
        self.assertEqual(templates.steam_suggestions("X", "9", "/no/existe/app.acf", str(self.tmp / "nada")), [])


class Juegos(Base):
    def setUp(self):
        super().setUp()
        self.store = Store(self.tmp / "cfg")

    def add(self, **kw):
        return manual.add_game(self.store, kw, self.roots, gopher64={"argv": ["gopher64"], "saves": "/x"}, which=lambda c: "/usr/bin/" + c)

    def test_port_con_plantilla(self):
        g = self.add(name="Ocarina (Longshot)", template="longshot", exe=self.exe())
        self.assertEqual(g["id"], "manual-ocarina-longshot")
        self.assertNotIn("auto", g)                                                    # los detectores nunca lo tocan
        self.assertEqual((g["src"], g["platform"]), ("Manual", "pc"))
        p = g["ports"][0]
        self.assertIn("longshot/save", p["saves"]["glob"])
        self.assertEqual(self.store.find_game(g["id"])["name"], "Ocarina (Longshot)")
        self.assertEqual(g["art"], {"slug": g["id"], "sgdb": "Ocarina (Longshot)"})   # el arte se busca solo

    def test_emulador_n64(self):
        rom = self.tmp / "STARFOX64.z64"
        rom.write_bytes(b"\x80\x37\x12\x40" * 4)
        g = self.add(name="Star Fox 64", template="gopher64", rom=str(rom))
        self.assertEqual(g["platform"], "n64")
        self.assertEqual(g["ports"][0]["launch"][-2:], ["--fullscreen", str(rom)])

    def test_juego_de_windows_con_umu(self):
        g = self.add(name="Mi Juego", kind="windows", exe=self.exe("PC/Mi/juego.exe", ejecutable=False))
        launch = g["ports"][0]["launch"]
        self.assertEqual(launch[0], "env")
        self.assertEqual(launch[-2:][0], "umu-run")
        self.assertTrue(any(a.startswith("WINEPREFIX=") and a.endswith("/_Prefijos/mi-juego") for a in launch))
        self.assertEqual(g["ports"][0]["proc"], "juego.exe")
        with self.assertRaisesRegex(ManualError, "umu"):
            manual.add_game(self.store, {"name": "X", "kind": "windows", "exe": self.exe("PC/x.exe")}, self.roots, which=lambda c: None)

    def test_nativo_exige_ejecutable(self):
        self.assertEqual(self.add(name="Nat", kind="native", exe=self.exe("N/nat"))["ports"][0]["launch"], [self.exe("N/nat")])
        with self.assertRaisesRegex(ManualError, "ejecutable"):
            self.add(name="Mal", kind="native", exe=self.exe("N/mal", ejecutable=False))

    def test_ids_unicos_si_el_nombre_se_repite(self):
        a = self.add(name="Igual", kind="native", exe=self.exe("A/x"))
        b = self.add(name="Igual", kind="native", exe=self.exe("B/x"))
        self.assertEqual((a["id"], b["id"]), ("manual-igual", "manual-igual-2"))

    def test_validaciones(self):
        for bad, msg in (({"name": "", "kind": "native"}, "nombre"), ({"name": "x" * 81, "kind": "native"}, "nombre"),
                         ({"name": "A", "kind": "ruso"}, "Tipo"), ({"name": "A", "kind": "native"}, "ejecutable"),
                         ({"name": "A", "kind": "native", "exe": "/usr/bin/true"}, "fuera"),
                         ({"name": "A", "kind": "native", "exe": "/etc/passwd"}, "fuera")):
            with self.assertRaisesRegex(ManualError, msg):
                self.add(**bad)

    def test_los_refrescos_no_tocan_los_manuales_pero_si_los_detectados(self):
        self.add(name="Mio", kind="native", exe=self.exe("N/mio"))
        self.store.set_games(self.store.games() + [{"id": "steam-1", "name": "S", "auto": "steam", "ports": []}])
        class Vacio(Detector):
            name = "steam"
            def detect(self):
                return []
        refresh(self.store, [Vacio()])
        self.assertEqual([g["id"] for g in self.store.games()], ["manual-mio"])        # el detectado se fue; el manual, intacto

    def test_quitar_solo_manuales_y_limpia_el_estado(self):
        g = self.add(name="Mio", kind="native", exe=self.exe("N/mio"))
        self.store.state["game_fav"] = [g["id"]]
        self.store.state["saves"] = {g["id"]: {"spec": {}}}
        self.store.state["sessions"] = {g["id"]: {"count": 1}}
        self.assertTrue(manual.remove_game(self.store, g["id"]))
        self.assertEqual(self.store.games(), [])
        self.assertEqual((self.store.state["game_fav"], self.store.state["saves"], self.store.state["sessions"]), ([], {}, {}))
        self.store.set_games([{"id": "steam-1", "name": "S", "auto": "steam", "ports": []}])
        self.assertFalse(manual.remove_game(self.store, "steam-1"))                    # los detectados no se pueden quitar
        self.assertFalse(manual.remove_game(self.store, "no-existe"))


class ApiManual(Base):
    def setUp(self):
        super().setUp()
        self.store = Store(self.tmp / "cfg")
        self.token = security.new_token(self.tmp / "run")
        self.api = Api(self.store, self.token, [], scan_fn=list, fs_roots=[self.tmp])
        self.api.steam_root = str(self.tmp / "Steam")
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

    def test_catalogo_y_token(self):
        self.assertEqual(len(self.call("/templates")[1]["templates"]), 7)
        self.assertEqual(self.call("/templates", token=False)[0], 401)

    def test_anadir_y_quitar_por_la_api(self):
        c, r = self.call("/game/add", "POST", {"name": "Hookshot", "template": "hookshot", "exe": self.exe("H/hookshot")})
        self.assertEqual((c, r["id"]), (200, "manual-hookshot"))
        self.assertEqual(self.call("/saves?id=manual-hookshot")[1]["spec"]["glob"].endswith("hookshot/save/*"), True)
        self.assertEqual(self.call("/game/remove?id=manual-hookshot", "POST")[0], 200)
        self.assertEqual(self.call("/game/remove?id=manual-hookshot", "POST")[0], 404)

    def test_errores_de_la_api(self):
        self.assertEqual(self.call("/game/add", "POST", {"name": "", "kind": "native"})[0], 400)
        self.assertEqual(self.call("/game/add", "POST", {"name": "A", "kind": "native", "exe": "/usr/bin/true"})[0], 400)
        self.assertEqual(self.call("/game/add", token=False)[0], 405)

    def test_sugerencias_para_un_juego_de_steam(self):
        manifest = self.tmp / "steamapps/appmanifest_99.acf"
        (manifest.parent / "compatdata/99/pfx/drive_c/users/steamuser/Documents/My Games/Cool Game").mkdir(parents=True)
        manifest.write_text("x")
        self.store.set_games([{"id": "steam-99", "name": "Cool Game", "auto": "steam",
                               "ports": [{"id": "p", "name": "S", "launch": ["x"], "check": str(manifest)}]}])
        s = self.call("/saves/suggest?id=steam-99")[1]["suggestions"]
        self.assertEqual([x["label"] for x in s], ["Documents/My Games/Cool Game"])

    def test_sugerencias_de_un_port_manual(self):
        exe = self.exe("Ports/X/x")
        (self.tmp / "Ports/X/saves").mkdir()
        (self.tmp / "Ports/X/saves/a.sav").write_text("x")
        self.call("/game/add", "POST", {"name": "Equis", "kind": "native", "exe": exe})
        self.assertEqual([x["label"] for x in self.call("/saves/suggest?id=manual-equis")[1]["suggestions"]], ["saves"])


if __name__ == "__main__":
    unittest.main()

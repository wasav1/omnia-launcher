import io
import json
import os
import shutil
import tarfile
import tempfile
import unittest
from pathlib import Path

from omnia import fsbrowse, saves
from omnia.saves import SaveError


class Base(unittest.TestCase):
    def setUp(self):
        self.tmp = Path(tempfile.mkdtemp())
        self.addCleanup(shutil.rmtree, self.tmp, True)
        self.data, self.bk = self.tmp / "datos", self.tmp / "respaldos"

    def slot(self, i, contenido="partida"):
        d = self.data / "save/cuenta1" / ("slot_%02d" % i)
        d.mkdir(parents=True, exist_ok=True)
        (d / "save.dat").write_text("%s %d" % (contenido, i))
        return d

    @property
    def spec(self):
        return {"glob": str(self.data / "save/*/slot_*"), "name": "Ranura {n}"}


class Localizar(Base):
    def test_ranuras_por_glob(self):
        self.slot(0); self.slot(3)
        (self.data / "save/cuenta1/otro.txt").write_text("no es una ranura")
        self.assertEqual([Path(p).name for p in saves.matches(self.spec)], ["slot_00", "slot_03"])
        self.assertEqual([s["name"] for s in saves.slots(self.spec)], ["Ranura 1", "Ranura 4"])

    def test_archivos_y_carpetas_y_sin_repetidos(self):
        f = self.data / "saves"
        f.mkdir(parents=True)
        (f / "juego-AAA.eep").write_text("x"); (f / "juego-BBB.eep").write_text("y")
        spec = {"files": [str(f / "*-AAA.*"), str(f / "*-AAA.eep")], "dirs": [str(f), str(f)]}
        got = saves.matches(spec)
        self.assertEqual(sum(1 for p in got if p.endswith("AAA.eep")), 1)                 # el mismo archivo por dos patrones: una vez
        self.assertIn(str(f), got)
        self.assertEqual([s["name"] for s in saves.slots({"files": [str(f / "*-AAA.*")]})], ["Partida (EEPROM)"])

    def test_raices_de_escritura(self):
        r = saves.roots({"glob": str(self.data / "save/*/slot_*"), "files": [str(self.data / "x/*.sav")], "dirs": [str(self.tmp / "d")]})
        self.assertEqual(sorted(r), sorted(os.path.realpath(p) for p in (self.data / "save", self.data / "x", self.tmp / "d")))
        self.assertEqual(saves.roots({"glob": "/*"}), [])                                  # nunca la raíz del sistema

    def test_sin_especificacion(self):
        self.assertEqual(saves.matches(None), [])
        self.assertEqual(saves.slots({}), [])


class Respaldar(Base):
    def test_respaldo_con_manifiesto(self):
        self.slot(0); self.slot(1)
        out = saves.backup(self.spec, self.bk, "Longshot", {"game": "ocarina"})
        self.assertRegex(out.name, r"^Longshot-\d{8}-\d{6}\.tar\.gz$")
        man = saves.read_manifest(out)
        self.assertEqual(len(man["entries"]), 2)
        self.assertEqual(man["game"], "ocarina")
        with tarfile.open(out) as tf:
            self.assertIn("data/0/slot_00/save.dat", tf.getnames())

    def test_dos_respaldos_en_el_mismo_segundo_no_se_pisan(self):
        self.slot(0)
        a, b = saves.backup(self.spec, self.bk, "J"), saves.backup(self.spec, self.bk, "J")
        self.assertNotEqual(a, b)
        self.assertTrue(a.exists() and b.exists())

    def test_sin_partidas_falla_claro(self):
        with self.assertRaisesRegex(SaveError, "No hay partidas"):
            saves.backup(self.spec, self.bk, "J")
        self.assertFalse(self.bk.exists() and list(self.bk.glob("*.part")))

    def test_demasiado_grande_se_rechaza(self):
        self.slot(0)
        with self.assertRaisesRegex(SaveError, "demasiado"):
            saves.backup(self.spec, self.bk, "J", max_bytes=3)

    def test_no_respalda_enlaces_simbolicos(self):
        d = self.slot(0)
        os.symlink("/etc/passwd", d / "enlace")
        out = saves.backup(self.spec, self.bk, "J")
        with tarfile.open(out) as tf:
            self.assertFalse(any("enlace" in n for n in tf.getnames()))

    def test_lista_con_restaurable_y_antiguos(self):
        self.slot(0)
        saves.backup(self.spec, self.bk, "Longshot")
        legacy = self.bk / "longshot-20200101-000000.tar.gz"                                # formato del prototipo: sin manifiesto
        with tarfile.open(legacy, "w:gz") as tf:
            ti = tarfile.TarInfo("x/y.dat"); ti.size = 1; tf.addfile(ti, io.BytesIO(b"x"))
        got = {b["name"]: b["restorable"] for b in saves.list_backups(self.bk)}
        self.assertEqual(sorted(got.values()), [False, True])
        self.assertFalse(got[legacy.name])
        self.assertEqual(len(saves.list_backups(self.bk, "Longshot")), 2)                   # el prefijo coincide con ambos
        self.assertEqual(saves.list_backups("/no/existe"), [])


class Restaurar(Base):
    def test_ida_y_vuelta(self):
        d0 = self.slot(0, "original")
        out = saves.backup(self.spec, self.bk, "J")
        (d0 / "save.dat").write_text("modificada despues")
        shutil.rmtree(self.data / "save/cuenta1/slot_01", ignore_errors=True)
        r = saves.restore(out, self.spec, self.bk, "J")
        self.assertEqual((d0 / "save.dat").read_text(), "original 0")                       # volvió el contenido del respaldo
        self.assertEqual(r["restored"], 1)
        self.assertTrue(r["safety"].startswith("J-antes-de-restaurar"))                     # lo que había se guardó antes
        safety = self.bk / r["safety"]
        with tarfile.open(safety) as tf:
            self.assertTrue(any(n.endswith("save.dat") for n in tf.getnames()))

    def test_restaurar_sin_nada_previo_no_hace_respaldo_de_seguridad(self):
        self.slot(0, "orig")
        out = saves.backup(self.spec, self.bk, "J")
        shutil.rmtree(self.data)
        r = saves.restore(out, self.spec, self.bk, "J")
        self.assertEqual(r["safety"], "")
        self.assertEqual((self.data / "save/cuenta1/slot_00/save.dat").read_text(), "orig 0")

    def test_carpeta_completa_elegida_por_el_usuario(self):                                 # el caso del explorador
        carpeta = self.tmp / "MiJuego/Saved"
        (carpeta / "sub").mkdir(parents=True)
        (carpeta / "a.sav").write_text("A"); (carpeta / "sub/b.sav").write_text("B")
        spec = {"dirs": [str(carpeta)]}
        out = saves.backup(spec, self.bk, "MiJuego")
        shutil.rmtree(carpeta)
        saves.restore(out, spec, self.bk, "MiJuego")
        self.assertEqual((carpeta / "a.sav").read_text() + (carpeta / "sub/b.sav").read_text(), "AB")

    def test_archivos_sueltos(self):
        f = self.tmp / "saves"
        f.mkdir()
        (f / "j-AAA.eep").write_text("E")
        spec = {"files": [str(f / "*-AAA.*")]}
        out = saves.backup(spec, self.bk, "G64")
        (f / "j-AAA.eep").write_text("roto")
        saves.restore(out, spec, self.bk, "G64")
        self.assertEqual((f / "j-AAA.eep").read_text(), "E")

    def test_respaldo_antiguo_sin_manifiesto(self):
        legacy = self.bk / "x.tar.gz"
        self.bk.mkdir()
        with tarfile.open(legacy, "w:gz") as tf:
            ti = tarfile.TarInfo("a"); ti.size = 0; tf.addfile(ti, io.BytesIO(b""))
        with self.assertRaisesRegex(SaveError, "antiguo"):
            saves.restore(legacy, self.spec, self.bk, "J")

    def hostil(self, entries, members):
        """Un .tar.gz con el manifiesto y los miembros que se le den (para probar ataques)."""
        self.bk.mkdir(exist_ok=True)
        out = self.bk / "hostil.tar.gz"
        with tarfile.open(out, "w:gz") as tf:
            raw = json.dumps({"version": 1, "entries": entries}).encode()
            ti = tarfile.TarInfo(saves.MANIFEST); ti.size = len(raw); tf.addfile(ti, io.BytesIO(raw))
            for name, data, kw in members:
                ti = tarfile.TarInfo(name); ti.size = len(data)
                for k, v in kw.items():
                    setattr(ti, k, v)
                tf.addfile(ti, io.BytesIO(data))
        return out

    def test_destino_fuera_de_las_carpetas_del_juego(self):
        self.slot(0)
        victima = self.tmp / "fuera/importante.txt"
        victima.parent.mkdir()
        victima.write_text("no tocar")
        out = self.hostil([{"arc": "data/0/x", "orig": str(victima), "kind": "file"}], [("data/0/x", b"pwned", {})])
        with self.assertRaisesRegex(SaveError, "fuera"):
            saves.restore(out, self.spec, self.bk, "J")
        self.assertEqual(victima.read_text(), "no tocar")

    def test_ruta_con_punto_punto(self):
        self.slot(0)
        orig = str(self.data / "save/cuenta1/slot_00/../../../../fuera.txt")
        out = self.hostil([{"arc": "data/0/x", "orig": orig, "kind": "file"}], [("data/0/x", b"pwned", {})])
        with self.assertRaises(SaveError):
            saves.restore(out, self.spec, self.bk, "J")
        self.assertFalse((self.tmp / "fuera.txt").exists())

    def test_miembro_con_tar_slip(self):
        self.slot(0)
        orig = str(self.data / "save/cuenta1/slot_00")
        out = self.hostil([{"arc": "data/0/slot_00", "orig": orig, "kind": "dir"}],
                          [("data/0/slot_00/../../../../../escape.txt", b"pwned", {})])
        with self.assertRaisesRegex(SaveError, "no permitida"):
            saves.restore(out, self.spec, self.bk, "J")                                     # se rechaza el respaldo entero
        self.assertFalse(list(self.tmp.rglob("escape.txt")))
        self.assertEqual((self.data / "save/cuenta1/slot_00/save.dat").read_text(), "partida 0")   # y no se tocó nada

    def test_un_respaldo_manipulado_no_restaura_a_medias(self):
        d = self.slot(0, "original")
        orig = str(d)
        out = self.hostil([{"arc": "data/0/slot_00", "orig": orig, "kind": "dir"}],
                          [("data/0/slot_00/save.dat", b"RESTAURADO", {}),          # válido…
                           ("data/0/slot_00/../../../../x.txt", b"pwned", {})])      # …y uno malicioso después
        with self.assertRaises(SaveError):
            saves.restore(out, self.spec, self.bk, "J")
        self.assertEqual((d / "save.dat").read_text(), "original 0")                  # el válido tampoco se aplicó
        self.assertEqual([p.name for p in self.bk.glob("*antes-de-restaurar*")], [])   # ni se hizo respaldo de seguridad

    def test_enlaces_simbolicos_en_el_respaldo_se_ignoran(self):
        d = self.slot(0)
        orig = str(d)
        out = self.hostil([{"arc": "data/0/slot_00", "orig": orig, "kind": "dir"}],
                          [("data/0/slot_00/enlace", b"", {"type": tarfile.SYMTYPE, "linkname": "/etc/passwd"})])
        saves.restore(out, self.spec, self.bk, "J")
        self.assertFalse(os.path.islink(d / "enlace"))

    def test_sin_carpeta_configurada(self):
        self.slot(0)
        out = saves.backup(self.spec, self.bk, "J")
        with self.assertRaisesRegex(SaveError, "carpeta de partidas"):
            saves.restore(out, {}, self.bk, "J")


class Explorador(Base):
    def setUp(self):
        super().setUp()
        for d in ("Juegos/PC", "Juegos/Nintendo", ".oculta", "Zeta", "alfa"):
            (self.tmp / d).mkdir(parents=True)
        (self.tmp / "alfa/juego.z64").write_text("x"); (self.tmp / "alfa/notas.txt").write_text("y")
        self.roots = [self.tmp]

    def test_lista_carpetas_ordenadas_sin_ocultas(self):
        r = fsbrowse.list_dir(self.tmp, self.roots)
        self.assertEqual([d["name"] for d in r["dirs"]], ["alfa", "Juegos", "Zeta"])        # sin «.oculta», sin distinguir mayúsculas
        self.assertEqual(r["files"], [])
        self.assertIsNone(r["parent"])                                                      # en la raíz permitida no se sube más
        self.assertIn(".oculta", [d["name"] for d in fsbrowse.list_dir(self.tmp, self.roots, hidden=True)["dirs"]])

    def test_archivos_con_filtro_de_extension(self):
        r = fsbrowse.list_dir(self.tmp / "alfa", self.roots, files=True, exts=[".z64", ".n64"])
        self.assertEqual([f["name"] for f in r["files"]], ["juego.z64"])
        self.assertEqual(r["parent"], os.path.realpath(self.tmp))

    def test_fuera_de_las_raices(self):
        for p in ("/etc", "/", str(self.tmp / ".."), "/root"):
            with self.assertRaisesRegex(fsbrowse.FsError, "fuera"):
                fsbrowse.list_dir(p, self.roots)

    def test_un_enlace_no_permite_escapar(self):
        os.symlink("/etc", self.tmp / "atajo")
        with self.assertRaisesRegex(fsbrowse.FsError, "fuera"):
            fsbrowse.list_dir(self.tmp / "atajo", self.roots)

    def test_no_es_carpeta(self):
        with self.assertRaisesRegex(fsbrowse.FsError, "carpeta"):
            fsbrowse.list_dir(self.tmp / "alfa/notas.txt", self.roots)

    def test_limite_de_entradas(self):
        for i in range(12):
            (self.tmp / "muchas").mkdir(exist_ok=True)
            (self.tmp / "muchas" / ("d%02d" % i)).mkdir()
        r = fsbrowse.list_dir(self.tmp / "muchas", self.roots, limit=5)
        self.assertEqual((len(r["dirs"]), r["truncated"]), (5, True))

    def test_atajos(self):
        self.assertEqual([s["name"] for s in fsbrowse.shortcuts([self.tmp])][:1], ["Inicio"])


if __name__ == "__main__":
    unittest.main()

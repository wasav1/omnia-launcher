import json
import shutil
import sqlite3
import tempfile
import unittest
from pathlib import Path

from omnia.games.heroic import HeroicDetector, gog_exe
from omnia.games.lutris import LutrisDetector
from omnia.games.refresh import refresh
from omnia.store import Store


def wjson(path: Path, obj):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(obj))


class Base(unittest.TestCase):
    def setUp(self):
        self.home = Path(tempfile.mkdtemp())
        self.addCleanup(shutil.rmtree, self.home, True)

    def folder(self, name) -> str:
        d = self.home / "juegos" / name
        d.mkdir(parents=True, exist_ok=True)
        return str(d)


class Heroic(Base):
    def setUp(self):
        super().setUp()
        self.cfg = self.home / ".config/heroic"

    def test_epic_gog_amazon(self):
        wjson(self.cfg / "legendaryConfig/legendary/installed.json",
              {"Fortnite": {"app_name": "Fortnite", "title": "Fortnite", "install_path": self.folder("Fortnite"),
                            "executable": "Bin/Fn.exe"}})
        wjson(self.cfg / "gog_store/installed.json", {"installed": [{"appName": "1207", "install_path": self.folder("Witcher")}]})
        wjson(self.cfg / "store_cache/gog_library.json", {"games": [{"app_name": "1207", "title": "The Witcher"}]})
        wjson(self.cfg / "nile_store/installed.json", {"installed": [{"app_name": "amz1", "install_path": self.folder("AmzGame")}]})
        g = {x["id"]: x for x in HeroicDetector(self.home).detect()}
        self.assertEqual(sorted(g), ["heroic-gog-1207", "heroic-legendary-Fortnite", "heroic-nile-amz1"])
        self.assertEqual(g["heroic-gog-1207"]["name"], "The Witcher")          # título desde la caché
        self.assertEqual(g["heroic-nile-amz1"]["name"], "AmzGame")             # sin título: carpeta
        self.assertEqual(g["heroic-legendary-Fortnite"]["ports"][0]["launch"], ["heroic", "heroic://launch/legendary/Fortnite"])
        self.assertEqual(g["heroic-legendary-Fortnite"]["ports"][0]["proc"], "Fn.exe")

    def test_no_instalados_ni_dlc(self):
        wjson(self.cfg / "legendaryConfig/legendary/installed.json", {
            "A": {"app_name": "A", "title": "SinCarpeta", "install_path": str(self.home / "no-existe")},
            "B": {"app_name": "B", "title": "Dlc", "install_path": self.folder("B"), "is_dlc": True},
            "C": {"app_name": "C", "title": "Bueno", "install_path": self.folder("C")}})
        self.assertEqual([x["name"] for x in HeroicDetector(self.home).detect()], ["Bueno"])

    def test_flatpak(self):
        cfg = self.home / ".var/app/com.heroicgameslauncher.hgl/config/heroic"
        wjson(cfg / "legendaryConfig/legendary/installed.json", {"A": {"app_name": "A", "title": "X", "install_path": self.folder("A")}})
        self.assertEqual(HeroicDetector(self.home).detect()[0]["ports"][0]["launch"][:3], ["flatpak", "run", "com.heroicgameslauncher.hgl"])

    def test_sin_heroic_o_json_roto(self):
        self.assertEqual(HeroicDetector(self.home).detect(), [])
        (self.cfg / "legendaryConfig/legendary").mkdir(parents=True)
        (self.cfg / "legendaryConfig/legendary/installed.json").write_text("{roto")
        self.assertEqual(HeroicDetector(self.home).detect(), [])

    def test_gog_exe_principal(self):
        d = Path(self.folder("G"))
        wjson(d / "goggame-1.info", {"playTasks": [{"path": "bin\\a.exe"}, {"isPrimary": True, "path": "bin\\game.exe"}]})
        self.assertEqual(gog_exe(str(d)), "bin/game.exe")


class Lutris(Base):
    def make_db(self, rows):
        db = self.home / "lutris/pga.db"
        db.parent.mkdir(parents=True)
        con = sqlite3.connect(db)
        con.execute("CREATE TABLE games (id INTEGER PRIMARY KEY, name TEXT, slug TEXT, runner TEXT, directory TEXT, installed INTEGER)")
        con.executemany("INSERT INTO games (name, slug, runner, directory, installed) VALUES (?,?,?,?,?)", rows)
        con.commit()
        con.close()
        return db

    def test_filtra_correctamente(self):
        db = self.make_db([("Juego Wine", "juego-wine", "wine", self.folder("w"), 1),
                           ("No Instalado", "ni", "wine", self.folder("n"), 0),
                           ("De Steam", "ds", "steam", self.folder("s"), 1),
                           ("EA app", "ea-app", "wine", self.folder("ea"), 1),
                           ("Ubisoft Connect", "ubisoft-connect", "wine", self.folder("u"), 1),
                           ("Sin Carpeta", "sc", "wine", str(self.home / "borrada"), 1)])
        g = LutrisDetector(db=db).detect()
        self.assertEqual([x["name"] for x in g], ["Juego Wine"])
        self.assertEqual(g[0]["ports"][0]["launch"], ["lutris", "lutris:rungameid/1"])

    def test_solo_lectura_y_sin_db(self):
        self.assertEqual(LutrisDetector(db=self.home / "nada.db").detect(), [])
        db = self.make_db([("A", "a", "wine", self.folder("a"), 1)])
        before = db.read_bytes()
        LutrisDetector(db=db).detect()
        self.assertEqual(db.read_bytes(), before)


class VariasFuentes(Base):
    def test_refresh_no_pisa_otras_fuentes(self):
        cfg = self.home / ".config/heroic"
        wjson(cfg / "legendaryConfig/legendary/installed.json", {"A": {"app_name": "A", "title": "Epico", "install_path": self.folder("A")}})
        db = Lutris.make_db(self, [("Wineado", "w", "wine", self.folder("w"), 1)])
        st = Store(self.home / "cfg")
        st.set_games([{"id": "steam-1", "name": "Vapor", "auto": "steam", "ports": []}])
        dets = [HeroicDetector(self.home), LutrisDetector(db=db)]
        self.assertEqual(refresh(st, dets)["added"], 2)
        self.assertEqual(sorted(g["id"] for g in st.games()), ["heroic-legendary-A", "lutris-1", "steam-1"])
        shutil.rmtree(self.home / "juegos" / "A")                      # se desinstala el de Epic
        self.assertEqual(refresh(st, dets)["removed"], 1)
        self.assertEqual(sorted(g["id"] for g in st.games()), ["lutris-1", "steam-1"])


if __name__ == "__main__":
    unittest.main()

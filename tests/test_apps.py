import json
import os
import shutil
import tempfile
import unittest
import urllib.error
import urllib.request
from pathlib import Path

from omnia import apps, security
from omnia.api import Api
from omnia.store import Store


def desktop(d: Path, fname: str, **kw):
    f = Path(d) / fname
    f.parent.mkdir(parents=True, exist_ok=True)
    fields = {"Type": "Application", "Name": "App", "Exec": "app %u", **kw}
    f.write_text("[Desktop Entry]\n" + "\n".join("{}={}".format(k.replace("__", "["), v) if "__" not in k else
                 "{}]={}".format(k.replace("__", "["), v) for k, v in fields.items()) + "\n")


class Catalogo(unittest.TestCase):
    def setUp(self):
        self.d = Path(tempfile.mkdtemp())
        self.addCleanup(shutil.rmtree, self.d, True)

    def load(self, **kw):
        return {a.id: a for a in apps.load_apps([self.d], langs=kw.get("langs", ["es_CO", "es"]))}

    def test_oculta_lo_que_no_debe_verse(self):
        desktop(self.d, "ok.desktop", Name="Visible")
        desktop(self.d, "nodisplay.desktop", Name="Oculta", NoDisplay="true")
        desktop(self.d, "hidden.desktop", Name="Borrada", Hidden="true")
        desktop(self.d, "gnome.desktop", Name="Solo GNOME", OnlyShowIn="GNOME;")
        desktop(self.d, "notkde.desktop", Name="No en KDE", NotShowIn="KDE;")
        desktop(self.d, "tryexec.desktop", Name="Sin binario", TryExec="/no/existe/nada")
        desktop(self.d, "noexec.desktop", Name="Sin Exec", Exec="")
        desktop(self.d, "link.desktop", Name="Enlace", Type="Link")
        self.assertEqual(sorted(self.load()), ["ok.desktop"])

    def test_solo_en_kde_si(self):
        desktop(self.d, "kde.desktop", Name="Mixta", OnlyShowIn="GNOME;KDE;")
        self.assertIn("kde.desktop", self.load())

    def test_nombre_localizado(self):
        desktop(self.d, "i.desktop", Name="Files", Name__es="Archivos", Name__es_CO="Archivos CO")
        self.assertEqual(self.load()["i.desktop"].name, "Archivos CO")
        self.assertEqual(self.load(langs=["es"])["i.desktop"].name, "Archivos")
        self.assertEqual(self.load(langs=["fr"])["i.desktop"].name, "Files")

    def test_grupos_por_categoria(self):
        desktop(self.d, "g.desktop", Name="G", Categories="Qt;Game;ActionGame;")
        desktop(self.d, "n.desktop", Name="N", Categories="Network;WebBrowser;")
        desktop(self.d, "s.desktop", Name="S", Categories="System;Utility;")       # gana System (antes que Utility)
        desktop(self.d, "x.desktop", Name="X", Categories="Qt;")
        a = self.load()
        self.assertEqual([a[k].group for k in ("g.desktop", "n.desktop", "s.desktop", "x.desktop")],
                         ["Juegos", "Internet", "Sistema", "Otras"])

    def test_la_carpeta_del_usuario_gana(self):
        usr, sysd = self.d / "usr", self.d / "sys"
        desktop(sysd, "a.desktop", Name="Del sistema")
        desktop(usr, "a.desktop", Name="Del usuario")
        self.assertEqual({a.id: a.name for a in apps.load_apps([usr, sysd], langs=[])}["a.desktop"], "Del usuario")

    def test_oculta_en_usuario_tapa_la_del_sistema(self):
        usr, sysd = self.d / "usr", self.d / "sys"
        desktop(sysd, "a.desktop", Name="Del sistema")
        desktop(usr, "a.desktop", Name="Oculta", NoDisplay="true")                  # así el usuario esconde una app
        self.assertEqual(apps.load_apps([usr, sysd], langs=[]), [])

    def test_id_con_subcarpeta(self):
        desktop(self.d, "kde/org.x.desktop", Name="Anidada")
        self.assertIn("kde-org.x.desktop", self.load())

    def test_archivo_roto_no_rompe(self):
        (self.d / "roto.desktop").write_text("no es un desktop \x00\x01 [[[")
        desktop(self.d, "ok.desktop", Name="Bien")
        self.assertEqual(list(self.load()), ["ok.desktop"])

    def test_cache_se_actualiza_al_instalar(self):
        cat = apps.Catalog([self.d])
        desktop(self.d, "a.desktop", Name="A")
        self.assertEqual([a.id for a in cat.apps()], ["a.desktop"])
        os.utime(self.d, ns=(1, 1))                                                  # fuerza otra firma de mtime
        desktop(self.d, "b.desktop", Name="B")
        os.utime(self.d, ns=(2, 2))
        self.assertEqual(sorted(a.id for a in cat.apps()), ["a.desktop", "b.desktop"])


class ApiApps(unittest.TestCase):
    def setUp(self):
        self.tmp = Path(tempfile.mkdtemp())
        self.addCleanup(shutil.rmtree, self.tmp, True)
        self.apps_dir = self.tmp / "apps"
        desktop(self.apps_dir, "org.kde.dolphin.desktop", Name="Dolphin", Categories="System;FileManager;")
        desktop(self.apps_dir, "otra.desktop", Name="Otra", Categories="Game;", Keywords="juego;cartas;")
        self.launched = []
        self.token = security.new_token(self.tmp / "run")
        self.store = Store(self.tmp / "cfg")
        self.api = Api(self.store, self.token, [], catalog=apps.Catalog([self.apps_dir]), scan_fn=list,
                       app_launch_fn=lambda a: self.launched.append(a.id))
        self.api.serve()
        self.addCleanup(self.api.stop)

    def call(self, path, method="GET", token=True):
        r = urllib.request.Request(f'http://127.0.0.1:{self.api.port:d}{path}', method=method, data=b"{}" if method == "POST" else None)
        if token:
            r.add_header("Authorization", "Bearer " + self.token)
        try:
            with urllib.request.urlopen(r, timeout=5) as x:
                return x.status, json.load(x)
        except urllib.error.HTTPError as e:
            return e.code, json.load(e)

    def test_lista_con_grupos_y_favoritos_por_defecto(self):
        code, d = self.call("/apps")
        self.assertEqual(code, 200)
        self.assertEqual(d["groups"], ["Juegos", "Sistema"])                          # orden fijo, no alfabético
        fav = {a["id"]: a["fav"] for a in d["apps"]}
        self.assertTrue(fav["org.kde.dolphin.desktop"])                               # favorito por defecto (existe)
        self.assertFalse(fav["otra.desktop"])
        self.assertEqual({a["id"]: a for a in d["apps"]}["otra.desktop"]["keywords"], ["juego", "cartas"])

    def test_lanzar_cuenta_usos_y_solo_del_catalogo(self):
        self.assertEqual(self.call("/app/launch?id=otra.desktop", "POST")[0], 200)
        self.assertEqual(self.launched, ["otra.desktop"])
        self.assertEqual({a["id"]: a for a in self.call("/apps")[1]["apps"]}["otra.desktop"]["uses"], 1)
        self.assertEqual(self.call("/app/launch?id=../../etc/passwd", "POST")[0], 404)
        self.assertEqual(self.call("/app/launch?id=/usr/bin/rm", "POST")[0], 404)
        self.assertEqual(self.launched, ["otra.desktop"])                             # nada más se ejecutó

    def test_favoritos_se_alternan_y_persisten(self):
        self.assertEqual(self.call("/app/fav?id=otra.desktop", "POST")[1]["on"], True)
        self.assertEqual(self.call("/app/fav?id=org.kde.dolphin.desktop", "POST")[1]["on"], False)   # quita un favorito por defecto
        self.assertEqual(Store(self.tmp / "cfg").state["apps_fav"], ["otra.desktop"])

    def test_exige_token_y_post(self):
        self.assertEqual(self.call("/apps", token=False)[0], 401)
        self.assertEqual(self.call("/app/launch?id=otra.desktop")[0], 405)
        self.assertEqual(self.launched, [])


if __name__ == "__main__":
    unittest.main()

import io
import json
import shutil
import tempfile
import unittest
from contextlib import redirect_stderr, redirect_stdout
from pathlib import Path
from unittest import mock

from omnia import setup
from omnia.setup import LAUNCHER, META_ALONE, META_D, NATIVE, OMENU, OURS, SetupError


class FakeKde:
    """KDE simulado: el atajo de Omnia solo existe cuando el script está activo y KWin se recargó."""

    def __init__(self, native=(META_D,), plugin=False, installed=True, watch=False):
        self.ALT_F1 = 150994992
        self.keys = {NATIVE: list(native), OURS: [], LAUNCHER: [META_ALONE, self.ALT_F1], OMENU: []}
        self.plugins = {"omnia-showdesktop": plugin, "omnia-watch": watch}
        self.meta = ""
        self.installed = set(self.plugins) if installed else set()
        self.loaded = False
        self.calls = []
        if plugin:
            self.loaded = True

    def shortcut_keys(self, a):
        return list(self.keys.get(a, [])) if (a not in (OURS, OMENU) or self.loaded) else []

    def set_shortcut_keys(self, a, keys):
        self.calls.append(("set", a, list(keys)))
        # como KDE de verdad: una tecla que ya tiene otra acción se rechaza (no se puede duplicar)
        taken = {k for other, ks in self.keys.items() if other != a for k in ks}
        self.keys[a] = [k for k in keys if k not in taken]

    def action_exists(self, a):
        return a not in (OURS, OMENU) or self.loaded

    def plugin_enabled(self, n):
        return self.plugins[n]

    def set_plugin_enabled(self, n, on):
        self.calls.append(("plugin", n, on))
        self.plugins[n] = on

    def meta_shortcut(self):
        return self.meta

    def set_meta_shortcut(self, v):
        self.calls.append(("meta", v))
        self.meta = v or ""

    def reload_kwin(self):
        self.calls.append(("reload",))
        self.loaded = self.plugins["omnia-showdesktop"]

    def script_installed(self, n):
        return n in self.installed

    def install_script(self, src):
        self.calls.append(("install", str(src)))
        self.installed.add(Path(src).name)


class LlamadasDBus(unittest.TestCase):
    """Fija el formato exacto de las llamadas a busctl: un solo argumento de firma (el simulado no puede detectarlo)."""

    def setUp(self):
        self.cmds = []
        self.be = setup.KdeBackend()
        self.be._run = lambda *c: (self.cmds.append(list(c)) or "ai 1 268435524")

    def test_escribir_la_tecla_windows_usa_kwriteconfig(self):
        self.be.set_meta_shortcut("a,b,c,d")
        self.be.set_meta_shortcut(None)
        self.assertEqual(self.cmds[0][0], "kwriteconfig6")
        self.assertEqual(self.cmds[1][-1], "--delete")

    def test_leer_usa_firma_as(self):
        self.assertEqual(self.be.shortcut_keys(NATIVE), [META_D])
        c = self.cmds[0]
        self.assertEqual(c[c.index("shortcut"):], ["shortcut", "as", "4", "kwin", "Show Desktop", "", ""])

    def test_escribir_usa_una_sola_firma_asai(self):
        self.be.set_shortcut_keys(NATIVE, [META_D, 5])
        c = self.cmds[0]
        self.assertEqual(c[c.index("setForeignShortcut"):],
                         ["setForeignShortcut", "asai", "4", "kwin", "Show Desktop", "", "", "2", str(META_D), "5"])

    def test_escribir_lista_vacia(self):
        self.be.set_shortcut_keys(OURS, [])
        c = self.cmds[0]
        self.assertEqual(c[c.index("setForeignShortcut"):],
                         ["setForeignShortcut", "asai", "4", "kwin", "OmniaShowDesktop", "", "", "0"])


class Setup(unittest.TestCase):
    def setUp(self):
        self.cfg = Path(tempfile.mkdtemp())
        self.addCleanup(shutil.rmtree, self.cfg, True)

    def run_main(self, be, *args):
        out, err = io.StringIO(), io.StringIO()
        with redirect_stdout(out), redirect_stderr(err):
            rc = setup.main(list(args), backend=be, config=self.cfg)
        return rc, out.getvalue(), err.getvalue()

    def test_apply_deja_meta_d_solo_en_omnia(self):
        be = FakeKde()
        setup.apply(be, self.cfg, wait=0.5)
        self.assertEqual(be.keys[NATIVE], [])
        self.assertEqual(be.keys[OURS], [META_D])
        self.assertTrue(all(be.plugins.values()))

    def test_conserva_otras_teclas_del_nativo(self):
        be = FakeKde(native=(META_D, 12345))
        setup.apply(be, self.cfg, wait=0.5)
        self.assertEqual(be.keys[NATIVE], [12345])

    def test_la_tecla_windows_pasa_del_lanzador_de_plasma_a_omnia_y_vuelve(self):
        be = FakeKde()
        setup.apply(be, self.cfg, wait=0.5)
        self.assertEqual(be.keys[LAUNCHER], [be.ALT_F1])                  # Alt+F1 se conserva
        self.assertEqual(be.keys[OMENU], [META_ALONE])
        setup.undo(be, self.cfg)
        self.assertEqual(be.keys[LAUNCHER], [META_ALONE, be.ALT_F1])      # volvió, aunque el simulado rechace duplicados
        self.assertEqual(be.keys[OMENU], [])

    def test_limpia_el_ajuste_antiguo_que_no_funcionaba(self):
        be = FakeKde()
        be.meta = setup.OMNIA_META
        setup.apply(be, self.cfg, wait=0.5)
        self.assertEqual(be.meta, "")
        self.assertIn(("meta", None), be.calls)

    def test_copia_antigua_sin_lanzador_no_rompe_el_undo(self):
        be = FakeKde()
        setup.apply(be, self.cfg, wait=0.5)
        bf = self.cfg / "setup-backup.json"
        d = json.loads(bf.read_text())
        d.pop("launcher_keys_before")
        bf.write_text(json.dumps(d))
        setup.undo(be, self.cfg)                                          # no sabe qué teclas tenía: no inventa
        self.assertEqual(be.keys[OMENU], [])

    def test_idempotente_y_no_pisa_la_copia_original(self):
        be = FakeKde()
        setup.apply(be, self.cfg, wait=0.5)
        original = (self.cfg / "setup-backup.json").read_text()
        self.assertEqual(setup.apply(be, self.cfg, wait=0.5), [])          # segunda vez: no hace nada
        self.assertEqual((self.cfg / "setup-backup.json").read_text(), original)
        self.assertEqual(json.loads(original)["native_keys"], [META_D])     # guardó el estado ANTES de cambiar

    def test_undo_restaura_todo(self):
        be = FakeKde(native=(META_D, 77))
        setup.apply(be, self.cfg, wait=0.5)
        setup.undo(be, self.cfg)
        self.assertEqual(be.keys[NATIVE], [META_D, 77])
        self.assertEqual(be.keys[OURS], [])
        self.assertFalse(any(be.plugins.values()))
        self.assertFalse((self.cfg / "setup-backup.json").exists())

    def test_undo_respeta_script_que_ya_estaba_activo(self):
        be = FakeKde(plugin=True)
        setup.apply(be, self.cfg, wait=0.5)
        setup.undo(be, self.cfg)
        self.assertTrue(be.plugins["omnia-showdesktop"])    # ya lo tenía el usuario: no se lo apagamos
        self.assertFalse(be.plugins["omnia-watch"])         # este lo activó Omnia: se apaga

    def test_undo_sin_copia_no_toca_nada(self):
        be = FakeKde()
        self.assertEqual(setup.undo(be, self.cfg), [])
        self.assertEqual(be.calls, [])

    def test_instala_el_script_si_falta(self):
        be = FakeKde(installed=False)
        src = self.cfg / "scripts"
        for n in ("omnia-showdesktop", "omnia-watch"):
            (src / n).mkdir(parents=True)
        setup.apply(be, self.cfg, script_src=src, wait=0.5)
        self.assertIn(("install", str(src / "omnia-watch")), be.calls)

    def test_script_ausente_y_sin_origen_falla_claro(self):
        with self.assertRaises(SetupError):
            setup.apply(FakeKde(installed=False), self.cfg, wait=0.5)

    def test_si_kwin_no_registra_el_atajo_falla_y_no_quita_nada(self):
        be = FakeKde()
        be.reload_kwin = lambda: None                   # el script nunca carga
        with self.assertRaises(SetupError):
            setup.apply(be, self.cfg, wait=0.4)
        self.assertEqual(be.keys[NATIVE], [META_D])     # el Win+D nativo sigue funcionando

    def test_sin_terminal_y_sin_yes_pide_consentimiento(self):
        be = FakeKde()
        with mock.patch("sys.stdin.isatty", return_value=False):
            rc, out, err = self.run_main(be)
        self.assertEqual(rc, 3)
        self.assertEqual(be.calls, [])                  # no cambió nada

    def test_dry_run_y_status_no_cambian_nada(self):
        be = FakeKde()
        self.assertEqual(self.run_main(be, "--dry-run")[0], 0)
        self.assertEqual(self.run_main(be, "--status")[0], 1)        # pendiente
        self.assertEqual(be.calls, [])
        self.assertEqual(be.keys[NATIVE], [META_D])

    def test_yes_aplica_y_status_confirma(self):
        be = FakeKde()
        self.assertEqual(self.run_main(be, "--yes")[0], 0)
        self.assertEqual(self.run_main(be, "--status")[0], 0)


if __name__ == "__main__":
    unittest.main()

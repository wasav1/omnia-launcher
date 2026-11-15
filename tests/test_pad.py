import json
import os
import shutil
import struct
import tempfile
import threading
import time
import unittest
import urllib.error
import urllib.request
from pathlib import Path

from omnia import pad, security
from omnia.api import Api
from omnia.events import EventBus
from omnia.pad import (ABS_BRAKE, ABS_HAT0X, ABS_HAT0Y, ABS_X, ABS_Y, BTN_EAST, BTN_NORTH, BTN_SOUTH, BTN_START,
                       BTN_TL, EV_ABS, EV_KEY, PadLogic)
from omnia.store import Store

DEVICES = '''I: Bus=0003 Vendor=046d Product=c52b Version=0111
N: Name="Logitech USB Receiver"
H: Handlers=sysrq kbd event3 leds

I: Bus=0005 Vendor=045e Product=0b13 Version=0001
N: Name="Xbox Wireless Controller"
H: Handlers=kbd event27 js0
B: KEY=7fff000000000000 0 8000000000 0 0

I: Bus=0003 Vendor=054c Product=0ce6 Version=0111
N: Name="Sony Interactive Entertainment DualSense Wireless Controller"
H: Handlers=event9 js1

I: Bus=0003 Vendor=057e Product=2009 Version=0111
N: Name="Nintendo Switch Pro Controller"
H: Handlers=event12 js2
'''


class Descubrir(unittest.TestCase):
    def test_solo_mandos_y_layout_por_nombre(self):
        tmp = Path(tempfile.mkdtemp())
        self.addCleanup(shutil.rmtree, tmp, True)
        f = tmp / "devices"
        f.write_text(DEVICES)
        d = {x.name: x for x in pad.discover(str(f))}
        self.assertEqual(len(d), 3)                                         # el receptor Logitech no es un mando
        self.assertEqual(d["Xbox Wireless Controller"].path, "/dev/input/event27")
        self.assertEqual(d["Xbox Wireless Controller"].layout, "xbox")
        self.assertEqual(d["Sony Interactive Entertainment DualSense Wireless Controller"].layout, "ps")
        self.assertEqual(d["Nintendo Switch Pro Controller"].layout, "switch")

    def test_sin_archivo(self):
        self.assertEqual(pad.discover("/no/existe"), [])


class Logica(unittest.TestCase):
    def test_botones_xbox_y_switch(self):
        x = PadLogic("xbox")
        self.assertEqual(x.feed(EV_KEY, BTN_SOUTH, 1, 0), ["A"])
        self.assertEqual(x.feed(EV_KEY, 0x133, 1, 0), ["X"])                # medido en un Xbox real: 0x133 = X (izquierda)
        self.assertEqual(x.feed(EV_KEY, 0x134, 1, 0), ["Y"])                # 0x134 = Y (arriba)
        self.assertEqual(x.feed(EV_KEY, BTN_SOUTH, 0, 0), [])               # soltar no emite
        s = PadLogic("switch")
        self.assertEqual(s.feed(EV_KEY, BTN_EAST, 1, 0), ["A"])             # en Nintendo A es el botón derecho
        self.assertEqual(s.feed(EV_KEY, BTN_SOUTH, 1, 0), ["B"])

    def test_hombros_y_start(self):
        p = PadLogic()
        self.assertEqual(p.feed(EV_KEY, BTN_TL, 1, 0), ["LB"])
        self.assertEqual(p.feed(EV_KEY, BTN_START, 1, 0), ["START"])

    def test_cruceta_y_repeticion(self):
        p = PadLogic()
        self.assertEqual(p.feed(EV_ABS, ABS_HAT0X, 1, 0.0), ["r"])
        self.assertEqual(p.feed(EV_ABS, ABS_HAT0X, 1, 0.1), [])             # sigue pulsado: no repite aún
        self.assertEqual(p.tick(0.3), [])
        self.assertEqual(p.tick(0.41), ["r"])                               # primer repetido a los 0,4 s
        self.assertEqual(p.tick(0.45), [])
        self.assertEqual(p.tick(0.54), ["r"])                               # luego cada 0,12 s
        p.feed(EV_ABS, ABS_HAT0X, 0, 0.6)
        self.assertEqual(p.tick(5.0), [])                                   # soltar detiene

    def test_stick_con_zona_muerta(self):
        p = PadLogic()
        self.assertEqual(p.feed(EV_ABS, ABS_X, 0.3, 0), [])                 # dentro de la zona muerta
        self.assertEqual(p.feed(EV_ABS, ABS_X, -0.9, 0), ["l"])
        self.assertEqual(p.feed(EV_ABS, ABS_Y, -0.8, 0.1), ["u"])           # arriba = valor negativo
        self.assertEqual(p.feed(EV_ABS, ABS_X, 0.0, 0.2), [])               # soltar X no cancela Y
        self.assertIn("u", p.held)
        self.assertNotIn("l", p.held)

    def test_stick_y_cruceta_a_la_vez_no_duplican(self):
        p = PadLogic()
        self.assertEqual(p.feed(EV_ABS, ABS_HAT0Y, 1, 0), ["d"])
        self.assertEqual(p.feed(EV_ABS, ABS_Y, 0.9, 0), [])                 # ya estaba «d»
        p.feed(EV_ABS, ABS_HAT0Y, 0, 0.1)
        self.assertIn("d", p.held)                                          # el stick la mantiene

    def test_gatillo_una_vez_por_pulsacion(self):
        p = PadLogic()
        self.assertEqual(p.feed(EV_ABS, ABS_BRAKE, 0.2, 0), [])
        self.assertEqual(p.feed(EV_ABS, ABS_BRAKE, 0.8, 0), ["LT"])
        self.assertEqual(p.feed(EV_ABS, ABS_BRAKE, 1.0, 0), [])
        p.feed(EV_ABS, ABS_BRAKE, 0.0, 0)
        self.assertEqual(p.feed(EV_ABS, ABS_BRAKE, 0.9, 0), ["LT"])

    def test_normalizar_con_el_rango_real_del_xbox(self):
        info = (0, 0, 65535, 255, 4095, 0)               # ABS_X medido en el mando real
        self.assertAlmostEqual(pad.normalize(ABS_X, 32767, info), 0.0, places=2)
        self.assertAlmostEqual(pad.normalize(ABS_X, 0, info), -1.0, places=2)
        self.assertAlmostEqual(pad.normalize(ABS_X, 65535, info), 1.0, places=2)
        self.assertAlmostEqual(pad.normalize(ABS_BRAKE, 1023, (0, 0, 1023, 0, 63, 0)), 1.0, places=2)


class Bus(unittest.TestCase):
    def test_espera_y_desbloquea(self):
        bus = EventBus()
        threading.Timer(0.1, bus.push, args=("A",)).start()
        t0 = time.time()
        r = bus.wait(0, 5)
        self.assertEqual([e["key"] for e in r["events"]], ["A"])
        self.assertLess(time.time() - t0, 2)

    def test_since_negativo_no_repite_eventos_viejos(self):
        bus = EventBus()
        bus.push("A")
        r = bus.wait(-1, 5)
        self.assertEqual((r["seq"], r["events"]), (1, []))

    def test_tiempo_agotado(self):
        self.assertEqual(EventBus().wait(0, 0.2)["events"], [])


class ApiMando(unittest.TestCase):
    def setUp(self):
        self.tmp = Path(tempfile.mkdtemp())
        self.addCleanup(shutil.rmtree, self.tmp, True)
        self.store = Store(self.tmp / "cfg")
        self.token = security.new_token(self.tmp / "run")
        self.cmds = []
        self.api = Api(self.store, self.token, [], scan_fn=lambda: self.cmds)
        self.api.serve()
        self.addCleanup(self.api.stop)
        self.base = "http://127.0.0.1:%d" % self.api.port

    def call(self, path, method="GET", token=True):
        r = urllib.request.Request(self.base + path, method=method, data=b"{}" if method == "POST" else None)
        if token:
            r.add_header("Authorization", "Bearer " + self.token)
        try:
            with urllib.request.urlopen(r, timeout=8) as x:
                return x.status, json.load(x)
        except urllib.error.HTTPError as e:
            return e.code, json.load(e)

    def test_events_exige_token(self):
        self.assertEqual(self.call("/events?since=-1", token=False)[0], 401)
        self.assertEqual(self.call("/emit?k=A", "POST", token=False)[0], 401)

    def test_emit_llega_por_events(self):
        self.assertEqual(self.call("/events?since=-1")[1]["seq"], 0)
        self.assertEqual(self.call("/emit?k=A", "POST")[0], 200)
        ev = self.call("/events?since=0&wait=2")[1]["events"]
        self.assertEqual([e["key"] for e in ev], ["A"])

    def test_emit_rechaza_teclas_raras_y_get(self):
        self.assertEqual(self.call("/emit?k=rm", "POST")[0], 400)
        self.assertEqual(self.call("/emit?k=A")[0], 405)

    def test_peticion_larga_se_desbloquea_con_un_evento(self):
        threading.Timer(0.3, self.api.bus.push, args=("r",)).start()
        t0 = time.time()
        r = self.call("/events?since=0&wait=10")[1]
        self.assertEqual(r["events"][0]["key"], "r")
        self.assertLess(time.time() - t0, 3)

    def test_con_juego_abierto_el_mando_no_actua(self):
        self.store.set_games([{"id": "g", "name": "G", "ports": [{"id": "p", "name": "x", "launch": ["x"], "check": str(self.tmp), "proc": "juego.exe"}]}])
        self.cmds = ["wine /x/juego.exe"]
        self.api._gate_t = 0
        self.call("/emit?k=A", "POST")
        self.assertEqual(self.call("/events?since=-1")[1]["seq"], 0)       # no se entregó
        self.assertFalse(self.call("/pad")[1]["active"])
        self.cmds = []
        self.api._gate_t = 0
        self.call("/emit?k=A", "POST")
        self.assertEqual(self.call("/events?since=-1")[1]["seq"], 1)

    def test_la_tecla_windows_abre_el_menu_aunque_el_mando_este_silenciado(self):
        self.call("/desktop?visible=0", "POST")                            # ventana encima: el mando no actúa…
        self.assertEqual(self.call("/menu", "POST")[0], 200)               # …pero la tecla Windows sí abre el menú
        self.assertEqual([e["key"] for e in self.call("/events?since=0&wait=2")[1]["events"]], ["MENU"])
        self.assertEqual(self.call("/menu", "POST", token=False)[0], 401)

    def test_el_menu_abierto_da_el_mando_al_menu_aunque_haya_ventanas(self):
        self.call("/desktop?visible=0", "POST")                            # una ventana con foco: el mando no actúa
        self.call("/emit?k=A", "POST")
        self.assertEqual(self.call("/events?since=-1")[1]["seq"], 0)
        self.call("/menu/state?open=1", "POST")                            # la UI avisa de que el Big Menu está abierto
        self.call("/events?since=-1")                                      # la UI está viva (sondea /events)
        self.call("/emit?k=d", "POST")
        self.assertEqual(self.call("/events?since=-1")[1]["seq"], 1)       # ahora sí llega
        self.call("/menu/state?open=0", "POST")                            # se cierra: vuelve la regla de las ventanas
        self.call("/emit?k=d", "POST")
        self.assertEqual(self.call("/events?since=-1")[1]["seq"], 1)

    def test_menu_abierto_pero_ui_muerta_no_deja_el_mando_atascado(self):
        self.call("/desktop?visible=0", "POST")
        self.call("/menu/state?open=1", "POST")
        self.api._last_poll = time.time() - 120                            # la UI dejó de sondear (se cerró o cayó)
        self.call("/emit?k=A", "POST")
        self.assertEqual(self.call("/events?since=-1")[1]["seq"], 0)

    def test_menu_abierto_no_salta_el_filtro_de_juego_abierto(self):
        self.store.set_games([{"id": "g", "name": "G", "ports": [{"id": "p", "name": "x", "launch": ["x"], "check": str(self.tmp), "proc": "juego.exe"}]}])
        self.cmds = ["wine /x/juego.exe"]
        self.api._gate_t = 0
        self.call("/menu/state?open=1", "POST")
        self.call("/events?since=-1")
        self.call("/emit?k=A", "POST")
        self.assertEqual(self.call("/events?since=-1")[1]["seq"], 0)       # con un juego en marcha el mando sigue siendo suyo

    def test_escritorio_tapado_silencia_el_mando(self):
        self.call("/desktop?visible=0", "POST")
        self.call("/emit?k=A", "POST")
        self.assertEqual(self.call("/events?since=-1")[1]["seq"], 0)
        self.call("/desktop?visible=1", "POST")
        self.call("/emit?k=A", "POST")
        self.assertEqual(self.call("/events?since=-1")[1]["seq"], 1)


class LectorReal(unittest.TestCase):
    """Ejercita PadReader de verdad con un dispositivo falso (tubería con nombre)."""

    def test_lee_eventos_y_detecta_altas_y_bajas(self):
        tmp = Path(tempfile.mkdtemp())
        self.addCleanup(shutil.rmtree, tmp, True)
        fifo = tmp / "event99"
        os.mkfifo(fifo)
        devs = tmp / "devices"
        devs.write_text('N: Name="Xbox Wireless Controller"\nH: Handlers=kbd event99 js9\n')
        bus = EventBus()
        r = pad.PadReader(bus, devices_file=str(devs), dev_dir=str(tmp))
        r.start()
        self.addCleanup(r.stop)
        t0 = time.time()
        while not bus.pad["connected"] and time.time() < t0 + 5:          # esperar a que lo abra
            time.sleep(0.05)
        self.assertTrue(bus.pad["connected"])
        self.assertEqual(bus.pad["name"], "Xbox Wireless Controller")
        wfd = os.open(fifo, os.O_WRONLY)
        try:
            os.write(wfd, pad.EVENT.pack(0, 0, EV_KEY, BTN_SOUTH, 1) + pad.EVENT.pack(0, 0, EV_KEY, BTN_NORTH, 1))
            t0 = time.time()
            while bus.seq < 2 and time.time() < t0 + 5:
                time.sleep(0.05)
        finally:
            os.close(wfd)
        self.assertEqual([e["key"] for e in bus.snapshot(0)["events"]], ["A", "X"])
        devs.write_text("")                                                # el mando se desconecta
        t0 = time.time()
        while bus.pad["connected"] and time.time() < t0 + 6:
            time.sleep(0.1)
        self.assertFalse(bus.pad["connected"])


if __name__ == "__main__":
    unittest.main()

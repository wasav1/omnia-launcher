import struct
import unittest

from omnia import pad
from omnia.events import EventBus


def reader_with_pad(layout="xbox", family="xbox", uniq="aa:bb", gas=False):
    r = pad.PadReader(EventBus(), power_dir="/nonexistent")
    dev = pad.Device("Xbox Wireless Controller", "/dev/input/event9", layout, family, "045e", "0b13", uniq)
    info = {pad.ABS_X: (0, -32768, 32767, 0, 0, 0), pad.ABS_Y: (0, -32768, 32767, 0, 0, 0),
            pad.ABS_RX: (0, -32768, 32767, 0, 0, 0), pad.ABS_RY: (0, -32768, 32767, 0, 0, 0),
            pad.ABS_Z: (0, 0, 1023, 0, 0, 0), pad.ABS_RZ: (0, 0, 1023, 0, 0, 0)}
    if gas:
        info = {k: v for k, v in info.items() if k not in (pad.ABS_RX, pad.ABS_RY)}
        info[pad.ABS_GAS] = (0, 0, 1023, 0, 0, 0)
        info[pad.ABS_BRAKE] = (0, 0, 1023, 0, 0, 0)
    r.open[10] = (dev, pad.PadLogic(layout), {})
    r.allinfo[10] = info
    r.state[10] = {"buttons": set(), "axes": {}}
    return r, dev


class RumbleEffectTests(unittest.TestCase):
    def test_the_effect_has_the_kernel_layout(self):
        raw = pad.ff_rumble_effect(1.0, 0.5, 300)
        self.assertEqual(len(raw), 48)
        etype, eid, direction, _, _, length, delay, strong, weak = struct.unpack_from("<HhHHHHHxxHH", raw)
        self.assertEqual((etype, eid, length, delay, strong), (pad.FF_RUMBLE, -1, 300, 0, 65535))
        self.assertEqual(weak, 32768)
        self.assertEqual(pad.EVIOCSFF, 0x40304580)

    def test_values_are_clamped(self):
        raw = pad.ff_rumble_effect(5, -3, 99999)
        etype, eid, direction, _, _, length, delay, strong, weak = struct.unpack_from("<HhHHHHHxxHH", raw)
        self.assertEqual((length, strong, weak), (5000, 65535, 0))


class DeadzoneTests(unittest.TestCase):
    def test_default_keeps_the_old_navigation_threshold(self):
        self.assertAlmostEqual(pad.PadLogic().stick, 0.5)

    def test_a_smaller_deadzone_navigates_with_less_tilt_and_a_bigger_one_needs_more(self):
        light, heavy = pad.PadLogic(deadzone=0.05), pad.PadLogic(deadzone=0.4)
        self.assertEqual(light.feed(pad.EV_ABS, pad.ABS_X, -0.45, 0.0), ["l"])
        self.assertEqual(pad.PadLogic().feed(pad.EV_ABS, pad.ABS_X, -0.45, 0.0), [])
        self.assertEqual(heavy.feed(pad.EV_ABS, pad.ABS_X, 0.7, 0.0), [])
        self.assertEqual(heavy.feed(pad.EV_ABS, pad.ABS_X, 0.8, 0.0), ["r"])


class SnapshotAndSettingsTests(unittest.TestCase):
    def test_snapshot_reports_buttons_sticks_and_triggers(self):
        r, dev = reader_with_pad()
        r.state[10]["buttons"] = {pad.BTN_SOUTH, pad.BTN_THUMBL, pad.BTN_TL, 0x2FF}
        r.state[10]["axes"] = {pad.ABS_X: -0.8, pad.ABS_Y: 0.05, pad.ABS_RX: 0.4, pad.ABS_RY: -0.6, pad.ABS_Z: 0.5, pad.ABS_HAT0X: 1}
        snap = r.snapshot()[0]
        self.assertEqual(snap["buttons"], ["A", "LB", "LS"])                 # el código desconocido no aparece
        self.assertEqual((snap["lx"], snap["ly"], snap["rx"], snap["ry"]), (-0.8, 0.0, 0.4, -0.6))   # 0,05 queda dentro de la zona muerta
        self.assertEqual((snap["lt"], snap["rt"], snap["hatx"]), (0.5, 0.0, 1))

    def test_xbox_over_bluetooth_uses_gas_brake_for_triggers_and_z_rz_for_the_right_stick(self):
        r, dev = reader_with_pad(gas=True)
        r.state[10]["axes"] = {pad.ABS_Z: 0.7, pad.ABS_RZ: -0.5, pad.ABS_GAS: 0.9, pad.ABS_BRAKE: 0.2}
        snap = r.snapshot()[0]
        self.assertEqual((snap["rx"], snap["ry"], snap["lt"], snap["rt"]), (0.7, -0.5, 0.9, 0.2))

    def test_settings_override_family_and_apply_the_deadzone_live(self):
        r, dev = reader_with_pad()
        r.configure({"aa:bb": {"family": "ps", "deadzone": 0.3, "nickname": "Mando del sofá", "haptics": True}})
        snap = r.snapshot()[0]
        self.assertEqual((snap["family"], snap["detectedFamily"], snap["nickname"], snap["haptics"]), ("ps", "xbox", "Mando del sofá", True))
        self.assertAlmostEqual(r.open[10][1].stick, 0.65)
        r.configure({"aa:bb": {"family": "inventada"}})
        self.assertEqual(r.snapshot()[0]["family"], "xbox")                    # una familia no válida se ignora

    def test_rumble_only_works_on_detected_pads(self):
        r, dev = reader_with_pad()
        calls = []
        r.haptic = lambda *a: calls.append(a)
        r.rumble("/dev/input/event9", 0.5, 0.2, 200)
        self.assertEqual(calls, [("/dev/input/event9", 0.5, 0.2, 200)])
        with self.assertRaises(OSError):
            r.rumble("/etc/passwd")
        self.assertEqual(len(calls), 1)

    def test_haptic_pulses_only_for_pads_with_haptics_and_are_throttled(self):
        r, dev = reader_with_pad()
        pulses = []
        r.haptic = lambda *a: pulses.append(a)
        r._haptic_pulse("A")
        self.assertEqual(pulses, [])
        r.configure({"aa:bb": {"haptics": True}})
        r._haptic_pulse("A")
        import time as _t
        for _ in range(50):
            if pulses:
                break
            _t.sleep(0.01)
        self.assertEqual(len(pulses), 1)
        r._haptic_pulse("A")                                                    # dentro de 0,12 s: no repite
        _t.sleep(0.05)
        self.assertEqual(len(pulses), 1)
        r._haptic_pulse("X")                                                    # una tecla sin pulso definido
        self.assertEqual(len(pulses), 1)


if __name__ == "__main__":
    unittest.main()

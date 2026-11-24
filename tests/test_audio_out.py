import json
import types
import unittest

from omnia import audio_out

SINKS = [
    {"name": "alsa_output.pci.hdmi-stereo", "description": "HDMI", "properties": {"device.description": "HDMI / DisplayPort"},
     "ports": [{"name": "hdmi-output-0", "description": "HDMI", "availability": "available"}], "active_port": "hdmi-output-0"},
    {"name": "alsa_output.pci.analog-stereo", "description": "Interno", "properties": {"device.description": "Audio interno"},
     "ports": [{"name": "analog-output-speaker", "description": "Altavoces", "availability": "unknown"},
               {"name": "analog-output-headphones", "description": "Auriculares", "availability": "available"},
               {"name": "analog-output-lineout", "description": "Línea", "availability": "not available"}],
     "active_port": "analog-output-speaker"},
    {"name": "alsa_output.usb-Foo", "description": "USB", "properties": {"device.description": "USB PnP"}, "ports": [], "active_port": None},
]


class Fake:
    def __init__(self, default="alsa_output.usb-Foo"):
        self.calls, self.default = [], default

    def __call__(self, cmd, **kw):
        a = cmd[1:]
        self.calls.append(a)
        out = ""
        if a[:1] == ["get-default-sink"]:
            out = self.default + "\n"
        elif a[:3] == ["-f", "json", "list"]:
            out = json.dumps(SINKS)
        elif a[:3] == ["list", "short", "sink-inputs"]:
            out = "12\t5\t6\tx\ts16le\n13\t5\t6\ty\ts16le\n"
        return types.SimpleNamespace(stdout=out, stderr="", returncode=0)


SOURCES = [
    {"name": "alsa_input.usb-Mic", "description": "Micrófono USB", "properties": {"device.description": "USB Microphone"}},
    {"name": "alsa_input.pci.analog", "description": "Interno", "properties": {"device.description": "Audio interno"}},
    {"name": "alsa_output.pci.analog-stereo.monitor", "description": "Monitor", "properties": {}, "monitor_of_sink": 7},
]


class FakeIO(Fake):
    def __call__(self, cmd, **kw):
        a = cmd[1:]
        out = ""
        if a[:1] == ["get-default-source"]:
            out = "alsa_input.usb-Mic\n"
            self.calls.append(a)
        elif a[:3] == ["-f", "json", "list"] and a[3] == "sources":
            self.calls.append(a)
            out = json.dumps(SOURCES)
        elif a[:3] == ["list", "short", "source-outputs"]:
            self.calls.append(a)
            out = "40\t5\t6\tx\ts16le\n"
        elif a[:1] == ["get-sink-volume"]:
            self.calls.append(a)
            out = "Volume: front-left: 41284 /  63% / -12.00 dB,   front-right: 41284 /  63% / -12.00 dB\n"
        elif a[:1] == ["get-sink-mute"]:
            self.calls.append(a)
            out = "Mute: no\n"
        elif a[:1] == ["get-source-volume"]:
            self.calls.append(a)
            out = "Volume: mono: 52428 /  80% / -5.81 dB\n"
        elif a[:1] == ["get-source-mute"]:
            self.calls.append(a)
            out = "Mute: yes\n"
        else:
            return super().__call__(cmd, **kw)
        return types.SimpleNamespace(stdout=out, stderr="", returncode=0)


class AudioInputTests(unittest.TestCase):
    def test_lists_microphones_without_monitors_and_marks_the_default(self):
        items = audio_out.list_inputs(FakeIO())
        self.assertEqual([i["source"] for i in items], ["alsa_input.usb-Mic", "alsa_input.pci.analog"])
        self.assertTrue(items[0]["current"] and not items[1]["current"])

    def test_set_input_only_accepts_listed_microphones_and_moves_recordings(self):
        run = FakeIO()
        with self.assertRaises(audio_out.AudioOutError):
            audio_out.set_input("alsa_input.fake; rm -rf /", run)
        audio_out.set_input("alsa_input.pci.analog", run)
        self.assertIn(["set-default-source", "alsa_input.pci.analog"], run.calls)
        self.assertIn(["move-source-output", "40", "alsa_input.pci.analog"], run.calls)

    def test_levels_and_validated_setters(self):
        run = FakeIO()
        self.assertEqual(audio_out.get_level("output", run), {"volume": 63, "muted": False})
        self.assertEqual(audio_out.get_level("input", run), {"volume": 80, "muted": True})
        audio_out.set_level("output", volume=70, muted=False, run=run)
        self.assertIn(["set-sink-volume", "@DEFAULT_SINK@", "70%"], run.calls)
        self.assertIn(["set-sink-mute", "@DEFAULT_SINK@", "0"], run.calls)
        for bad in (-1, 151, "50", 50.5, True):
            with self.assertRaises(audio_out.AudioOutError):
                audio_out.set_level("input", volume=bad, run=run)


class AudioOutTests(unittest.TestCase):
    def test_lists_one_entry_per_sink_and_per_available_port(self):
        items = audio_out.list_outputs(Fake())
        labels = [i["label"] for i in items]
        self.assertIn("HDMI / DisplayPort · HDMI", labels)
        self.assertIn("Audio interno · Altavoces", labels)
        self.assertIn("Audio interno · Auriculares", labels)
        self.assertNotIn("Audio interno · Línea", labels)            # puerto no disponible
        self.assertIn("USB PnP", labels)

    def test_marks_only_the_current_one(self):
        cur = [i["label"] for i in audio_out.list_outputs(Fake()) if i["current"]]
        self.assertEqual(cur, ["USB PnP"])

    def test_kinds(self):
        k = {i["label"]: i["kind"] for i in audio_out.list_outputs(Fake())}
        self.assertEqual(k["HDMI / DisplayPort · HDMI"], "hdmi")
        self.assertEqual(k["USB PnP"], "usb")

    def test_set_changes_default_port_and_moves_streams(self):
        f = Fake()
        audio_out.set_output("alsa_output.pci.analog-stereo", "analog-output-headphones", f)
        self.assertIn(["set-default-sink", "alsa_output.pci.analog-stereo"], f.calls)
        self.assertIn(["set-sink-port", "alsa_output.pci.analog-stereo", "analog-output-headphones"], f.calls)
        self.assertIn(["move-sink-input", "12", "alsa_output.pci.analog-stereo"], f.calls)
        self.assertIn(["move-sink-input", "13", "alsa_output.pci.analog-stereo"], f.calls)

    def test_rejects_unknown_sink_and_port_without_running_anything_destructive(self):
        f = Fake()
        with self.assertRaises(audio_out.AudioOutError):
            audio_out.set_output("no-existe; rm -rf /", "", f)
        with self.assertRaises(audio_out.AudioOutError):
            audio_out.set_output("alsa_output.pci.analog-stereo", "puerto-inventado", f)
        self.assertFalse(any(c[0] in ("set-default-sink", "set-sink-port", "move-sink-input") for c in f.calls))

    def test_reports_pactl_failure(self):
        def failed(cmd, **kw):
            return types.SimpleNamespace(stdout="", stderr="No such entity", returncode=1)
        with self.assertRaisesRegex(audio_out.AudioOutError, "No such entity"):
            audio_out.list_outputs(failed)


if __name__ == "__main__":
    unittest.main()

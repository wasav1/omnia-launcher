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

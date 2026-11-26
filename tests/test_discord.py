import socket
import struct
import threading
import unittest

from omnia import discord


class FakeDiscord:
    """Servidor IPC de prueba sobre un par de sockets."""

    def __init__(self, ok=True):
        self.client, self.server = socket.socketpair()
        self.frames = []
        self.ok = ok
        threading.Thread(target=self._serve, daemon=True).start()

    def _serve(self):
        try:
            while True:
                op, data = discord.read_frame(self.server)
                self.frames.append((op, data))
                if op == discord.HANDSHAKE:
                    reply = {"evt": "READY", "data": {"user": {"username": "alex"}}} if self.ok else {"evt": "ERROR"}
                    self.server.sendall(discord.encode(discord.FRAME, reply))
                else:
                    self.server.sendall(discord.encode(discord.FRAME, {"evt": None, "data": {}}))
        except OSError:
            pass


class DiscordTests(unittest.TestCase):
    APP = "1234567890123456789"

    def make(self, enabled=True, app=APP, ok=True):
        self.fake = FakeDiscord(ok)
        self.settings = {"enabled": enabled, "app_id": app, "lang": "es"}
        return discord.DiscordPresence(lambda: dict(self.settings), connect=lambda: self.fake.client, clock=lambda: 1000)

    def test_frame_roundtrip(self):
        a, b = socket.socketpair()
        a.sendall(discord.encode(1, {"x": 1}))
        self.assertEqual(discord.read_frame(b), (1, {"x": 1}))
        a.sendall(struct.pack("<II", 1, 5_000_000))
        with self.assertRaises(OSError):
            discord.read_frame(b)

    def test_sets_and_clears_activity(self):
        p = self.make()
        p.set_game("Hades", 900)
        p._tick()
        self.assertTrue(p.connected)
        self.assertEqual(p.user, "alex")
        hs = self.fake.frames[0]
        self.assertEqual((hs[0], hs[1]["client_id"]), (discord.HANDSHAKE, self.APP))
        act = self.fake.frames[1][1]["args"]["activity"]
        self.assertEqual((act["details"], act["timestamps"]["start"]), ("Jugando a Hades", 900))
        p._tick()                                           # sin cambios: no reenvía
        self.assertEqual(len(self.fake.frames), 2)
        p.set_game(None)
        p._tick()
        self.assertIsNone(self.fake.frames[2][1]["args"]["activity"])

    def test_disabled_or_bad_id_never_connects(self):
        for kw in ({"enabled": False}, {"app": "abc"}, {"app": ""}):
            p = self.make(**kw)
            p.set_game("X")
            p._tick()
            self.assertFalse(p.connected)
            self.assertEqual(self.fake.frames, [])

    def test_rejected_app_id_backs_off(self):
        p = self.make(ok=False)
        p._tick()
        self.assertFalse(p.connected)
        self.assertGreater(p._next_try, 1000)

    def test_disabling_clears_presence(self):
        p = self.make()
        p.set_game("Hades")
        p._tick()
        self.settings["enabled"] = False
        p._tick()
        self.assertFalse(p.connected)
        self.assertIsNone(self.fake.frames[-1][1]["args"]["activity"])

    def test_socket_paths_cover_flatpak(self):
        paths = discord.socket_paths({"XDG_RUNTIME_DIR": "/run/user/1000"})
        self.assertIn("/run/user/1000/discord-ipc-0", paths)
        self.assertIn("/run/user/1000/app/com.discordapp.Discord/discord-ipc-0", paths)


if __name__ == "__main__":
    unittest.main()

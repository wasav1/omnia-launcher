import json
import subprocess
import tempfile
import unittest
from pathlib import Path

from omnia.stores.amazon import Amazon
from omnia.stores.base import StoreError, pasted_code
from omnia.stores.gog import Gog

GCODE = "Abc_123-" * 4


class FakeGogdl:
    def __init__(self, auth_file_getter):
        self.calls = []

    def __call__(self, cmd, **kw):
        self.calls.append(cmd)
        auth = Path(cmd[cmd.index("--auth-config-path") + 1])
        if "--code" in cmd:
            if cmd[-1] != GCODE:
                return subprocess.CompletedProcess(cmd, 1, "", "bad")
            auth.write_text("{}")
            return subprocess.CompletedProcess(cmd, 0, "{}", "")
        return subprocess.CompletedProcess(cmd, 0, json.dumps({"46899977096215655": {"access_token": "T0K", "user_id": "1"}}), "")


class FakeResp:
    def __init__(self, data):
        self.data = json.dumps(data).encode()

    def __enter__(self):
        return self

    def __exit__(self, *a):
        return False

    def read(self, n=-1):
        return self.data


def fake_opener(req, timeout=0):
    assert req.headers["Authorization"] == "Bearer T0K"
    if req.full_url.endswith("userData.json"):
        return FakeResp({"username": "wasav"})
    page = int(req.full_url.rsplit("=", 1)[1])
    return FakeResp({"totalPages": 2, "products": [
        {"id": 10 + page, "title": "Juego %d" % page, "image": "//images-2.gog-statics.com/abcdef0123456789", "worksOn": {"Linux": page == 1}},
        {"id": "x", "title": "malo"}]})


class GogTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.gog = Gog(Path(self.tmp.name), runner=FakeGogdl(None), tool="/bin/gogdl", opener=fake_opener)

    def test_pasted_url_login_and_library(self):
        self.assertFalse(self.gog.status()["logged_in"])
        st = self.gog.login("https://embed.gog.com/on_login_success?origin=client&code=" + GCODE)
        self.assertEqual((st["logged_in"], st["account"]), (True, "wasav"))
        self.assertEqual(self.gog.auth_file.stat().st_mode & 0o777, 0o600)
        lib = self.gog.library()
        self.assertEqual([g["id"] for g in lib], ["11", "12"])
        self.assertEqual(lib[0]["art"], "https://images-2.gog-statics.com/abcdef0123456789_product_card_v2_mobile_slider_639.jpg")
        self.assertTrue(lib[0]["linux"] and not lib[1]["linux"])
        self.assertFalse(self.gog.logout()["logged_in"])
        with self.assertRaises(StoreError):
            self.gog.library()

    def test_bad_codes(self):
        for bad in ("", "x", "https://embed.gog.com/?foo=1", "a;rm -rf" * 4):
            with self.assertRaises(StoreError):
                self.gog.login(bad)
        with self.assertRaises(StoreError):
            self.gog.login("Z" * 30)


class FakeNile:
    def __init__(self):
        self.logged = False
        self.calls = []

    def __call__(self, cmd, **kw):
        self.calls.append((cmd, kw["env"]["XDG_CONFIG_HOME"]))
        a = cmd[1:]
        out, rc = "", 0
        if a[:2] == ["auth", "--status"]:
            out = json.dumps({"Username": "ana" if self.logged else "<not logged in>", "LoggedIn": self.logged})
        elif a[:2] == ["auth", "--login"]:
            out = json.dumps({"client_id": "cid", "code_verifier": "ver", "serial": "SER", "url": "https://amazon.com/ap/signin?x=1"})
        elif a[0] == "register":
            self.logged = a[a.index("--code") + 1] == "GOODCODE12"
            rc = 0 if self.logged else 1
        elif a[:2] == ["auth", "--logout"]:
            self.logged = False
        elif a[:2] == ["library", "list"]:
            lst = [{"id": "amzn1.B", "product": {"title": "Zed", "productDetail": {"iconUrl": "https://m.media-amazon.com/i.png"}}},
                   {"id": "amzn1.A", "product": {"title": "Alfa", "productDetail": {"iconUrl": "http://evil/x.png"}}}]
            out = json.dumps(lst[1:] if "--installed" in a else lst)
        return subprocess.CompletedProcess(cmd, rc, out, "")


class AmazonTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.fake = FakeNile()
        self.az = Amazon(Path(self.tmp.name), runner=self.fake, tool="/bin/nile")

    def test_flow(self):
        with self.assertRaises(StoreError):
            self.az.login("GOODCODE12")
        self.assertTrue(self.az.login_url().startswith("https://amazon.com/"))
        st = self.az.login("https://www.amazon.com/?openid.oa2.authorization_code=GOODCODE12&x=1")
        self.assertEqual((st["logged_in"], st["account"]), (True, "ana"))
        reg = [c for c in self.fake.calls if c[0][1] == "register"][0][0]
        self.assertEqual(reg[reg.index("--code-verifier") + 1], "ver")
        self.assertTrue(all(c[1] == str(Path(self.tmp.name) / "nile") for c in self.fake.calls))
        lib = self.az.library()
        self.assertEqual([(g["title"], g["installed"], bool(g["art"])) for g in lib], [("Alfa", True, False), ("Zed", False, True)])
        self.assertFalse(self.az.logout()["logged_in"])

    def test_rejected_code(self):
        self.az.login_url()
        with self.assertRaises(StoreError):
            self.az.login("BADCODE123")


class PastedTests(unittest.TestCase):
    def test_pasted_code(self):
        self.assertEqual(pasted_code("https://x/?code=ABCDEFGH12", ("code",), r"[A-Z0-9]{8,20}"), "ABCDEFGH12")
        with self.assertRaises(StoreError):
            pasted_code("https://x/?code=a b", ("code",), r"[A-Z0-9]{8,20}")


if __name__ == "__main__":
    unittest.main()

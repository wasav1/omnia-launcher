"""Entrega 6: Ubisoft Connect y EA app — inicio de sesión, biblioteca, lanzador en Wine y juegos instalados (sin red)."""
import json
import os
import tempfile
import time
import unittest
from pathlib import Path
from unittest import mock

from omnia import security
from omnia.api import Api, ApiError
from omnia.games.launcher_games import LauncherGamesDetector
from omnia.store import Store
from omnia.stores import ea, launchers, ubisoft
from omnia.stores.base import StoreError

ROOT = Path(__file__).resolve().parents[1]
UBI_EXE = "drive_c/Program Files (x86)/Ubisoft/Ubisoft Game Launcher/UbisoftConnect.exe"
EA_EXE = "drive_c/Program Files/Electronic Arts/EA Desktop/EA Desktop/EADesktop.exe"


def make_prefix(path: Path, exe: str, reg="") -> Path:
    (path / exe).parent.mkdir(parents=True, exist_ok=True)
    (path / exe).write_bytes(b"MZ")
    (path / "system.reg").write_text(reg)
    return path


UBI_REG = ('[Software\\\\Wow6432Node\\\\Ubisoft\\\\Launcher\\\\Installs\\\\2688] 1795845748\n'
           '"InstallDir"="C:/Program Files (x86)/Ubisoft/Ubisoft Game Launcher/games/WATCH_DOGS2/"\n')


class Launchers(unittest.TestCase):
    def setUp(self):
        self.tmp = Path(self.enterContext(tempfile.TemporaryDirectory()))
        launchers.forget()
        self.addCleanup(launchers.forget)
        self.home = self.tmp / "home"
        self.home.mkdir()
        patcher = mock.patch.object(launchers, "_home", return_value=self.home)
        patcher.start()
        self.addCleanup(patcher.stop)
        mock.patch.object(launchers, "_lutris_rows", return_value=[]).start()
        self.addCleanup(mock.patch.stopall)

    def test_finds_launchers_in_the_chosen_route_and_their_games(self):
        route = self.tmp / "JUEGOS"
        prefix = make_prefix(route / "Lutris/ubisoft-connect", UBI_EXE, UBI_REG)
        (prefix / "drive_c/Program Files (x86)/Ubisoft/Ubisoft Game Launcher/games/WATCH_DOGS2").mkdir(parents=True)
        eap = make_prefix(route / "PC", EA_EXE)
        game = eap / "drive_c/Program Files/EA Games/Dead Space/__Installer"
        game.mkdir(parents=True)
        (game / "installerdata.xml").write_text("<DiPManifest><contentIDs><contentID>1234567</contentID>"
                                                "<contentID>7654321</contentID></contentIDs></DiPManifest>")
        found = launchers.find("ubisoft", [route])
        self.assertEqual([f["prefix"] for f in found], [str(prefix)])
        games = launchers.installed_games("ubisoft", str(prefix))
        self.assertEqual((games[0]["id"], games[0]["title"]), ("2688", "WATCH DOGS2"))
        self.assertTrue(os.path.isdir(games[0]["folder"]))
        self.assertEqual(launchers.installed_games("ea", str(launchers.find("ea", [route])[0]["prefix"])),
                         [{"id": "1234567,7654321", "title": "Dead Space", "folder": str(game.parent)}])
        self.assertEqual(launchers.find("ea", [self.tmp / "otro"]), [])

    def test_detector_skips_games_lutris_already_lists(self):
        route = self.tmp / "JUEGOS"
        prefix = make_prefix(route / "U", UBI_EXE, UBI_REG)
        (prefix / "drive_c/Program Files (x86)/Ubisoft/Ubisoft Game Launcher/games/WATCH_DOGS2").mkdir(parents=True)
        store = Store(self.tmp / "cfg")
        (self.tmp / "cfg").mkdir(exist_ok=True)
        (self.tmp / "cfg/config.json").write_text(json.dumps({"install_root": str(route)}))
        with mock.patch.object(launchers, "search_roots", return_value=[str(route)]):
            games = LauncherGamesDetector(store).detect()
            self.assertEqual(len(games), 1)
            port = games[0]["ports"][0]
            self.assertEqual(games[0]["store_id"], {"store": "ubisoft", "id": "2688"})
            self.assertIn("umu-run", port["launch"])
            self.assertEqual(port["launch"][-1], "uplay://launch/2688/0")
            self.assertIn("WINEPREFIX=" + str(prefix), port["launch"])
            launchers.forget()
            with mock.patch.object(launchers, "_lutris_rows", return_value=[("Watch Dogs 2", "watch-dogs-2", str(prefix))]):
                self.assertEqual(LauncherGamesDetector(store).detect(), [])


def fake_open(responses):
    """opener falso: devuelve la siguiente respuesta (dict o excepción) y guarda las peticiones."""
    calls = []

    class Resp:
        def __init__(self, data): self.data = json.dumps(data).encode()
        def read(self, n=-1): return self.data
        def __enter__(self): return self
        def __exit__(self, *a): return False

    def opener(req, timeout=30):
        calls.append(req)
        nxt = responses.pop(0)
        if isinstance(nxt, Exception):
            raise nxt
        return Resp(nxt)
    return opener, calls


class UbisoftStore(unittest.TestCase):
    def setUp(self):
        self.tmp = Path(self.enterContext(tempfile.TemporaryDirectory()))

    def raw(self):
        login = {"ticket": "T" * 40, "sessionId": "abcd-1234-efgh", "userId": "user-1234-5678", "nameOnPlatform": "Jugador"}
        return json.dumps({"loginData": json.dumps(login), "rememberMe": json.dumps({"rememberMeTicket": "R" * 40}), "lastProfile": None})

    def test_login_saves_a_private_session_and_lists_pc_games(self):
        opener, calls = fake_open([
            {"ticket": "N" * 40, "sessionId": "abcd-1234-efgh"},
            {"data": {"viewer": {"ownedGames": {"nodes": [
                {"id": "g1", "spaceId": "space-0001", "name": "Far Cry 5", "coverUrl": "https://ubiservices.cdn.ubi.com/a.jpg",
                 "viewer": {"meta": {"ownedPlatformGroups": [[{"type": "PC"}]]}}},
                {"id": "g2", "spaceId": "space-0002", "name": "Solo consola", "viewer": {"meta": {"ownedPlatformGroups": [[{"type": "PS4"}]]}}}]}}}},
        ])
        store = ubisoft.Ubisoft(self.tmp, opener=opener)
        st = store.login(self.raw())
        self.assertEqual((st["logged_in"], st["account"]), (True, "Jugador"))
        self.assertEqual(oct(store.file.stat().st_mode & 0o777), "0o600")
        self.assertEqual(calls[0].get_method(), "PUT")
        self.assertEqual(json.loads(store.file.read_text())["ticket"], "N" * 40)
        games = store.library()
        self.assertEqual([g["title"] for g in games], ["Far Cry 5"])
        self.assertTrue(calls[1].full_url.startswith("https://public-ubiservices.ubi.com/"))
        self.assertEqual(calls[1].headers["Authorization"], "Ubi_v1 t=" + "N" * 40)

    def test_expired_ticket_uses_remember_me_and_a_bad_session_is_rejected(self):
        opener, calls = fake_open([OSError("401"), {"ticket": "M" * 40, "sessionId": "abcd-1234-efgh"}])
        store = ubisoft.Ubisoft(self.tmp, opener=opener)
        store.login(self.raw())
        self.assertEqual(calls[1].headers["Authorization"], "rm_v1 t=" + "R" * 40)
        with self.assertRaises(StoreError):
            ubisoft.Ubisoft(self.tmp, opener=fake_open([OSError("x"), OSError("y")])[0]).login(self.raw())
        self.assertFalse(store.file.exists())
        for bad in ("", "{}", json.dumps({"loginData": "{\"ticket\": \"x\"}"})):
            with self.assertRaises(StoreError):
                ubisoft.parse_login(bad)


class EaStore(unittest.TestCase):
    def setUp(self):
        self.tmp = Path(self.enterContext(tempfile.TemporaryDirectory()))

    def test_token_page_login_and_library(self):
        opener, calls = fake_open([
            {"data": {"me": {"player": {"displayName": "JugadorEA"}}}},
            {"data": {"me": {"ownedGameProducts": {"next": None, "items": [
                {"originOfferId": "Origin.OFR.50.0001", "product": {"baseItem": {"gameType": "BASE_GAME"}}},
                {"originOfferId": "Origin.OFR.50.0002", "product": {"baseItem": {"gameType": "EXPANSION"}}}]}}}},
            {"data": {"legacyOffers": [{"offerId": "Origin.OFR.50.0001", "contentId": "1234567"}],
                      "gameProducts": {"items": [{"originOfferId": "Origin.OFR.50.0001", "baseItem": {"title": "Dead Space",
                                       "packArt": {"largestImage": {"path": "https://drh.img.ea.com/x.jpg"}}}}]}}},
        ])
        store = ea.Ea(self.tmp, opener=opener)
        page = 'Algo {"access_token":"' + "A" * 60 + '","token_type":"Bearer","expires_in":"3599"}'
        st = store.login(page)
        self.assertEqual((st["logged_in"], st["account"], st["token_expired"]), (True, "JugadorEA", False))
        self.assertEqual(calls[0].headers["Authorization"], "Bearer " + "A" * 60)
        self.assertEqual(oct(store.file.stat().st_mode & 0o777), "0o600")
        session = json.loads(store.file.read_text())
        session["expiresAt"] = time.time() - 5
        store.file.write_text(json.dumps(session))
        self.assertTrue(store.status()["token_expired"])
        self.assertEqual([(g["id"], g["title"]) for g in store.library()], [("1234567", "Dead Space")])   # sin red: la lista guardada
        with self.assertRaises(StoreError):
            ea.parse_token("<html>login</html>")


class ApiRoutes(unittest.TestCase):
    def setUp(self):
        self.tmp = Path(self.enterContext(tempfile.TemporaryDirectory()))
        self.api = Api(Store(self.tmp / "cfg"), security.new_token(self.tmp / "run"), [], fs_roots=[self.tmp], scan_fn=lambda: [])
        self.addCleanup(self.api.package_installs.shutdown)
        self.addCleanup(self.api.httpd.server_close)
        launchers.forget()
        self.addCleanup(launchers.forget)

    def test_both_stores_are_listed_with_web_login(self):
        ids = {s["id"]: s for s in self.api.stores_list({})["stores"]}
        self.assertTrue(ids["ubisoft"]["web_login"] and ids["ea"]["web_login"])
        self.assertFalse(ids["ubisoft"]["logged_in"])

    def test_launcher_state_prefers_the_chosen_route_and_install_opens_the_launcher(self):
        route = self.tmp / "JUEGOS"
        make_prefix(route / "PC", UBI_EXE)
        self.api._update_config(install_root=str(route))
        with mock.patch.object(launchers, "search_roots", return_value=[str(route)]), \
                mock.patch.object(launchers, "_lutris_rows", return_value=[]), \
                mock.patch.object(launchers, "_home", return_value=self.tmp / "h"):
            st = self.api.stores_launcher({"store": "ubisoft"})
            self.assertTrue(st["installed"])
            self.assertTrue(st["found"][0]["inRoute"])
            self.assertEqual(st["target"], str(route / "_Prefijos/ubisoft-connect"))
            with mock.patch("omnia.launcher.launch") as run:
                out = self.api.stores_install({"_body": {"store": "ubisoft", "id": "space-0001"}})
            self.assertTrue(out["launcher"])
            self.assertIn("umu-run", run.call_args.args[0]["launch"])
            ea_state = self.api.stores_launcher({"store": "ea"})
            self.assertFalse(ea_state["installed"])
            with self.assertRaises(ApiError):
                self.api.stores_launcher_open({"_body": {"store": "ea", "id": "1234567"}})
        with self.assertRaises(ApiError):
            self.api.stores_launcher({"store": "steam"})


class UiTests(unittest.TestCase):
    def test_login_window_captures_both_stores(self):
        text = (ROOT / "ui/qml/StoreLogin.qml").read_text()
        self.assertTrue("PRODloginData" in text and "accounts.ea.com/connect/auth" in text, "StoreLogin sin Ubisoft/EA")
        for name in ("ManagerStores.qml", "OmniaBigSettings.qml"):
            self.assertTrue('"ubisoft"' in (ROOT / "ui/qml" / name).read_text(), name)


if __name__ == "__main__":
    unittest.main()

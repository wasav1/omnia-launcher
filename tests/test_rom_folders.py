import shutil
import tempfile
import unittest
from pathlib import Path
from unittest import mock

from omnia import manual, roms, service
from omnia.api import Api, ApiError
from omnia.games import refresh as games_refresh
from omnia.games.rom_folders import RomFolderDetector, clean_title
from omnia.store import Store


def n64_rom(path: Path, title=b"TEST GAME", code=b"NTSE"):
    data = bytearray(0x1000)
    data[0:4] = b"\x80\x37\x12\x40"
    data[0x20:0x34] = title.ljust(20, b" ")
    data[0x3B:0x3F] = code
    path.write_bytes(bytes(data))


class Base(unittest.TestCase):
    def setUp(self):
        self.tmp = Path(tempfile.mkdtemp())
        self.addCleanup(shutil.rmtree, self.tmp, True)
        self.roms = self.tmp / "roms"
        self.roms.mkdir()
        n64_rom(self.roms / "A Bug_s Life (U) [!].z64", b"A BUGS LIFE", b"NBYE")
        n64_rom(self.roms / "Banjo-Kazooie (U) [!].n64", b"BANJO-KAZOOIE", b"NB7E")
        (self.roms / "notas.txt").write_text("no es una ROM")
        self.store = Store(self.tmp / "cfg")

    def detector(self):
        return RomFolderDetector(self.store, folders_fn=lambda: [str(self.roms)])


class Titles(unittest.TestCase):
    def test_clean_title(self):
        self.assertEqual(clean_title("A Bug_s Life (U) [!].z64"), "A Bug's Life")
        self.assertEqual(clean_title("All Star Tennis 99 (U) (!).n64"), "All Star Tennis 99")
        self.assertEqual(clean_title("007 - GoldenEye.v64"), "007 - GoldenEye")
        self.assertEqual(clean_title("(U).z64", "Fallback"), "Fallback")
        self.assertEqual(clean_title("Legend of Zelda, The - Ocarina of Time (U) (V1.0) [!].z64"), "The Legend of Zelda - Ocarina of Time")
        self.assertEqual(clean_title("Bug's Life, A (U).z64"), "A Bug's Life")


class Detector(Base):
    def test_detects_roms_without_any_emulator(self):
        with mock.patch.object(roms, "available_emulators", return_value=[]):
            games = self.detector().detect()
        self.assertEqual(sorted(g["name"] for g in games), ["A Bug's Life", "Banjo-Kazooie"])
        bug = next(g for g in games if g["name"] == "A Bug's Life")
        port = bug["ports"][0]
        self.assertEqual((bug["auto"], bug["platform"], port["launch"]), ("roms", "n64", []))
        self.assertEqual((port["rom"]["internalId"], port["rom"]["internalIdType"]), ("NBYE", "n64"))
        self.assertTrue(games_refresh.port_installed(port))          # existe la ROM: se muestra y se puede pulsar Jugar

    def test_ids_are_stable_and_refresh_adds_and_removes(self):
        det = self.detector()
        first = {g["id"] for g in det.detect()}
        self.assertEqual(first, {g["id"] for g in self.detector().detect()})
        with mock.patch.object(roms, "available_emulators", return_value=[]):
            self.assertEqual(games_refresh.refresh(self.store, [det])["added"], 2)
            n64_rom(self.roms / "Extra.z64", b"EXTRA", b"NEXE")
            self.assertEqual(games_refresh.refresh(self.store, [det])["added"], 1)     # carpeta modificada: se vuelve a leer
            (self.roms / "Extra.z64").unlink()
            self.assertEqual(games_refresh.refresh(self.store, [det])["removed"], 1)

    def test_no_folders_no_games_and_manual_rom_is_not_duplicated(self):
        self.assertEqual(RomFolderDetector(self.store, folders_fn=lambda: []).detect(), [])
        manual_rom = str(self.roms / "Banjo-Kazooie (U) [!].n64")
        self.store.set_games([{"id": "manual-banjo", "name": "Banjo", "ports": [{"id": "p", "check": manual_rom}]}])
        names = [g["name"] for g in self.detector().detect()]
        self.assertEqual(names, ["A Bug's Life"])


class Launch(Base):
    def _port(self):
        game = self.detector().detect()[0]
        return game, game["ports"][0]

    def test_resolve_needs_an_emulator_and_says_which(self):
        _, port = self._port()
        with mock.patch.object(roms, "available_emulators", return_value=[]):
            with self.assertRaises(manual.ManualError) as ctx:
                manual.resolve_rom_launch(port, [str(self.tmp)])
        self.assertIn("Nintendo 64", str(ctx.exception))
        self.assertIn("Gopher64", str(ctx.exception))

    def test_resolve_builds_the_launch_when_an_emulator_appears(self):
        _, port = self._port()
        with mock.patch.object(roms, "available_emulators", return_value=[{"id": "retroarch", "label": "RetroArch"}]), \
                mock.patch.object(roms, "launch_command", return_value=(["retroarch", "-L", "core", port["check"]], "RetroArch")), \
                mock.patch.object(roms, "_find_retroarch_core", return_value="core"):
            resolved = manual.resolve_rom_launch(port, [str(self.tmp)])
        self.assertEqual((resolved["name"], resolved["rom"]["emulator"]), ("RetroArch", "retroarch"))
        self.assertEqual(resolved["launch"][0], "retroarch")
        self.assertEqual(port["launch"], [])                              # la entrada original no se modifica

    def test_api_launch_reports_missing_emulator_and_saves_the_resolution(self):
        game = self.detector().detect()[0]
        self.store.set_games([game])
        launched = []
        api = Api(self.store, "t", [], scan_fn=list, launch_fn=lambda p, gid, **kw: launched.append((p, gid)))
        self.addCleanup(api.httpd.server_close)
        with mock.patch.object(roms, "available_emulators", return_value=[]):
            with self.assertRaises(ApiError) as ctx:
                api.launch({"id": game["id"], "port": game["ports"][0]["id"]})
        self.assertEqual(ctx.exception.code, 409)
        self.assertIn("Instala", ctx.exception.msg)
        self.assertEqual(launched, [])
        with mock.patch.object(roms, "available_emulators", return_value=[{"id": "retroarch", "label": "RetroArch"}]), \
                mock.patch.object(roms, "launch_command", return_value=(["retroarch", game["ports"][0]["check"]], "RetroArch")):
            api.launch({"id": game["id"], "port": game["ports"][0]["id"]})
        self.assertEqual(launched[0][0]["launch"][0], "retroarch")
        self.assertEqual(self.store.games()[0]["ports"][0]["rom"]["emulator"], "retroarch")


class ManualAdd(Base):
    def test_add_rom_without_emulator(self):
        entry = manual.add_rom_game(self.store, {"name": "Bug", "path": str(self.roms / "A Bug_s Life (U) [!].z64"), "system": "n64", "emulator": ""}, [str(self.tmp)])
        self.assertEqual(entry["ports"][0]["launch"], [])
        self.assertEqual(entry["ports"][0]["rom"]["system"], "n64")
        self.assertTrue(games_refresh.port_installed(entry["ports"][0]))


class LinkById(Base):
    def test_rom_is_linked_by_header_id_and_never_overrides_a_valid_ficha(self):
        det = self.detector()
        self.store.set_games(det.detect())
        index = {("n64", "NBYE"): "a-bugs-life"}
        self.assertEqual(service.link_roms_by_id(self.store, index), 1)
        links = {g["name"]: g.get("catalogSlug") for g in self.store.games()}
        self.assertEqual(links, {"A Bug's Life": "a-bugs-life", "Banjo-Kazooie": None})
        self.assertEqual(service.link_roms_by_id(self.store, {("n64", "NBYE"): "otra"}), 0)      # ya tiene una ficha


if __name__ == "__main__":
    unittest.main()


class SwitchTitleIds(unittest.TestCase):
    def setUp(self):
        self.tmp = Path(tempfile.mkdtemp())
        self.addCleanup(shutil.rmtree, self.tmp, True)

    def nsp(self, name: str, ticket: str | None):
        """NSP mínimo: contenedor PFS0 con un archivo .tik cuyo nombre es el Rights ID."""
        entries = [ticket + ".tik"] if ticket else ["datos.bin"]
        names = b"".join(e.encode() + b"\0" for e in entries)
        header = b"PFS0" + len(entries).to_bytes(4, "little") + len(names).to_bytes(4, "little") + b"\0\0\0\0"
        offset = 0
        for entry in entries:
            header += (0).to_bytes(8, "little") + (16).to_bytes(8, "little") + offset.to_bytes(4, "little") + b"\0\0\0\0"
            offset += len(entry) + 1
        path = self.tmp / name
        path.write_bytes(header + names + b"\0" * 64)
        return str(path)

    def test_title_id_from_ticket_and_from_file_name(self):
        path = self.nsp("juego.nsp", "0100AAAA0000B000" + "0" * 15 + "3")
        self.assertEqual(roms.switch_title_id(path), ("0100AAAA0000B000", "ticket"))
        path = self.nsp("Otro [0100BBBB0000C000].nsp", None)
        self.assertEqual(roms.switch_title_id(path), ("0100BBBB0000C000", "name"))
        xci = self.tmp / "Solo Nombre [0100CCCC0000D000].xci"
        xci.write_bytes(b"\0" * 64)
        self.assertEqual(roms.switch_title_id(str(xci)), ("0100CCCC0000D000", "name"))
        self.assertEqual(roms.switch_title_id(self.nsp("sin_id.nsp", None)), ("", ""))

    def test_switch_2_is_told_apart_and_updates_are_not_games(self):
        self.assertEqual((roms.switch_kind("0100AAAA0000B000"), roms.switch_kind("0400AAAA0000B000")), ("switch", "switch2"))
        self.assertEqual((roms.platform_for("switch", "switch"), roms.platform_for("switch", "switch2"), roms.platform_for("n64")), ("sw1", "sw2", "n64"))
        base = roms.inspect_file(self.nsp("base.nsp", "0100AAAA0000B000" + "0" * 15 + "1"), [str(self.tmp)], include_emulators=False)
        self.assertEqual((base["system"], base["internalId"], base["internalIdType"], base["confidence"]), ("switch", "0100AAAA0000B000", "switch", "header"))
        sw2 = roms.inspect_file(self.nsp("sw2.nsp", "0400AAAA0000B000" + "0" * 15 + "1"), [str(self.tmp)], include_emulators=False)
        self.assertEqual(sw2["internalIdType"], "switch2")
        self.assertIsNone(roms.inspect_file(self.nsp("update.nsp", "0100AAAA0000B800" + "0" * 15 + "1"), [str(self.tmp)], include_emulators=False))
        self.assertIsNone(roms.inspect_file(self.nsp("dlc.nsp", "0100AAAA0000B001" + "0" * 15 + "1"), [str(self.tmp)], include_emulators=False))

    def test_detector_puts_a_switch_2_dump_on_the_switch_2_platform(self):
        self.nsp("Zelda sw2.nsp", "0400AAAA0000B000" + "0" * 15 + "1")
        self.nsp("Zelda sw1.nsp", "0100AAAA0000C000" + "0" * 15 + "1")
        det = RomFolderDetector(None, folders_fn=lambda: [str(self.tmp)])
        with mock.patch.object(roms, "available_emulators", return_value=[]):
            games = {g["name"]: g for g in det.detect()}
        self.assertEqual((games["Zelda sw2"]["platform"], games["Zelda sw1"]["platform"]), ("sw2", "sw1"))
        self.assertEqual(games["Zelda sw2"]["ports"][0]["rom"]["internalIdType"], "switch2")
        self.assertIn("Switch 2", games["Zelda sw2"]["sub"])


class NameMatching(unittest.TestCase):
    CAT = [
        {"slug": "bug", "name": "A Bug's Life", "platforms": [{"slug": "n64"}]},
        {"slug": "mk64", "name": "Mario Kart 64", "platforms": [{"slug": "n64"}]},
        {"slug": "mk8", "name": "Mario Kart 8 Deluxe", "platforms": [{"slug": "switch"}]},
        {"slug": "zelda-oot", "name": "The Legend of Zelda: Ocarina of Time", "platforms": [{"slug": "n64"}]},
        {"slug": "zelda-mm", "name": "The Legend of Zelda: Majora's Mask", "platforms": [{"slug": "n64"}]},
    ]

    def link(self, name, platform="n64", fuzzy=True):
        from omnia import online_catalog as oc
        return oc.match_local_game({"name": name, "platform": platform}, self.CAT, fuzzy=fuzzy)

    def test_matches_by_words_ignoring_tags_and_stop_words(self):
        self.assertEqual(self.link("Legend of Zelda - Ocarina of Time (U) (V1.0) [!]"), "zelda-oot")
        self.assertEqual(self.link("Mario Kart 64 (USA)"), "mk64")
        self.assertEqual(self.link("A Bugs Life"), "bug")

    def test_does_not_guess(self):
        self.assertEqual(self.link("Mario Kart"), "")                                   # faltan palabras del juego
        self.assertEqual(self.link("The Legend of Zelda"), "")                          # ambiguo y incompleto
        self.assertEqual(self.link("Mario Kart 64 Mega Pack Edition Extreme Plus"), "")  # demasiadas palabras ajenas
        self.assertEqual(self.link("Mario Kart 64", platform="sw1"), "")                 # otra consola
        self.assertEqual(self.link("Legend of Zelda - Ocarina of Time (U) [!]", fuzzy=False), "")  # solo con ROMs

    def test_service_uses_words_only_for_roms(self):
        tmp = Path(tempfile.mkdtemp())
        self.addCleanup(shutil.rmtree, tmp, True)
        st = Store(tmp)
        st.set_games([
            {"id": "r", "name": "Mario Kart 64 (USA)", "platform": "n64", "ports": [{"id": "p", "rom": {"path": "/x"}}]},
            {"id": "m", "name": "Mario Kart 64 (USA)", "platform": "n64", "ports": [{"id": "p"}]},
        ])
        self.assertEqual(service.auto_link_catalog(st, self.CAT), 1)
        self.assertEqual({g["id"]: g.get("catalogSlug") for g in st.games()}, {"r": "mk64", "m": None})

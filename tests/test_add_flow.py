"""Entrega 4: añadir juegos desde una carpeta sin elegir el tipo, varios a la vez, y nombres parecidos para ficha y arte."""
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

from omnia import online_catalog
from omnia.api import Api, ApiError
from omnia.service import art_queries, sync_unlinked_art
from omnia.store import Store

ROOT = Path(__file__).resolve().parents[1]


def n64_rom(path: Path, title=b"TEST GAME"):
    rom = bytearray(0x1000)
    rom[0:4] = b"\x80\x37\x12\x40"
    rom[0x20:0x34] = title.ljust(20, b" ")
    rom[0x3B:0x3F] = b"NTSE"
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_bytes(bytes(rom))


def script(path: Path):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_bytes(b"#!/bin/sh\nexit 0\n")
    path.chmod(0o755)


class AddScanTests(unittest.TestCase):
    def setUp(self):
        self.root = Path(self.enterContext(tempfile.TemporaryDirectory()))
        self.store = Store(self.root / ".config")
        self.games = self.root / "Juegos"
        self.games.mkdir()
        self.api = Api(self.store, "token", fs_roots=[self.root], scan_fn=lambda: [])
        self.addCleanup(self.api.package_installs.shutdown)
        self.addCleanup(self.api.httpd.server_close)

    def test_scan_detects_ports_games_and_roms_with_their_type(self):
        script(self.games / "Longshot" / "bin" / "longshot")
        script(self.games / "Mi Juego" / "mijuego")
        n64_rom(self.games / "N64" / "Legend of Zelda, The - Ocarina of Time (U) [!].z64")
        n64_rom(self.games / "N64" / "Mario Kart 64 (U).z64", b"MARIOKART64")
        items = self.api.add_scan({"path": str(self.games)})["items"]
        types = {i["name"]: i["type"] for i in items}
        self.assertEqual(types["The Legend of Zelda: Ocarina of Time"], "port")
        self.assertEqual(types["Mario Kart 64"], "rom")
        self.assertIn("game", types.values())
        port = next(i for i in items if i["type"] == "port")
        self.assertEqual(port["template"], "longshot")
        zelda = next(i for i in items if i["type"] == "rom" and "Ocarina" in i["name"])
        self.assertEqual(zelda["portKey"], port["key"])          # la ROM sabe que su port está en la misma carpeta
        self.assertEqual([i["type"] for i in items], sorted((i["type"] for i in items), key=["port", "game", "rom"].index))

    def test_batch_adds_several_and_marks_them_as_existing(self):
        n64_rom(self.games / "Mario Kart 64 (U).z64", b"MARIOKART64")
        n64_rom(self.games / "Star Fox 64 (U).z64", b"STARFOX64")
        items = self.api.add_scan({"path": str(self.games)})["items"]
        self.assertEqual(len(items), 2)
        out = self.api.add_batch({"_body": {"items": items}})
        self.assertEqual(len(out["added"]), 2)
        self.assertEqual(out["failed"], [])
        again = self.api.add_scan({"path": str(self.games)})["items"]
        self.assertTrue(all(i["existingId"] for i in again))
        twice = self.api.add_batch({"_body": {"items": again[:1]}})
        self.assertEqual(twice["added"], [])
        self.assertEqual(len(twice["failed"]), 1)                 # ya estaba: se informa sin detener el lote

    def test_after_adding_a_rom_its_port_is_searched_in_the_libraries(self):
        n64_rom(self.games / "ROMs" / "Legend of Zelda, The - Ocarina of Time (U) [!].z64")
        script(self.root / "Otros" / "Ports" / "Longshot" / "bin" / "longshot")
        rom = next(i for i in self.api.add_scan({"path": str(self.games / "ROMs")})["items"])
        out = self.api.add_batch({"_body": {"items": [rom]}})
        self.assertEqual([p["template"] for p in out["portsFound"]], ["longshot"])

    def test_scan_rejects_folders_outside_the_libraries(self):
        with self.assertRaises(ApiError):
            self.api.add_scan({"path": "/usr"})
        with self.assertRaises(ApiError):
            self.api.add_batch({"_body": {"items": []}})


class SimilarNameTests(unittest.TestCase):
    def test_canonical_title_drops_marks_editions_and_roman_numerals(self):
        c = online_catalog.canonical_title
        self.assertEqual(c("The Witcher® 3: Wild Hunt – Game of the Year Edition"), "the witcher 3 wild hunt")
        self.assertEqual(c("Final Fantasy VII"), "final fantasy 7")
        self.assertEqual(c("The Elder Scrolls V: Skyrim Special Edition"), "the elder scrolls 5 skyrim")
        self.assertEqual(c("Ratchet & Clank"), "ratchet and clank")
        self.assertEqual(c("Pokémon Gold"), "pokemon gold")             # «gold» sola no es una edición

    def test_catalog_link_uses_similar_names_but_never_guesses(self):
        items = [{"slug": "witcher3", "name": "The Witcher 3: Wild Hunt", "platforms": [{"slug": "pc"}]},
                 {"slug": "gold", "name": "Pokémon Gold", "platforms": [{"slug": "game-boy-color"}]},
                 {"slug": "silver", "name": "Pokémon Silver", "platforms": [{"slug": "game-boy-color"}]}]
        game = {"name": "The Witcher® 3: Wild Hunt - Game of the Year Edition", "platform": "pc"}
        self.assertEqual(online_catalog.match_local_game(game, items, fuzzy=True), "witcher3")
        self.assertEqual(online_catalog.match_local_game({"name": "Pokemon", "platform": "gbc"}, items, fuzzy=True), "")

    def test_art_retries_with_the_canonical_title(self):
        self.assertEqual(art_queries("Skyrim® Special Edition"), ["Skyrim® Special Edition", "skyrim"])
        store = Store(Path(self.enterContext(tempfile.TemporaryDirectory())))
        game = {"id": "g", "name": "Skyrim® Special Edition", "platform": "pc", "src": "Manual", "ports": []}
        with patch("omnia.online_catalog.lookup_pc_artwork", side_effect=[{}, {}]) as lookup:
            sync_unlinked_art(store, game, {})
        self.assertEqual([c.args[0] for c in lookup.call_args_list], ["Skyrim® Special Edition", "skyrim"])


class AddWizardUiTests(unittest.TestCase):
    def test_desktop_wizard_has_no_type_picker_and_uses_the_unified_scan(self):
        text = (ROOT / "ui/qml/ManagerAddGame.qml").read_text()
        self.assertFalse("templateList" in text, "sigue la lista de tipos")
        self.assertFalse("Elige el tipo de juego" in text, "sigue la lista de tipos")
        self.assertTrue("api.addScan(" in text and "api.addBatch(" in text, "no usa el escaneo unificado")
        api = (ROOT / "ui/qml/Api.qml").read_text()
        self.assertIn('"/add/scan?path="', api)
        self.assertIn('"/add/batch"', api)


if __name__ == "__main__":
    unittest.main()

"""Detectores activos. Para añadir una fuente nueva: crear su módulo y listarlo aquí."""
from .bedrock import BedrockDetector
from .gfn import GeForceNowDetector
from .heroic import HeroicDetector
from .lutris import LutrisDetector
from .rom_folders import RomFolderDetector
from .steam import SteamDetector


def default_detectors(store=None) -> list:
    return [SteamDetector(), HeroicDetector(), LutrisDetector(), GeForceNowDetector(), RomFolderDetector(store), BedrockDetector(store)]

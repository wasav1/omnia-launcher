"""Detectores activos. Para añadir una fuente nueva: crear su módulo y listarlo aquí."""
from .heroic import HeroicDetector
from .lutris import LutrisDetector
from .steam import SteamDetector


def default_detectors() -> list:
    return [SteamDetector(), HeroicDetector(), LutrisDetector()]

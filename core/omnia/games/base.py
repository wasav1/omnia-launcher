"""Contrato de un detector de juegos.

Una fuente nueva es un archivo Python con una clase que hereda de Detector y cumple tres cosas:
  detect()                -> lista de juegos instalados de verdad (dicts en el formato de library.json)
  is_installed(g, port)   -> sigue instalado (para quitarlo solo al desinstalarse)
  launch (opcional)       -> por defecto se usa port["launch"]
El núcleo no cambia al añadir una fuente.
"""
import os


class Detector:
    name = "base"          # se guarda en game["auto"]; solo se tocan los juegos con ese valor
    label = ""             # texto para el usuario (game["src"])

    def detect(self) -> list:
        raise NotImplementedError

    def is_installed(self, game: dict, port: dict) -> bool:
        chk = port.get("check") or (port.get("launch") or [""])[0]
        return bool(port.get("launch")) and bool(chk) and os.path.exists(os.path.expanduser(chk))

    def is_running(self, game: dict, port: dict, cmdlines: list) -> bool:
        """Por defecto, port["proc"] es un texto que aparece en la línea de comando del juego en ejecución."""
        needle = port.get("proc") or ""
        return bool(needle) and any(needle in c for c in cmdlines)

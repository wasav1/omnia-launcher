"""Juegos de Ubisoft Connect y de la EA app instalados en prefijos de Wine (entrega 6).

Cada juego se lanza abriendo su lanzador en el prefijo con umu-run y la dirección del juego (`uplay://launch/<producto>/0`,
`origin2://game/launch?offerIds=…`). Los juegos que Lutris ya lista (mismo prefijo y mismo nombre) no se repiten.
"""
import hashlib
import os

from .. import online_catalog
from ..stores import launchers
from .base import Detector


class LauncherGamesDetector(Detector):
    name = "launchers"
    label = "Ubisoft / EA"

    def __init__(self, store=None):
        self.store = store

    def detect(self) -> list:
        roots = launchers.search_roots(self.store.dir if self.store is not None else None)
        lutris = {(os.path.realpath(d), online_catalog._name_key(n)) for n, _s, d in launchers._lutris_rows() if d and n}
        games, seen = [], set()
        for launcher, spec in launchers.LAUNCHERS.items():
            for where in launchers.find(launcher, roots):
                for item in launchers.installed_games(launcher, where["prefix"]):
                    key = online_catalog._name_key(item["title"])
                    if (where["prefix"], key) in lutris or (launcher, item["id"]) in seen or not item["folder"]:
                        continue
                    seen.add((launcher, item["id"]))
                    gid = launcher + "-" + hashlib.sha1((where["prefix"] + "|" + item["id"]).encode()).hexdigest()[:12]
                    uri = launchers.launch_uri(launcher, item["id"].split(",")[0])
                    games.append({
                        "id": gid, "name": item["title"], "sub": "PC · " + spec["name"], "platform": "pc", "src": spec["name"],
                        "auto": self.name, "art": {"slug": gid, "sgdb": item["title"]},
                        "store_id": {"store": launcher, "id": item["id"]},
                        "ports": [{"id": gid + "-main", "name": spec["name"], "chips": [spec["name"]],
                                   "launch": launchers.launch_argv(where["prefix"], where["exe"], uri),
                                   "cwd": os.path.dirname(where["exe"]), "check": item["folder"],
                                   "proc": os.path.basename(where["exe"])}]})
        return games

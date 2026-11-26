"""Apply explicitly chosen first-run settings through the local Omnia API."""

import json
import os
from pathlib import Path
import sys
import time
import urllib.request


def main(install_root, game_folder, scan):
    if not (install_root or game_folder or scan == "scan"):
        return
    token = Path(os.environ["XDG_RUNTIME_DIR"]) / "omnia" / "token"
    for _ in range(80):
        if token.is_file():
            break
        time.sleep(0.1)
    try:
        headers = {"Authorization": "Bearer " + token.read_text().strip(), "Content-Type": "application/json"}
    except OSError:
        print("Omnia se instaló. Abre Ajustes para completar la configuración de la biblioteca.")
        return

    def post(route, data):
        request = urllib.request.Request("http://127.0.0.1:47831" + route, json.dumps(data).encode(),
                                         headers, method="POST")
        with urllib.request.urlopen(request, timeout=8):
            return

    for route, body in (
        ("/settings/install-root", {"path": install_root} if install_root else None),
        ("/library/roots/set", {"action": "add", "path": game_folder} if game_folder else None),
        ("/library/refresh", {} if scan == "scan" else None),
    ):
        if body is not None:
            try:
                post(route, body)
            except OSError:
                print("La instalación terminó. No se pudo guardar un ajuste de biblioteca; puedes revisarlo en Ajustes.")
                return


if __name__ == "__main__":
    main(*sys.argv[1:])

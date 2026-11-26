"""Read the package payload shared by the graphical installer and the in-app updater."""

import io
from pathlib import Path
import re
import shutil
import tarfile

MARKER = b"# __OMNIA_SUITE_ARCHIVE__\n"
MAX_BUNDLE = 512 * 1024 * 1024
PACKAGES = ("omnia-core", "omnia-app", "omnia-hyprland")


def version(value):
    match = re.fullmatch(r"v?(\d{1,6})\.(\d{1,6})\.(\d{1,6})(?:-(\d{1,6}))?", str(value))
    if not match:
        raise ValueError("Versión de Omnia no válida.")
    a, b, c, revision = match.groups()
    return int(a), int(b), int(c), int(revision or 0)


def stage_packages(bundle, destination, expected):
    """Extract only the three expected regular package files, without running the installer."""
    with Path(bundle).open("rb") as source:
        header = source.read(16384)
        marker = header.find(b"\n" + MARKER)
        if marker < 0:
            raise ValueError("Formato de instalador desconocido.")
        source.seek(marker + 1 + len(MARKER))
        class Payload(io.RawIOBase):
            def readable(self):
                return True

            def readinto(self, data):
                return source.readinto(data)

        with tarfile.open(fileobj=Payload(), mode="r|gz") as archive:
            total = 0
            candidates = {}
            for member in archive:
                total += member.size
                if total > MAX_BUNDLE:
                    raise ValueError("El contenido del instalador excede el límite.")
                name = member.name
                if not name.startswith("packages/") or member.isdir():
                    continue
                match = re.fullmatch(r"packages/(omnia-core|omnia-app|omnia-hyprland)-([0-9.]+-[0-9]+)-(x86_64|any)\.pkg\.tar\.zst", name)
                if not member.isfile() or not match or match[1] in candidates:
                    raise ValueError("El instalador contiene paquetes no válidos.")
                actual = version(match[2])
                if actual[:3] != expected[:3] or (expected[3] and actual != expected):
                    raise ValueError("La versión del paquete no coincide con la publicación.")
                with archive.extractfile(member) as reader, (destination / Path(name).name).open("xb") as archive_out:
                    shutil.copyfileobj(reader, archive_out)
                candidates[match[1]] = (destination / Path(name).name, actual)
            if set(candidates) != set(PACKAGES) or len({v for _, v in candidates.values()}) != 1:
                raise ValueError("Faltan paquetes de la misma versión en el instalador.")
            return [candidates[name][0] for name in PACKAGES]

#!/usr/bin/env python3
"""Build the single x86-64 Omnia Game Suite installer from the Arch packages."""

import argparse
import os
from pathlib import Path
import shlex
import shutil
import subprocess
import sys
import tarfile
import tempfile

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "packaging" / "distros"))
from build_appimage import libraries

STUB = """#!/usr/bin/env bash
set -euo pipefail
self=$(readlink -f -- "$0")
line=$(awk '$0=="# __OMNIA_SUITE_ARCHIVE__" {print NR+1; exit}' "$self")
[[ -n $line ]] || exit 2
tmp=$(mktemp -d)
trap 'rm -rf -- "$tmp"' EXIT
tail -n +"$line" "$self" | tar xz -C "$tmp"
unset QT_QPA_PLATFORMTHEME
export QT_PLUGIN_PATH="$tmp/qt/plugins"
export QT_QPA_PLATFORM_PLUGIN_PATH="$tmp/qt/plugins/platforms"
export LD_LIBRARY_PATH="$tmp/qt/lib"
"$tmp/omnia-installer" "$tmp"
exit
# __OMNIA_SUITE_ARCHIVE__
"""


def bundle_qt(data):
    binary = data / "omnia-installer"
    flags = subprocess.check_output(["pkg-config", "--cflags", "--libs", "Qt6Widgets"], text=True)
    subprocess.run(["c++", "-fPIC", "-std=c++17", "-O2", str(ROOT / "packaging/suite/wizard.cpp"),
                    "-o", str(binary), *shlex.split(flags)], check=True)
    source = Path(subprocess.check_output(["qmake6", "-query", "QT_INSTALL_PLUGINS"], text=True).strip())
    plugins = [
        file for folder, names in {
            "platforms": ("libqwayland.so", "libqwayland-generic.so", "libqwayland-egl.so", "libqxcb.so", "libqoffscreen.so"),
            "imageformats": ("libqsvg.so",),
        }.items()
        for name in names if (file := source / folder / name).is_file()
    ]
    for folder in ("wayland-shell-integration", "wayland-graphics-integration-client", "wayland-decoration-client", "xcbglintegrations"):
        plugins += list((source / folder).glob("*.so"))
    if not any(p.name.startswith("libqwayland") for p in plugins):
        raise ValueError("No están los complementos Qt de Wayland.")
    lib = data / "qt/lib"
    lib.mkdir(parents=True)
    for plugin in plugins:
        target = data / "qt/plugins" / plugin.relative_to(source)
        target.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(plugin, target)
    for entry in [binary, *plugins]:
        for library in libraries(entry):
            target = lib / library.name
            if not target.is_file():
                shutil.copy2(library, target)
    for package in ("qt6-base", "qt6-wayland", "qt6-svg"):
        license_path = Path("/usr/share/licenses") / package
        if license_path.is_dir():
            shutil.copytree(license_path, data / "licenses" / package)


def main():
    sys.path.insert(0, str(ROOT / "core"))
    from omnia.suite_bundle import PACKAGES, version

    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--packages", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    if os.uname().machine != "x86_64":
        parser.error("El instalador de esta edición requiere x86-64.")
    archives = {}
    editions = set()
    for package in PACKAGES:
        matches = list(args.packages.glob(package + "-*.pkg.tar.zst"))
        if len(matches) != 1:
            parser.error(f"Se requiere un paquete {package} en {args.packages}.")
        package_file = matches[0]
        edition, arch = package_file.name[len(package) + 1:-len(".pkg.tar.zst")].rsplit("-", 1)
        if arch not in ("x86_64", "any"):
            parser.error(f"Arquitectura no admitida en {package_file.name}.")
        archives[package] = package_file
        editions.add(edition)
    if len(editions) != 1:
        parser.error("Los paquetes deben ser de la misma versión.")
    edition = editions.pop()
    release = ".".join(map(str, version(edition)[:3]))
    args.output.mkdir(exist_ok=True, parents=True)
    final = args.output / f"Omnia-Game-Suite-{release}-x86_64.run"
    with tempfile.TemporaryDirectory() as tmp:
        data = Path(tmp) / "payload"
        data.mkdir()
        (data / "packages").mkdir()
        (data / "version").write_text(edition + "\n")
        for script in ("apply.sh", "setup-library.py"):
            shutil.copy2(ROOT / "packaging/suite" / script, data / script)
        for archive in archives.values():
            shutil.copy2(archive, data / "packages" / archive.name)
        shutil.copy2(ROOT / "LICENSE", data / "LICENSE")
        shutil.copy2(ROOT / "assets/branding/omnia-game-suite.svg", data / "omnia-game-suite.svg")
        bundle_qt(data)
        subprocess.run(["lrelease6", str(ROOT / "packaging/suite/wizard_en_US.ts"),
                        "-qm", str(data / "wizard_en_US.qm")], check=True)
        partial = final.with_suffix(".tmp")
        with partial.open("wb") as stream:
            stream.write(STUB.encode())
            # Gzip begins at the marker; tar offsets must start at zero.
            import gzip
            with gzip.GzipFile(fileobj=stream, mode="wb", compresslevel=6) as compressed:
                with tarfile.open(fileobj=compressed, mode="w|") as tar:
                    for file in sorted(data.iterdir()):
                        tar.add(file, arcname=file.name)
        partial.chmod(0o755)
        partial.replace(final)
    print(final)


if __name__ == "__main__":
    main()

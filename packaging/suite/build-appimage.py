#!/usr/bin/env python3
"""Package the Omnia Game Suite installer as an AppImage."""
import argparse
import os
from pathlib import Path
import shutil
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[2]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--installer", type=Path, required=True)
    parser.add_argument("--appimagetool", type=Path, required=True)
    parser.add_argument("--runtime", type=Path, required=True)
    args = parser.parse_args()

    target = args.installer.with_suffix(".AppImage").resolve()
    with tempfile.TemporaryDirectory(prefix="omnia-appimage-") as work:
        app = Path(work) / "Omnia.AppDir"
        app.mkdir()
        shutil.copy2(args.installer, app / "omnia-installer")
        subprocess.run(
            ["rsvg-convert", "-w", "256", "-h", "256",
             str(ROOT / "assets/branding/omnia-icon.svg"), "-o", str(app / "omnia.png")],
            check=True,
        )
        (app / ".DirIcon").symlink_to("omnia.png")
        (app / "omnia.desktop").write_text(
            "[Desktop Entry]\nType=Application\nName=Omnia Game Suite\n"
            "Exec=omnia-installer\nIcon=omnia\nTerminal=false\nCategories=Game;\n"
        )
        (app / "AppRun").write_text('#!/usr/bin/env bash\nexec "$(dirname -- "$0")/omnia-installer" "$@"\n')
        (app / "AppRun").chmod(0o755)
        subprocess.run(
            [str(args.appimagetool.resolve()), "--appimage-extract-and-run", "--no-appstream",
             "--runtime-file", str(args.runtime.resolve()), str(app), str(target)],
            env={**os.environ, "ARCH": "x86_64"},
            check=True,
        )
    target.chmod(0o755)
    print(target)


if __name__ == "__main__":
    main()

"""Checking and staging updates for the standalone Omnia Game Suite."""

import argparse
import hashlib
import json
import os
import platform
from pathlib import Path
import re
import subprocess
import tempfile
import tarfile
import threading
import time
import urllib.request

from . import paths, suite_bundle
from .big_mode import is_open
from .store import write_json_atomic

REPOSITORY = "wasav1/omnia-launcher"
RELEASE_API = f"https://api.github.com/repos/{REPOSITORY}/releases/latest"
NAME = re.compile(r"Omnia-Game-Suite-([0-9]+\.[0-9]+\.[0-9]+)-x86_64\.run")
CHECK_INTERVAL = 1800
SURFACES = ("desktop", "big-mode", "dux")


def installed_version():
    result = subprocess.run(["/usr/bin/pacman", "-Q", "omnia-app"], text=True, capture_output=True, timeout=5)
    return result.stdout.split()[1] if result.returncode == 0 and len(result.stdout.split()) == 2 else ""


def release_asset(data):
    if not isinstance(data, dict) or not isinstance(data.get("assets"), list):
        raise ValueError("La publicación no contiene archivos.")
    tag = data.get("tag_name", "")
    number = suite_bundle.version(tag)
    for asset in data["assets"]:
        if not isinstance(asset, dict):
            continue
        name = asset.get("name", "")
        match = NAME.fullmatch(name)
        url = f"https://github.com/{REPOSITORY}/releases/download/{tag}/{name}"
        digest = asset.get("digest") or ""
        size = asset.get("size")
        if (match and suite_bundle.version(match[1]) == number and asset.get("browser_download_url") == url
                and re.fullmatch(r"sha256:[0-9a-f]{64}", digest) and type(size) is int
                and 0 < size <= suite_bundle.MAX_BUNDLE):
            return {"tag": tag, "url": url, "size": size, "digest": digest[7:]}
    raise ValueError("La publicación no contiene un instalador verificable.")


def github_request(url):
    request = urllib.request.Request(url, headers={"User-Agent": "Omnia-Game-Suite", "Accept": "application/vnd.github+json"})
    return urllib.request.urlopen(request, timeout=20)


def digest_file(path):
    with path.open("rb") as stream:
        return hashlib.file_digest(stream, "sha256").hexdigest()


class SuiteUpdater:
    def __init__(self):
        self.directory = paths.cache_dir() / "suite-update"
        self.bundle = self.directory / "update.run"
        self.receipt = self.directory / "verified.json"
        self.result = self.directory / "result.json"
        self.lock = threading.RLock()
        self.checked = False
        self.checked_at = 0.0
        self.asset = None
        self.phase = "idle"
        self.progress = 0
        self.error = ""
        self.installed = ""
        self.visible_surfaces = {}

    def snapshot(self, surface="", visible=True):
        with self.lock:
            if surface in SURFACES:
                if visible:
                    self.visible_surfaces[surface] = time.monotonic()
                else:
                    self.visible_surfaces.pop(surface, None)
            if self.phase not in ("checking", "downloading", "ready", "applying") and (
                    not self.checked or time.monotonic() - self.checked_at > CHECK_INTERVAL):
                self.checked = True
                self.checked_at = time.monotonic()
                self.phase = "checking"
                threading.Thread(target=self.check, daemon=True).start()
            if self.phase == "applying" and self.result.is_file():
                try:
                    result = json.loads(self.result.read_text())
                    self.phase = "ready"
                    self.error = result.get("error", "")
                except (OSError, ValueError):
                    pass
            return {"phase": self.phase, "current": self.installed,
                    "available": self.asset["tag"] if self.asset else "", "progress": self.progress, "error": self.error}

    def check(self):
        try:
            current = installed_version() if platform.machine() == "x86_64" else ""
            if not current:
                with self.lock:
                    self.phase = "idle"
                return
            with self.lock:
                self.installed = current
            if self.bundle.is_file() and self.receipt.is_file():
                try:
                    asset = release_asset({"tag_name": (saved := json.loads(self.receipt.read_text()))["tag"],
                                           "assets": [{"name": saved["url"].rsplit("/", 1)[-1],
                                                       "browser_download_url": saved["url"], "size": saved["size"],
                                                       "digest": "sha256:" + saved["digest"]}]})
                    if suite_bundle.version(asset["tag"]) > suite_bundle.version(current):
                        with self.lock:
                            self.asset = asset
                            self.phase = "ready"
                        return
                except (OSError, ValueError, KeyError, TypeError):
                    pass
            with github_request(RELEASE_API) as response:
                data = json.loads(response.read(512 * 1024))
            if not isinstance(data, dict):
                raise ValueError("Respuesta de versiones no válida.")
            tag = data.get("tag_name", "")
            if not data.get("draft") and not data.get("prerelease") and suite_bundle.version(tag) > suite_bundle.version(current):
                with self.lock:
                    self.asset = release_asset(data)
                    self.phase = "available"
                    self.error = ""
            else:
                with self.lock:
                    self.asset = None
                    self.phase = "idle"
                    self.error = ""
        except (OSError, ValueError, TypeError, subprocess.SubprocessError):
            with self.lock:
                self.phase = "error"
                self.error = "No se pudo comprobar la versión de Omnia."

    def start(self):
        with self.lock:
            if self.phase == "downloading":
                return
            if not self.asset or self.phase not in ("available", "error"):
                raise ValueError("No hay una actualización lista para descargar.")
            self.phase, self.progress, self.error = "downloading", 0, ""
            threading.Thread(target=self.download, args=(self.asset,), daemon=True).start()

    def download(self, asset):
        try:
            self.directory.mkdir(parents=True, exist_ok=True, mode=0o700)
            with tempfile.NamedTemporaryFile(dir=self.directory, delete=False) as temp:
                target = Path(temp.name)
                try:
                    count = 0
                    sha = hashlib.sha256()
                    with github_request(asset["url"]) as response:
                        final = response.geturl()
                        if not final.startswith(("https://github.com/", "https://release-assets.githubusercontent.com/", "https://objects.githubusercontent.com/")):
                            raise ValueError("La descarga no proviene de GitHub.")
                        while block := response.read(128 * 1024):
                            count += len(block)
                            if count > asset["size"]:
                                raise ValueError("El tamaño no coincide.")
                            sha.update(block)
                            temp.write(block)
                            with self.lock:
                                self.progress = count * 100 // asset["size"]
                    if sha.hexdigest() != asset["digest"] or count != asset["size"]:
                        raise ValueError("El instalador no coincide con el publicado.")
                    temp.flush()
                    with tempfile.TemporaryDirectory(dir=self.directory) as staged:
                        suite_bundle.stage_packages(target, Path(staged), suite_bundle.version(asset["tag"]))
                    os.replace(target, self.bundle)
                    write_json_atomic(self.receipt, asset, mode=0o600)
                finally:
                    target.unlink(missing_ok=True)
            with self.lock:
                self.phase = "ready"
        except (OSError, ValueError, EOFError, tarfile.TarError):
            with self.lock:
                self.phase, self.error = "error", "No se pudo descargar o verificar la actualización."

    def apply(self):
        with self.lock:
            if self.phase != "ready":
                raise ValueError("No hay una actualización preparada.")
            recent = time.monotonic() - 20
            surfaces = [name for name, stamp in self.visible_surfaces.items() if stamp >= recent]
            if is_open() and "big-mode" not in surfaces:
                surfaces.append("big-mode")
            self.result.unlink(missing_ok=True)
            subprocess.run(["systemd-run", "--user", "--quiet", "--collect", "--unit=omnia-suite-update",
                            "/usr/bin/omnia-suite-update", *surfaces], check=True, timeout=8,
                           stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
            self.phase = "applying"
            self.error = ""


def _run(args, **kwargs):
    return subprocess.run(args, check=True, **kwargs)


def apply_packages(packages):
    _run(["/usr/bin/pkexec", "/usr/bin/pacman", "-U", "--noconfirm", *map(str, packages)])


def _ui_processes():
    for path in Path("/proc").iterdir():
        if not path.name.isdecimal():
            continue
        try:
            if path.stat().st_uid != os.getuid():
                continue
            args = (path / "cmdline").read_bytes().split(b"\0")
            if not args or Path(os.fsdecode(args[0])).name != "qml6":
                continue
            for kind, name in (("desktop", b"manager-window.qml"), ("big-mode", b"main-window.qml")):
                if b"/usr/share/omnia/ui/qml/" + name in args:
                    yield kind, int(path.name)
        except OSError:
            continue


def restart_suite(running, surfaces, embedded):
    desktop = any(kind == "desktop" for kind, _ in running)
    standalone = any(kind == "big-mode" for kind, _ in running)
    for _, pid in running:
        try:
            os.kill(pid, 15)
        except ProcessLookupError:
            pass
    _run(["systemctl", "--user", "daemon-reload"])
    _run(["systemctl", "--user", "reenable", "omnia.service"])
    _run(["systemctl", "--user", "restart", "omnia.service"])
    dux = paths.config_dir().parent / "dms" / "plugins" / "omnia-panel"
    if dux.is_dir():
        subprocess.run(["/usr/share/omnia/dux/install.sh"], check=False, timeout=20)
        if "dux" in surfaces:
            subprocess.run(["dms", "ipc", "call", "omniaPanel", "open"], check=False, timeout=8)
    def reopen(mode, *flags):
        _run(["systemd-run", "--user", "--quiet", "--collect", "--",
              "/usr/bin/omnia-ui", mode, *flags], timeout=10)
    if desktop:
        reopen("--manager", *(["--open-big-mode", "1"] if embedded else []))
    if standalone:
        reopen("--window")


def main(argv=None):
    parser = argparse.ArgumentParser()
    parser.add_argument("--restart-installed", action="store_true")
    parser.add_argument("surfaces", nargs="*")
    args = parser.parse_args(argv)
    if args.restart_installed:
        try:
            running = list(_ui_processes())
            standalone = any(kind == "big-mode" for kind, _ in running)
            restart_suite(running, args.surfaces, is_open() and not standalone)
            return 0
        except (OSError, subprocess.SubprocessError) as exc:
            parser.exit(1, f"{exc}\n")
    updater = SuiteUpdater()
    try:
        asset = json.loads(updater.receipt.read_text())
        target = suite_bundle.version(asset["tag"])
        if target <= suite_bundle.version(installed_version()):
            raise ValueError("La versión instalada ya es igual o más reciente.")
        if digest_file(updater.bundle) != asset["digest"]:
            raise ValueError("El instalador ya no coincide con el verificado.")
        running = list(_ui_processes())
        desktop = any(kind == "desktop" for kind, _ in running)
        standalone = any(kind == "big-mode" for kind, _ in running)
        embedded = desktop and "big-mode" in args.surfaces and not standalone
        with tempfile.TemporaryDirectory(dir=updater.directory) as tmp:
            packages = suite_bundle.stage_packages(updater.bundle, Path(tmp), target)
            apply_packages(packages)
        restart_suite(running, args.surfaces, embedded)
        updater.receipt.unlink(missing_ok=True)
        updater.bundle.unlink(missing_ok=True)
        return 0
    except (OSError, ValueError, KeyError, TypeError, EOFError, subprocess.SubprocessError, tarfile.TarError) as exc:
        write_json_atomic(updater.result, {"error": str(exc)}, mode=0o600)
        return 1

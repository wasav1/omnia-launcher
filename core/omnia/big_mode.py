"""Present the controller connection prompt independently of the current Omnia surface."""

import errno
import fcntl
import os
import shlex
import subprocess

from . import paths
from .events import EventBus

OPEN_BIG_MODE = 43
DISPLAY_VARS = ("DISPLAY", "WAYLAND_DISPLAY", "XAUTHORITY", "XDG_RUNTIME_DIR", "XDG_SESSION_TYPE", "DBUS_SESSION_BUS_ADDRESS")


def is_open():
    """Each live Big Mode window holds a shared lock, released even on a crash."""
    lock = paths.runtime_dir() / "big-mode.lock"
    try:
        with lock.open("rb") as handle:
            fcntl.flock(handle, fcntl.LOCK_EX | fcntl.LOCK_NB)
    except OSError as exc:
        return exc.errno in (errno.EAGAIN, errno.EACCES)
    return False


def graphical_environment():
    env = os.environ.copy()
    try:
        result = subprocess.run(["systemctl", "--user", "show-environment"],
                                capture_output=True, text=True, timeout=2)
    except (OSError, subprocess.TimeoutExpired):
        return env
    for line in result.stdout.splitlines():
        key, sep, value = line.partition("=")
        if sep and key in DISPLAY_VARS:
            try:
                words = shlex.split(value)
            except ValueError:
                continue
            if len(words) == 1:
                env[key] = words[0]
    return env


class ConnectionPrompt:
    def __init__(self, launcher, port, log, token_path):
        self.launcher = launcher
        self.port = port
        self.log = log
        self.token_path = token_path
        self.bus = EventBus()
        self.process = None
        self.launched_big_mode = None

    def _launch(self, mode):
        env = graphical_environment()
        if not (env.get("WAYLAND_DISPLAY") or env.get("DISPLAY")):
            return None
        env["OMNIA_PORT"] = str(self.port)
        env["OMNIA_TOKEN_FILE"] = str(self.token_path)
        try:
            return subprocess.Popen([self.launcher, mode], env=env)
        except OSError as exc:
            self.log.warning("No se pudo abrir %s: %s", mode, exc)
            return None

    def update(self, connected, new_connection, name, family):
        """Called by the controller reader after each scan, on its own thread."""
        if self.launched_big_mode is not None and self.launched_big_mode.poll() is not None:
            self.launched_big_mode = None
        if self.process is not None:
            result = self.process.poll()
            if result is not None:
                active = self.bus.pad["connected"]
                self.bus.set_pad(False)
                self.process = None
                if active and result == OPEN_BIG_MODE and connected and not is_open():
                    self.launched_big_mode = self._launch("--window")
                    return
            else:
                if not connected or is_open():
                    self.bus.set_pad(False)
                return

        if connected and new_connection and self.launched_big_mode is None and not is_open():
            self.bus.set_pad(True, name, family=family)
            self.process = self._launch("--pad-prompt")
            if self.process is None:
                self.bus.set_pad(False)

    def consume(self, key):
        if self.process is None or self.process.poll() is not None or not self.bus.pad["connected"]:
            return False
        if is_open():
            self.bus.set_pad(False)
            return False
        if key in ("l", "r", "A", "B"):
            self.bus.push(key)
        return True

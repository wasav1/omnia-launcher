"""Instalar juegos de las tiendas (Epic, GOG, Amazon) con legendary, gogdl y nile, con progreso, y registrarlos en la biblioteca.

Cada instalación es un trabajo con el mismo formato que los de package_installs (id, name, status, progress, error, destination), así
la pantalla Descargas los muestra sin cambios. Al terminar, el juego queda en la biblioteca con el ejecutable de Windows y se
lanza con umu/Proton (manual.add_game).
"""
import os
import re
import signal
import subprocess
import threading
import time
import uuid
from pathlib import Path

from .. import manual
from .base import StoreError

PROGRESS_RE = re.compile(r"(?:Progress:\s*)?(\d{1,3}(?:\.\d+)?)\s*%|Progress:\s*(\d{1,3}(?:\.\d+)?)")
ETA_RE = re.compile(r"ETA:\s*(\d+:\d{2}:\d{2})")
SPEED_RE = re.compile(r"(?:Download|Speed)\s*[-:]?\s*([\d.]+\s*[KMG]i?B/s)", re.I)
FORBIDDEN = ("/", "/usr", "/etc", "/boot", "/bin", "/sbin", "/lib", "/lib64", "/var", "/proc", "/sys", "/dev", "/run", "/opt", "/root")
TERMINAL = {"completed", "failed", "cancelled"}


def parse_line(line: str) -> dict:
    """Progreso, ETA y velocidad que se puedan leer de una línea de salida de las herramientas."""
    out = {}
    m = PROGRESS_RE.search(line)
    if m:
        value = float(m.group(1) or m.group(2))
        if 0 <= value <= 100:
            out["progress"] = value
    m = ETA_RE.search(line)
    if m:
        out["eta"] = m.group(1)
    m = SPEED_RE.search(line)
    if m:
        out["speed"] = m.group(1)
    return out


def check_destination(path: str) -> str:
    """Carpeta de destino válida: absoluta, existente, escribible, no es el HOME ni una carpeta del sistema."""
    if not isinstance(path, str) or not path.startswith("/"):
        raise StoreError("Elige una carpeta de destino.")
    real = os.path.realpath(path)
    home = os.path.realpath(Path.home())
    if not os.path.isdir(real) or real == home or real in FORBIDDEN or any(real == f or real.startswith(f + "/") for f in FORBIDDEN if f != "/"):
        raise StoreError("Esa carpeta no sirve para instalar juegos. Elige una carpeta propia (por ejemplo ~/Juegos).")
    if not os.access(real, os.W_OK):
        raise StoreError("No hay permiso de escritura en esa carpeta.")
    return real


class StoreInstalls:
    def __init__(self, stores: dict, store, roots_fn, on_change=None, popen=subprocess.Popen, which=None):
        self.stores = stores
        self.store = store
        self.roots_fn = roots_fn
        self.on_change = on_change
        self._popen = popen
        self._jobs = {}
        self._procs = {}
        self._cancel = set()
        self._lock = threading.Lock()
        self._run_lock = threading.Lock()              # una instalación a la vez
        self._which = which

    # ---- consulta
    def jobs(self) -> list:
        with self._lock:
            return [dict(j) for j in self._jobs.values()]

    def owns(self, job_id) -> bool:
        with self._lock:
            return job_id in self._jobs

    def _update(self, job_id, **kw):
        with self._lock:
            if job_id in self._jobs:
                self._jobs[job_id].update(kw)
        if self.on_change:
            self.on_change()

    # ---- acciones
    def start(self, store_id: str, game_id: str, title: str, destination: str) -> dict:
        store = self.stores.get(store_id)
        if store is None or not hasattr(store, "install_command"):
            raise StoreError("Esta tienda aún no permite instalar desde Omnia.")
        if not isinstance(game_id, str) or not re.fullmatch(r"[A-Za-z0-9._\-]{1,128}", game_id):
            raise StoreError("Juego no válido.")
        title = str(title or game_id).strip()[:80] or game_id
        status = store.status()
        if not status.get("available") or not status.get("logged_in"):
            raise StoreError("Conecta la cuenta de la tienda primero.")
        if not (self._which or __import__("shutil").which)("umu-run"):
            raise StoreError("Falta umu-launcher para ejecutar juegos de Windows.")
        root = check_destination(destination)
        with self._lock:
            for j in self._jobs.values():
                if j["store"] == store_id and j["gameId"] == game_id and j["status"] not in TERMINAL:
                    raise StoreError("Ese juego ya se está instalando.")
        folder = Path(root) / manual.slug(title)
        if folder.exists() and any(folder.iterdir()):
            raise StoreError("Ya existe una carpeta con ese nombre en el destino; elige otro destino.")
        job_id = str(uuid.uuid4())
        job = {"id": job_id, "kind": "store", "store": store_id, "gameId": game_id, "name": title, "status": "queued", "progress": 0,
               "speed": "", "eta": "", "destination": str(folder), "error": "", "startedAt": int(time.time())}
        with self._lock:
            self._jobs[job_id] = job
        threading.Thread(target=self._run, args=(job_id, store, folder), daemon=True).start()
        self._update(job_id)
        return dict(job)

    def cancel(self, job_id: str) -> bool:
        with self._lock:
            job = self._jobs.get(job_id)
            if not job or job["status"] in TERMINAL:
                return False
            self._cancel.add(job_id)
            proc = self._procs.get(job_id)
        if proc is not None:
            try:
                os.killpg(proc.pid, signal.SIGTERM)
            except (OSError, ProcessLookupError):
                pass
        return True

    def dismiss(self, job_id: str | None = None, only_failed: bool = False) -> int:
        with self._lock:
            ids = [job_id] if job_id is not None and self._jobs.get(job_id, {}).get("status") in TERMINAL else []
            if job_id is None:
                bad = {"failed", "cancelled"} if only_failed else TERMINAL
                ids = [i for i, j in self._jobs.items() if j["status"] in bad]
            for i in ids:
                self._jobs.pop(i, None)
        return len(ids)

    # ---- ejecución
    def _run(self, job_id, store, folder: Path):
        with self._run_lock:
            if job_id in self._cancel:
                self._update(job_id, status="cancelled")
                return
            self._update(job_id, status="downloading")
            try:
                folder.mkdir(parents=True, exist_ok=True)
                cmd, env = store.install_command(self._jobs[job_id]["gameId"], str(folder))
                proc = self._popen(cmd, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True, bufsize=1,
                                   env={**os.environ, **env}, stdin=subprocess.DEVNULL, start_new_session=True)
                with self._lock:
                    self._procs[job_id] = proc
                tail = []
                for line in proc.stdout:
                    line = line.rstrip()
                    tail = (tail + [line])[-12:]
                    info = parse_line(line)
                    if info:
                        self._update(job_id, **info)
                code = proc.wait()
                with self._lock:
                    self._procs.pop(job_id, None)
                if job_id in self._cancel:
                    self._update(job_id, status="cancelled", error="")
                    return
                if code != 0:
                    raise StoreError("La tienda no pudo instalar el juego (código %d)." % code)
                self._update(job_id, status="finalizing", progress=99)
                exe = store.find_executable(self._jobs[job_id]["gameId"], str(folder))
                self._register(job_id, store, exe)
                self._update(job_id, status="completed", progress=100, completedAt=int(time.time()), speed="", eta="")
            except StoreError as e:
                self._update(job_id, status="failed", error=str(e))
            except Exception as e:                       # una instalación nunca debe tumbar el servicio
                self._update(job_id, status="failed", error="Error inesperado al instalar (%s)." % type(e).__name__)

    def _register(self, job_id, store, exe: str):
        job = self._jobs[job_id]
        roots = list(self.roots_fn()) + [job["destination"]]
        try:
            entry = manual.add_game(self.store, {"name": job["name"], "kind": "windows", "exe": exe, "platform": "pc"}, roots)
        except manual.ManualError as e:
            raise StoreError(str(e))
        with self.store.lock:
            games = self.store.games()
            for g in games:
                if g.get("id") == entry["id"]:
                    g["sub"] = "PC · " + store.short
                    g["store_id"] = {"store": store.id, "id": job["gameId"]}
            self.store.set_games(games)

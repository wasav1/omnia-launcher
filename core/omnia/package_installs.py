"""Instalación de paquetes publicados por Omnia Backend.

El manifiesto nunca contiene comandos. Los archivos se descargan a un staging local,
se comprueban por tamaño/SHA-256 y se extraen sin enlaces ni rutas fuera del destino.
"""
from __future__ import annotations

import hashlib
import http.client
import ipaddress
import logging
import os
import shutil
import socket
import tarfile
import tempfile
import threading
import time
import urllib.parse
import urllib.request
import uuid
import zipfile
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path, PurePosixPath

from . import manual, online_catalog, paths
from .store import load_json, write_json_atomic

MAX_PACKAGE_BYTES = 20 * 1024 * 1024 * 1024
MAX_EXPANDED_BYTES = 40 * 1024 * 1024 * 1024
MAX_ARCHIVE_ITEMS = 200_000
MIN_FREE_MARGIN = 32 * 1024 * 1024
MAX_FREE_MARGIN = 256 * 1024 * 1024
CHUNK = 1024 * 1024
FORMATS = {"zip", "tar.gz", "tar.xz"}


class PackageInstallError(Exception):
    pass


log = logging.getLogger("omnia.installs")


def _safe_https(url: str) -> urllib.parse.SplitResult:
    try:
        parsed = urllib.parse.urlsplit(url)
        port = parsed.port
    except ValueError as exc:
        raise PackageInstallError("La URL del paquete no es válida.") from exc
    if (parsed.scheme != "https" or not parsed.hostname or parsed.username or parsed.password
            or parsed.fragment or port not in (None, 443)):
        raise PackageInstallError("El paquete debe usar una URL HTTPS pública.")
    host = parsed.hostname.rstrip(".").lower()
    if host in {"localhost", "localhost.localdomain"} or ".local" in host:
        raise PackageInstallError("La fuente del paquete no es pública.")
    _public_addresses(host)
    return parsed


def _public_addresses(host: str):
    """Devuelve direcciones DNS públicas que luego se usan directamente al abrir TLS.

    Validar DNS y permitir que urllib resuelva el nombre otra vez deja una ventana de DNS rebinding.
    La conexión usa una de estas direcciones concretas y conserva el nombre original para SNI/certificado.
    """
    try:
        records = socket.getaddrinfo(host, 443, type=socket.SOCK_STREAM)
    except OSError as exc:
        raise PackageInstallError("No se pudo resolver la fuente del paquete.") from exc
    if not records:
        raise PackageInstallError("La fuente del paquete debe resolver a direcciones públicas.")
    addresses = []
    for family, socktype, proto, _, sockaddr in records:
        try:
            ip = ipaddress.ip_address(sockaddr[0].split("%", 1)[0])
        except ValueError as exc:
            raise PackageInstallError("La fuente del paquete resolvió una dirección no válida.") from exc
        if not ip.is_global:
            raise PackageInstallError("La fuente del paquete debe resolver a direcciones públicas.")
        item = (family, socktype, proto, sockaddr)
        if item not in addresses:
            addresses.append(item)
    return addresses


class _PublicHTTPSConnection(http.client.HTTPSConnection):
    """Conecta al IP ya validado, pero verifica TLS usando el hostname del manifiesto."""

    def connect(self):
        if self._tunnel_host:
            raise PackageInstallError("No se permiten proxies ni túneles para instalar paquetes.")
        # Validar y conservar la misma resolución que se conecta. Resolver aquí sin
        # volver a comprobar cada IP abriría una ventana de DNS rebinding después de
        # que _safe_https validara inicialmente la URL.
        addresses = _public_addresses(self.host)
        last_error = None
        for family, socktype, proto, sockaddr in addresses:
            sock = socket.socket(family, socktype, proto)
            try:
                if self.timeout is not socket._GLOBAL_DEFAULT_TIMEOUT:
                    sock.settimeout(self.timeout)
                if self.source_address:
                    sock.bind(self.source_address)
                sock.connect(sockaddr)
                self.sock = self._context.wrap_socket(sock, server_hostname=self.host)
                return
            except OSError as exc:
                last_error = exc
                sock.close()
        if last_error:
            raise last_error
        raise PackageInstallError("No se pudo conectar con la fuente del paquete.")


class _PublicHTTPSHandler(urllib.request.HTTPSHandler):
    def https_open(self, request):
        return self.do_open(_PublicHTTPSConnection, request, context=self._context,
                            check_hostname=self._check_hostname)


class _SafeRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, req, fp, code, msg, headers, newurl):
        _safe_https(newurl)
        return super().redirect_request(req, fp, code, msg, headers, newurl)


def _safe_package_opener():
    # Ignora HTTP_PROXY/HTTPS_PROXY: un proxy podría resolver una URL privada por nuestra cuenta
    # y saltarse la validación/pinning DNS local.
    return urllib.request.build_opener(urllib.request.ProxyHandler({}), _SafeRedirect(), _PublicHTTPSHandler())


def _archive_path(raw: str) -> PurePosixPath:
    if not isinstance(raw, str) or not raw or "\\" in raw or "\x00" in raw:
        raise PackageInstallError("El paquete contiene una ruta insegura.")
    path = PurePosixPath(raw)
    if path.is_absolute() or any(part in ("", ".", "..") for part in path.parts):
        raise PackageInstallError("El paquete contiene una ruta fuera de su carpeta.")
    return path


def _target_path(stage: Path, raw: str) -> Path:
    relative = _archive_path(raw)
    target = stage.joinpath(*relative.parts)
    if os.path.commonpath((str(stage.resolve()), str(target.resolve(strict=False)))) != str(stage.resolve()):
        raise PackageInstallError("El paquete intenta salir de su carpeta de instalación.")
    return target


def _extract_zip(archive: Path, stage: Path, progress, reserve_space=None, consume_space=None):
    with zipfile.ZipFile(archive) as package:
        infos = package.infolist()
        if len(infos) > MAX_ARCHIVE_ITEMS:
            raise PackageInstallError("El paquete contiene demasiados archivos.")
        total = sum(info.file_size for info in infos if not info.is_dir())
        if total > MAX_EXPANDED_BYTES:
            raise PackageInstallError("El tamaño expandido supera el límite de Omnia.")
        if reserve_space:
            reserve_space(total)
        extracted = 0
        for index, info in enumerate(infos):
            if info.is_dir():
                target = _target_path(stage, info.filename.rstrip("/")) if info.filename.rstrip("/") else stage
                target.mkdir(parents=True, exist_ok=True)
                continue
            target = _target_path(stage, info.filename)
            mode = (info.external_attr >> 16) & 0xFFFF
            if mode and (mode & 0o170000) not in (0, 0o100000):
                raise PackageInstallError("El paquete ZIP incluye enlaces o archivos especiales.")
            target.parent.mkdir(parents=True, exist_ok=True)
            actual = 0
            with package.open(info, "r") as source, target.open("xb") as output:
                while True:
                    block = source.read(CHUNK)
                    if not block:
                        break
                    actual += len(block)
                    if actual > info.file_size or extracted + actual > MAX_EXPANDED_BYTES:
                        raise PackageInstallError("El tamaño expandido no coincide con el ZIP o supera el límite.")
                    output.write(block)
                    if consume_space:
                        consume_space(len(block))
                    progress(75 + int(20 * min(extracted + actual, total) / max(1, total)))
            if actual != info.file_size:
                raise PackageInstallError("Un archivo del paquete ZIP quedó incompleto.")
            if mode & 0o111:
                target.chmod(0o755)
            extracted += actual
            progress(75 + int(20 * extracted / max(1, total)))


def _extract_tar(archive: Path, stage: Path, mode: str, progress, reserve_space=None, consume_space=None):
    with tarfile.open(archive, mode) as package:
        members = package.getmembers()
        if len(members) > MAX_ARCHIVE_ITEMS:
            raise PackageInstallError("El paquete contiene demasiados archivos.")
        total = sum(member.size for member in members if member.isfile())
        if total > MAX_EXPANDED_BYTES:
            raise PackageInstallError("El tamaño expandido supera el límite de Omnia.")
        if reserve_space:
            reserve_space(total)
        extracted = 0
        for index, member in enumerate(members):
            target = _target_path(stage, member.name)
            if member.isdir():
                target.mkdir(parents=True, exist_ok=True)
            elif member.isfile():
                target.parent.mkdir(parents=True, exist_ok=True)
                src = package.extractfile(member)
                if src is None:
                    raise PackageInstallError("No se pudo leer un archivo del paquete.")
                actual = 0
                with src, target.open("xb") as output:
                    while True:
                        block = src.read(CHUNK)
                        if not block:
                            break
                        actual += len(block)
                        if actual > member.size or extracted + actual > MAX_EXPANDED_BYTES:
                            raise PackageInstallError("El tamaño expandido no coincide con TAR o supera el límite.")
                        output.write(block)
                        if consume_space:
                            consume_space(len(block))
                        progress(75 + int(20 * min(extracted + actual, total) / max(1, total)))
                if actual != member.size:
                    raise PackageInstallError("Un archivo del paquete TAR quedó incompleto.")
                target.chmod(0o755 if member.mode & 0o111 else 0o644)
                extracted += actual
            else:
                raise PackageInstallError("El paquete TAR incluye enlaces o archivos especiales.")
            progress(75 + int(20 * extracted / max(1, total)))


class PackageInstallManager:
    def __init__(self, store, allowed_roots, on_change=None):
        self.store = store
        self.allowed_roots = allowed_roots
        self.on_change = on_change or (lambda: None)
        self._lock = threading.RLock()
        self._pool = ThreadPoolExecutor(max_workers=2, thread_name_prefix="omnia-install")
        self._jobs: dict[str, dict] = {}
        self._cancel: dict[str, threading.Event] = {}
        self._pause: dict[str, threading.Event] = {}
        self._reservations: dict[str, tuple[int, int]] = {}
        self._file = paths.data_dir() / "package-installs.json"
        self._jobs_file = paths.data_dir() / "package-install-jobs.json"
        self._restore_jobs()

    def _restore_jobs(self):
        """Conserva el historial; una tarea activa no se reanuda desde staging parcial."""
        saved = load_json(self._jobs_file, [])
        if not isinstance(saved, list):
            return
        terminal = {"completed", "failed", "cancelled", "interrupted"}
        for item in saved[-100:]:
            if not isinstance(item, dict) or not isinstance(item.get("id"), str):
                continue
            saved_status = item.get("status")
            if not isinstance(saved_status, str):
                saved_status = ""
            job = {key: item.get(key) for key in (
                "id", "slug", "packageId", "name", "status", "progress", "destination",
                "error", "gameId",
            ) if key in item}
            if saved_status not in terminal:
                job.update(status="interrupted", error=(
                    "Omnia se reinició. Esta instalación no se reanudó; inicia una nueva descarga."
                ))
            try:
                job["progress"] = max(0, min(100, int(job.get("progress", 0) or 0)))
            except (TypeError, ValueError):
                job["progress"] = 0
            self._jobs[job["id"]] = job
        if self._jobs:
            self._persist_jobs_locked()

    def _persist_jobs_locked(self):
        # No guardar URLs ni datos completos del manifiesto, solo el historial visible.
        rows = list(self._jobs.values())[-100:]
        try:
            write_json_atomic(self._jobs_file, rows, mode=0o600)
        except OSError as exc:
            log.warning("no se pudo guardar el historial de instalaciones: %s", exc)

    @staticmethod
    def _free_margin(amount: int) -> int:
        return min(MAX_FREE_MARGIN, max(MIN_FREE_MARGIN, amount // 100))

    def _reserve_space(self, job_id: str, location: Path, amount: int, *, extra_margin: bool = True):
        """Reserva espacio por volumen para instalaciones en paralelo y extracciones expansivas."""
        margin = self._free_margin(amount) if extra_margin else 0
        with self._lock:
            try:
                device = location.stat().st_dev
                free = shutil.disk_usage(location).free
            except OSError as exc:
                raise PackageInstallError("No se pudo comprobar el espacio libre en la carpeta elegida.") from exc
            reserved = sum(size for dev, size in self._reservations.values() if dev == device)
            if free - reserved < amount + margin:
                raise PackageInstallError("No hay suficiente espacio libre para descargar y extraer este paquete.")
            current_device, current_size = self._reservations.get(job_id, (device, 0))
            if current_device != device:
                raise PackageInstallError("La instalación cambió de volumen durante la descarga.")
            self._reservations[job_id] = (device, current_size + amount)

    def _release_space(self, job_id: str):
        with self._lock:
            self._reservations.pop(job_id, None)

    def _consume_space(self, job_id: str, amount: int):
        """Convierte una reserva temporal en espacio ya ocupado por los bytes descargados."""
        with self._lock:
            device, reserved = self._reservations.get(job_id, (-1, 0))
            self._reservations[job_id] = (device, max(0, reserved - amount))

    def installed(self):
        data = load_json(self._file, [])
        return data if isinstance(data, list) else []

    def snapshot(self):
        with self._lock:
            jobs = [dict(job) for job in self._jobs.values()]
        return {"jobs": jobs, "installed": self.installed()}

    def start(self, slug: str, package_id: str, destination: str) -> dict:
        manifest = online_catalog.install_package(slug, package_id)
        if not isinstance(manifest, dict):
            raise PackageInstallError("El paquete no aparece publicado en el catálogo.")
        package = self._validate_manifest(manifest)
        root = os.path.realpath(os.path.expanduser(destination))
        if not os.path.isdir(root) or not any(root == os.path.realpath(r) or root.startswith(os.path.realpath(r).rstrip(os.sep) + os.sep)
                                              for r in self.allowed_roots()):
            raise PackageInstallError("Elige una carpeta de instalación permitida y existente.")
        install_name = manual.slug(package["title"] + "-" + package["version"])
        final = Path(root) / install_name
        if final.exists():
            raise PackageInstallError("Ya existe una carpeta con ese nombre; elige otro destino.")
        job_id = str(uuid.uuid4())
        self._reserve_space(job_id, Path(root), package["sizeBytes"])
        cancel = threading.Event()
        pause = threading.Event()
        job = {"id": job_id, "slug": slug, "packageId": package_id, "name": package["title"],
               "status": "queued", "progress": 0, "destination": str(final), "error": ""}
        try:
            with self._lock:
                self._jobs[job_id] = job
                self._cancel[job_id] = cancel
                self._pause[job_id] = pause
                self._persist_jobs_locked()
            self._pool.submit(self._run, job_id, package, final, cancel)
        except Exception:
            self._release_space(job_id)
            with self._lock:
                self._jobs.pop(job_id, None)
                self._cancel.pop(job_id, None)
                self._pause.pop(job_id, None)
                self._persist_jobs_locked()
            raise
        return dict(job)

    def cancel(self, job_id: str) -> bool:
        with self._lock:
            event = self._cancel.get(job_id)
            job = self._jobs.get(job_id)
            if not event or not job or job["status"] not in {"queued", "downloading", "verifying", "extracting", "paused"}:
                return False
            event.set()
            return True

    def pause(self, job_id: str) -> bool:
        """Pausa entre bloques de descarga o extracción, conservando el staging y el hash parcial."""
        with self._lock:
            job = self._jobs.get(job_id)
            event = self._pause.get(job_id)
            if not job or not event or job["status"] not in {"queued", "downloading", "extracting"}:
                return False
            job["resumeStatus"] = job["status"]
            job["status"] = "paused"
            event.set()
            self._persist_jobs_locked()
            return True

    def resume(self, job_id: str) -> bool:
        with self._lock:
            job = self._jobs.get(job_id)
            event = self._pause.get(job_id)
            if not job or not event or job["status"] != "paused":
                return False
            job["status"] = job.pop("resumeStatus", "downloading")
            event.clear()
            self._persist_jobs_locked()
            return True

    def uninstall(self, game_id: str, remove_files: bool = True) -> bool:
        with self._lock:
            installed = self.installed()
            record = next((item for item in installed if isinstance(item, dict) and item.get("gameId") == game_id), None)
            game = self.store.find_game(game_id)
            if not record or not game or game.get("installPackageId") != record.get("packageId"):
                return False
            folder = os.path.realpath(os.path.expanduser(str(record.get("path", ""))))
            allowed = [os.path.realpath(root) for root in self.allowed_roots()]
            if not folder or folder == os.path.realpath(Path.home()) or not any(
                    folder.startswith(root.rstrip(os.sep) + os.sep) for root in allowed):
                raise PackageInstallError("La carpeta de instalación no supera la validación de seguridad.")
            if remove_files:
                if os.path.islink(str(record.get("path", ""))) or not os.path.isdir(folder):
                    raise PackageInstallError("La carpeta de instalación ya no existe o no es segura.")
                shutil.rmtree(folder)
            if not manual.remove_game(self.store, game_id):
                raise PackageInstallError("Omnia no pudo retirar el juego de la biblioteca.")
            write_json_atomic(self._file, [item for item in installed if item is not record], mode=0o600)
            self.on_change()
            return True

    def shutdown(self):
        with self._lock:
            for event in self._cancel.values():
                event.set()
        self._pool.shutdown(wait=False, cancel_futures=True)

    @staticmethod
    def _validate_manifest(item: dict) -> dict:
        required = {"id", "title", "version", "sourceUrl", "sourceName", "licenseName", "archiveFormat", "sizeBytes", "sha256", "installSubdir", "entrypoint", "platformSlug"}
        if not required.issubset(item) or item.get("archiveFormat") not in FORMATS:
            raise PackageInstallError("El manifiesto publicado está incompleto o usa un formato no admitido.")
        if (not isinstance(item["id"], str) or len(item["id"]) != 36
                or any(not isinstance(item[key], str) or not item[key].strip() for key in ("title", "version", "sourceName", "licenseName"))
                or any(any(ord(char) < 32 for char in item[key]) for key in ("title", "version", "sourceName", "licenseName"))):
            raise PackageInstallError("El manifiesto contiene información de identificación no válida.")
        try:
            size = int(item["sizeBytes"])
        except (ValueError, TypeError):
            raise PackageInstallError("El tamaño declarado del paquete no es válido.")
        if not 0 < size <= MAX_PACKAGE_BYTES or not isinstance(item["sha256"], str) or len(item["sha256"]) != 64 or any(c not in "0123456789abcdef" for c in item["sha256"]):
            raise PackageInstallError("El tamaño o SHA-256 declarado no es válido.")
        if item.get("platformSlug") != "pc":
            raise PackageInstallError("Por ahora la instalación directa solo admite paquetes de PC.")
        if not item.get("sourceName") or not item.get("licenseName"):
            raise PackageInstallError("El paquete debe declarar su fuente y licencia.")
        _safe_https(str(item["sourceUrl"]))
        if item.get("licenseUrl"):
            _safe_https(str(item["licenseUrl"]))
        if not item.get("entrypoint"):
            raise PackageInstallError("El paquete no declara el ejecutable de inicio.")
        _archive_path(item.get("entrypoint"))
        if item.get("installSubdir"):
            _archive_path(item["installSubdir"])
        return {**item, "sizeBytes": size}

    def _set(self, job_id, **fields):
        with self._lock:
            job = self._jobs.get(job_id)
            if job:
                old_status = job.get("status")
                old_progress = int(job.get("progress", 0) or 0)
                job.update(fields)
                new_progress = int(job.get("progress", 0) or 0)
                if (job.get("status") != old_status or new_progress // 2 != old_progress // 2
                        or "error" in fields or "gameId" in fields):
                    self._persist_jobs_locked()

    def _pause_point(self, job_id: str, cancel: threading.Event, pause: threading.Event):
        while pause.is_set():
            if cancel.is_set():
                raise PackageInstallError("Instalación cancelada.")
            time.sleep(0.1)
        if cancel.is_set():
            raise PackageInstallError("Instalación cancelada.")

    def _phase(self, job_id: str, phase: str, cancel: threading.Event, pause: threading.Event, **fields):
        """Cambia de fase sin pisar una pausa solicitada concurrentemente."""
        while True:
            self._pause_point(job_id, cancel, pause)
            with self._lock:
                if pause.is_set():
                    continue
                job = self._jobs.get(job_id)
                if job:
                    old_status = job.get("status")
                    job.update(status=phase, **fields)
                    if job.get("status") != old_status or "progress" in fields:
                        self._persist_jobs_locked()
                return

    def _run(self, job_id, package, final: Path, cancel: threading.Event):
        stage = None
        final_created = False
        registered_game_id = ""
        try:
            pause = self._pause[job_id]
            self._phase(job_id, "downloading", cancel, pause)
            stage = Path(tempfile.mkdtemp(prefix=".omnia-install-", dir=final.parent))
            archive = stage / ("package." + package["archiveFormat"])
            digest = hashlib.sha256()
            received = 0
            opener = _safe_package_opener()
            request = urllib.request.Request(package["sourceUrl"], headers={"User-Agent": "Omnia/0.4", "Accept": "application/octet-stream"})
            with opener.open(request, timeout=20) as response, archive.open("xb") as out:
                if urllib.parse.urlsplit(response.geturl()).scheme != "https":
                    raise PackageInstallError("La descarga redirigió a una conexión no segura.")
                length = response.headers.get("Content-Length")
                if length and int(length) != package["sizeBytes"]:
                    raise PackageInstallError("El tamaño recibido no coincide con el manifiesto.")
                while True:
                    self._pause_point(job_id, cancel, self._pause[job_id])
                    block = response.read(CHUNK)
                    if not block:
                        break
                    received += len(block)
                    if received > package["sizeBytes"] or received > MAX_PACKAGE_BYTES:
                        raise PackageInstallError("La descarga superó el tamaño publicado.")
                    digest.update(block)
                    out.write(block)
                    self._consume_space(job_id, len(block))
                    self._set(job_id, progress=min(74, int(received * 74 / package["sizeBytes"])))
            if received != package["sizeBytes"]:
                raise PackageInstallError("La descarga quedó incompleta.")
            self._phase(job_id, "verifying", cancel, pause, progress=75)
            if digest.hexdigest() != package["sha256"]:
                raise PackageInstallError("El SHA-256 descargado no coincide; se descartó el paquete.")
            self._phase(job_id, "extracting", cancel, pause)
            def reserve_expanded_space(amount):
                self._reserve_space(job_id, final.parent, amount)

            def extraction_progress(value):
                self._pause_point(job_id, cancel, self._pause[job_id])
                self._set(job_id, progress=value)
            extract_root = stage / "contents"
            extract_root.mkdir(mode=0o700)
            if package["archiveFormat"] == "zip":
                _extract_zip(archive, extract_root, extraction_progress, reserve_expanded_space,
                             lambda amount: self._consume_space(job_id, amount))
            else:
                _extract_tar(archive, extract_root, "r:gz" if package["archiveFormat"] == "tar.gz" else "r:xz",
                             extraction_progress, reserve_expanded_space,
                             lambda amount: self._consume_space(job_id, amount))
            self._pause_point(job_id, cancel, pause)
            self._phase(job_id, "finalizing", cancel, pause)
            subdir = extract_root.joinpath(*PurePosixPath(package["installSubdir"]).parts) if package["installSubdir"] else extract_root
            entry = _target_path(extract_root, package["installSubdir"] + "/" + package["entrypoint"] if package["installSubdir"] else package["entrypoint"])
            if not subdir.is_dir() or not entry.is_file():
                raise PackageInstallError("El punto de entrada declarado no está dentro del paquete.")
            if entry.suffix.lower() != ".exe":
                entry.chmod(entry.stat().st_mode | 0o111)
            shutil.rmtree(archive)
            shutil.rmtree(stage / "contents" / "__pycache__", ignore_errors=True)
            os.replace(extract_root, final)
            final_created = True
            installed_entry = final.joinpath(*PurePosixPath(package["installSubdir"]).parts, *PurePosixPath(package["entrypoint"]).parts)
            kind = "windows" if installed_entry.suffix.lower() == ".exe" else "native"
            game = manual.add_game(self.store, {"name": package["title"], "kind": kind, "exe": str(installed_entry), "platform": "pc"}, self.allowed_roots())
            registered_game_id = game["id"]
            with self.store.lock:
                games = self.store.games()
                record = next((g for g in games if g.get("id") == game["id"]), None)
                if record:
                    with self._lock:
                        catalog_slug = self._jobs[job_id]["slug"]
                    record.update({"catalogSlug": catalog_slug, "installPackageId": package["id"],
                                   "installPath": str(final), "installVersion": package["version"], "src": "Omnia"})
                    self.store.set_games(games)
            installed = self.installed()
            installed.append({"gameId": game["id"], "packageId": package["id"], "catalogSlug": catalog_slug,
                              "name": package["title"], "version": package["version"], "path": str(final),
                              "entrypoint": str(installed_entry), "installedAt": int(time.time())})
            write_json_atomic(self._file, installed, mode=0o600)
            self._phase(job_id, "completed", cancel, pause, progress=100, gameId=game["id"], destination=str(final))
            self.on_change()
        except Exception as exc:
            if registered_game_id:
                manual.remove_game(self.store, registered_game_id)
            if stage and stage.exists():
                shutil.rmtree(stage, ignore_errors=True)
            if final_created and final.exists():
                shutil.rmtree(final, ignore_errors=True)
            self._set(job_id, status="cancelled" if cancel.is_set() else "failed", error=str(exc)[:300])
        finally:
            self._release_space(job_id)
            with self._lock:
                self._cancel.pop(job_id, None)
                self._pause.pop(job_id, None)

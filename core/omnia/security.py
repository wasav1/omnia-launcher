"""Autenticación de la API local.

Una petición a 127.0.0.1 puede venir de cualquier página web abierta en el navegador, así que escuchar solo en
loopback NO basta. La API exige un token aleatorio por sesión, guardado en $XDG_RUNTIME_DIR/omnia/token (0600), y
rechaza cualquier Host que no sea el propio. Un navegador no puede leer ese archivo ni enviar la cabecera
Authorization entre orígenes sin pasar por un preflight CORS, que la API nunca autoriza.
"""
import hmac
import os
import secrets
from pathlib import Path

from . import paths


def new_token(runtime: Path | None = None) -> str:
    """Genera un token nuevo y lo escribe con permisos 0600 (reemplaza al anterior)."""
    d = paths.ensure(Path(runtime) if runtime else paths.runtime_dir())
    token = secrets.token_urlsafe(32)
    f = d / "token"
    tmp = d / "token.tmp"
    fd = os.open(tmp, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
    with os.fdopen(fd, "w") as fh:
        fh.write(token)
    os.replace(tmp, f)
    return token


def check_bearer(header: str, token: str) -> bool:
    scheme, _, value = (header or "").partition(" ")
    return scheme.lower() == "bearer" and hmac.compare_digest(value.strip().encode(), token.encode())


def host_ok(host: str, port: int) -> bool:
    return (host or "").lower() in (f"127.0.0.1:{port}", f"localhost:{port}", f"[::1]:{port}")

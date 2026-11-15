"""Lectura de procesos desde /proc (sin pgrep ni dependencias): lista de líneas de comando del usuario actual."""
import os


def scan() -> list:
    """Devuelve las líneas de comando (argumentos unidos por espacios) de los procesos del usuario actual."""
    uid, out = os.getuid(), []
    try:
        pids = [p for p in os.listdir("/proc") if p.isdigit()]
    except OSError:
        return out
    for pid in pids:
        try:
            if os.stat("/proc/" + pid).st_uid != uid:
                continue
            with open("/proc/%s/cmdline" % pid, "rb") as f:
                raw = f.read(4096)
        except OSError:
            continue
        if raw:
            out.append(raw.replace(b"\0", b" ").decode("utf-8", "replace").strip())
    return out

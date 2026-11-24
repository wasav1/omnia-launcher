"""Estilo de MangoHud con la identidad de Omnia: una sola línea horizontal, centrada arriba, tipografía Rajdhani y la paleta de la app.

Omnia escribe `MangoHud.conf` en su carpeta de configuración y se lo pasa a MangoHud con `MANGOHUD_CONFIGFILE`; no toca el
`~/.config/MangoHud` del usuario. El archivo lleva una marca en la primera línea: mientras esté, Omnia lo regenera cuando cambia el
diseño; si el usuario la borra para editarlo a mano, Omnia lo respeta y no lo vuelve a escribir."""
from __future__ import annotations

import functools
import os
import re
import subprocess
from pathlib import Path

OWNED = "# omnia-generado"                  # cualquier versión del archivo que escribió Omnia (se actualiza); sin esta marca es del usuario
MARKER = OWNED + " v4"
FONT_NAME = "Rajdhani-SemiBold.ttf"
FONT_DIRS = (Path("/usr/share/omnia/ui/qml/fonts"), Path(__file__).resolve().parents[2] / "assets" / "fonts")

# Paleta de Omnia (ui/qml): fondo #0B0F14, texto #F3EFE3, acento #336599, azul #5B9BE0, dorado #E8B86D, estados verde/ámbar/rojo.
_BODY = """\
legacy_layout=0
horizontal
horizontal_stretch=0
position=top-center
hud_no_margin
{font}font_size=20
round_corners=18
background_color=0B0F14
background_alpha=0.55
alpha=1
text_color=F3EFE3
engine_color=91A9C2
horizontal_separator_color=6F8DAA
horizontal_separator_dot
window_padding_x=24
concave_top_corners=14
fps
fps_color_change
fps_color=E86D6D,E8A24B,7FD69F
fps_value=30,60
gpu_stats
{gpu_extra}gpu_temp
gpu_color=5B9BE0
gpu_load_change
gpu_load_color=7FD69F,E8A24B,E86D6D
gpu_load_value=60,90
cpu_stats
{cpu_extra}cpu_temp
cpu_color=5B9BE0
cpu_load_change
cpu_load_color=7FD69F,E8A24B,E86D6D
cpu_load_value=60,90
vram
vram_color=E8B86D
ram
ram_color=E8B86D
frame_timing
frametime_color=5B9BE0
"""


_SAFE = re.compile(r"[^A-Za-z0-9 ._+/-]")


def _clean(text: str, limit: int = 28) -> str:
    return re.sub(r"\s+", " ", _SAFE.sub("", text or "")).strip()[:limit].strip()


def short_cpu(model: str) -> str:
    """«Intel(R) Core(TM) i5-10300H CPU @ 2.50GHz» → «i5-10300H»; «AMD Ryzen 7 5800H with Radeon Graphics» → «Ryzen 7 5800H»."""
    text = re.sub(r"\((?:R|TM|tm|r)\)", "", model or "")
    text = re.sub(r"\s+(?:CPU|Processor)\b", "", text, flags=re.I)
    text = re.sub(r"\s+with\s+.*$", "", text, flags=re.I)
    text = re.sub(r"\s+@.*$", "", text)
    text = re.sub(r"^(?:\d+(?:st|nd|rd|th) Gen )?(?:Intel |AMD )?(?:Core |Xeon |Pentium |Celeron )?", "", text.strip(), flags=re.I)
    return _clean(text)


def short_gpu(model: str) -> str:
    """«NVIDIA GeForce GTX 1650 Ti» → «GTX 1650 Ti»; «Radeon RX 6800 XT» → «RX 6800 XT»."""
    bracket = re.search(r"\[(.+)\]", model or "")              # lspci: «Navi 21 [Radeon RX 6800 XT]» → lo de los corchetes
    text = re.sub(r"\b(?:NVIDIA|AMD|ATI|Intel|Corporation)\b", "", bracket.group(1) if bracket else (model or ""))
    text = re.sub(r"\b(?:GeForce|Radeon|Graphics)\b", "", text)
    text = re.sub(r"\b(?:Mobile|Laptop GPU|Max-Q)\b", "", text, flags=re.I)
    return _clean(text)


def _lspci_name(addr: str) -> str:
    try:
        out = subprocess.run(["lspci", "-mm", "-s", addr], capture_output=True, text=True, timeout=3).stdout
    except (OSError, subprocess.SubprocessError):
        return ""
    fields = re.findall(r'"([^"]*)"', out)
    device = fields[2] if len(fields) > 2 else ""
    bracket = re.search(r"\[(.+)\]", device)
    return bracket.group(1) if bracket else device


def detect_hardware(pci=Path("/sys/bus/pci/devices"), cpuinfo=Path("/proc/cpuinfo"), nvidia=Path("/proc/driver/nvidia/gpus"), name_of=_lspci_name) -> dict:
    """{cpu, gpu, pci}: nombre corto del procesador, de la gráfica dedicada (la única, o la que no es la de arranque) y,
    solo si hay más de una gráfica, su dirección PCI para que MangoHud muestre esa. Lo que no se pueda saber queda en ''."""
    out = {"cpu": "", "gpu": "", "pci": ""}
    try:
        for line in Path(cpuinfo).read_text(errors="replace").splitlines():
            if line.lower().startswith("model name"):
                out["cpu"] = short_cpu(line.split(":", 1)[1])
                break
    except OSError:
        pass
    gpus = []
    try:
        for device in sorted(Path(pci).iterdir()):
            try:
                if (device / "class").read_text().strip().startswith("0x03"):
                    boot = (device / "boot_vga").read_text().strip() == "1" if (device / "boot_vga").exists() else False
                    gpus.append((device.name, boot))
            except OSError:
                continue
    except OSError:
        return out
    if not gpus:
        return out
    pick = next((g for g in gpus if not g[1]), gpus[0]) if len(gpus) > 1 else gpus[0]
    addr = pick[0]
    if len(gpus) > 1:
        out["pci"] = addr
    model = ""
    try:
        info = Path(nvidia) / addr.lower() / "information"
        match = re.search(r"^Model:\s*(.+)$", info.read_text(errors="replace"), re.M)
        model = match.group(1) if match else ""
    except OSError:
        pass
    out["gpu"] = short_gpu(model or name_of(addr))
    return out


@functools.lru_cache(maxsize=1)
def _hardware() -> dict:
    return detect_hardware()


def find_font(dirs=FONT_DIRS) -> str:
    for base in dirs:
        candidate = Path(base) / FONT_NAME
        if candidate.is_file():
            return str(candidate)
    return ""


def render(font: str | None = None, hardware: dict | None = None) -> str:
    font = find_font() if font is None else font
    hw = _hardware() if hardware is None else hardware
    gpu_extra = (f"pci_dev={hw['pci']}\n" if hw.get("pci") else "") + (f"gpu_text={hw['gpu']}\n" if hw.get("gpu") else "")
    cpu_extra = f"cpu_text={hw['cpu']}\n" if hw.get("cpu") else ""
    line = f"font_file={font}\n" if font and "\n" not in font else ""
    return f"{MARKER}\n# Quita la línea de arriba si quieres editar este archivo a mano: Omnia dejará de reescribirlo.\n" + _BODY.format(font=line, gpu_extra=gpu_extra, cpu_extra=cpu_extra)


def ensure(config_dir) -> Path:
    """Escribe (o actualiza) `MangoHud.conf` con el estilo de Omnia y devuelve su ruta. Un archivo sin la marca no se toca."""
    path = Path(config_dir) / "MangoHud.conf"
    if path.is_symlink():
        return path
    try:
        current = path.read_text(encoding="utf-8") if path.is_file() else None
    except (OSError, UnicodeDecodeError):
        return path
    if current is not None and not current.startswith(OWNED):
        return path
    text = render()
    if current != text:
        try:
            path.parent.mkdir(parents=True, exist_ok=True)
            tmp = path.with_name(path.name + ".tmp")
            tmp.write_text(text, encoding="utf-8")
            os.replace(tmp, path)
        except OSError:
            pass
    return path

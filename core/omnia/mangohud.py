"""Estilo de MangoHud con la identidad de Omnia: una sola línea horizontal, centrada arriba, tipografía Rajdhani y la paleta de la app.

Omnia escribe `MangoHud.conf` en su carpeta de configuración y se lo pasa a MangoHud con `MANGOHUD_CONFIGFILE`; no toca el
`~/.config/MangoHud` del usuario. El archivo lleva una marca en la primera línea: mientras esté, Omnia lo regenera cuando cambia el
diseño; si el usuario la borra para editarlo a mano, Omnia lo respeta y no lo vuelve a escribir."""
from __future__ import annotations

import os
from pathlib import Path

OWNED = "# omnia-generado"                  # cualquier versión del archivo que escribió Omnia (se actualiza); sin esta marca es del usuario
MARKER = OWNED + " v3"
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
gpu_list=1
gpu_temp
gpu_color=5B9BE0
gpu_load_change
gpu_load_color=7FD69F,E8A24B,E86D6D
gpu_load_value=60,90
cpu_stats
cpu_temp
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


def find_font(dirs=FONT_DIRS) -> str:
    for base in dirs:
        candidate = Path(base) / FONT_NAME
        if candidate.is_file():
            return str(candidate)
    return ""


def render(font: str | None = None) -> str:
    font = find_font() if font is None else font
    line = f"font_file={font}\n" if font and "\n" not in font else ""
    return f"{MARKER}\n# Quita la línea de arriba si quieres editar este archivo a mano: Omnia dejará de reescribirlo.\n" + _BODY.format(font=line)


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

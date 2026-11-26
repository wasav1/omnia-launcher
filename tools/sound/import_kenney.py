#!/usr/bin/env python3
"""Crea el paquete de sonidos «kenney» de Big Mode a partir de «Interface Sounds» de Kenney (Creative Commons CC0, https://kenney.nl/assets/interface-sounds).

No descarga nada: recibe el ZIP que se bajó de kenney.nl, lee solo los .ogg que necesita (nunca extrae rutas del ZIP al disco), los convierte a WAV
mono de 44,1 kHz con el mismo nivel que el paquete de Omnia y copia su licencia. Resultado en ui/qml/sounds/kenney/.

    python3 tools/sound/import_kenney.py ~/Descargas/kenney_interface-sounds.zip
"""
import io, subprocess, sys, wave, zipfile
from pathlib import Path
import numpy as np

MAPPING = {   # nombre en Omnia -> archivo de Kenney
    "move": "tick_001", "confirm": "confirmation_001", "back": "back_001", "menu": "open_001", "page": "scroll_003", "error": "error_001",
    "done": "confirmation_002", "pad-on": "maximize_001", "pad-off": "minimize_001", "toggle": "toggle_001", "open": "open_002", "close": "close_001",
}
SR = 44100
PEAK = 0.45          # igual que el paquete de Omnia (≈ −7 dBFS); el volumen lo ajusta la interfaz
MAX_MS = 700         # algunos sonidos de Kenney duran más: se recortan con un desvanecido corto
LIMITS = {"page": (260, 0.05)}   # (duración máxima en ms, desvanecido en s): el barrido de «scroll» dura 1 s y un salto de página debe ser breve


def decode(ogg: bytes) -> np.ndarray:
    raw = subprocess.run(["ffmpeg", "-loglevel", "error", "-i", "pipe:0", "-f", "s16le", "-ac", "1", "-ar", str(SR), "pipe:1"],
                         input=ogg, capture_output=True, check=True).stdout
    return np.frombuffer(raw, dtype="<i2").astype(np.float64) / 32768


def main(zip_path: str):
    out = Path(__file__).resolve().parents[2] / "ui/qml/sounds/kenney"
    out.mkdir(parents=True, exist_ok=True)
    z = zipfile.ZipFile(zip_path)
    names = {Path(i.filename).name: i for i in z.infolist() if not i.is_dir()}
    for ours, theirs in MAPPING.items():
        sig = decode(z.read(names[theirs + ".ogg"]))
        limit, fade_s = LIMITS.get(ours, (MAX_MS, 0.008))
        sig = sig[: int(limit / 1000 * SR)]
        fade = min(len(sig), int(fade_s * SR))
        sig[-fade:] *= np.linspace(1, 0, fade)
        sig = sig / (np.abs(sig).max() + 1e-9) * PEAK
        with wave.open(str(out / f"{ours}.wav"), "wb") as w:
            w.setnchannels(1); w.setsampwidth(2); w.setframerate(SR); w.writeframes((sig * 32767).astype("<i2").tobytes())
        print(f"{ours:8s} ← {theirs:18s} {len(sig)/SR*1000:4.0f} ms")
    (out / "LICENSE-Kenney-CC0.txt").write_bytes(z.read(names["License.txt"]))
    (out / "README.txt").write_text("Paquete «Kenney · Interface Sounds» (Creative Commons CC0).\nOrigen: https://kenney.nl/assets/interface-sounds (kenney_interface-sounds.zip, versión 1.0).\n"
                                    "Convertido a WAV mono de 44,1 kHz con tools/sound/import_kenney.py; correspondencia en ese script. La licencia está en LICENSE-Kenney-CC0.txt.\n", encoding="utf-8")


if __name__ == "__main__":
    main(sys.argv[1])

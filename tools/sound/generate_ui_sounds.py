#!/usr/bin/env python3
"""Sonidos de la interfaz de Big Mode («paquete Omnia»), sintetizados desde cero: sin muestras ni licencias de terceros.

Son cortos, suaves y de tono cálido (nada de bips agudos ni zumbidos); el volumen lo controla la propia interfaz.
Escribe WAV mono de 44,1 kHz en ui/qml/sounds/omnia/:
  move      mover la selección          confirm   aceptar / jugar        back    volver
  menu      abrir menú o panel          page      cambiar de página      error   algo no se pudo hacer
  done      descarga o tarea terminada  pad-on    mando conectado        pad-off mando desconectado
  toggle    interruptor activado/desactivado        open  abrir una pantalla       close   cerrar una pantalla
"""
import sys, wave
from pathlib import Path
import numpy as np

SR = 44100
rng = np.random.default_rng(3)


def tone(freq, dur, amp=0.3, shape="sine", attack=0.004, decay=None, vib=0.0):
    n = int(dur * SR)
    t = np.arange(n) / SR
    f = freq * (1 + vib * np.sin(2 * np.pi * 5.5 * t))
    ph = 2 * np.pi * np.cumsum(f) / SR
    wave_ = np.sin(ph) if shape == "sine" else (2 / np.pi) * np.arcsin(np.sin(ph))           # triángulo: más suave que un cuadrado
    if shape == "soft":                                                                       # seno con un armónico bajo: calidez
        wave_ = np.sin(ph) + 0.25 * np.sin(2 * ph)
    env = np.minimum(1, t / attack) * np.exp(-t / (decay or dur / 3.5))
    env *= np.minimum(1, (dur - t) / 0.01)                                                     # sin clic al final
    return wave_ * env * amp


def seq(*parts):
    """Notas (start, array) → una sola señal."""
    end = max(int(s * SR) + len(a) for s, a in parts)
    out = np.zeros(end)
    for s, a in parts:
        i = int(s * SR)
        out[i:i + len(a)] += a
    return out


def whoosh(dur, f0, f1, amp):
    n = int(dur * SR)
    noise = rng.standard_normal(n)
    out = np.zeros(n)
    win = np.hanning(512)
    freqs = np.fft.rfftfreq(512, 1 / SR)
    for i in range(0, n - 512, 128):
        fc = f0 * (f1 / f0) ** (i / n)
        mask = np.exp(-0.5 * (np.log2(np.maximum(freqs, 1) / fc) / 0.8) ** 2)
        out[i:i + 512] += np.fft.irfft(np.fft.rfft(noise[i:i + 512] * win) * mask, 512) * win
    env = np.sin(np.pi * np.linspace(0, 1, n)) ** 2
    return out / (np.abs(out).max() + 1e-9) * env * amp


SOUNDS = {
    "move": lambda: seq((0, tone(1180, 0.05, 0.22, "soft", decay=0.014))),
    "confirm": lambda: seq((0, tone(659, 0.09, 0.26, "soft", decay=0.03)), (0.065, tone(988, 0.16, 0.26, "soft", decay=0.05))),
    "back": lambda: seq((0, tone(622, 0.08, 0.22, "soft", decay=0.03)), (0.06, tone(440, 0.14, 0.22, "soft", decay=0.05))),
    "menu": lambda: seq((0, tone(523, 0.06, 0.2, "triangle", decay=0.02)), (0.045, tone(784, 0.12, 0.2, "triangle", decay=0.04))),
    "page": lambda: seq((0, whoosh(0.16, 600, 2600, 0.18)), (0.1, tone(1318, 0.09, 0.12, "soft", decay=0.03))),
    "error": lambda: seq((0, tone(233, 0.12, 0.25, "soft", decay=0.05)), (0.1, tone(185, 0.2, 0.25, "soft", decay=0.08))),
    "done": lambda: seq((0, tone(784, 0.1, 0.22, "soft", decay=0.04)), (0.09, tone(988, 0.1, 0.22, "soft", decay=0.04)), (0.18, tone(1318, 0.3, 0.22, "soft", decay=0.1))),
    "pad-on": lambda: seq((0, tone(523, 0.1, 0.22, "soft", decay=0.04)), (0.08, tone(784, 0.22, 0.22, "soft", decay=0.08))),
    "pad-off": lambda: seq((0, tone(784, 0.1, 0.2, "soft", decay=0.04)), (0.08, tone(523, 0.22, 0.2, "soft", decay=0.08))),
    "toggle": lambda: seq((0, tone(880, 0.05, 0.2, "soft", decay=0.02)), (0.04, tone(1175, 0.08, 0.2, "soft", decay=0.03))),
    "open": lambda: seq((0, whoosh(0.2, 400, 1800, 0.14)), (0.12, tone(698, 0.14, 0.14, "soft", decay=0.05))),
    "close": lambda: seq((0, whoosh(0.18, 1800, 400, 0.12)), (0.08, tone(523, 0.12, 0.12, "soft", decay=0.04))),
}


def write(path: Path, sig):
    peak = np.abs(sig).max()
    sig = sig / peak * min(peak, 0.45)                          # picos ≤ −7 dBFS; la interfaz sube o baja el volumen
    data = (np.clip(sig, -1, 1) * 32767).astype("<i2")
    with wave.open(str(path), "wb") as w:
        w.setnchannels(1); w.setsampwidth(2); w.setframerate(SR); w.writeframes(data.tobytes())


if __name__ == "__main__":
    out = Path(sys.argv[1] if len(sys.argv) > 1 else Path(__file__).resolve().parents[2] / "ui/qml/sounds/omnia")
    out.mkdir(parents=True, exist_ok=True)
    for name, make in SOUNDS.items():
        sig = make()
        write(out / f"{name}.wav", sig)
        print(f"{name:8s} {len(sig)/SR*1000:4.0f} ms · pico {20*np.log10(min(np.abs(sig).max(), .45)):.1f} dBFS")

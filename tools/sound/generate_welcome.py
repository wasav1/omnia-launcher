#!/usr/bin/env python3
"""Sonido de bienvenida de Big Mode («Omnia · Nace de la constelación»), sintetizado desde cero (sin muestras ni licencias de terceros).

Va sincronizado con la animación (tiempos en segundos):
  0.0–1.6  los puntos de la constelación convergen      → oleaje ascendente + destellos de cristal al posarse
  1.3–2.6  las líneas unen el contorno del logo         → tensión: barrido ascendente de cuerdas y platillo invertido
  2.3      el logo se rellena                           → impacto grave + campana brillante
  2.3–5.0  acorde cálido (Re mayor con novena) que se abre y se desvanece con reverberación
  2.9/4.5  pulsos del aro                               → latidos graves suaves
  3.1/3.5/3.9  saludo, resumen y frase                  → tres notas suaves de cristal

    python3 tools/sound/generate_welcome.py [salida.wav]      # escribe también salida.ogg si hay ffmpeg
"""
import subprocess, sys, wave
from pathlib import Path
import numpy as np

SR = 44100
LEN = 5.8
TARGET = 0.6                                       # pico final ≈ −4,4 dBFS: un sonido de interfaz no debe ir al máximo; el volumen lo ajusta la propia interfaz
N = int(SR * LEN)
rng = np.random.default_rng(7)
t = np.arange(N) / SR


def env(start, attack, hold, release, amp=1.0):
    """Envolvente lineal-exponencial: sube en `attack`, se mantiene `hold` y baja en `release`."""
    e = np.zeros(N)
    a0, a1 = int(start * SR), int((start + attack) * SR)
    h1 = int((start + attack + hold) * SR)
    r1 = int((start + attack + hold + release) * SR)
    a1, h1, r1 = min(a1, N), min(h1, N), min(r1, N)
    if a1 > a0:
        e[a0:a1] = np.linspace(0, 1, a1 - a0) ** 2
    e[a1:h1] = 1.0
    if r1 > h1:
        e[h1:r1] = np.exp(-5.0 * np.linspace(0, 1, r1 - h1))
    return e * amp


def sweep(f0, f1, start, dur, curve=2.0):
    """Frecuencia que va de f0 a f1 en `dur` (curva exponencial), devuelve la fase integrada."""
    x = np.clip((t - start) / dur, 0, 1)
    f = f0 * (f1 / f0) ** (x ** (1 / curve))
    return 2 * np.pi * np.cumsum(f) / SR


def stft_filter(sig, centers, width_oct, gain=1.0, n=2048, hop=512):
    """Filtro paso banda de frecuencia central variable en el tiempo (centers: función de t en segundos → Hz)."""
    win = np.hanning(n)
    out = np.zeros(len(sig) + n)
    norm = np.zeros(len(sig) + n)
    freqs = np.fft.rfftfreq(n, 1 / SR)
    for i in range(0, len(sig) - n, hop):
        seg = np.fft.rfft(sig[i:i + n] * win)
        fc = max(60.0, float(centers((i + n / 2) / SR)))
        mask = np.exp(-0.5 * (np.log2(np.maximum(freqs, 1) / fc) / width_oct) ** 2)
        out[i:i + n] += np.fft.irfft(seg * mask, n) * win
        norm[i:i + n] += win ** 2
    return (out / np.maximum(norm, 1e-6))[:len(sig)] * gain


def lowpass(sig, fc):
    a = np.exp(-2 * np.pi * fc / SR)
    out = np.zeros_like(sig)
    y = 0.0
    for i, x in enumerate(sig):
        y = (1 - a) * x + a * y
        out[i] = y
    return out


def bell(freq, start, dur=2.2, amp=0.2, bright=1.0):
    """Campana de cristal: parciales inarmónicos que se apagan a distinta velocidad."""
    sig = np.zeros(N)
    for ratio, a, d in ((1.0, 1.0, 1.0), (2.01, 0.55 * bright, 0.7), (2.76, 0.35 * bright, 0.5), (4.07, 0.22 * bright, 0.35), (5.4, 0.12 * bright, 0.25)):
        x = np.clip(t - start, 0, None)
        e = np.where(t >= start, np.exp(-x / (dur * d / 4.2)), 0) * np.minimum(1, x / 0.004)
        sig += a * np.sin(2 * np.pi * freq * ratio * x) * e
    return sig * amp


L = np.zeros(N)
R = np.zeros(N)


def add(sig, pan=0.0, gain=1.0):
    """Suma una señal mono al estéreo con panorama pan∈[-1,1] (ley de potencia constante)."""
    ang = (pan + 1) * np.pi / 4
    L[:] += sig * np.cos(ang) * gain
    R[:] += sig * np.sin(ang) * gain


# --- 1. oleaje ascendente (olas que suben) ---------------------------------------------------------------------------------
noise = rng.standard_normal(N)
wave_bed = stft_filter(noise, lambda x: 180 * (3200 / 180) ** (min(x, 2.3) / 2.3), 1.1)
wave_bed *= env(0.05, 1.6, 0.3, 0.9, 0.30)
add(wave_bed, -0.25, 1.0)
add(np.roll(wave_bed, int(0.012 * SR)), 0.25, 1.0)                       # ensancha el estéreo con un retardo mínimo
sub = np.sin(sweep(38, 62, 0.1, 2.2)) * env(0.1, 1.8, 0.4, 1.0, 0.10)       # retumbo grave que crece
add(sub, 0, 1.0)

# --- 2. destellos de cristal al posarse los puntos (pentatónica de Re mayor) ---------------------------------------------------
penta = [587.33, 659.25, 739.99, 880.0, 987.77, 1174.66, 1318.51, 1479.98]
for i in range(30):
    when = 0.18 + 1.45 * (i / 30) ** 0.8 + rng.uniform(0, 0.03)
    add(bell(penta[rng.integers(len(penta))], when, dur=1.6, amp=0.045 + 0.02 * rng.random(), bright=0.8), rng.uniform(-0.9, 0.9))

# --- 3. tensión: cuerdas que suben y platillo invertido ---------------------------------------------------------------------
tension = np.zeros(N)
for detune, f0, f1 in ((0.0, 146.83, 293.66), (0.4, 146.83, 293.66), (-0.4, 146.83, 293.66), (0.0, 220.0, 440.0)):
    ph = sweep(f0 * 2 ** (detune / 12 / 5), f1 * 2 ** (detune / 12 / 5), 1.2, 1.1)
    tension += sum(np.sin(h * ph) / h for h in range(1, 7))
tension = lowpass(tension, 2400) * env(1.2, 1.0, 0.12, 0.25, 0.035)
add(tension, 0, 1.0)
rev_cym = stft_filter(rng.standard_normal(N), lambda x: 4500, 1.4) * env(1.5, 0.8, 0.0, 0.05, 0.22)
add(rev_cym, 0.1, 1.0)

# --- 4. impacto cuando el logo se rellena (2,30 s) -----------------------------------------------------------------------
ti = 2.3
x = np.clip(t - ti, 0, None)
boom = np.sin(2 * np.pi * (36 * x + 62 * (1 - np.exp(-x * 7)) / 7)) * np.exp(-x / 0.42) * (t >= ti) * 0.85
click = lowpass(rng.standard_normal(N), 900) * np.exp(-x / 0.09) * (t >= ti) * 0.8
add(boom, 0, 1.0)
add(click, 0, 0.35)
add(bell(1174.66, ti + 0.01, dur=3.4, amp=0.2, bright=1.3), -0.15)
add(bell(1760.0, ti + 0.02, dur=3.0, amp=0.11, bright=1.2), 0.2)

# --- 5. acorde cálido (Re mayor con novena: Re2 La2 Mi3 Fa#3 La3 Do#4) que se abre y se apaga ---------------------------------
pad = np.zeros(N)
for f, a in ((73.42, 0.9), (110.0, 0.8), (164.81, 0.7), (185.0, 0.55), (220.0, 0.5), (277.18, 0.35)):
    for d in (-0.003, 0.0, 0.003):
        ph = 2 * np.pi * f * (1 + d) * t + 0.35 * np.sin(2 * np.pi * (0.2 + d * 40) * t)
        pad += a * (np.sin(ph) + 0.35 * np.sin(2 * ph) + 0.12 * np.sin(3 * ph)) / 3
pad = lowpass(pad, 1800) * env(ti + 0.05, 0.9, 1.3, 1.9, 0.028)
add(pad, -0.2, 1.0)
add(np.roll(pad, int(0.017 * SR)), 0.2, 1.0)

# --- 6. latidos del aro (2,9 y 4,5 s) y notas de saludo (3,1 / 3,5 / 3,9 s) -------------------------------------------------
for tp in (2.9, 4.5):
    xp = np.clip(t - tp, 0, None)
    add(np.sin(2 * np.pi * 52 * xp * np.exp(-xp / 1.2)) * np.exp(-xp / 0.45) * (t >= tp) * 0.16, 0)
for tn, f in ((3.1, 1318.51), (3.5, 1479.98), (3.9, 1760.0)):
    add(bell(f, tn, dur=1.9, amp=0.085, bright=0.9), 0.1)

# --- reverberación (respuesta sintética de sala grande) y masterización -----------------------------------------------------
ir_len = int(2.3 * SR)
irx = np.arange(ir_len) / SR
ir = [rng.standard_normal(ir_len) * np.exp(-irx / 0.55) for _ in range(2)]
ir = [lowpass(c, 5200) for c in ir]
size = 1 << (N + ir_len - 1).bit_length()
wetL = np.fft.irfft(np.fft.rfft(L, size) * np.fft.rfft(ir[0], size), size)[:N]
wetR = np.fft.irfft(np.fft.rfft(R, size) * np.fft.rfft(ir[1], size), size)[:N]
wet = 0.045
L2 = L + wet * wetL
R2 = R + wet * wetR
fade = np.minimum(1, (LEN - t) / 0.7)                                  # desvanecido final
fade_in = np.minimum(1, t / 0.03)
L2, R2 = np.tanh(L2 * fade * fade_in), np.tanh(R2 * fade * fade_in)
peak = max(np.abs(L2).max(), np.abs(R2).max())
L2, R2 = L2 / peak * TARGET, R2 / peak * TARGET


def write(path):
    data = (np.stack([L2, R2], 1) * 32767).astype("<i2")
    with wave.open(str(path), "wb") as w:
        w.setnchannels(2); w.setsampwidth(2); w.setframerate(SR); w.writeframes(data.tobytes())


if __name__ == "__main__":
    out = Path(sys.argv[1] if len(sys.argv) > 1 else Path(__file__).resolve().parents[2] / "assets/sounds/omnia/welcome.wav")
    out.parent.mkdir(parents=True, exist_ok=True)
    write(out)
    rms = float(np.sqrt(np.mean(np.concatenate([L2, R2]) ** 2)))
    print(f"{out} · {LEN:.1f} s · pico {20*np.log10(TARGET):.1f} dBFS · RMS {20*np.log10(rms):.1f} dBFS")
    try:
        subprocess.run(["ffmpeg", "-y", "-loglevel", "error", "-i", str(out), "-c:a", "libvorbis", "-q:a", "5", str(out.with_suffix(".ogg"))], check=True)
        print(out.with_suffix(".ogg"), out.with_suffix(".ogg").stat().st_size, "bytes")
    except (OSError, subprocess.CalledProcessError) as e:
        print("sin OGG:", e)

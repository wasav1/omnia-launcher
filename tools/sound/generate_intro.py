#!/usr/bin/env python3
"""Banda sonora de la introducción de Big Mode («cintas de seda → destello → logo»), sintetizada desde cero.

Sigue la estructura que se midió en los vídeos de referencia (10 s):
   0,0–1,2  casi silencio: aire y un retumbo que crece
   0,8–2,7  las cintas de seda entran (barridos que cruzan de lado a lado, claro y oscuro)
   1,5–3,6  chispas (crepitar) y cuerdas que suben; hueco de tensión a 3,0–3,3
   3,3–3,72 inspiración: platillo invertido y «vaciado» del sonido justo antes del golpe
   3,75     DESTELLO: impacto muy grave, estallido radial y brillo; la cola grave dura hasta ~6 s
   4,2–8,6  acorde cálido (Re mayor con novena) y partículas que centellean
   5,9–7,3  luz que orbita el logo (brillo circular que gira entre altavoces) y aparición del nombre
   8,3      campana final larga; desvanecido hasta 10,0

    python3 tools/sound/generate_intro.py [salida.wav]      # también escribe .ogg si hay ffmpeg
"""
import subprocess, sys, wave
from pathlib import Path
import numpy as np

SR = 44100
LEN = 10.0
N = int(SR * LEN)
TARGET = 0.5
rng = np.random.default_rng(11)
t = np.arange(N) / SR
L = np.zeros(N)
R = np.zeros(N)


def env(start, attack, hold, release, amp=1.0):
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
    x = np.clip((t - start) / dur, 0, 1)
    return 2 * np.pi * np.cumsum(f0 * (f1 / f0) ** (x ** (1 / curve))) / SR


def stft_filter(sig, centers, width_oct, n=2048, hop=512):
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
    return (out / np.maximum(norm, 1e-6))[:len(sig)]


def lowpass(sig, fc):
    a = np.exp(-2 * np.pi * fc / SR)
    out = np.zeros_like(sig)
    y = 0.0
    for i, x in enumerate(sig):
        y = (1 - a) * x + a * y
        out[i] = y
    return out


def highpass(sig, fc):
    return sig - lowpass(sig, fc)


def bell(freq, start, dur=2.2, amp=0.2, bright=1.0):
    sig = np.zeros(N)
    x = np.clip(t - start, 0, None)
    for ratio, a, d in ((1.0, 1.0, 1.0), (2.01, 0.55 * bright, 0.7), (2.76, 0.35 * bright, 0.5), (4.07, 0.22 * bright, 0.35), (5.4, 0.12 * bright, 0.25)):
        e = np.where(t >= start, np.exp(-x / (dur * d / 4.2)), 0) * np.minimum(1, x / 0.004)
        sig += a * np.sin(2 * np.pi * freq * ratio * x) * e
    return sig * amp


def add(sig, pan=0.0, gain=1.0):
    """pan: número fijo o arreglo de −1 a 1 (ley de potencia constante)."""
    ang = (np.asarray(pan) + 1) * np.pi / 4
    L[:] += sig * np.cos(ang) * gain
    R[:] += sig * np.sin(ang) * gain


def ramp(a, b, start, dur):
    """Valor que va de a a b entre start y start+dur (constante fuera)."""
    return a + (b - a) * np.clip((t - start) / dur, 0, 1)


HIT = 3.75
noise = rng.standard_normal(N)

# "vaciado" justo antes del golpe: las capas previas bajan 3,66–3,74 y vuelven a 1 en el impacto
duck = np.ones(N)
duck -= 0.85 * np.clip((t - 3.66) / 0.04, 0, 1) * (t < HIT)
duck = np.where(t >= HIT, 1.0, duck)

# --- 1. aire y retumbo que crece -------------------------------------------------------------------------------------------------
air = stft_filter(noise, lambda x: 120 + 160 * min(x / 3.6, 1), 1.3) * env(0.2, 3.2, 0.25, 0.1, 0.16) * duck
add(air, np.sin(2 * np.pi * 0.12 * t) * 0.5)
add(np.sin(sweep(34, 49, 0.3, 3.4)) * env(0.3, 3.2, 0.3, 0.08, 0.085) * duck, 0)

# --- 2. cintas de seda: dos barridos que cruzan el estéreo (claro de izquierda a derecha, oscuro de derecha a izquierda) -------------
w1 = stft_filter(noise, lambda x: 300 * (3400 / 300) ** np.clip((x - 0.85) / 1.25, 0, 1), 1.0)
w1 *= np.exp(-0.5 * ((t - 1.65) / 0.42) ** 2) * 0.55
add(w1 * duck, ramp(-0.95, 0.95, 0.85, 1.25))
w2 = stft_filter(rng.standard_normal(N), lambda x: 2600 * (380 / 2600) ** np.clip((x - 1.45) / 1.3, 0, 1), 0.9)
w2 *= np.exp(-0.5 * ((t - 2.2) / 0.5) ** 2) * 0.5
add(w2 * duck, ramp(0.9, -0.9, 1.45, 1.3))

# --- 3. chispas (crepitar de ascuas) --------------------------------------------------------------------------------------------
sparks = np.zeros(N)
for _ in range(95):
    when = 1.5 + 2.2 * rng.random() ** 0.7
    i0 = int(when * SR)
    ln = int(rng.uniform(0.0008, 0.004) * SR)
    sparks[i0:i0 + ln] += rng.standard_normal(ln) * rng.uniform(0.2, 0.7) * np.hanning(ln)
sparks = highpass(sparks, 3500)
add(sparks * 0.5 * duck, rng.uniform(-0.9, 0.9, N).cumsum() * 0 + np.sin(2 * np.pi * 0.7 * t))

# --- 4. cuerdas que suben, con respiro de tensión en 3,0–3,3 -------------------------------------------------------------------
strings = np.zeros(N)
for det in (0.0, 0.35, -0.35):
    ph = sweep(146.83 * 2 ** (det / 60), 293.66 * 2 ** (det / 60), 1.7, 2.0)
    strings += sum(np.sin(h * ph) / h for h in range(1, 7))
strings = lowpass(strings, 2200)
breath = 1 - 0.55 * np.exp(-0.5 * ((t - 3.15) / 0.12) ** 2)
add(strings * env(1.7, 1.6, 0.3, 0.1, 0.05) * breath * duck, 0)

# --- 5. inspiración: platillo invertido que culmina en el golpe ---------------------------------------------------------------
rc = stft_filter(rng.standard_normal(N), lambda x: 5200, 1.5) * env(2.9, 0.82, 0.0, 0.03, 0.30)
add(rc, 0.15)

# --- 6. destello: impacto, estallido radial y brillo -------------------------------------------------------------------------------
x = np.clip(t - HIT, 0, None)
boom = np.sin(2 * np.pi * (31 * x + 80 * (1 - np.exp(-x * 6)) / 6)) * np.exp(-x / 0.7) * (t >= HIT)
thump = lowpass(rng.standard_normal(N), 700) * np.exp(-x / 0.12) * (t >= HIT)
add(boom, 0, 0.9)
add(thump, 0, 0.4)
burst = stft_filter(rng.standard_normal(N), lambda xx: 7000 * (700 / 7000) ** np.clip((xx - HIT) / 1.0, 0, 1), 1.2) * env(HIT, 0.02, 0.08, 0.9, 0.7)
burst2 = stft_filter(rng.standard_normal(N), lambda xx: 7000 * (700 / 7000) ** np.clip((xx - HIT) / 1.0, 0, 1), 1.2) * env(HIT, 0.02, 0.08, 0.9, 0.7)
L[:] += burst
R[:] += burst2                                                       # dos ruidos distintos: el estallido se abre por todo el estéreo
add(bell(1174.66, HIT + 0.01, dur=3.8, amp=0.2, bright=1.4), -0.2)
add(bell(1760.0, HIT + 0.02, dur=3.4, amp=0.12, bright=1.3), 0.25)
add(bell(2349.3, HIT + 0.03, dur=2.6, amp=0.07, bright=1.2), 0.0)

# --- 7. acorde cálido (Re2 La2 Mi3 Fa#3 La3 Do#4) -------------------------------------------------------------------------------
pad = np.zeros(N)
for f, a in ((73.42, 0.9), (110.0, 0.8), (164.81, 0.7), (185.0, 0.55), (220.0, 0.5), (277.18, 0.35)):
    for d in (-0.003, 0.0, 0.003):
        ph = 2 * np.pi * f * (1 + d) * t + 0.35 * np.sin(2 * np.pi * (0.2 + d * 40) * t)
        pad += a * (np.sin(ph) + 0.35 * np.sin(2 * ph) + 0.12 * np.sin(3 * ph)) / 3
pad = lowpass(pad, 1700) * env(4.2, 1.3, 2.6, 2.2, 0.016)
add(pad, -0.2)
add(np.roll(pad, int(0.019 * SR)), 0.2)

# --- 8. partículas que centellean (pentatónica de Re mayor) -----------------------------------------------------------------
penta = [587.33, 659.25, 739.99, 880.0, 987.77, 1174.66, 1318.51, 1479.98]
for i in range(26):
    when = 4.5 + 1.7 * rng.random() ** 1.2
    add(bell(penta[rng.integers(len(penta))], when, dur=1.7, amp=0.03 + 0.014 * rng.random(), bright=0.8), rng.uniform(-0.9, 0.9))

# --- 9. luz que orbita el logo (brillo circular entre altavoces) y aparición del nombre --------------------------------------------
for start, dur, amp in ((5.9, 1.4, 0.2), (7.4, 1.0, 0.11)):
    orb = highpass(stft_filter(rng.standard_normal(N), lambda xx: 5200, 1.1), 3000) * np.sin(np.pi * np.clip((t - start) / dur, 0, 1)) ** 2 * amp
    ph = sweep(780, 3100, start, dur)
    orb += np.sin(ph + 0.8 * np.sin(2 * np.pi * 6 * t)) * np.sin(np.pi * np.clip((t - start) / dur, 0, 1)) ** 2 * amp * 0.22
    add(orb, np.sin(2 * np.pi * (1 / dur) * (t - start) * 1.5) * 0.95)
sw = np.sin(sweep(55, 70, 6.1, 0.6)) * env(6.1, 0.45, 0.1, 0.9, 0.12)
add(sw, 0)
add(bell(587.33, 6.45, dur=2.4, amp=0.065, bright=1.0), 0.0)             # «OM»
add(bell(880.0, 6.9, dur=2.8, amp=0.065, bright=1.0), 0.0)               # «NIA»

# --- 10. campana final ------------------------------------------------------------------------------------------------------------
add(bell(880.0, 8.3, dur=3.2, amp=0.07, bright=1.0), -0.1)
add(bell(1318.51, 8.32, dur=3.0, amp=0.05, bright=1.0), 0.1)
add(bell(1760.0, 8.34, dur=2.6, amp=0.032, bright=1.1), 0.0)

# --- reverberación y masterización ---------------------------------------------------------------------------------------------------
ir_len = int(2.6 * SR)
irx = np.arange(ir_len) / SR
ir = [lowpass(rng.standard_normal(ir_len) * np.exp(-irx / 0.6), 5000) for _ in range(2)]
size = 1 << (N + ir_len - 1).bit_length()
wetL = np.fft.irfft(np.fft.rfft(L, size) * np.fft.rfft(ir[0], size), size)[:N]
wetR = np.fft.irfft(np.fft.rfft(R, size) * np.fft.rfft(ir[1], size), size)[:N]
L2 = L + 0.05 * wetL
R2 = R + 0.05 * wetR
fade = np.minimum(1, (LEN - t) / 0.8)
L2, R2 = np.tanh(L2 * fade), np.tanh(R2 * fade)
peak = max(np.abs(L2).max(), np.abs(R2).max())
L2, R2 = L2 / peak * TARGET, R2 / peak * TARGET


def write(path):
    data = (np.stack([L2, R2], 1) * 32767).astype("<i2")
    with wave.open(str(path), "wb") as w:
        w.setnchannels(2); w.setsampwidth(2); w.setframerate(SR); w.writeframes(data.tobytes())


if __name__ == "__main__":
    out = Path(sys.argv[1] if len(sys.argv) > 1 else Path(__file__).resolve().parents[2] / "assets/sounds/omnia/intro.wav")
    out.parent.mkdir(parents=True, exist_ok=True)
    write(out)
    m = (L2 + R2) / 2
    print(out, f"· {LEN:.1f} s · pico {20*np.log10(TARGET):.1f} dBFS · RMS {20*np.log10(np.sqrt((np.concatenate([L2, R2])**2).mean())):.1f} dBFS")
    print(" ".join(f"{i/10:.1f}:{20*np.log10(np.sqrt((m[int(i*.1*SR):int((i+5)*.1*SR)]**2).mean())+1e-9):.0f}" for i in range(0, 100, 5)))
    try:
        subprocess.run(["ffmpeg", "-y", "-loglevel", "error", "-i", str(out), "-c:a", "libvorbis", "-q:a", "5", str(out.with_suffix(".ogg"))], check=True)
        print(out.with_suffix(".ogg").name, out.with_suffix(".ogg").stat().st_size, "bytes")
    except (OSError, subprocess.CalledProcessError) as e:
        print("sin OGG:", e)

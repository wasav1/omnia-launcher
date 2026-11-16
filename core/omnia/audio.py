"""Captura el monitor de salida y resume el espectro en 16 bandas.

El audio solo vive en memoria. `parec` lee el monitor de PipeWire-Pulse y
Omnia expone niveles agregados, nunca muestras de audio, por su API local.
"""
from __future__ import annotations

import math
import shutil
import subprocess
import threading


RATE = 48000
SIZE = 2048
BANDS = 16
LOW_HZ = 20.0
HIGH_HZ = RATE / 2


def _fft(values: list[complex]) -> list[complex]:
    """FFT radix-2 in-place, returned as a new list."""
    n = len(values)
    out = values[:]
    j = 0
    for i in range(1, n):
        bit = n >> 1
        while j & bit:
            j ^= bit
            bit >>= 1
        j ^= bit
        if i < j:
            out[i], out[j] = out[j], out[i]
    length = 2
    while length <= n:
        angle = -2.0 * math.pi / length
        root = complex(math.cos(angle), math.sin(angle))
        half = length >> 1
        for start in range(0, n, length):
            factor = 1 + 0j
            for k in range(start, start + half):
                even = out[k]
                odd = factor * out[k + half]
                out[k] = even + odd
                out[k + half] = even - odd
                factor *= root
        length <<= 1
    return out


def spectrum(samples: list[int]) -> list[float]:
    """Return 16 logarithmic RMS bands (20 Hz–Nyquist), normalized 0..1."""
    if len(samples) != SIZE:
        return [0.0] * BANDS
    windowed = []
    for i, sample in enumerate(samples):
        hann = 0.5 - 0.5 * math.cos(2.0 * math.pi * i / (SIZE - 1))
        windowed.append(complex((sample / 32768.0) * hann, 0.0))
    bins = _fft(windowed)
    powers = [(abs(bins[i]) * 2.0 / SIZE) ** 2 for i in range(SIZE // 2 + 1)]
    edges = [LOW_HZ * (HIGH_HZ / LOW_HZ) ** (i / BANDS) for i in range(BANDS + 1)]
    result = []
    for band in range(BANDS):
        first = max(1, math.ceil(edges[band] * SIZE / RATE))
        last = min(SIZE // 2, math.ceil(edges[band + 1] * SIZE / RATE))
        chunk = powers[first:last]
        rms = math.sqrt(sum(chunk) / len(chunk)) if chunk else 0.0
        db = 20.0 * math.log10(max(rms, 1e-6))
        result.append(max(0.0, min(1.0, (db + 72.0) / 54.0)))
    return result


class AudioSpectrum:
    """Background reader for the default output monitor."""

    def __init__(self, log=None):
        self.log = log or (lambda _message: None)
        self._lock = threading.Lock()
        self._stop = threading.Event()
        self._thread: threading.Thread | None = None
        self._proc: subprocess.Popen | None = None
        self._bands = [0.0] * BANDS
        self._available = False
        self._active = False
        self._warned = False

    def start(self):
        if not shutil.which("parec"):
            self.log("espectro de audio inactivo: instala pipewire-pulse (parec)")
            return
        if self._thread and self._thread.is_alive():
            return
        self._stop.clear()
        self._thread = threading.Thread(target=self._run, name="omnia-audio", daemon=True)
        self._thread.start()

    def stop(self):
        self._stop.set()
        proc = self._proc
        if proc and proc.poll() is None:
            proc.terminate()
        if self._thread and self._thread.is_alive():
            self._thread.join(timeout=2)

    def snapshot(self) -> dict:
        with self._lock:
            return {"available": self._available, "active": self._active,
                    "bands": self._bands[:], "rate": RATE, "bandCount": BANDS}

    def _publish(self, values):
        peak = max(values, default=0.0)
        with self._lock:
            self._bands = values
            self._available = True
            self._active = peak >= 0.035

    def _run(self):
        while not self._stop.is_set():
            proc = None
            try:
                proc = subprocess.Popen(
                    ["parec", "--raw", "--format=s16le", f"--rate={RATE}", "--channels=1",
                     "--device=@DEFAULT_MONITOR@", "--latency-msec=90", "--stream-name=Omnia Audio Spectrum"],
                    stdin=subprocess.DEVNULL, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL,
                    start_new_session=True)
                self._proc = proc
                stream = proc.stdout
                while not self._stop.is_set():
                    raw = stream.read(SIZE * 2)
                    if len(raw) != SIZE * 2:
                        break
                    samples = [int.from_bytes(raw[i:i + 2], "little", signed=True)
                               for i in range(0, len(raw), 2)]
                    self._publish(spectrum(samples))
                if proc.poll() is None:
                    proc.terminate()
                proc.wait(timeout=1)
                if not self._stop.is_set() and not self._warned:
                    self.log("parec perdió el monitor de audio; reintentando")
                    self._warned = True
            except (OSError, subprocess.SubprocessError) as exc:
                if not self._stop.is_set() and not self._warned:
                    self.log(f"no se pudo abrir el monitor de audio: {exc}")
                    self._warned = True
            finally:
                self._proc = None
                if proc and proc.stdout:
                    proc.stdout.close()
            with self._lock:
                self._available = False
                self._active = False
            if not self._stop.wait(3):
                continue
            break


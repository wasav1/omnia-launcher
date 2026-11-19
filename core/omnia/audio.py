"""Espectro de la salida de audio para las ondas del escritorio.

El audio solo vive en memoria: `parec` lee el monitor de PipeWire-Pulse y Omnia expone niveles agregados
(32 bandas), nunca muestras, por su API local.

Motor ligero en Python puro (sin numpy): bandas en escala mel de 55 Hz a 9,5 kHz y un Goertzel por banda con ventana
propia (larga en graves para resolver mejor, corta en agudos para reaccionar rápido). Cada trozo de 20 ms recalcula la
mitad de las bandas, así que el coste queda en pocos puntos de CPU (una FFT de 2048 puntos en Python costaba ~27 %).
Sin sonido no se analiza nada.
"""
from __future__ import annotations

import array
import math
import shutil
import subprocess
import threading

RATE = 22050            # cubre hasta ~11 kHz: suficiente para las ondas
CHUNK = 441             # muestras por lectura = 20 ms
BANDS = 32
LOW_HZ = 55.0
HIGH_HZ = 9500.0
WINDOW = 512            # historial de muestras (la ventana de cada banda es una cola de este)
SILENCE_PEAK = 90       # pico absoluto (s16) por debajo del cual se considera silencio
PEAK_FLOOR = 80.0
PEAK_DECAY = 0.996      # el normalizador cae poco a poco: respeta la dinámica de la música
GAMMA = 0.7
TILT = 0.07             # realce suave hacia agudos (la música cae con la frecuencia)


def band_plan(rate: int = RATE, bands: int = BANDS):
    """[(coeficiente Goertzel, longitud de ventana, ventana Hann)] por banda, con centros equiespaciados en mel."""
    def mel(f): return 2595.0 * math.log10(1.0 + f / 700.0)
    def imel(m): return 700.0 * (10.0 ** (m / 2595.0) - 1.0)
    lo, hi = mel(LOW_HZ), mel(HIGH_HZ)
    centers = [imel(lo + (hi - lo) * i / (bands - 1)) for i in range(bands)]
    plan = []
    for i, f in enumerate(centers):
        a = centers[i - 1] if i > 0 else f / 1.2
        b = centers[i + 1] if i < bands - 1 else f * 1.2
        bw = max(20.0, (b - a) / 2.0)
        n = int(min(WINDOW, max(48, 1.6 * rate / bw)))
        win = [0.5 - 0.5 * math.cos(2 * math.pi * k / (n - 1)) for k in range(n)]
        plan.append((2.0 * math.cos(2 * math.pi * f / rate), n, win))
    return plan


def goertzel(samples, coeff: float, window) -> float:
    """Amplitud (no normalizada) de una frecuencia en las últimas len(window) muestras."""
    n = len(window)
    q1 = q2 = 0.0
    for v, w in zip(samples[-n:], window):
        q0 = coeff * q1 - q2 + v * w
        q2 = q1
        q1 = q0
    return max(0.0, q1 * q1 + q2 * q2 - coeff * q1 * q2) ** 0.5 / n


class Analyzer:
    """Estado del análisis: recibe trozos de muestras s16 y devuelve las bandas 0..1 (o ceros en silencio)."""

    def __init__(self, rate: int = RATE, bands: int = BANDS):
        self.bands = bands
        self.plan = band_plan(rate, bands)
        self.buf = array.array("h", [0] * WINDOW)
        self.values = [0.0] * bands
        self.peak = PEAK_FLOOR * 1.5
        self.parity = 0

    def feed(self, chunk: array.array) -> list[float]:
        if not len(chunk):
            return [0.0] * self.bands
        self.buf.extend(chunk)
        if len(self.buf) > WINDOW:
            del self.buf[:len(self.buf) - WINDOW]
        if max(max(chunk), -min(chunk)) < SILENCE_PEAK or len(self.buf) < WINDOW:
            self.values = [0.0] * self.bands
            return list(self.values)
        par = self.parity
        self.parity ^= 1
        for i, (coeff, _n, win) in enumerate(self.plan):
            if (i & 1) != par:
                continue                                    # cada trozo recalcula la mitad de las bandas (25 Hz por banda)
            self.values[i] = goertzel(self.buf, coeff, win) * (1.0 + i * TILT)
        self.peak = max(max(self.values), self.peak * PEAK_DECAY, PEAK_FLOOR)
        return [round(min(1.0, (v / self.peak) ** GAMMA), 3) for v in self.values]


class AudioSpectrum:
    """Lector en segundo plano del monitor de la salida por defecto."""

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
        with self._lock:
            self._bands = values
            self._available = True
            self._active = max(values, default=0.0) > 0.0

    def _run(self):
        analyzer = Analyzer()
        while not self._stop.is_set():
            proc = None
            try:
                proc = subprocess.Popen(
                    ["parec", "--raw", "--format=s16le", f"--rate={RATE}", "--channels=1",
                     "--device=@DEFAULT_MONITOR@", "--latency-msec=20", "--stream-name=Omnia Audio Spectrum"],
                    stdin=subprocess.DEVNULL, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL,
                    start_new_session=True)
                self._proc = proc
                stream = proc.stdout
                while not self._stop.is_set():
                    raw = stream.read(CHUNK * 2)
                    if len(raw) != CHUNK * 2:
                        break
                    chunk = array.array("h")
                    chunk.frombytes(raw)
                    self._publish(analyzer.feed(chunk))
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

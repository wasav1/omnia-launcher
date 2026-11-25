"""Muestras de transferencias a partir de contadores publicados por cada instalador."""
import re
import threading
import time
from collections import deque


class TransferMetrics:
    def __init__(self, clock=time.monotonic):
        self.clock = clock
        self.lock = threading.Lock()
        self.observed = {}

    def observe(self, jobs):
        with self.lock:
            now = self.clock()
            active = {job["id"] for job in jobs}
            for key in self.observed.keys() - active:
                del self.observed[key]
            for job in jobs:
                self._sample(job, now)
        return jobs

    def _sample(self, job, now):
        network = job.get("downloadedBytes")
        disk = job.get("writtenBytes")
        rate_match = re.fullmatch(r"([0-9.]+)\s*([KMG])(i?)B/s", str(job.get("speed") or ""), re.I)
        reported_rate = None
        if rate_match:
            try:
                reported_rate = float(rate_match[1]) * ((1024 if rate_match[3] else 1000) ** ("KMG".index(rate_match[2].upper()) + 1))
                if not 0 <= reported_rate < 10**12:
                    reported_rate = None
            except ValueError:
                pass
        if network is None and disk is None and reported_rate is None:
            return
        key = job["id"]
        old = self.observed.get(key)
        if old is None:
            old = self.observed[key] = {
                "time": now, "bytes": (network, disk), "history": deque(maxlen=40),
                "peak": None, "rate": None, "diskRate": None,
            }
        elapsed = now - old["time"]
        if elapsed >= 0.75:
            speeds = [
                max(0, current - previous) / elapsed if current is not None and previous is not None else None
                for current, previous in zip((network, disk), old["bytes"])
            ]
            if reported_rate is not None:
                speeds[0] = reported_rate
            old.update(time=now, bytes=(network, disk), rate=speeds[0], diskRate=speeds[1])
            if speeds[0] is not None:
                old["peak"] = max(old["peak"] or 0, speeds[0])
            old["history"].append({"network": speeds[0], "disk": speeds[1]})
        job["networkRate"] = (reported_rate if reported_rate is not None else old["rate"]) if job["status"] == "downloading" else None
        job["diskRate"] = old["diskRate"] if job["status"] in {"downloading", "extracting", "finalizing"} else None
        job["networkPeak"] = old["peak"]
        job["rateHistory"] = list(old["history"])
        total = job.get("downloadTotal")
        rate = job["networkRate"]
        if total and network is not None and rate and network < total:
            job["etaSeconds"] = round((total - network) / rate)

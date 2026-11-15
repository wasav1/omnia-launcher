"""Bus de eventos del mando: la UI los recoge con una petición larga (/events), igual que el prototipo."""
import threading
import time
from collections import deque


class EventBus:
    def __init__(self, maxlen: int = 200):
        self.cv = threading.Condition()
        self.seq = 0
        self.events = deque(maxlen=maxlen)
        self.pad = {"connected": False, "name": "", "layout": ""}
        # lo publica el vigilante de ventanas de KWin: ¿manda la estantería (no hay una ventana normal activa) y está tapada?
        self.desktop = {"active": True, "covered": False}

    def set_desktop(self, active: bool, covered: bool) -> None:
        with self.cv:
            if self.desktop != {"active": active, "covered": covered}:
                self.desktop = {"active": active, "covered": covered}
                self.cv.notify_all()

    def push(self, key: str) -> None:
        with self.cv:
            self.seq += 1
            self.events.append({"seq": self.seq, "key": key, "t": round(time.time(), 3)})
            self.cv.notify_all()

    def set_pad(self, connected: bool, name: str = "", layout: str = "") -> None:
        with self.cv:
            self.pad = {"connected": connected, "name": name, "layout": layout}
            self.cv.notify_all()

    def snapshot(self, since: int) -> dict:
        return {"seq": self.seq, "events": [e for e in self.events if e["seq"] > since],
                "padOn": self.pad["connected"], "padName": self.pad["name"], "padLayout": self.pad["layout"],
                "shelfActive": self.desktop["active"], "covered": self.desktop["covered"]}

    def wait(self, since: int, timeout: float) -> dict:
        """Devuelve en cuanto haya eventos nuevos o al agotar el tiempo. since < 0: solo el contador actual
        (así un cliente nuevo no repite eventos viejos)."""
        end = time.time() + timeout
        with self.cv:
            if since < 0:
                return self.snapshot(self.seq)
            since = min(since, self.seq)
            while True:
                snap = self.snapshot(since)
                if snap["events"] or time.time() >= end:
                    return snap
                self.cv.wait(timeout=max(0.05, end - time.time()))

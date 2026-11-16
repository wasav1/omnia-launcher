"""Historial de juego: sesiones, último jugado y tiempo total por juego.

Se alimenta del mismo sondeo rápido que el modo juego (cada 350 ms). Reglas:
  * Una sesión empieza tras 2 sondeos seguidos con el juego en marcha y termina tras 2 sin verlo,
    para no contar parpadeos de lanzadores; la duración llega hasta la ÚLTIMA vez que se vio el juego, no hasta que se
    notó que se había cerrado.
  * Las sesiones de menos de 10 s no cuentan (un lanzador que abre y cierra).
  * Si el servicio muere en mitad de una partida, la sesión se anota cada 30 s en `active_sessions` y se cierra al
    arrancar de nuevo con la última hora vista (se pierden como mucho 30 s).
Todo vive en state.json: sessions[id], last_played[id], active_sessions, history (últimas 200 sesiones).
"""
import logging
import time

log = logging.getLogger("omnia")

START_AFTER, END_AFTER = 2, 2
MIN_SECS = 10
PERSIST_EVERY = 30
HISTORY_MAX = 200


class Sessions:
    def __init__(self, store, now=time.time, say=log.info):
        self.store, self.now, self.say = store, now, say
        self.active = {}        # id -> {"name", "start", "seen", "absent"}
        self._pending = {}      # id -> (sondeos seguidos, primera vez visto)
        self._persisted = 0.0

    # --- ciclo de vida
    def recover(self) -> int:
        """Cierra las sesiones que quedaron abiertas si el servicio murió, con la última hora vista."""
        n = 0
        with self.store.lock:
            left = dict(self.store.state.get("active_sessions") or {})
            self.store.state["active_sessions"] = {}
            for gid, a in left.items():
                n += bool(self._close(gid, a.get("name", gid), a.get("start", 0), a.get("seen", a.get("start", 0))))
            self.store.save_state()
        return n

    def update(self, running: dict) -> bool:
        """running: {id del juego: nombre}. Devuelve True si empezó o terminó alguna sesión."""
        now, changed = self.now(), False
        with self.store.lock:
            for gid, name in running.items():
                if gid in self.active:
                    self.active[gid]["seen"], self.active[gid]["absent"] = now, 0
                    continue
                count, first = self._pending.get(gid, (0, now))
                if count + 1 >= START_AFTER:
                    self.active[gid] = {"name": name, "start": first, "seen": now, "absent": 0}
                    self._pending.pop(gid, None)
                    self.say("sesión iniciada: %s", name)
                    changed = True
                else:
                    self._pending[gid] = (count + 1, first)
            for gid in [g for g in self._pending if g not in running]:
                del self._pending[gid]
            for gid in [g for g in self.active if g not in running]:
                a = self.active[gid]
                a["absent"] += 1
                if a["absent"] >= END_AFTER:
                    del self.active[gid]
                    self._close(gid, a["name"], a["start"], a["seen"])
                    changed = True
            if changed or now - self._persisted >= PERSIST_EVERY:
                self._persist(now)
        return changed

    def shutdown(self) -> None:
        """Al parar el servicio: las sesiones en curso se cierran con la hora actual."""
        now = self.now()
        with self.store.lock:
            for gid, a in list(self.active.items()):
                self._close(gid, a["name"], a["start"], now)
            self.active.clear()
            self._persist(now)

    # --- datos
    def snapshot(self, gid: str) -> dict:
        """Lo que se muestra de un juego: último jugado, tiempo total (incluida la sesión en curso) y partidas."""
        with self.store.lock:
            s = (self.store.state.get("sessions") or {}).get(gid) or {}
            a = self.active.get(gid)
            now = self.now()
            total = int(s.get("total_secs", 0)) + (int(now - a["start"]) if a else 0)
            return {"lastPlayed": int(now) if a else int(self.store.state.get("last_played", {}).get(gid, 0)),
                    "totalSecs": total, "plays": int(s.get("count", 0)) + (1 if a else 0),
                    "playingSince": int(a["start"]) if a else 0}

    def _close(self, gid, name, start, end) -> bool:
        secs = int(end - start)
        if secs < MIN_SECS:
            return False
        st = self.store.state
        s = st.setdefault("sessions", {}).setdefault(gid, {"total_secs": 0, "count": 0})
        s["total_secs"] += secs
        s["count"] += 1
        s["last_secs"], s["last_started"], s["last_ended"] = secs, int(start), int(end)
        st.setdefault("last_played", {})[gid] = int(end)
        hist = st.setdefault("history", [])
        hist.append({"id": gid, "name": name, "start": int(start), "end": int(end), "secs": secs})
        del hist[:-HISTORY_MAX]
        self.say("sesión terminada: %s (%d min %d s)", name, secs // 60, secs % 60)
        return True

    def _persist(self, now) -> None:
        self.store.state["active_sessions"] = {g: {"name": a["name"], "start": int(a["start"]), "seen": int(a["seen"])}
                                               for g, a in self.active.items()}
        self.store.save_state()
        self._persisted = now

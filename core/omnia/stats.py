"""Estadísticas de juego a partir del historial de sesiones (state.json). Función pura: no toca disco ni red."""
import time

DAY = 86400


def _midnight(ts: float) -> int:
    t = time.localtime(ts)
    return int(time.mktime((t.tm_year, t.tm_mon, t.tm_mday, 0, 0, 0, 0, 0, -1)))


def _day_start(day0: int, n: int) -> int:
    """Medianoche local del día `day0` + n días (robusto a cambios de hora)."""
    return _midnight(day0 + n * DAY + 12 * 3600)


def compute(state: dict, games: list, active: dict, now: float, days: int = 14, history_max: int = 1000) -> dict:
    """active: {id: {"name", "start"}} de las sesiones en curso (cuentan hasta ahora)."""
    names = {g.get("id"): g.get("name", g.get("id")) for g in games}
    sessions = state.get("sessions") or {}
    history = [h for h in (state.get("history") or []) if isinstance(h, dict) and h.get("end", 0) > h.get("start", 0)]
    live = [{"id": gid, "name": a.get("name", gid), "start": int(a["start"]), "end": int(now), "secs": int(now - a["start"])}
            for gid, a in (active or {}).items() if now > a.get("start", now)]
    events = history + live

    # tiempo por juego de todos los tiempos (sessions[id] + sesión en curso)
    totals = {}
    for gid, s in sessions.items():
        totals[gid] = {"secs": int(s.get("total_secs", 0)), "plays": int(s.get("count", 0))}
    for e in live:
        t = totals.setdefault(e["id"], {"secs": 0, "plays": 0})
        t["secs"] += e["secs"]
        t["plays"] += 1

    def top(source, limit=10):
        rows = [{"id": gid, "name": names.get(gid) or next((e["name"] for e in events if e["id"] == gid), gid), "secs": v["secs"], "plays": v["plays"]}
                for gid, v in source.items() if v["secs"] > 0]
        rows.sort(key=lambda r: -r["secs"])
        return rows[:limit]

    # últimos N días: segundos por día local (una sesión que cruza la medianoche se reparte)
    today0 = _midnight(now)
    day_starts = [_day_start(today0, -i) for i in range(days - 1, -1, -1)]
    per_day = [0] * days
    recent = {}
    recent_cut = day_starts[0]
    for e in events:
        if e["end"] <= recent_cut:
            continue
        r = recent.setdefault(e["id"], {"secs": 0, "plays": 0})
        r["plays"] += 1
        for i, start in enumerate(day_starts):
            end = day_starts[i + 1] if i + 1 < days else today0 + 2 * DAY
            lo, hi = max(e["start"], start), min(e["end"], end)
            if hi > lo:
                per_day[i] += hi - lo
                r["secs"] += hi - lo

    # racha: días seguidos con juego, contando hoy o ayer como último
    played_days = set()
    for e in events:
        d = _midnight(e["start"])
        last = _midnight(e["end"])
        while d <= last and len(played_days) < 4000:
            played_days.add(d)
            d = _day_start(d, 1)
    streak, cursor = 0, today0 if today0 in played_days else _day_start(today0, -1)
    while cursor in played_days:
        streak += 1
        cursor = _day_start(cursor, -1)

    secs_all = sum(v["secs"] for v in totals.values())
    longest = max(events, key=lambda e: e["secs"], default=None)
    n_sessions = sum(v["plays"] for v in totals.values())
    return {
        "totalSecs": secs_all, "sessions": n_sessions, "gamesPlayed": sum(1 for v in totals.values() if v["secs"] > 0),
        "avgSessionSecs": int(secs_all / n_sessions) if n_sessions else 0,
        "longest": {"name": longest["name"], "secs": longest["secs"], "start": longest["start"]} if longest else None,
        "streakDays": streak, "days": [{"start": s, "secs": v} for s, v in zip(day_starts, per_day)],
        "recentSecs": sum(per_day), "topAll": top(totals), "topRecent": top(recent),
        "historyComplete": len(state.get("history") or []) < history_max,
    }

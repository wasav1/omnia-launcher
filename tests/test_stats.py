import time
import unittest

from omnia import stats

NOW = time.mktime((2026, 11, 24, 15, 0, 0, 0, 0, -1))
H = 3600


def at(day_offset, hour):
    t = time.localtime(NOW)
    return int(time.mktime((t.tm_year, t.tm_mon, t.tm_mday + day_offset, hour, 0, 0, 0, 0, -1)))


def sess(gid, name, start, secs):
    return {"id": gid, "name": name, "start": start, "end": start + secs, "secs": secs}


GAMES = [{"id": "a", "name": "Alfa"}, {"id": "b", "name": "Beta"}]


class StatsTests(unittest.TestCase):
    def state(self, history):
        tot = {}
        for h in history:
            t = tot.setdefault(h["id"], {"total_secs": 0, "count": 0})
            t["total_secs"] += h["secs"]
            t["count"] += 1
        return {"sessions": tot, "history": history}

    def test_empty(self):
        r = stats.compute({}, GAMES, {}, NOW)
        self.assertEqual((r["totalSecs"], r["sessions"], r["streakDays"], r["longest"], r["topAll"]), (0, 0, 0, None, []))
        self.assertEqual(len(r["days"]), 14)

    def test_totals_top_and_days(self):
        hist = [sess("a", "Alfa", at(0, 9), 2 * H), sess("b", "Beta", at(-1, 20), H), sess("a", "Alfa", at(-20, 10), 4 * H)]
        r = stats.compute(self.state(hist), GAMES, {}, NOW)
        self.assertEqual((r["totalSecs"], r["sessions"], r["gamesPlayed"]), (7 * H, 3, 2))
        self.assertEqual([(t["name"], t["secs"]) for t in r["topAll"]], [("Alfa", 6 * H), ("Beta", H)])
        self.assertEqual([(t["name"], t["secs"]) for t in r["topRecent"]], [("Alfa", 2 * H), ("Beta", H)])   # la de hace 20 días queda fuera de 14
        self.assertEqual(r["days"][-1]["secs"], 2 * H)
        self.assertEqual(r["days"][-2]["secs"], H)
        self.assertEqual(r["recentSecs"], 3 * H)
        self.assertEqual(r["longest"]["secs"], 4 * H)
        self.assertEqual(r["avgSessionSecs"], 7 * H // 3)

    def test_midnight_split_and_streak(self):
        hist = [sess("a", "Alfa", at(-1, 23), 2 * H), sess("a", "Alfa", at(-3, 10), H)]
        r = stats.compute(self.state(hist), GAMES, {}, NOW)
        self.assertEqual((r["days"][-2]["secs"], r["days"][-1]["secs"]), (H, H))     # 1 h antes y 1 h después de la medianoche
        self.assertEqual(r["streakDays"], 2)                                         # ayer y hoy; hace 3 días queda aparte

    def test_streak_counts_from_yesterday_and_breaks(self):
        r = stats.compute(self.state([sess("a", "Alfa", at(-1, 10), H), sess("a", "Alfa", at(-2, 10), H), sess("a", "Alfa", at(-4, 10), H)]), GAMES, {}, NOW)
        self.assertEqual(r["streakDays"], 2)
        r = stats.compute(self.state([sess("a", "Alfa", at(-2, 10), H)]), GAMES, {}, NOW)
        self.assertEqual(r["streakDays"], 0)

    def test_active_session_counts_until_now(self):
        r = stats.compute({"sessions": {"a": {"total_secs": H, "count": 1}}, "history": []}, GAMES, {"a": {"name": "Alfa", "start": NOW - H}}, NOW)
        self.assertEqual((r["totalSecs"], r["sessions"]), (2 * H, 2))
        self.assertEqual(r["days"][-1]["secs"], H)
        self.assertEqual(r["streakDays"], 1)

    def test_history_complete_flag_and_unknown_game_name(self):
        r = stats.compute(self.state([sess("z", "Borrado", at(0, 9), H)]), GAMES, {}, NOW, history_max=1)
        self.assertFalse(r["historyComplete"])
        self.assertEqual(r["topAll"][0]["name"], "Borrado")


if __name__ == "__main__":
    unittest.main()

import unittest

from omnia.transfer_metrics import TransferMetrics


class TransferMetricsTests(unittest.TestCase):
    def test_rates_follow_real_counters_and_pause_drops_estimates(self):
        now = [0.0]
        tracker = TransferMetrics(clock=lambda: now[0])
        job = {"id": "port", "status": "downloading", "downloadedBytes": 100,
               "downloadTotal": 1000, "writtenBytes": 200}
        self.assertIsNone(tracker.observe([dict(job)])[0]["networkRate"])
        now[0] = 2
        job.update(downloadedBytes=300, writtenBytes=350)
        row, = tracker.observe([dict(job)])
        self.assertEqual(row["networkRate"], 100)
        self.assertEqual(row["diskRate"], 75)
        self.assertEqual(row["etaSeconds"], 7)
        self.assertEqual(row["networkPeak"], 100)
        paused, = tracker.observe([dict(job, status="paused")])
        self.assertIsNone(paused["networkRate"])
        self.assertNotIn("etaSeconds", paused)

    def test_store_speed_does_not_create_disk_data(self):
        job = {"id": "store", "status": "downloading", "speed": "2 MiB/s"}
        row, = TransferMetrics().observe([job])
        self.assertEqual(row["networkRate"], 2 * 1024**2)
        self.assertIsNone(row["diskRate"])

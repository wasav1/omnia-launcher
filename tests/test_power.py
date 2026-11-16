import unittest

from omnia import power


class PowerTests(unittest.TestCase):
    def test_runs_only_known_actions(self):
        calls = []
        self.assertTrue(power.run("lock", lambda cmd, **kw: calls.append(cmd)))
        self.assertEqual(calls, [["loginctl", "lock-session"]])
        self.assertFalse(power.run("rm -rf /", lambda cmd, **kw: calls.append(cmd)))
        self.assertFalse(power.run("", lambda cmd, **kw: calls.append(cmd)))
        self.assertEqual(len(calls), 1)

    def test_five_actions_and_three_need_confirmation(self):
        self.assertEqual(set(power.COMMANDS), {"lock", "suspend", "logout", "reboot", "shutdown"})
        self.assertEqual(power.CONFIRM, {"logout", "reboot", "shutdown"})
        self.assertTrue(power.CONFIRM <= set(power.COMMANDS))


if __name__ == "__main__":
    unittest.main()

import subprocess
import unittest
from unittest.mock import patch

from omnia.api import Api, ApiError


class SettingsLaunch(unittest.TestCase):
    def test_settings_get_independent_systemd_unit(self):
        api=Api.__new__(Api)
        with patch('shutil.which',side_effect=lambda name:'/usr/bin/'+name), patch('omnia.api.subprocess.run',return_value=subprocess.CompletedProcess([],0)) as run:
            self.assertEqual(api.settings_open({}),{'ok':True})
        args=run.call_args.args[0]
        self.assertIn('--property=Type=exec',args)
        self.assertTrue(any(x.startswith('--unit=omnia-settings-') for x in args))
        self.assertEqual(args[-2:],['--','/usr/bin/omnia-settings'])

    def test_launch_failure_is_reported(self):
        api=Api.__new__(Api)
        with patch('shutil.which',side_effect=lambda name:'/usr/bin/'+name), patch('omnia.api.subprocess.run',return_value=subprocess.CompletedProcess([],1)), self.assertRaises(ApiError):
            api.settings_open({})

    def test_missing_runner_does_not_fall_back_to_same_service(self):
        api=Api.__new__(Api)
        with patch('shutil.which',side_effect=lambda name:'/usr/bin/omnia-settings' if name=='omnia-settings' else None), patch('omnia.api.subprocess.Popen') as spawn, self.assertRaises(ApiError):
            api.settings_open({})
            spawn.assert_not_called()

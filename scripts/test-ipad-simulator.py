#!/usr/bin/env python3
"""Offline CI contracts for simulator resource ownership and bounded failures."""

import contextlib
import io
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import time
import unittest
from unittest.mock import patch

import ipad_simulator as runner


DEVICES = [('11-inch', {'name': 'iPad Air 11-inch', 'udid': 'small'}),
           ('13-inch', {'name': 'iPad Air 13-inch', 'udid': 'large'})]


class SimulatorContracts(unittest.TestCase):
    def setUp(self):
        self.scratch = tempfile.TemporaryDirectory(prefix='ipad-simulator-contract-', dir=os.environ['TMPDIR'])
        self.addCleanup(self.scratch.cleanup)
        self.root = Path(self.scratch.name)
        self.quiet = contextlib.redirect_stdout(io.StringIO())
        self.quiet.__enter__()
        self.addCleanup(self.quiet.__exit__, None, None, None)

    def test_newest_runtime_with_both_sizes(self):
        inventory = {
            'com.apple.CoreSimulator.SimRuntime.iOS-26-10': [DEVICES[0][1]],
            'com.apple.CoreSimulator.SimRuntime.iOS-26-2': [device for _, device in DEVICES],
            'com.apple.CoreSimulator.SimRuntime.iOS-18-5': [device for _, device in DEVICES],
        }
        self.assertEqual(runner.select_devices(inventory), DEVICES)
        with self.assertRaises(RuntimeError):
            runner.select_devices({'com.apple.CoreSimulator.SimRuntime.iOS-26-10': [DEVICES[0][1]]})

    def exercise(self, failure=None):
        active = set()
        events = []
        result_paths = []

        def command(args, timeout, **_options):
            if args[0] == 'xcodebuild':
                device = args[args.index('-destination') + 1].split('id=')[1]
                operation = 'test'
                self.assertEqual(active, {device})
                self.assertIn('test-without-building', args)
                self.assertNotIn('-project', args)
                result_paths.append(args[args.index('-resultBundlePath') + 1])
            else:
                operation, device = args[2:4]
                if operation == 'bootstatus':
                    self.assertFalse(active, 'A second simulator was booted before the first shut down')
                    active.add(device)
                elif operation == 'shutdown':
                    if failure != ('shutdown', device):
                        active.discard(device)
            events.append((operation, device))
            self.assertGreater(timeout, 0)
            if (operation, device) == failure:
                raise subprocess.TimeoutExpired(args, timeout)
            return subprocess.CompletedProcess(args, 0)

        with patch.object(runner, 'run', side_effect=command), patch.object(runner, 'diagnostics'):
            passed = runner.test_devices(DEVICES, self.root / 'test.xctestrun', self.root)
        self.assertFalse(active)
        self.assertEqual(len(result_paths), len(set(result_paths)))
        return passed, events

    def test_sizes_never_overlap_and_keep_separate_results(self):
        passed, events = self.exercise()
        self.assertTrue(passed)
        self.assertEqual(events, [('bootstatus', 'small'), ('test', 'small'), ('shutdown', 'small'),
                                  ('bootstatus', 'large'), ('test', 'large'), ('shutdown', 'large')])

    def test_boot_failure_cleans_up_and_other_size_still_runs(self):
        passed, events = self.exercise(('bootstatus', 'small'))
        self.assertFalse(passed)
        self.assertNotIn(('test', 'small'), events)
        self.assertIn(('test', 'large'), events)

    def test_test_failure_cleans_up_and_cannot_report_success(self):
        passed, events = self.exercise(('test', 'small'))
        self.assertFalse(passed)
        self.assertLess(events.index(('shutdown', 'small')), events.index(('bootstatus', 'large')))

    def test_shutdown_failure_stops_before_other_size(self):
        with self.assertRaises(subprocess.TimeoutExpired):
            self.exercise(('shutdown', 'small'))

    def test_timeout_kills_descendants_holding_output_open(self):
        # A surviving child keeps communicate() blocked. This tests real process
        # cleanup without CoreSimulator, networking or a development database.
        program = ("import subprocess, sys, time; "
                   "subprocess.Popen([sys.executable, '-c', 'import time; time.sleep(30)']); "
                   "print('started', flush=True); time.sleep(30)")
        started = time.monotonic()
        with self.assertRaises(subprocess.TimeoutExpired):
            runner.run([sys.executable, '-c', program], 0.5, capture=True)
        self.assertLess(time.monotonic() - started, 3)


if __name__ == '__main__':
    unittest.main()

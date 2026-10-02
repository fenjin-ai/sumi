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

    def test_newest_runtime_for_requested_size(self):
        inventory = {
            'com.apple.CoreSimulator.SimRuntime.iOS-26-10': [DEVICES[0][1]],
            'com.apple.CoreSimulator.SimRuntime.iOS-26-2': [device for _, device in DEVICES],
            'com.apple.CoreSimulator.SimRuntime.iOS-18-5': [device for _, device in DEVICES],
        }
        for size, device in DEVICES:
            self.assertEqual(runner.select_device(inventory, size), device)
        with self.assertRaises(RuntimeError):
            runner.select_device({'com.apple.CoreSimulator.SimRuntime.iOS-26-10': [DEVICES[0][1]]}, '13-inch')

    def test_invocation_requires_one_explicit_size_before_any_boot(self):
        with patch.object(runner, 'inventory') as inventory, contextlib.redirect_stderr(io.StringIO()):
            for arguments in ([], ['--size', 'both']):
                with self.assertRaises(SystemExit) as error:
                    runner.main(arguments)
                self.assertEqual(error.exception.code, 2)
            inventory.assert_not_called()

    def exercise(self, failure=None, size='11-inch'):
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

        device = next(device for label, device in DEVICES if label == size)
        with patch.object(runner, 'run', side_effect=command), patch.object(runner, 'diagnostics'):
            passed = runner.test_device(size, device, self.root / 'test.xctestrun', self.root)
        self.assertFalse(active)
        self.assertEqual(len(result_paths), len(set(result_paths)))
        return passed, events

    def test_each_invocation_runs_only_its_size_and_full_suite(self):
        for size, device in DEVICES:
            passed, events = self.exercise(size=size)
            self.assertTrue(passed)
            self.assertEqual(events, [(operation, device['udid']) for operation in ('bootstatus', 'test', 'shutdown')])

    def test_boot_failure_cleans_up_without_testing(self):
        passed, events = self.exercise(('bootstatus', 'small'))
        self.assertFalse(passed)
        self.assertNotIn(('test', 'small'), events)
        self.assertEqual(events[-1], ('shutdown', 'small'))

    def test_test_failure_cleans_up_and_cannot_report_success(self):
        passed, events = self.exercise(('test', 'small'))
        self.assertFalse(passed)
        self.assertEqual(events[-1], ('shutdown', 'small'))

    def test_shutdown_failure_cannot_report_success(self):
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

#!/usr/bin/env python3
"""Offline CI contracts for simulator resource ownership and bounded failures."""

import contextlib
import io
import json
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

    def prepare_bundle(self):
        bundle = self.root / 'build/iPad/Build/Products/test.xctestrun'
        bundle.parent.mkdir(parents=True)
        bundle.touch()
        return bundle

    def test_cold_discovery_waits_past_old_limit_then_runs_requested_suite(self):
        bundle = self.prepare_bundle()
        devices = {'com.apple.CoreSimulator.SimRuntime.iOS-26-2': [device for _, device in DEVICES]}

        def command(args, timeout, **_options):
            if args[:3] == ['xcrun', 'simctl', 'list']:
                # Model a cold service that cannot return within the old limit.
                if timeout < 90:
                    raise subprocess.TimeoutExpired(args, timeout)
                self.assertLessEqual(timeout, 180)
                return subprocess.CompletedProcess(args, 0, stdout=json.dumps({'devices': devices}))
            return subprocess.CompletedProcess(args, 0)

        with patch.object(runner, '__file__', str(self.root / 'scripts/ipad_simulator.py')), \
             patch.object(runner, 'run', side_effect=command), \
             patch.object(runner, 'test_device', return_value=True) as tests:
            self.assertEqual(runner.main(['--size', '13-inch']), 0)
        tests.assert_called_once_with('13-inch', DEVICES[1][1], bundle, self.root / 'build/iPad-writing')

    def test_discovery_failure_saves_diagnostics_without_booting_or_testing(self):
        self.prepare_bundle()
        for error in (subprocess.TimeoutExpired(['xcrun', 'simctl'], 180),
                      subprocess.CalledProcessError(1, ['xcrun', 'simctl']),
                      RuntimeError('No available iOS runtime with a 11-inch iPad')):
            with self.subTest(error=error), \
                 patch.object(runner, '__file__', str(self.root / 'scripts/ipad_simulator.py')), \
                 patch.object(runner, 'run'), patch.object(runner, 'inventory', side_effect=error), \
                 patch.object(runner, 'test_device') as tests, \
                 patch.object(runner, 'diagnostics') as diagnostics:
                self.assertEqual(runner.main(['--size', '11-inch']), 1)
                tests.assert_not_called()
                diagnostics.assert_called_once_with(
                    self.root / 'build/iPad-writing/11-inch-discovery-diagnostics.log')

    def test_diagnostics_remain_bounded_when_simulator_service_hangs(self):
        calls = []

        def command(args, timeout, **options):
            calls.append(args)
            self.assertEqual(timeout, 10)
            self.assertEqual(options, {'capture': True, 'check': False})
            if args[:2] == ['xcrun', 'simctl']:
                raise subprocess.TimeoutExpired(args, timeout)
            return subprocess.CompletedProcess(args, 0, stdout='diagnostic output\n')

        path = self.root / 'diagnostics.log'
        with patch.object(runner, 'run', side_effect=command):
            runner.diagnostics(path)
        self.assertIn('Diagnostic command timed out after 10 seconds.', path.read_text())
        self.assertEqual(calls[-1][0], 'tail', 'Service logs must survive a hung inventory query')

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

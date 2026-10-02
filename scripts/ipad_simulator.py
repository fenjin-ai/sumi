#!/usr/bin/env python3
"""Run native UI tests on one iPad simulator at a time."""

import json
import os
from pathlib import Path
import shlex
import signal
import subprocess
import sys


def run(command, timeout, *, capture=False, check=True):
    print(f"+ {shlex.join(map(str, command))} (limit {timeout}s)", flush=True)
    process = subprocess.Popen(command, start_new_session=True,
                               stdout=subprocess.PIPE if capture else None,
                               stderr=subprocess.STDOUT if capture else None, text=True)
    try:
        output, _ = process.communicate(timeout=timeout)
    except BaseException:
        # xcodebuild can leave test workers behind if only its parent is killed.
        try:
            os.killpg(process.pid, signal.SIGKILL)
        except ProcessLookupError:
            pass
        process.communicate()
        raise
    if check and process.returncode:
        raise subprocess.CalledProcessError(process.returncode, command, output=output)
    return subprocess.CompletedProcess(command, process.returncode, stdout=output)


def inventory():
    return json.loads(run(['xcrun', 'simctl', 'list', 'devices', 'available', '-j'],
                          30, capture=True).stdout)['devices']


def select_devices(devices):
    runtimes = sorted((runtime for runtime in devices if '.iOS-' in runtime),
                      key=lambda runtime: tuple(map(int, runtime.split('.iOS-')[1].split('-'))),
                      reverse=True)
    for runtime in runtimes:
        selected = []
        for size in ('11-inch', '13-inch'):
            matches = [entry for entry in devices[runtime]
                       if 'iPad' in entry['name'] and size in entry['name']]
            if not matches:
                break
            selected.append((size, sorted(matches, key=lambda entry: entry['name'])[0]))
        if len(selected) == 2:
            print(f"Using {runtime}: {', '.join(device['name'] for _, device in selected)}", flush=True)
            return selected
    raise RuntimeError('No available iOS runtime with both 11-inch and 13-inch iPads')


def diagnostics(path):
    commands = [
        ['sysctl', 'hw.memsize', 'hw.ncpu', 'vm.swapusage'],
        ['vm_stat'],
        ['ps', '-axo', 'pid,ppid,%cpu,%mem,rss,comm'],
        ['xcrun', 'simctl', 'list', 'devices'],
    ]
    with path.open('w') as output:
        for command in commands:
            output.write(f"+ {shlex.join(command)}\n")
            try:
                result = run(command, 10, capture=True, check=False)
                output.write(result.stdout)
                print(result.stdout, flush=True)
            except subprocess.TimeoutExpired:
                output.write('Diagnostic command timed out after 10 seconds.\n')


def shutdown(device):
    result = run(['xcrun', 'simctl', 'shutdown', device['udid']], 60, check=False)
    if result.returncode:
        # A failed boot can already be shut down; verify rather than hiding errors.
        states = [entry['state'] for entries in inventory().values()
                  for entry in entries if entry['udid'] == device['udid']]
        if states != ['Shutdown']:
            raise RuntimeError(f"Could not shut down {device['name']}; refusing to boot another iPad")


def test_devices(devices, bundle, results):
    passed = True
    for size, device in devices:
        print(f"::group::{size}: boot, native UI tests, shutdown", flush=True)
        try:
            # bootstatus also initiates the boot and reports migration progress.
            run(['xcrun', 'simctl', 'bootstatus', device['udid'], '-b', '-d'], 240)
            run(['xcodebuild', '-xctestrun', str(bundle),
                 '-destination', f"platform=iOS Simulator,id={device['udid']}",
                 '-destination-timeout', '30', '-parallel-testing-enabled', 'NO',
                 '-maximum-concurrent-test-simulator-destinations', '1',
                 '-test-timeouts-enabled', 'YES', '-default-test-execution-time-allowance', '150',
                 '-maximum-test-execution-time-allowance', '180',
                 '-resultBundlePath', str(results / f'{size}.xcresult'), 'test-without-building'], 720)
        except (subprocess.CalledProcessError, subprocess.TimeoutExpired) as error:
            passed = False
            print(f"::error::{size}: {error}", flush=True)
            diagnostics(results / f'{size}-diagnostics.log')
        finally:
            # Finish the complete lifecycle before starting the other size.
            try:
                shutdown(device)
            finally:
                print('::endgroup::', flush=True)
    return passed


def main():
    root = Path(__file__).resolve().parent.parent
    bundles = list((root / 'build/iPad/Build/Products').glob('*.xctestrun'))
    if len(bundles) != 1:
        raise RuntimeError('Expected one .xctestrun bundle; run scripts/build-ipad.sh simulator first')
    results = root / 'build/iPad-writing'
    results.mkdir(parents=True, exist_ok=True)
    run(['sysctl', 'hw.memsize', 'hw.ncpu'], 10)
    devices = select_devices(inventory())
    return 0 if test_devices(devices, bundles[0], results) else 1


if __name__ == '__main__':
    # Give the current simulator its cleanup even when Actions cancels the step.
    def cancelled(_signum, _frame):
        raise KeyboardInterrupt

    signal.signal(signal.SIGTERM, cancelled)
    try:
        sys.exit(main())
    except (RuntimeError, subprocess.SubprocessError) as error:
        print(f'::error::{error}', flush=True)
        sys.exit(1)

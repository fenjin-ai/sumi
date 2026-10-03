#!/usr/bin/env python3
"""Run the full native UI suite on one requested iPad size."""

import argparse
import json
import os
from pathlib import Path
import plistlib
import shlex
import signal
import subprocess
import sys
import time
import uuid


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


def inventory(*, timeout=30):
    return json.loads(run(['xcrun', 'simctl', 'list', 'devices', 'available', '-j'],
                          timeout, capture=True).stdout)['devices']


def select_device(devices, size):
    runtimes = sorted((runtime for runtime in devices if '.iOS-' in runtime),
                      key=lambda runtime: tuple(map(int, runtime.split('.iOS-')[1].split('-'))),
                      reverse=True)
    for runtime in runtimes:
        matches = [entry for entry in devices[runtime]
                   if 'iPad' in entry['name'] and size in entry['name']]
        if matches:
            device = sorted(matches, key=lambda entry: entry['name'])[0]
            print(f"Using {device['name']} on {runtime}", flush=True)
            return device
    raise RuntimeError(f'No available iOS runtime with a {size} iPad')


def diagnostics(path, device=None):
    commands = [
        ['xcode-select', '-p'],
        ['xcodebuild', '-version'],
        ['sysctl', 'hw.memsize', 'hw.ncpu', 'vm.swapusage'],
        ['vm_stat'],
        ['ps', '-axo', 'pid,ppid,%cpu,%mem,rss,comm'],
        ['xcrun', 'simctl', 'list', 'devices'],
        ['tail', '-n', '200', str(Path.home() / 'Library/Logs/CoreSimulator/CoreSimulator.log')],
    ]
    if device:
        commands.append(['xcrun', 'simctl', 'spawn', device['udid'], 'log', 'show',
                         '--last', '20m', '--style', 'compact', '--predicate',
                         'eventMessage CONTAINS[c] "orient" OR eventMessage CONTAINS[c] "rotat"'])
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
            raise RuntimeError(f"Could not shut down {device['name']}")


def verify_result(bundle, output, *, memory=False):
    summary = json.loads(run(['xcrun', 'xcresulttool', 'get', 'test-results', 'summary',
                              '--path', str(bundle)], 30, capture=True).stdout)
    (output / 'test-summary.json').write_text(json.dumps(summary, indent=2) + '\n')
    if summary['result'] != 'Passed' or summary['passedTests'] < 1 or summary['failedTests']:
        raise RuntimeError('Result bundle must contain executed, passing tests')
    if summary.get('runtimeWarnings'):
        raise RuntimeError('Xcode recorded runtime safety warnings; see test-summary.json')
    if memory:
        metrics = run(['xcrun', 'xcresulttool', 'get', 'test-results', 'metrics',
                       '--path', str(bundle)], 30, capture=True).stdout
        (output / 'memory-metrics.json').write_text(metrics)
        measurements = [value for test in json.loads(metrics)
                        if test['testIdentifier'] == 'TabletLifecycleTests/testWorkspaceOwnershipMemory()'
                        for test_run in test['testRuns'] for metric in test_run['metrics']
                        if metric['identifier'] == 'com.apple.dt.XCTMetric_Memory.physical_peak'
                        for value in metric['measurements']]
        if not measurements or any(value <= 0 for value in measurements):
            raise RuntimeError('The ownership workload must record physical peak memory measurements')


def export_coverage(bundle, device, results, size, started):
    products = bundle.parent
    directory = products.parent / 'ProfileData' / device['udid']
    profiles = sorted(path for path in directory.glob('*.profraw') if path.stat().st_mtime >= started)
    profile = directory / 'Coverage.profdata'
    if profiles:
        profile = results / (size + '.profdata')
        run(['xcrun', 'llvm-profdata', 'merge', '-sparse', *map(str, profiles), '-o', str(profile)], 60)
    elif not profile.is_file() or profile.stat().st_mtime < started:
        raise RuntimeError('This simulator run must produce a fresh coverage profile')
    app = products / 'Debug-iphonesimulator/LeftBlank.app'
    executable = app / 'LeftBlank.debug.dylib'
    if not executable.is_file():
        executable = app / 'LeftBlank'
    images = [executable]
    core = products / 'Debug-iphonesimulator/PackageFrameworks/LeftBlankCore.framework/LeftBlankCore'
    if not core.is_file():
        raise RuntimeError('Coverage requires the instrumented shared Core image')
    # Only our app and Core are instrumented for the production denominator.
    # Hosted test runs inject universal Apple XCTest frameworks; those are not
    # production coverage objects and require a separate architecture selection.
    images.append(core)
    objects = [str(images[0])]
    for image in images[1:]:
        objects += ['-object', str(image)]
    report = run(['xcrun', 'llvm-cov', 'export', *objects,
                  '-instr-profile=' + str(profile), '-format=lcov'], 60, capture=True).stdout
    (results / (size + '.lcov')).write_text(report)


def configure_coverage(bundle):
    # Xcode can omit package/app entries when producing a relocatable test run.
    # Declare the two actual instrumented images using Apple's xctestrun schema.
    root = Path(__file__).resolve().parent.parent
    products = bundle.parent
    images = [('LeftBlank.app', 'A00000000000000000000005:primary', 'iPad/Sources',
               'LeftBlank.app/LeftBlank.debug.dylib'),
              ('LeftBlankCore.framework', 'LeftBlankCore:primary', 'Sources/LeftBlankCore',
               'PackageFrameworks/LeftBlankCore.framework/LeftBlankCore')]
    targets = []
    for name, identifier, folder, image in images:
        base = root / folder
        sources = sorted(base.rglob('*.swift'))
        if not sources or not (products / 'Debug-iphonesimulator' / image).is_file():
            raise RuntimeError('Coverage requires the compiled iPad app and shared Core images')
        targets.append({'Name': name, 'BuildableIdentifier': identifier, 'IncludeInReport': True,
                        'IsStatic': False, 'Architectures': ['arm64'],
                        'ProductPaths': ['__TESTROOT__/Debug-iphonesimulator/' + image],
                        'SourceFiles': [str(path.relative_to(base)) for path in sources],
                        'SourceFilesCommonPathPrefix': str(base) + '/',
                        'Toolchains': ['com.apple.dt.toolchain.XcodeDefault']})
    parameters = plistlib.loads(bundle.read_bytes())
    parameters['CodeCoverageBuildableInfos'] = targets
    bundle.write_bytes(plistlib.dumps(parameters))


def test_device(size, device, bundle, results, *, suite='all', memory=False, coverage=True, appearance=None, show_device=False):
    print(f"::group::{size}: boot, native {suite} tests, shutdown", flush=True)
    try:
        if coverage:
            configure_coverage(bundle)
        # bootstatus also initiates the boot and reports migration progress.
        run(['xcrun', 'simctl', 'bootstatus', device['udid'], '-b', '-d'], 240)
        if show_device:
            # Attach the hosted UI device to Simulator's display before XCTest
            # sends orientation events. Keep the actual window-shape assertions.
            developer = os.environ.get('DEVELOPER_DIR')
            if not developer:
                raise RuntimeError('Hosted UI tests require an explicit DEVELOPER_DIR')
            simulator = str(Path(developer) / 'Applications/Simulator.app')
            run(['open', '-a', simulator, '--args', '-CurrentDeviceUDID', device['udid']], 30)
        if appearance:
            # A cold hosted simulator can still be initializing UI services after
            # bootstatus completes. Keep a bounded startup allowance and confirm
            # the actual appearance before measuring the test run.
            run(['xcrun', 'simctl', 'ui', device['udid'], 'appearance', appearance], 120)
            actual = run(['xcrun', 'simctl', 'ui', device['udid'], 'appearance'], 120, capture=True).stdout
            if actual.strip().lower() != appearance:
                raise RuntimeError('Simulator appearance differs from the requested ' + appearance)
        # Xcode's verbose sysdiagnose can spend ten minutes after a test failure.
        # Keep the test report and attachments, then collect our bounded diagnostics.
        selection = ['-only-testing:LeftBlankTabletTests'] if suite == 'unit' else []
        if memory:
            selection += ['-enablePerformanceTestsDiagnostics', 'YES']
        started = time.time()
        run(['xcodebuild', '-xctestrun', str(bundle),
             '-derivedDataPath', str(bundle.parent.parent.parent),
             '-destination', f"platform=iOS Simulator,id={device['udid']}",
             '-destination-timeout', '30', '-parallel-testing-enabled', 'NO',
             '-maximum-concurrent-test-simulator-destinations', '1',
             '-test-timeouts-enabled', 'YES', '-default-test-execution-time-allowance', '150',
             '-maximum-test-execution-time-allowance', '180',
             '-collect-test-diagnostics', 'never',
             '-enableCodeCoverage', 'YES' if coverage else 'NO',
             '-resultBundlePath', str(results / f'{size}.xcresult'),
             *selection, 'test-without-building'], 1080)
        verify_result(results / f'{size}.xcresult', results, memory=memory)
        if coverage:
            export_coverage(bundle, device, results, size, started)
        return True
    except (RuntimeError, subprocess.CalledProcessError, subprocess.TimeoutExpired) as error:
        print(f"::error::{size}: {error}", flush=True)
        if isinstance(error, subprocess.CalledProcessError) and error.output:
            print(error.output, flush=True)
        diagnostics(results / f'{size}-diagnostics.log', device)
        return False
    finally:
        try:
            shutdown(device)
        finally:
            print('::endgroup::', flush=True)


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--size', choices=('11-inch', '13-inch'), required=True)
    parser.add_argument('--suite', choices=('all', 'unit'), default='all')
    parser.add_argument('--derived-data', type=Path, default=Path('build/iPad'))
    parser.add_argument('--results', type=Path, default=Path('build/iPad-writing'))
    parser.add_argument('--memory', action='store_true')
    parser.add_argument('--no-coverage', action='store_true')
    parser.add_argument('--appearance', choices=('light', 'dark'))
    parser.add_argument('--fresh-device', action='store_true',
                        help='Create a disposable simulator on a hosted CI runner')
    args = parser.parse_args(argv)
    if args.fresh_device and os.environ.get('GITHUB_ACTIONS') != 'true':
        parser.error('--fresh-device is restricted to disposable hosted CI runners')
    root = Path(__file__).resolve().parent.parent
    bundles = list((root / args.derived_data / 'Build/Products').glob('*.xctestrun'))
    if len(bundles) != 1:
        raise RuntimeError('Expected one .xctestrun bundle; run scripts/build-ipad.sh simulator first')
    results = root / args.results
    results.mkdir(parents=True, exist_ok=True)
    run(['sysctl', 'hw.memsize', 'hw.ncpu'], 10)
    print(f'::group::{args.size}: initialize simulator service and discover device', flush=True)
    try:
        # A fresh UI runner has not warmed CoreSimulator through compilation.
        # Allow its first query to initialize services and mount runtimes;
        # subsequent inventory checks retain their short timeout.
        devices = inventory(timeout=180)
        device = select_device(devices, args.size)
        if args.fresh_device:
            runtime = next(runtime for runtime, entries in devices.items() if device in entries)
            name = 'LeftBlank-' + args.size + '-' + uuid.uuid4().hex[:8]
            identifier = run(['xcrun', 'simctl', 'create', name,
                              device['deviceTypeIdentifier'], runtime], 60, capture=True).stdout.strip()
            uuid.UUID(identifier)
            device = dict(device, udid=identifier, name=name)
            print(f'Created disposable simulator {identifier}', flush=True)
    except (RuntimeError, subprocess.SubprocessError, json.JSONDecodeError) as error:
        print(f'::error::{args.size}: simulator discovery failed: {error}', flush=True)
        diagnostics(results / f'{args.size}-discovery-diagnostics.log')
        return 1
    finally:
        print('::endgroup::', flush=True)
    options = {'show_device': True} if args.fresh_device else {}
    if args.appearance:
        options['appearance'] = args.appearance
    if args.suite != 'all':
        options['suite'] = args.suite
    if args.memory:
        options['memory'] = True
    if args.no_coverage:
        options['coverage'] = False
    try:
        return 0 if test_device(args.size, device, bundles[0], results, **options) else 1
    finally:
        if args.fresh_device:
            run(['xcrun', 'simctl', 'delete', device['udid']], 60)


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

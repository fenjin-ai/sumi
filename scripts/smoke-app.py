#!/usr/bin/env python3
"""Cold-launch a relocated app without SwiftPM's build-directory fallback.

Runs with a fresh library. Only the process group created here is terminated.
Use after building, never concurrently with a build using the same resources.
"""
import argparse
import json
import os
from pathlib import Path
import shutil
import signal
import subprocess
import tempfile
import time
import uuid

from running_app import verify_running_app


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--app', type=Path, default=Path('build/Sumi.app'))
    parser.add_argument('--development-resources', type=Path, required=True)
    parser.add_argument('--artifacts', type=Path, default=Path('build/launch-smoke'))
    args = parser.parse_args()
    app = args.app.resolve(strict=True)
    resources = args.development_resources.resolve(strict=True)
    if resources.name != 'Sumi_SumiCore.bundle':
        parser.error('Expected the SwiftPM Sumi_SumiCore.bundle directory')
    artifacts = args.artifacts.resolve()
    artifacts.mkdir(parents=True, exist_ok=True)
    # Require an explicitly configured temporary directory (SSD locally).
    temp_root = Path(os.environ['TMPDIR']).resolve(strict=True)
    hidden = resources.with_name(resources.name + '.smoke-' + uuid.uuid4().hex)
    with tempfile.TemporaryDirectory(prefix='sumi-launch-', dir=temp_root) as temporary:
        root = Path(temporary)
        relocated = root / 'Sumi.app'
        shutil.copytree(app, relocated, symlinks=True)
        state = root / 'State'
        process = None
        resources.rename(hidden)
        try:
            with (artifacts / 'process.log').open('wb') as output:
                process = subprocess.Popen(
                    [str(relocated / 'Contents/MacOS/Sumi'), '-appLanguage', 'zh-Hans',
                     '-SUEnableAutomaticChecks', 'NO'],
                    cwd=root, env={**os.environ, 'SUMI_STATE_DIR': str(state)},
                    stdin=subprocess.DEVNULL, stdout=output, stderr=subprocess.STDOUT,
                    start_new_session=True,
                )
                deadline = time.monotonic() + 30
                events_file = state / 'Logs/events.jsonl'
                while time.monotonic() < deadline:
                    if process.poll() is not None:
                        raise RuntimeError(f'Relocated app exited early: {process.returncode}')
                    events = []
                    if events_file.exists():
                        for line in events_file.read_text().splitlines():
                            try:
                                events.append(json.loads(line))
                            except json.JSONDecodeError:
                                pass  # A live append may not be complete yet.
                    ready = any(event.get('event') == 'service.ready' for event in events)
                    icon_loaded = any(event.get('event') == 'application.iconLoaded' for event in events)
                    localized = any('此中有真意，欲辨已忘言' in source.read_text()
                                    for source in (state / 'Library/Documents').glob('*/main.typ'))
                    if ready and localized and icon_loaded:
                        verify_running_app(relocated, process.pid)
                        print('PASS: relocated app launched, app icon and Chinese resources loaded, library created, Tinymist ready.')
                        return
                    time.sleep(0.1)
                raise RuntimeError('App did not reach a localized library and ready typesetting service in 30 seconds')
        finally:
            if process is not None:
                try:
                    os.killpg(process.pid, signal.SIGTERM)
                    process.wait(timeout=5)
                except subprocess.TimeoutExpired:
                    os.killpg(process.pid, signal.SIGKILL)
                    process.wait(timeout=5)
                except ProcessLookupError:
                    pass
            hidden.rename(resources)
            logs = state / 'Logs'
            if logs.exists():
                shutil.copytree(logs, artifacts / 'Logs', dirs_exist_ok=True)


if __name__ == '__main__':
    main()

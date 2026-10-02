"""Read-only macOS process identity check for cold launches and Sparkle relaunches."""
from __future__ import annotations

import argparse
import ctypes
from pathlib import Path
import plistlib
import sys


def verify_running_app(app: Path, pid: int, expected_build: str | None = None) -> dict:
    if sys.platform != 'darwin':
        raise RuntimeError('Running app verification requires macOS')
    if pid <= 0:
        raise ValueError('Expected a positive process ID')
    app = app.resolve(strict=True)
    info = plistlib.loads((app / 'Contents/Info.plist').read_bytes())
    executable = (app / 'Contents/MacOS' / info['CFBundleExecutable']).resolve(strict=True)
    libproc = ctypes.CDLL('/usr/lib/libproc.dylib', use_errno=True)
    libproc.proc_pidpath.argtypes = [ctypes.c_int, ctypes.c_void_p, ctypes.c_uint32]
    libproc.proc_pidpath.restype = ctypes.c_int
    buffer = ctypes.create_string_buffer(4096)  # PROC_PIDPATHINFO_MAXSIZE
    if libproc.proc_pidpath(pid, buffer, len(buffer)) <= 0:
        raise RuntimeError(f'Process {pid} has no resolvable executable; it may have exited '
                           'or still be running a removed version of the app')
    running = Path(buffer.value.decode()).resolve(strict=True)
    if running != executable:
        raise RuntimeError(f'Process {pid} is running {running}, not {executable}')
    build = str(info['CFBundleVersion'])
    if expected_build is not None and build != expected_build:
        raise RuntimeError(f'Expected build {expected_build}, found {build}')
    return {'pid': pid, 'executable': str(running), 'build': build}


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--app', type=Path, required=True)
    parser.add_argument('--pid', type=int, required=True)
    parser.add_argument('--expected-build')
    args = parser.parse_args()
    try:
        result = verify_running_app(args.app, args.pid, args.expected_build)
        print(f"PASS: process {result['pid']} runs build {result['build']} at {result['executable']}")
    except (OSError, ValueError, KeyError, RuntimeError) as error:
        parser.exit(1, f'FAIL: {error}\n')

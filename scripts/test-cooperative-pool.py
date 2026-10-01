#!/usr/bin/env python3
"""Run the real bridge tests with one Swift cooperative worker, with diagnostics."""
import os
from pathlib import Path
import signal
import subprocess
import sys

output = Path("build/cooperative-pool")
output.mkdir(parents=True, exist_ok=True)
# Coverage is produced by the preceding full run. Rebuilding the report here
# also constrains SwiftPM's report subprocesses, unrelated to the bridge test.
environment = os.environ | {
    "LIBDISPATCH_COOPERATIVE_POOL_STRICT": "1",
    "LLVM_PROFILE_FILE": str(output.resolve() / "%p.profraw"),
}
command = ["swift", "test", "--skip-build", "--filter", "AutomationIntegrationTests"]
# A PTY makes Swift Testing's progress visible even if a test hangs before exit.
process = subprocess.Popen(["script", "-q", "/dev/null", *command], env=environment, start_new_session=True)
try:
    sys.exit(process.wait(timeout=90))
except subprocess.TimeoutExpired:
    print("Single-worker bridge tests exceeded 90 seconds. Capturing owned process stacks.", flush=True)
    rows = subprocess.check_output(["ps", "-axo", "pid,ppid,command"], text=True).splitlines()[1:]
    processes = [line.strip().split(None, 2) for line in rows]
    descendants = {process.pid}
    while True:
        children = {int(pid) for pid, parent, _ in processes if int(parent) in descendants}
        if children <= descendants:
            break
        descendants |= children
    for pid, parent, command in processes:
        if int(pid) not in descendants:
            continue
        print(f"pid={pid} ppid={parent} {command}", flush=True)
        stack = output / f"sample-{pid}.txt"
        try:
            subprocess.run(["sample", pid, "1", "1", "-file", str(stack)], timeout=5, capture_output=True)
            if stack.exists():
                print(stack.read_text()[:32_000], flush=True)
        except subprocess.TimeoutExpired:
            pass
    os.killpg(process.pid, signal.SIGKILL)
    process.wait()
    sys.exit(1)

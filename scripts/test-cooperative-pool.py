#!/usr/bin/env python3
"""Run the real bridge tests with one Swift cooperative worker, with diagnostics."""
import os
from pathlib import Path
import signal
import subprocess
import sys

output = Path("build/cooperative-pool")
output.mkdir(parents=True, exist_ok=True)
# SwiftPM 6.2 still invokes llbuild during --skip-build and deadlocks when its
# own cooperative pool is restricted. Use the same official Swift Testing
# helper as SwiftPM, applying the restriction only to the already-built tests.
# The preceding full test run remains responsible for coverage reporting.
environment = os.environ | {
    "LIBDISPATCH_COOPERATIVE_POOL_STRICT": "1",
    "LLVM_PROFILE_FILE": str(output.resolve() / "%p.profraw"),
}
binary_directory = Path(subprocess.check_output(["swift", "build", "--show-bin-path"], text=True).strip())
bundle = binary_directory / "LeftBlankAutomationTests.xctest"
if not bundle.is_dir():
    bundle = binary_directory / "LeftBlankPackageTests.xctest"
test_binary = bundle / "Contents/MacOS" / bundle.stem
if not test_binary.is_file():
    sys.exit(f"Built automation tests not found: {test_binary}")
swift = Path(subprocess.check_output(["xcrun", "--find", "swift"], text=True).strip())
helper = swift.parent.parent / "libexec/swift/pm/swiftpm-testing-helper"
# Match SwiftPM's test environment so dlopen can resolve XCTest and Testing.
platform = Path(subprocess.check_output(
    ["xcrun", "--sdk", "macosx", "--show-sdk-platform-path"], text=True).strip())
for key, path in {
    "DYLD_FRAMEWORK_PATH": platform / "Developer/Library/Frameworks",
    "DYLD_LIBRARY_PATH": platform / "Developer/usr/lib",
}.items():
    environment[key] = ":".join(filter(None, [environment.get(key), str(path)]))
command = [str(helper), "--test-bundle-path", str(test_binary),
           "--filter", "AutomationIntegrationTests", str(test_binary),
           "--testing-library", "swift-testing"]
# Launch directly: Apple's system utilities strip DYLD_* from child processes.
process = subprocess.Popen(command, env=environment, start_new_session=True)
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
                print(stack.read_text().split("Binary Images:")[0][:32_000], flush=True)
        except subprocess.TimeoutExpired:
            pass
    for pid in descendants:
        try:
            os.kill(pid, signal.SIGKILL)
        except ProcessLookupError:
            pass
    process.wait()
    sys.exit(1)

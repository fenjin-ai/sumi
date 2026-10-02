#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
source scripts/environment.sh
python3 scripts/test-icloud-profile.py
scripts/bootstrap.sh
swift build --build-tests --enable-code-coverage -Xswiftc -warnings-as-errors
export LEFTBLANK_MCP_HELPER="$(swift build --show-bin-path)/LeftBlankMCP"
# SwiftPM's Xcode backend can leave command-line products unsigned on Apple silicon.
# Sign after the complete build so a subsequent link cannot invalidate the helper.
codesign --force --sign - "$LEFTBLANK_MCP_HELPER"
coverage_dir="$(swift build --show-bin-path)/codecov"
export LEFTBLANK_MCP_COVERAGE_DIR="$coverage_dir"
mkdir -p "$coverage_dir"
rm -f "$coverage_dir"/*.profraw "$coverage_dir"/*.profdata
rm -rf build/coverage
test_status=0
LEFTBLANK_INTEGRATION=1 swift test --skip-build --enable-code-coverage "$@" || test_status=$?
coverage_status=0
python3 scripts/coverage.py --minimum 80 || coverage_status=$?
if [ "$test_status" -ne 0 ]; then exit "$test_status"; fi
exit "$coverage_status"

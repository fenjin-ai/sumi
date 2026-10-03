#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
source scripts/environment.sh
python3 scripts/test-icloud-profile.py
scripts/bootstrap.sh
scripts/build-mcp.sh
swift build --build-tests --enable-code-coverage -Xswiftc -warnings-as-errors
export LEFTBLANK_MCP_HELPER="$PWD/Tools/LeftBlankMCP/target/debug/LeftBlankMCP"
# The MCP helper is a separately built macOS executable.
codesign --force --sign - "$LEFTBLANK_MCP_HELPER"
coverage_dir="$(swift build --show-bin-path)/codecov"
mkdir -p "$coverage_dir"
rm -f "$coverage_dir"/*.profraw "$coverage_dir"/*.profdata
rm -rf build/coverage
scripts/test-mcp.sh
test_status=0
LEFTBLANK_INTEGRATION=1 swift test --skip-build --enable-code-coverage "$@" || test_status=$?
coverage_status=0
python3 scripts/coverage.py --minimum 80 || coverage_status=$?
if [ "$test_status" -ne 0 ]; then exit "$test_status"; fi
exit "$coverage_status"

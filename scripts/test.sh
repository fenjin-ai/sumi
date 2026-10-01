#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
source scripts/environment.sh
scripts/bootstrap.sh
coverage_dir="$(swift build --show-bin-path)/codecov"
mkdir -p "$coverage_dir"
rm -f "$coverage_dir"/*.profraw "$coverage_dir"/*.profdata
rm -rf build/coverage
test_status=0
SUMI_INTEGRATION=1 swift test --enable-code-coverage "$@" || test_status=$?
coverage_status=0
python3 scripts/coverage.py --minimum 80 || coverage_status=$?
if [ "$test_status" -ne 0 ]; then exit "$test_status"; fi
exit "$coverage_status"

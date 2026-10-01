#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
export TMPDIR=/Volumes/SSD/Developer/Codex/tmp TMP=/Volumes/SSD/Developer/Codex/tmp TEMP=/Volumes/SSD/Developer/Codex/tmp
test -d /Volumes/SSD/Developer || { echo 'The development SSD is not mounted.' >&2; exit 1; }
mkdir -p "$TMPDIR"
scripts/bootstrap.sh
SUMI_INTEGRATION=1 swift test

#!/bin/bash
# Source from development scripts. Local build artifacts always stay on the SSD;
# hosted CI uses the runner's disposable workspace and temporary directory.
if [ "${GITHUB_ACTIONS:-}" = true ]; then
  : "${RUNNER_TEMP:?GitHub Actions must provide RUNNER_TEMP}"
  export TMPDIR="$RUNNER_TEMP/leftblank" TMP="$RUNNER_TEMP/leftblank" TEMP="$RUNNER_TEMP/leftblank"
else
  test -d /Volumes/SSD/Developer || { echo 'The development SSD is not mounted.' >&2; exit 1; }
  case "$(pwd -P)" in
    /Volumes/SSD/Developer/*) ;;
    *) echo 'Run development builds from an SSD-backed checkout under /Volumes/SSD/Developer.' >&2; exit 1 ;;
  esac
  export TMPDIR=/Volumes/SSD/Developer/Codex/tmp TMP=/Volumes/SSD/Developer/Codex/tmp TEMP=/Volumes/SSD/Developer/Codex/tmp
fi
mkdir -p "$TMPDIR"

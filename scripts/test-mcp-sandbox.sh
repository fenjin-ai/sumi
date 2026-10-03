#!/bin/bash
# Real signed sandbox test uses the hosted runner's disposable group container.
set -euo pipefail
source "$(dirname "$0")/environment.sh"
[ "${GITHUB_ACTIONS:-}" = true ] || { echo 'Run signed sandbox validation in release CI.' >&2; exit 1; }
app=$1
identity=$2
keychain=$3
probe=$(mktemp -d "$TMPDIR/leftblank-mcp-sandbox.XXXXXX")
pid=""
cleanup() {
  if [ -n "$pid" ]; then kill "$pid" 2>/dev/null || true; wait "$pid" 2>/dev/null || true; fi
  rm -rf "$probe"
}
trap cleanup EXIT
mkdir -p "$probe/Probe.app/Contents/MacOS"
swiftc scripts/mcp-sandbox-probe.swift -module-cache-path .build/sandbox-module-cache \
  -o "$probe/Probe.app/Contents/MacOS/Probe"
python3 - "$app" "$probe" <<'PY'
from pathlib import Path
import plistlib, sys
app, temporary = map(Path, sys.argv[1:])
info = plistlib.loads((app / 'Contents/Info.plist').read_bytes())
group = info['LeftBlankAgentGroup']
info.update(CFBundleExecutable='Probe', CFBundleIdentifier='app.leftblank.writer', LeftBlankDistribution='appstore')
(temporary / 'Probe.app/Contents/Info.plist').write_bytes(plistlib.dumps(info))
entitlements = {'com.apple.security.app-sandbox': True, 'com.apple.security.network.server': True,
                'com.apple.security.application-groups': [group]}
(temporary / 'probe.plist').write_bytes(plistlib.dumps(entitlements))
PY
codesign --force --sign "$identity" --options runtime --timestamp --keychain "$keychain" \
  --entitlements "$probe/probe.plist" "$probe/Probe.app"
"$probe/Probe.app/Contents/MacOS/Probe" > "$probe/probe.log" 2>&1 &
pid=$!
# --check is read-only; retries only wait for the fixture listener to start.
for attempt in {1..50}; do
  if env -u LEFTBLANK_STATE_DIR "$app/Contents/Helpers/LeftBlankMCP" --check --app-bundle "$probe/Probe.app" > "$probe/status.json"; then
    wait "$pid"
    pid=""
    echo 'PASS: external signed helper reached a sandboxed peer through its Team-ID App Group.'
    exit 0
  fi
  kill -0 "$pid" 2>/dev/null || { cat "$probe/probe.log" >&2; exit 1; }
  sleep 0.1
done
cat "$probe/probe.log" >&2
cat "$probe/status.json" >&2
exit 1

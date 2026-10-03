#!/bin/bash
# Sign nested Sparkle executables before the framework and outer app.
set -euo pipefail
source "$(dirname "$0")/environment.sh"
app=$1
identity=${2:--}
keychain=${3:-}
entitlements=${4:-}
args=(--force --sign "$identity")
if [ "$identity" != - ]; then args+=(--options runtime --timestamp); fi
if [ -n "$keychain" ]; then args+=(--keychain "$keychain"); fi
framework="$app/Contents/Frameworks/Sparkle.framework"
if [ -d "$framework" ]; then
  for service in "$framework"/Versions/B/XPCServices/*.xpc; do
    [ ! -d "$service" ] || codesign "${args[@]}" --preserve-metadata=entitlements "$service"
  done
  codesign "${args[@]}" "$framework/Versions/B/Autoupdate"
  codesign "${args[@]}" "$framework/Versions/B/Updater.app"
  codesign "${args[@]}" "$framework"
fi
distribution=$(/usr/libexec/PlistBuddy -c 'Print LeftBlankDistribution' "$app/Contents/Info.plist")
helper_args=("${args[@]}")
if [ "$distribution" = appstore ]; then
  helper_args+=(--entitlements Resources/LeftBlank.Helper.entitlements)
  if [ -z "$entitlements" ]; then
    if [ "$identity" != - ]; then
      echo 'App Store signing requires validated provisioning-profile entitlements.' >&2
      exit 1
    fi
    entitlements=Resources/LeftBlank.AppStore.entitlements
  fi
fi
# A macOS Team-ID group needs no profile registration and allows the external
# helper to reach a sandboxed app without asking for access to its private data.
signing_dir=$(mktemp -d "$TMPDIR/leftblank-agent-signing.XXXXXX")
trap 'rm -rf "$signing_dir"' EXIT
if [ "$identity" != - ]; then
  codesign "${args[@]}" "$app/Contents/MacOS/LeftBlank"
  team=$(codesign -d --verbose=4 "$app/Contents/MacOS/LeftBlank" 2>&1 | sed -n 's/^TeamIdentifier=//p')
  python3 - "$app" "$team" "$entitlements" "$signing_dir" <<'PY'
from pathlib import Path
import plistlib, re, sys
app, team, original, temporary = sys.argv[1:]
if not re.fullmatch(r'[A-Z0-9]{10}', team):
    raise SystemExit('A valid Apple developer team is required for the MCP group.')
group = team + '.lb.mcp'
info_path = Path(app) / 'Contents/Info.plist'
info = plistlib.loads(info_path.read_bytes())
info['LeftBlankAgentGroup'] = group
info_path.write_bytes(plistlib.dumps(info))
app_entitlements = plistlib.loads(Path(original).read_bytes()) if original else {}
app_entitlements['com.apple.security.application-groups'] = [group]
Path(temporary, 'app.plist').write_bytes(plistlib.dumps(app_entitlements))
Path(temporary, 'helper.plist').write_bytes(plistlib.dumps({'com.apple.security.application-groups': [group]}))
PY
  entitlements="$signing_dir/app.plist"
fi
codesign "${helper_args[@]}" "$app/Contents/Helpers/tinymist"
if [ -f "$app/Contents/Helpers/LeftBlankMCP" ]; then
  if [ "$identity" = - ]; then
    codesign "${args[@]}" "$app/Contents/Helpers/LeftBlankMCP"
  else
    codesign "${args[@]}" --entitlements "$signing_dir/helper.plist" "$app/Contents/Helpers/LeftBlankMCP"
  fi
fi
if [ -n "$entitlements" ]; then args+=(--entitlements "$entitlements"); fi
codesign "${args[@]}" "$app"
codesign --verify --deep --strict "$app"

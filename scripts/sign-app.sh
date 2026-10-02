#!/bin/bash
# Sign nested Sparkle executables before the framework and outer app.
set -euo pipefail
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
codesign "${args[@]}" "$app/Contents/Helpers/tinymist"
codesign "${args[@]}" "$app/Contents/Helpers/LeftBlankMCP"
if [ -n "$entitlements" ]; then args+=(--entitlements "$entitlements"); fi
codesign "${args[@]}" "$app"
codesign --verify --deep --strict "$app"

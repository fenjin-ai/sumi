#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
source scripts/environment.sh
scripts/bootstrap.sh
configuration=${1:-debug}
swift build -c "$configuration"
binary_dir=$(swift build -c "$configuration" --show-bin-path)
app=build/Sumi.app
rm -f "$app/Contents/embedded.provisionprofile"
rm -rf "$app/Contents/Resources"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources" "$app/Contents/Helpers"
cp "$binary_dir/Sumi" "$app/Contents/MacOS/Sumi"
cp .tools/tinymist "$app/Contents/Helpers/tinymist"
cp "$binary_dir/SumiMCP" "$app/Contents/Helpers/SumiMCP"
cp -R Resources/. "$app/Contents/Resources/"
for bundle in "$binary_dir"/*.bundle; do
  [ -d "$bundle" ] && cp -R "$bundle" "$app/Contents/Resources/"
done
cp Resources/Info.plist "$app/Contents/Info.plist"
codesign --force --sign - "$app/Contents/Helpers/tinymist"
codesign --force --sign - "$app/Contents/Helpers/SumiMCP"
codesign --force --sign - "$app"
echo "Built $PWD/$app"

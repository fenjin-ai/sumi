#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
export TMPDIR=/Volumes/SSD/Developer/Codex/tmp TMP=/Volumes/SSD/Developer/Codex/tmp TEMP=/Volumes/SSD/Developer/Codex/tmp
test -d /Volumes/SSD/Developer || { echo 'The development SSD is not mounted.' >&2; exit 1; }
scripts/bootstrap.sh
configuration=${1:-debug}
swift build -c "$configuration"
binary_dir=$(swift build -c "$configuration" --show-bin-path)
app=build/Sumi.app
rm -rf "$app/Contents/Resources"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources" "$app/Contents/Helpers"
cp "$binary_dir/Sumi" "$app/Contents/MacOS/Sumi"
cp .tools/tinymist "$app/Contents/Helpers/tinymist"
cp -R Resources/. "$app/Contents/Resources/"
cp Resources/Info.plist "$app/Contents/Info.plist"
codesign --force --sign - "$app/Contents/Helpers/tinymist"
codesign --force --sign - "$app"
echo "Built $PWD/$app"

#!/bin/bash
# A public release must be Developer ID signed and accepted by Apple's notary service.
set -euo pipefail
set +x
cd "$(dirname "$0")/.."
source scripts/environment.sh
for variable in SIGNING_CERTIFICATE_P12 SIGNING_CERTIFICATE_PASSWORD APP_STORE_CONNECT_KEY_ID APP_STORE_CONNECT_ISSUER_ID APP_STORE_CONNECT_PRIVATE_KEY APPLE_TEAM_ID; do
  if [ -z "${!variable:-}" ]; then echo "Missing release credential: $variable" >&2; exit 1; fi
done
test "$(uname -m)" = arm64 || { echo 'Public releases support Apple Silicon only.' >&2; exit 1; }
umask 077
signing_dir=$(mktemp -d "$TMPDIR/sumi-signing.XXXXXX")
keychain="$signing_dir/signing.keychain-db"
cleanup() {
  security delete-keychain "$keychain" >/dev/null 2>&1 || true
  rm -rf "$signing_dir"
}
trap cleanup EXIT
keychain_password=$(openssl rand -base64 32)
python3 - "$signing_dir" <<'PY'
import base64, os, pathlib, sys
folder = pathlib.Path(sys.argv[1])
(folder / "certificate.p12").write_bytes(base64.b64decode(os.environ["SIGNING_CERTIFICATE_P12"], validate=True))
(folder / "notary.p8").write_text(os.environ["APP_STORE_CONNECT_PRIVATE_KEY"])
PY
security create-keychain -p "$keychain_password" "$keychain"
security set-keychain-settings -lut 21600 "$keychain"
security unlock-keychain -p "$keychain_password" "$keychain"
curl --fail --silent --show-error --location --proto '=https' \
  https://www.apple.com/certificateauthority/DeveloperIDG2CA.cer -o "$signing_dir/DeveloperIDG2CA.cer"
printf '%s  %s\n' f16cd3c54c7f83cea4bf1a3e6a0819c8aaa8e4a1528fd144715f350643d2df3a "$signing_dir/DeveloperIDG2CA.cer" | shasum -a 256 -c -
security import "$signing_dir/DeveloperIDG2CA.cer" -k "$keychain" >/dev/null
security import "$signing_dir/certificate.p12" -k "$keychain" -P "$SIGNING_CERTIFICATE_PASSWORD" -T /usr/bin/codesign >/dev/null
security set-key-partition-list -S apple-tool:,apple:,codesign: -k "$keychain_password" "$keychain" >/dev/null
unset SIGNING_CERTIFICATE_P12 SIGNING_CERTIFICATE_PASSWORD APP_STORE_CONNECT_PRIVATE_KEY
identities=$(security find-identity -v -p codesigning "$keychain" | awk '/"Developer ID Application:/ {print $2}')
test "$(printf '%s\n' "$identities" | awk 'NF {n++} END {print n+0}')" = 1 || { echo 'Expected exactly one valid Developer ID Application identity.' >&2; exit 1; }
scripts/build.sh release
app=build/Sumi.app
codesign --force --options runtime --timestamp --keychain "$keychain" --sign "$identities" "$app/Contents/Helpers/tinymist"
codesign --force --options runtime --timestamp --keychain "$keychain" --sign "$identities" "$app"
codesign --verify --deep --strict "$app"
actual_team=$(codesign -d --verbose=4 "$app" 2>&1 | sed -n 's/^TeamIdentifier=//p')
test "$actual_team" = "$APPLE_TEAM_ID" || { echo 'Signing certificate team does not match APPLE_TEAM_ID.' >&2; exit 1; }
mkdir -p build/notarization build/release
ditto -c -k --sequesterRsrc --keepParent "$app" "$signing_dir/submission.zip"
notary_status=0
xcrun notarytool submit "$signing_dir/submission.zip" --key "$signing_dir/notary.p8" \
  --key-id "$APP_STORE_CONNECT_KEY_ID" --issuer "$APP_STORE_CONNECT_ISSUER_ID" \
  --wait --timeout 30m --output-format json > build/notarization/result.json || notary_status=$?
if [ "$notary_status" -ne 0 ]; then
  echo 'Apple notarization did not complete successfully; no release archive will be published.' >&2
  exit "$notary_status"
fi
python3 - <<'PY'
import json
from pathlib import Path
result = json.loads(Path("build/notarization/result.json").read_text())
if result.get("status") != "Accepted":
    raise SystemExit("Apple notarization status: " + str(result.get("status", "unknown")))
print("Apple notarization accepted: " + result["id"])
PY
xcrun stapler staple "$app"
xcrun stapler validate "$app"
codesign --verify --deep --strict "$app"
spctl --assess --type execute --verbose=2 "$app"
version=$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' Resources/Info.plist)
archive="Sumi-${version}-macOS-arm64.zip"
ditto -c -k --sequesterRsrc --keepParent "$app" "build/release/$archive"
(cd build/release && shasum -a 256 "$archive" > "$archive.sha256")
echo "Signed, notarized and stapled: build/release/$archive"

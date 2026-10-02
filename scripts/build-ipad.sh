#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
source scripts/environment.sh

platform="${1:-simulator}"
case "$platform" in
  simulator) target=aarch64-apple-ios-sim; destination='generic/platform=iOS Simulator' ;;
  device) target=aarch64-apple-ios; destination='generic/platform=iOS' ;;
  *) echo 'Usage: scripts/build-ipad.sh [simulator|device]' >&2; exit 2 ;;
esac
# Cargo keeps build outputs in this SSD workspace; dependency sources also stay
# on the development volume. CI uses its disposable checkout.
if [ "${GITHUB_ACTIONS:-}" = true ]; then
  export CARGO_HOME="$PWD/.tools/cargo-ipad"
else
  export CARGO_HOME=/Volumes/SSD/Developer/Codex/cargo-ipad
fi
export IPHONEOS_DEPLOYMENT_TARGET=17.0
rustup toolchain install 1.92.0 --profile minimal --target "$target"
cargo +1.92.0 build --locked --manifest-path Engine/TinymistBridge/Cargo.toml --release --target "$target"
xcodebuild -project iPad/LeftBlank.xcodeproj -scheme LeftBlank-iPad \
  -destination "$destination" -derivedDataPath build/iPad \
  -clonedSourcePackagesDirPath .build/xcode-packages \
  CODE_SIGNING_ALLOWED=NO build

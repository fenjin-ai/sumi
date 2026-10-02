#!/bin/bash
# Use the macOS TLS backend rather than embedding Rust TLS in the store build.
set -euo pipefail
cd "$(dirname "$0")/.."
source scripts/environment.sh
source_dir="$PWD/.tools/tinymist-appstore-source"
revision=32f908199ee17ea295512bbc27166e890c438175
patch="$PWD/scripts/tinymist-appstore.patch"
stamp=$(shasum -a 256 "$patch" | awk '{print $1}')
if [ -x .tools/tinymist-appstore ] && [ "$(cat .tools/tinymist-appstore.stamp 2>/dev/null)" = "$stamp" ]; then
  .tools/tinymist-appstore --version
  exit 0
fi
if [ ! -d "$source_dir" ]; then
  git clone --depth 1 --branch v0.15.8 https://github.com/Myriad-Dreamin/tinymist.git "$source_dir"
fi
test "$(git -C "$source_dir" rev-parse HEAD)" = "$revision"
if git -C "$source_dir" apply --check "$patch"; then
  git -C "$source_dir" apply "$patch"
else
  git -C "$source_dir" apply --reverse --check "$patch"
fi
export CARGO_HOME="$source_dir/.cargo-home"
export MACOSX_DEPLOYMENT_TARGET=14.0
# macOS 27 rejects misaligned proc-macro dylibs produced when debug info is stripped.
export CARGO_PROFILE_RELEASE_BUILD_OVERRIDE_DEBUG=1
export CARGO_PROFILE_RELEASE_BUILD_OVERRIDE_STRIP=none
(cd "$source_dir" && cargo +1.92.0 build --release --locked -p tinymist-cli)
cp "$source_dir/target/release/tinymist" .tools/tinymist-appstore
printf '%s\n' "$stamp" > .tools/tinymist-appstore.stamp
.tools/tinymist-appstore --version

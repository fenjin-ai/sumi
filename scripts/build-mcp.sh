#!/bin/bash
# Independent macOS helper; never part of the iPad package graph.
set -euo pipefail
cd "$(dirname "$0")/.."
source scripts/environment.sh
test "$(uname -m)" = arm64 || { echo 'LeftBlank supports Apple Silicon only.' >&2; exit 1; }
export CARGO_HOME="$PWD/.tools/cargo-mcp"
export MACOSX_DEPLOYMENT_TARGET=14.0
# Retain proc-macro alignment on newer local macOS toolchains.
export CARGO_PROFILE_RELEASE_BUILD_OVERRIDE_DEBUG=1
export CARGO_PROFILE_RELEASE_BUILD_OVERRIDE_STRIP=none
rustup toolchain install 1.92.0 --profile minimal
configuration=${1:-debug}
case "$configuration" in
  debug) options=(--profile dev) ;;
  release) options=(--release) ;;
  *) echo 'Usage: scripts/build-mcp.sh [debug|release]' >&2; exit 2 ;;
esac
cargo +1.92.0 build --locked --manifest-path Tools/LeftBlankMCP/Cargo.toml "${options[@]}"

#!/bin/bash
# Native stdio/Unix-socket tests; no network server, DB or container runtime.
set -euo pipefail
cd "$(dirname "$0")/.."
source scripts/environment.sh
export CARGO_HOME="$PWD/.tools/cargo-mcp"
export LEFTBLANK_TEST_TMP_ROOT="$TMPDIR"
export MACOSX_DEPLOYMENT_TARGET=14.0
export CARGO_PROFILE_RELEASE_BUILD_OVERRIDE_DEBUG=1
export CARGO_PROFILE_RELEASE_BUILD_OVERRIDE_STRIP=none
rustup toolchain install 1.92.0 --profile minimal --component rustfmt,clippy,llvm-tools-preview
cargo +1.92.0 fmt --manifest-path Tools/LeftBlankMCP/Cargo.toml --check
cargo +1.92.0 clippy --locked --manifest-path Tools/LeftBlankMCP/Cargo.toml --all-targets -- -D warnings
if ! cargo llvm-cov --version 2>/dev/null | grep -qx 'cargo-llvm-cov 0.9.1'; then
  cargo +1.92.0 install cargo-llvm-cov --version 0.9.1 --locked --root "$PWD/.tools/mcp-test-tools"
  export PATH="$PWD/.tools/mcp-test-tools/bin:$PATH"
fi
mkdir -p build/coverage
cargo +1.92.0 llvm-cov --locked --manifest-path Tools/LeftBlankMCP/Cargo.toml \
  --lcov --output-path "$PWD/build/coverage/mcp.lcov" --fail-under-lines 80 \
  --ignore-filename-regex '/tests/'

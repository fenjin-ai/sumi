#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
source scripts/environment.sh
mkdir -p .tools
version=0.15.8
case "$(uname -m)" in
  arm64) arch=aarch64; expected=c3e8673fe4b7d8d21ad6d90e3c0684317191e1350758f7eaa02b5bde84339885 ;;
  *) echo 'Sumi supports Apple Silicon (arm64) only' >&2; exit 1 ;;
esac
archive="tinymist-${arch}-apple-darwin.tar.gz"
base="https://github.com/Myriad-Dreamin/tinymist/releases/download/v${version}"
if [ ! -x .tools/tinymist ] || ! .tools/tinymist --version | grep -q "v$version"; then
  curl --fail --location --retry 3 --retry-all-errors --connect-timeout 20 --max-time 180 "$base/$archive" -o ".tools/$archive"
  actual=$(shasum -a 256 ".tools/$archive" | awk '{print $1}')
  test "$actual" = "$expected" || { echo 'Tinymist checksum mismatch' >&2; exit 1; }
  tar -xzf ".tools/$archive" -C .tools
  binary=".tools/tinymist-${arch}-apple-darwin/tinymist"
  test -x "$binary"
  cp "$binary" .tools/tinymist
  chmod +x .tools/tinymist
fi
.tools/tinymist --version

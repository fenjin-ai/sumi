#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
export TMPDIR=/Volumes/SSD/Developer/Codex/tmp TMP=/Volumes/SSD/Developer/Codex/tmp TEMP=/Volumes/SSD/Developer/Codex/tmp
test -d /Volumes/SSD/Developer || { echo 'The development SSD is not mounted.' >&2; exit 1; }
mkdir -p .tools
version=0.15.8
case "$(uname -m)" in
  arm64) arch=aarch64 ;;
  x86_64) arch=x86_64 ;;
  *) echo 'Unsupported architecture' >&2; exit 1 ;;
esac
archive="tinymist-${arch}-apple-darwin.tar.gz"
base="https://github.com/Myriad-Dreamin/tinymist/releases/download/v${version}"
if [ ! -x .tools/tinymist ] || ! .tools/tinymist --version | grep -q "v$version"; then
  curl --fail --location --retry 3 "$base/$archive" -o ".tools/$archive"
  curl --fail --location --retry 3 "$base/$archive.sha256" -o ".tools/$archive.sha256"
  expected=$(awk '{print $1}' ".tools/$archive.sha256")
  actual=$(shasum -a 256 ".tools/$archive" | awk '{print $1}')
  test "$actual" = "$expected" || { echo 'Tinymist checksum mismatch' >&2; exit 1; }
  tar -xzf ".tools/$archive" -C .tools
  binary=".tools/tinymist-${arch}-apple-darwin/tinymist"
  test -x "$binary"
  cp "$binary" .tools/tinymist
  chmod +x .tools/tinymist
fi
.tools/tinymist --version

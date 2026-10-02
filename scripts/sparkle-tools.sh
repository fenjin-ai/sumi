#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
source scripts/environment.sh
version=2.10.0
expected=c2bf58aa8387266ac179357b1415d6f2635f044da8be41042af32425dae6da0c
archive=.tools/sparkle.tar.xz
mkdir -p .tools/sparkle
if [ ! -f "$archive" ]; then
  curl --fail --location --retry 3 --connect-timeout 20 --max-time 180 \
    "https://github.com/sparkle-project/Sparkle/releases/download/$version/Sparkle-$version.tar.xz" -o "$archive"
fi
actual=$(shasum -a 256 "$archive" | awk '{print $1}')
test "$actual" = "$expected" || { echo 'Sparkle tools checksum mismatch' >&2; exit 1; }
tar -xJf "$archive" -C .tools/sparkle

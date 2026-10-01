#!/bin/bash
# Run after scripts/test.sh. Reuses its instrumented debug test binary.
set -euo pipefail
cd "$(dirname "$0")/.."
source scripts/environment.sh
mkdir -p build/benchmarks
SUMI_INTEGRATION=1 \
  SUMI_LARGE_FIXTURE="$PWD/Examples/Books/WarAndPeace/war-and-peace-highlighted.typ" \
  SUMI_PERFORMANCE_REPORT="$PWD/build/benchmarks/war-and-peace.json" \
  swift test --skip-build --enable-code-coverage --filter realMultiMegabyteDocumentNavigationScrollingAndTyping
SUMI_INTEGRATION=1 SUMI_CODE_WORD="define size" SUMI_SEARCH_WORD=procedure SUMI_BENCH_EXPORT=1 \
  SUMI_LARGE_FIXTURE="$PWD/Examples/Books/SICP/main.typ" \
  SUMI_PERFORMANCE_REPORT="$PWD/build/benchmarks/sicp.json" \
  swift test --skip-build --enable-code-coverage --filter realMultiMegabyteDocumentNavigationScrollingAndTyping
python3 - <<'PY'
import json
from pathlib import Path
rows = ['# Book editing benchmarks', '', '| Book | Source bytes | Open (s) | Typing median / max (ms) | Navigate + draw median (ms) | Scroll + draw p95 (ms) |', '|---|---:|---:|---:|---:|---:|']
for book in ['war-and-peace', 'sicp']:
    r = json.loads(Path(f'build/benchmarks/{book}.json').read_text())
    rows.append(f'| {book} | {r["bytes"]:,} | {r["open_seconds"]:.2f} | {r["typing_ms"]["median"]:.2f} / {r["typing_ms"]["max"]:.2f} | {r["navigation_ms"]["median"]:.2f} | {r["scroll_draw_ms"]["p95"]:.2f} |')
rows += ['', 'Instrumented debug AppKit tests. CPU layout and bitmap painting, not display FPS. Memory excludes Tinymist and WebKit. See docs/large-document-performance.md for scope.']
Path('build/benchmarks/summary.md').write_text('\n'.join(rows) + '\n')
PY

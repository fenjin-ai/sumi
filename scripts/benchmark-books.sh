#!/bin/bash
# Run after scripts/test.sh. Reuses its instrumented debug test binary.
set -euo pipefail
cd "$(dirname "$0")/.."
source scripts/environment.sh
mkdir -p build/benchmarks
status=0
# Keep the other book and preview evidence even if one scenario fails. Never
# retry a failing measurement or let an old report stand in for the current run.
python3 - <<'PYCLEAN'
from pathlib import Path
for name in ('war-and-peace.json', 'sicp.json', 'summary.md', 'book-preview-1.png', 'book-preview-224.png', 'book-preview-448.png'):
    (Path('build/benchmarks') / name).unlink(missing_ok=True)
PYCLEAN
SUMI_INTEGRATION=1 \
  SUMI_LARGE_FIXTURE="$PWD/Examples/Books/WarAndPeace/war-and-peace-highlighted.typ" \
  SUMI_PERFORMANCE_REPORT="$PWD/build/benchmarks/war-and-peace.json" \
  swift test --skip-build --enable-code-coverage --filter realMultiMegabyteDocumentNavigationScrollingAndTyping || status=1
SUMI_INTEGRATION=1 SUMI_CODE_WORD="define size" SUMI_SEARCH_WORD=procedure SUMI_BENCH_EXPORT=1 \
  SUMI_LARGE_FIXTURE="$PWD/Examples/Books/SICP/main.typ" \
  SUMI_PERFORMANCE_REPORT="$PWD/build/benchmarks/sicp.json" \
  swift test --skip-build --enable-code-coverage --filter realMultiMegabyteDocumentNavigationScrollingAndTyping || status=1
SUMI_INTEGRATION=1 SUMI_BOOK_PREVIEW=1 \
  swift test --skip-build --enable-code-coverage --filter completeBookPreviewRemainsUsableInLargeWindow || status=1
python3 - <<'PY'
import json
from pathlib import Path
rows = ['# Book editing benchmarks', '', '| Book | Source bytes | Open (s) | Typing median / p95 / max (ms) | Typing CPU max (ms) | Navigate + draw median (ms) | Scroll + draw p95 (ms) |', '|---|---:|---:|---:|---:|---:|---:|']
for book in ['war-and-peace', 'sicp']:
    report = Path(f'build/benchmarks/{book}.json')
    if not report.exists():
        rows.append(f'| {book} | Report unavailable: scenario failed before completion | | | | | |')
        continue
    r = json.loads(report.read_text())
    rows.append(f'| {book} | {r["bytes"]:,} | {r["open_seconds"]:.2f} | {r["typing_ms"]["median"]:.2f} / {r["typing_ms"]["p95"]:.2f} / {r["typing_ms"]["max"]:.2f} | {r["typing_thread_cpu_ms"]["max"]:.2f} | {r["navigation_ms"]["median"]:.2f} | {r["scroll_draw_ms"]["p95"]:.2f} |')
rows += ['', 'Typing gates: 80 samples, wall p95 < 100 ms, wall max < 250 ms, main-thread CPU max < 100 ms. First input is included; no retries or discarded outliers.', '', 'Instrumented debug AppKit tests. CPU layout and bitmap painting, not display FPS. Memory excludes Tinymist and WebKit. See docs/large-document-performance.md for scope.']
Path('build/benchmarks/summary.md').write_text('\n'.join(rows) + '\n')
PY
exit "$status"

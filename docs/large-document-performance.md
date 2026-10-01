# Real-book editor performance

Measured on 2026-10-01, Apple M4 Pro, macOS 27.0, native AppKit editor,
Tinymist 0.15.8 / Typst 0.15.1. These are instrumented debug test runs, not a
release-mode FPS claim. Both fixture sources, licenses and generators are in
[Examples/Books](../Examples/Books/README.md).

## Workload and results

The 3.3 MB War and Peace fixture preserves the downloaded novel and adds 39
small, distributed Python/math/Unicode blocks. SICP is the complete original
Scheme second edition: 1.45 MB of manuscript, 1,098 Scheme blocks, 1,356 math
expressions and 84 SVG figures. It imports its own local typography module.
Neither book is repeated to manufacture a larger buffer.

| Book | Source bytes | Open (s) | Typing median / max (ms) | Navigate + draw median (ms) | Scroll + draw p95 (ms) |
|---|---:|---:|---:|---:|---:|
| war-and-peace | 3,302,718 | 4.09 | 9.29 / 52.23 | 4.20 | 5.04 |
| sicp | 1,446,633 | 3.32 | 6.70 / 10.88 | 6.07 | 3.89 |

SICP exported to **448 pages** in 2.41 seconds after engine startup.
The test/editor process ended at 290.7 MiB for War and Peace and
287.8 MiB for SICP. These are process physical-footprint snapshots,
not peak memory and not total application memory: Tinymist and WebKit are separate
processes. Each current report comes from its own fresh test process.

The earlier War and Peace run had a 619.3 ms median / 628.1 ms maximum synchronous
typing path. The current run measures 9.29 / 52.23 ms. Opening the
buffer increased from 1.37 to 4.09 seconds because contiguous layout was
restored for reliable pointer geometry. The earlier run failed distant pointer
round-trip checks; current checks pass. Its scrolling measurement only included
layout, so it is not directly comparable to the new draw measurement.

Raw reports: [War and Peace before](benchmarks/war-and-peace-before.json),
[War and Peace after](benchmarks/war-and-peace.json), [SICP](benchmarks/sicp.json).
Absolute timings vary with hardware, instrumentation, caches and background load.

## What changed

- Native text-storage edits carry a replacement range into the document metrics.
  Grapheme counts and UTF-16 line positions rescan neighboring lines and shift
  later offsets. Emoji, combining marks and CRLF boundaries are checked against
  full recomputation over 240 deterministic edit transactions.
- Swift strings backed by AppKit UTF-16 storage are materialized once for full
  grapheme scans. Frequent styling and UI reconciliation compare revisions,
  avoiding repeated multi-megabyte String equality on the UI thread.
- Semantic-token decoding runs off the main actor. Embedded-language analysis is
  cached and bounded; the offline Scheme grammar covers the real book's code.
  Nested highlight spans keep their specificity when their ranges coincide.
- TextKit uses contiguous layout. Noncontiguous layout shifted a previously
  drawn line by 27 points during the first hit test after a distant jump. The
  increased initial layout cost is preferable to moving the cursor incorrectly.

The native text storage remains authoritative; we did not introduce a second
rope buffer or a terminal editor with another selection/undo model. These fixes
address measured costs. Line-index suffix shifts are still O(number of lines),
not a claim of constant-time edits or unlimited document size. Full-document
semantic snapshots, synchronous save boundaries and background analysis can
still consume time and memory; see [editor foundations](editor-foundations.md).

## Reproduce and interpret

```sh
scripts/test.sh
scripts/benchmark-books.sh
```

The second script reuses the instrumented test binary. It runs on each PR in CI
and uploads `build/benchmarks` plus a job summary. No fixture download is required.
Each scenario uses production Workspace, NSTextView and real Tinymist:

1. Open a complete source and wait for semantic highlighting; assert a known
   built-in inside a fenced code block has the embedded-language color.
2. Jump among six distant offsets, apply styles, force layout and draw the
   visible region into a bitmap. Map a rendered glyph back to a native insertion
   point and check the position, rather than only checking a selection integer.
3. Search later text and scroll through 60 frames with native visible-region
   layout and bitmap painting.
4. Insert 16 mixed Latin/CJK/emoji characters through the native editor, include
   metric reads, then undo and verify the original source exactly.
5. For SICP, export through Tinymist and require more than 400 PDF pages.
6. Open the 448-page book in a 1920 × 1300 pt WebKit preview. Jump to pages
   1, 224, 448 and back to 1; require visible SVG glyphs and snapshots with
   actual painted text, with no canvas fallback surfaces. CI retains page
   snapshots alongside timing reports. Real-window acceptance also covers
   scrolling from the cover to page 448 and back to page 340.

The test uses a hidden native window and CPU bitmap rendering. It does not
measure physical display refresh, GPU compositing, human typing latency,
continuous wheel/trackpad events, or the full asynchronous autosave/preview cycle.
Typing samples time the synchronous editor/Workspace/metrics path. Broad 100 ms
input and 200 ms navigation guards catch severe regressions without presenting
a hardware-independent performance SLA. Real-window acceptance complements
these tests; it does not replace them.

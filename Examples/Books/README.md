# Real-book editor fixtures

These complete books exercise real source editing, language highlighting,
positioning, scrolling and typesetting. They are development examples and are
not bundled into the application.

| Book | Open in Sumi | Contents |
| --- | --- | --- |
| SICP, original Scheme second edition | [SICP/main.typ](SICP/main.typ) | 1.45 MB manuscript, 84 SVG figures, Scheme code, math, footnotes and cross-references. Includes the [448-page PDF](SICP/main.pdf) and upstream editable Texinfo source. |
| War and Peace | [WarAndPeace/war-and-peace-highlighted.typ](WarAndPeace/war-and-peace-highlighted.typ) | 3.30 MB Typst stress manuscript with 39 benchmark code/math blocks. The 3.36 MB original text is included for provenance. |

Keep SICP's `fig` directory beside `main.typ`, or import the whole SICP project
into Sumi. Sources, licenses, content hashes and generation details are included
with each book. These third-party books have their own licenses, separate from
Sumi's application code. SICP and its Typst adaptation are CC BY-SA 4.0; see
[SICP/ATTRIBUTION.md](SICP/ATTRIBUTION.md). War and Peace retains its full Project
Gutenberg notice; see [its attribution](WarAndPeace/ATTRIBUTION.md).

See [conversion details](../../docs/sicp-fixture.md) and
[benchmark instructions and measurements](../../docs/large-document-performance.md).

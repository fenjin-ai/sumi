# Template and package discovery

Sumi treats a template as a starting document and a package as a tool for the current document. The two intents share the official catalog, but have separate collections and actions.

## Starting a document

The library has a visible **Browse templates** action beside **New document**. New document and Command-N still create a blank document immediately; a gallery is never a mandatory step.

The template gallery uses actual versioned thumbnails from Typst Universe. Missing images have a clearly labeled typographic placeholder, not a fabricated document preview. Selecting a template reveals its description, license, version, author, documentation, and a **Create document** action. In wider windows the details remain beside the grid. Below 850 points the selected detail replaces the grid, with an explicit Back to results action. The sheet fits the writing window and grows to 1040 by 720 points; the ordinary library grows to 980 by 680 points.

Collections combine the official technical categories into writing tasks:

- Research and study: papers and theses.
- Work and reports: reports, letters, invoices, and office documents.
- CVs and applications.
- Slides and posters.
- Books and writing.

Creating a template runs the bundled Tinymist `tinymist.doInitTemplate` command through a separate short-lived service. This reuses the official package resolver, versioned download cache, and TOML parser without stopping the current document's service. The result is validated and imported as an independent managed project, preserving images, bibliography files, and subdirectories. The staging directory is removed afterward. The previous writing stays open until the new project is available. Browsing alone creates no documents and downloads no package code.

## Downloadable example books

The library and the Books template collection include a SICP card with an
original typographic cover, source/license link and **Add to my writing** action.
It also matches SICP and bilingual book searches. No book is downloaded at app
launch. Adding it downloads about 1.9 MB, verifies the pinned SHA-256 and byte
count, and imports a complete editable copy with all 84 illustrations and local
styles. The archive is cached for offline reuse. Each addition has a new library
identity; editing one copy cannot change another or the cached original.

The ZIP has a content-addressed filename in `Examples/Books/SICP`, published via
the public repository. `scripts/package-sicp.py` reproducibly builds it from the
reviewed sources. The app's size and digest constants must be reviewed together
when updating an example. The source PDF and upstream Texinfo are committed for
inspection but omitted from this download. Attribution and CC BY-SA 4.0 travel
with every copy. Download errors stay in the discovery surface and can be
retried; failed or cancelled downloads never replace the current writing.

## Finding tools while writing

The existing Universe command opens the Packages intent. Its collections are diagrams and charts, math and science, code and algorithms, layout and typography, tables and data, and writing tools. Templates are excluded from this list.

Search matches package names, descriptions, keywords, categories, disciplines, and bilingual intent synonyms. Exact name and literal query matches take precedence over broader synonyms. A small explicit editorial list gives useful packages a starting position in the unfiltered catalog; this is not a popularity or quality score. Search remains available offline from the saved index. Incompatible engine versions remain visible for discovery, with the create/import action disabled and a reason shown.

**Insert import** preserves the existing native, undoable insertion path and pins the chosen version. Package documentation remains the authority for setup and examples. An empty library can browse packages, but must open a document before inserting one.

## Responsiveness and storage

The catalog store constructs the searchable index once off the UI actor. The browser computes results when its query, collection, intent, or snapshot changes, rather than searching again for every card render. Lazy grids keep view creation proportional to visible cards.

Thumbnails load asynchronously from the official versioned `packages.typst.org/preview/thumbnails/` endpoints. Responses are bounded to 5 MiB and images are downsampled to at most 600 pixels before display. The decoded image cache is limited to 32 MiB / 60 entries, the URL cache to 48 MiB on disk, and concurrent connections to four per host. Duplicate in-flight requests share a task; failures have a five-minute cooldown. Missing previews never block a search or document creation.

No document text, click history, or query is uploaded to a recommendation service. Foundation Models is not required for discovery. It may later translate natural-language intent into these same bounded collections and queries, but the catalog must remain the source of package names and versions. The bilingual evaluation gate in [local-intelligence.md](local-intelligence.md) still applies before that feature ships.

## Verification

Functional tests cover cached/offline catalog behavior, bilingual search and mode switching, narrow/wide native rendering, no document changes while browsing, source/asset validation, and an opt-in network path through the official registry and real Tinymist to a managed document and PDF. The app-level network scenario also verifies that creation opens the new managed document, preserves the previous writing, and cleans the staging directory.

```sh
source scripts/environment.sh
SUMI_INTEGRATION=1 SUMI_UNIVERSE_NETWORK=1 swift test --filter 'universe|Universe|templateGallery|templateCreationOpens|cachedPackageBrowser|discoveryModel'
```

The network scenarios are opt-in so ordinary CI is deterministic. Set `SUMI_DISCOVERY_ARTIFACTS` to an SSD-backed directory to save the 620- and 1040-point gallery renders for visual inspection.

## Primary references

- [Official Typst package catalog](https://packages.typst.org/preview/index.json)
- [Typst packages repository and template manifest documentation](https://github.com/typst/packages)
- [Tinymist template scaffolding implementation](https://github.com/Myriad-Dreamin/tinymist/blob/v0.15.8/crates/tinymist/src/cmd.rs)
- [Foundation Models](https://developer.apple.com/documentation/foundationmodels)

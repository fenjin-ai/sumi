# Implementation and verification record

Date: 2026-10-01. This record preserves evidence from each development iteration. New feature acceptance is recorded separately; historical counts and measurements refer to the stated version.


## 0.4.0 (7) · Trash without replacement drafts

Deleting the active document previously created a new Untitled as a safe landing document, so the list count did not decrease. The library now preserves pending edits, moves the document to recoverable trash and selects a remaining document. Deleting the last document shows the library itself, with no implicit draft; this state persists across relaunch. Import dialogs keep the parent window even when no editor is present. Local action logs record rename, trash and restore by document identity without titles or content.

## 0.4 acceptance follow-up · Direct document controls

- Single-click managed-document titles to rename inline; Return commits and Escape cancels. Double-click the toolbar title for the library, or a library title to open its document. Library rows provide direct trash/restore icons.
- Preview color controls retain a centered, fixed-size hit target in both states. Native menu icons use a compact intrinsic size.
- All native interface scenarios now run in a shared serialized suite, avoiding cross-test interference from AppKit's process-wide focus, menus and sheet presentation.
- Local acceptance: **70 Swift tests passed**, three profile-validation checks passed, and production source-line coverage reached **88.13% (4048/4593)**. A relocated app launched with build resources hidden, loaded its Chinese welcome document and connected to Tinymist.
- The packaged app explicitly finds localization resources in Contents/Resources. CI includes an isolated cold-launch check with diagnostic artifacts to detect checkout-dependent builds.

## 0.4.0 · Library, agent access and languages

- The title opens a searchable document library with templates, renaming, recoverable trash, source/project import and export. Stable document identities hide implementation filenames from normal writing.
- Optional iCloud Drive storage uses native file coordination, change discovery, download states and conflict protection. Independent incoming source edits merge against the editor's saved baseline with native undo, selection and focus preservation. Settings reconcile per field before publishing local changes.
- The dedicated App ID, iCloud container and Developer ID provisioning profile were configured. The release workflow now validates and embeds the profile before signing. A newly provisioned signed release and real two-Mac delivery have **not** yet been verified; isolated tests do not establish Notes-like sync performance.
- The bundled MCP helper uses the official Swift SDK. Opt-in local access exposes the live buffer, undoable revision-checked edits, library navigation, bounded settings changes, diagnostics, PDF export and rendered page inspection. Agent access is local to the Mac and never synchronized.
- Native English and Simplified Chinese resources switch without recreating the editor. Public documentation and brand materials are English. The outline's pin lives in the left margin, becomes a close mark on hover and stays within the margin when pinned.
- An explicit Code Notes template bundles pinned Codly packages for styled code blocks. It compiles without a first-use package download. Executing code blocks is documented as a separate future feature, not enabled by the template.
- **69 Swift tests passed**: 36 core, 4 socket/protocol and 29 app flows, plus **3 provisioning-profile checks**. Production source-line coverage was **87.33% (3907/4474)** with an 80% gate. Tests include real Tinymist compilation, native editing/undo, MCP client calls and PDF/page content.
- Native app acceptance checked document creation, Code Notes rendering, language/menu changes and outline placement. The final release-configuration development build is 0.4.0 (6).
- Research records cover [three-way merge and Forked](merge-evaluation.md) and [optional local intelligence](local-intelligence.md). A synthetic on-device Foundation Models probe classified four bilingual requests correctly (first request about 1.5 seconds, later requests about 0.4 seconds); this is feasibility evidence, not a quality or responsiveness benchmark. Model suggestions are not part of the shipped editor yet.

### 0.4 acceptance follow-up

Real-window checks covered command search and table insertion, undo/redo, Unicode, library content search, rename, trash/restore, retained preview after a syntax error and PDF export. The exported PDF was independently opened with PDFKit and checked for the document title, table and Chinese text. Visual inspection found oversized native menu icons; their intrinsic PDF size is now bounded. Managed exports suggest the document's title.

Hosted CI exposed a Swift 6.2.4 compiler crash and a case-sensitive localized-resource lookup difference. Both were fixed. A fixed-delay form assertion was replaced with a wait for the expected accessible fields; existing text fields also refresh their localized labels. The complete **69-test** suite passed locally under both build systems, with **88.07% (3951/4486)** production coverage in the instrumented run. See [the testing strategy](testing-strategy.md) for current checks and proposed UI/screenshot layers.

## 0.3.0 · Interaction, performance and identity

- The outline became an independent left-margin overlay: fine marks at rest, gradual hover expansion, `⌘4` to pin and Esc to dismiss. The separate border, shadow, full-row highlight and close button were removed.
- Toolbar help shrank to the action name and shortcut. Direct shortcuts coexist with discovery paths: 25 frequent actions, 106 discoverable commands and distinct command/category icons.
- A fixed command-panel height and guide position keep the editor stable through search, keyboard selection and parameter forms. Hover no longer causes a selection/scroll feedback loop.
- Repeated whole-document metrics, icon decoding, queries and full-buffer style refreshes were removed from command navigation. A roughly 100,000-character benchmark is documented in [interaction and performance](interaction.md).
- **43 tests passed**: 23 core and 20 app functional tests. Production line coverage was **88.97% (2404/2702)**. Added checks cover native window geometry, narrow forms, icon resources, shortcut aliases, tooltip size, Unicode caches and long-document performance.
- The signing workflow passed real Apple notarization and Gatekeeper verification. Codecov uses GitHub OIDC, a main badge, numeric PR comments and 80% project/patch checks. See [PR #2's coverage report](https://github.com/fenjin-ai/sumi/pull/2#issuecomment-5926250299).
- The approved identity is a continuous Sigma generated from a golden-ratio skeleton and sine pressure envelope. App icons, README, social previews and favicons share its source and documented generation process. Development build 5 includes the icon.

## 0.2.0 · Discovery, reading and engineering

- 97 commands across nine root groups and nested mathematics paths. All 74 insertions and 18 math-context uses compiled with real Tinymist, including image, bibliography and multiple-file fixtures.
- The native Universe browser supports official-index search, categories, versions, documentation, pinned imports, compiler compatibility, a 24-hour cache and offline fallback. A live index smoke check found 1,636 packages, including 216 visualization packages; automated tests use isolated fixed indexes.
- Visible-region rendering, retained successful pages and explicit stale status support uninterrupted writing. Dark reading preserves exported colors. Compilation errors cannot export an old PDF as current.
- Reading styles for headings, emphasis and inline code reveal source in the active paragraph. Indentation, comments, formatting and native undo are available. Integration testing found and fixed a workspace/editor mismatch after insertion undo.
- **36 tests passed**: 22 core/protocol/compilation cases and 14 native app flows. They use `NSTextView`, Workspace, `WKWebView`, Tinymist and PDF content checks. Hidden WebKit windows drive animation frames with a timer while still running the real WASM renderer and asserting retained pages and page-count changes.
- Production line coverage was **88.65% (2163/2440)**. CI requires 80% without excluding interface files and retains LCOV, LLVM JSON and HTML.
- The public repository is [fenjin-ai/sumi](https://github.com/fenjin-ai/sumi). Release publication requires Developer ID, notarization, stapling and Gatekeeper success. Configuration and real release validation are documented in [signing](signing.md).

User edits to an existing local example were preserved and excluded from implementation commits.

## 0.1.1 · Crash-path removal and diagnostic logs

A user reported a crash after command search and insertion. The supplied stack entered an `AppDelegate` keyboard-monitor closure on the main thread and failed an executor check through `MainActor.assumeIsolated`, producing `EXC_BAD_ACCESS`. Testing table and equation paths in the old package did not reproduce the intermittent crash reliably; it was not attributed to a particular Typst command or claimed as a proven operating-system defect.

Changes:

- Removed the application-wide `NSEvent` monitor and `MainActor.assumeIsolated`. Commands now use `WritingWindow.sendEvent`, with menu shortcuts recorded through `performKeyEquivalent`. File dialogs suspend main-window command handling.
- Unified the document title and actions in `NSToolbar.unifiedCompact`, retaining system traffic lights and removing the second branding row.
- Added rotating local JSONL logs for sessions, control keys, commands, insertion, saving, export and service failures. A menu item and searchable command reveal the logs.
- Logs rotate around 1 MiB with three archives. They omit source, clipboard, search terms and parameters. Ordinary typing is only `text`; system errors can include paths.

The release build and development signature passed. **13 automated tests passed**, including persistence, cross-session append, timestamps and line-by-line JSON checks after rotation. Real UI checks searched for a table, edited parameters, inserted with Return, moved through Chinese placeholders with Tab, used undo/redo, and searched for bold and display equations without terminating the app. Logs captured `command.selected → command.execute → insertion.begin → insertion.finished` without search terms or manuscript text. Searching for the log action revealed `events.jsonl` in Finder.

The evidence supports removal of the failing execution path and regression coverage of important actions. The original intermittent crash was not reproduced reliably, so ongoing use and local logs remain relevant.

## 0.1.0 · Initial delivery

The implementation delivered a native dark writing interface, Phosphor actions, original icon, source editing, highlighting, undo, find, placeholders, 34 commands including 20 insertions, bilingual search, forms, atomic autosave, conflict protection, draft recovery, session restoration, diagnostics, completion, outline, reconnect, real unsaved preview, resizing, zoom, source/page navigation, PDF export and multiple-file compilation.

Verification used macOS 27, Xcode Swift 6.4 and an arm64 Mac, targeting macOS 14. Build and test temporary files stayed on the SSD. No database, Hurl or containers were used.

| Check | Result |
|---|---|
| `scripts/build.sh release` | Passed; app includes arm64 Tinymist |
| `scripts/test.sh` | 11 tests passed, none failed |
| `codesign --verify --deep --strict --verbose=2 build/Sumi.app` | Development signature passed |
| `git diff --check` | No whitespace errors |

Ten core tests covered UTF-16/emoji/CRLF positions, byte-boundary framing, malformed headers, parameter validation, string escaping, literal preservation, code fences, paragraph separation, preamble order, external modification/deletion protection, discovery and recovery data.

One real integration flow launched the production `TinymistClient` and verified:

- Local preview served the real frontend. Unsaved text compiled into PDF, including Unicode, without overwriting the source file on disk.
- Markup, math, raw and code contexts, document symbols, completion and preview navigation worked.
- Invalid source produced diagnostics and `compileError`; export failed instead of copying stale output.
- All 20 initial insertion/style/page commands compiled, including a real SVG and numbered cross-reference targets.
- Stop/restart restored synchronization, and unsaved edits to an included document appeared in the main PDF.

## Real app acceptance

The initial native UI checks covered launch, writing/split/preview views, command categories/search/forms, fast search typing isolated from the manuscript, tables, selection wrapping, placeholders, single-step undo, rejected body commands inside math, Unicode save paths, relaunch restoration, PDF export, deliberate compilation errors and recovery, double-click preview navigation, 100%→110% zoom, split resizing and a compact window around 961×526 pt.

Historical app screenshots remain in `docs/screenshots/`. They record the running application, including its then-selected Chinese interface; they are not current marketing mockups. The purple corner indicator came from macOS screen-control status. The current public sample is [Welcome.typ](../Examples/Welcome.typ).

## Known limits and unverified areas

- Complete Pinyin candidate selection and third-party input methods still need manual checks. Marked-text protection, Chinese paste, selection transformations, saving and compilation have tests.
- A physical Mac running macOS 14 and a complete VoiceOver workflow have not been verified. Benchmarks cover roughly 100,000 UTF-16 units; sustained typing/typesetting in substantially larger documents remains unverified. Intel builds are not supplied.
- One active editor buffer preserves the main compilation entry when navigating included files. General project configuration and arbitrary main-file switching remain limited.
- Page commands handle contiguous initial `#set` rules, not arbitrary functions or `#show` scopes; later rules may override earlier settings.
- Source highlighting is a visual aid. Context checks at selection endpoints are conservative, not semantic refactoring.
- Some Tinymist diagnostics lack document versions and can briefly trail fast typing.
- The release pipeline is signed and notarized as recorded separately. App Store distribution and automatic updating are not implemented.
- Preferences and document-management behavior evolve after 0.3; consult current feature documentation instead of assuming historical limits still apply.

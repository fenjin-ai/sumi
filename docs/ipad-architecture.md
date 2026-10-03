# Mac and iPad architecture and parity

## Shared core, native presentation

The goal is the same document behavior and design language on both platforms.
Keep business rules in `LeftBlankCore`; keep AppKit/UIKit views, native editor
integration, lifecycle and engine startup in their platform targets. Native
layout adapts to window size and input methods. Templates and packages do not
need separate discovery, installation or caching implementations for iPad.

| Layer | Shared implementation | Platform responsibility |
| --- | --- | --- |
| Documents | `DocumentLibrary`, conflict-aware saves, recovery and history | File pickers, library navigation, background save |
| Editing | Commands, insertion plans, syntax presentation, `DocumentMetrics`, UTF-16 positions | `NSTextView` / `UITextView`, selection, IME, undo and focus |
| Templates and packages | `UniverseBrowserModel`, catalog/discovery, template installer, bounded thumbnail download/cache | Gallery layout and NSImage / UIImage decoding |
| Typesetting | `TinymistClient`, framed LSP, diagnostics, formatting, PDF export | `ProcessTinymistTransport` / `EmbeddedTinymist` |
| Preview | Tinymist frontend, `PreviewScripts`, source-location decoding | Native WebKit host, sizing and editor reveal |
| Design | Phosphor PDF icons, localized copy, syntax palette | Platform colors, toolbar and touch targets |

```mermaid
flowchart TB
    Mac[Mac AppKit and SwiftUI] --> Core[LeftBlankCore]
    iPad[iPad UIKit and SwiftUI] --> Core
    Core --> Client[TinymistClient and framed LSP]
    Client --> Process[Mac process transport]
    Client --> Embedded[iPad static library transport]
    Process --> Engine[Tinymist 0.15.8 / Typst 0.15.1]
    Embedded --> Engine
```

This follows Apple's support for [sharing code across platform targets](https://developer.apple.com/documentation/Xcode/configuring-a-multiplatform-app-target).
It is an architectural choice, not a claim that Apple requires this exact split.
The platform workspaces still contain presentation orchestration; future features
should extend shared services rather than copy business rules into both workspaces.

The Mac Swift package uses the repository's `Package.swift`. The iPad Xcode
project points to the fixed core-only manifest in `Sources/Package.swift`, which
compiles the same `Sources/LeftBlankCore` files and resources. Its only package
dependency is ZIPFoundation; the UI test target separately uses Nimble. iPad
does not resolve or compile the Mac app or Sparkle updater. The shared engine
process transport is also guarded with `os(macOS)`.

The manifests use the same package and target names to preserve the generated
resource bundle identity. iPad's graph stays fixed even when
`LEFTBLANK_DISTRIBUTION=preview` is present in the host environment. Checking the
host operating system in one manifest would not distinguish an iPad destination:
Xcode evaluates both manifests on a Mac. `scripts/test-package-graphs.py`
evaluates both real manifests in standard and preview modes without dependency
downloads, and verifies the iPad project and dependency lock against this boundary.

## Why Mac still runs an engine process

iPad embeds Tinymist as a Rust static library. Its background worker and pipes
carry the same LSP messages as Mac, without replacing application stdin/stdout or
changing the app's working directory. Mac packages and starts a Tinymist helper
executable. Both use the same engine generation and shared Swift client.

Embedding does not remove the Typst compiler or intentionally restrict its
typesetting features. It also does not establish equal speed, memory use or
recovery behavior. The iPad bridge currently uses two Tokio workers and a
size-optimized release build; there is no controlled comparison with Mac's
upstream executable. Platform fonts can also change pagination.

Keep Mac's process boundary for now: an engine crash can terminate the helper
without terminating the editor, and its memory has a separate lifetime. Apple's
[XPC guidance](https://developer.apple.com/library/archive/documentation/MacOSX/Conceptual/BPSystemStartup/Chapters/CreatingXPCServices.html)
describes process isolation as a stability technique; our current helper uses
`Process`, not XPC. An embedded engine shares the app's failure and memory domain.
The Rust bridge catches unwinding panics at its entry point, but that does not
isolate an abort or a fatal worker failure.

Before changing Mac's transport, compare both transports on the same Mac, engine
revision, fonts, documents and release settings. Measure cold and warm startup,
first preview, edit-to-preview p50/p95, PDF export, combined app/engine/WebKit peak
memory, repeated document switches and failure recovery. Then run representative
books on iPad and test background suspension. Use the same output checks in both
cases. Apple's [performance workflow](https://developer.apple.com/documentation/xcode/improving-your-app-s-performance/)
supports measurement before optimization. Small-document correctness tests are
not a substitute for these measurements.

## Independent builds and releases

| Platform | Build and validation | Distribution |
| --- | --- | --- |
| Mac | SwiftPM, `scripts/test.sh`, existing Mac CI and book benchmarks | Existing signed preview and Mac release workflows |
| iPad | Xcode target, `scripts/build-ipad.sh`, iPad jobs in `.github/workflows/ci.yml` | `ipad-v*` release tags start production signing, upload and storefront preparation |

One `build and test` workflow contains Mac and iPad validation. Mac regression
and main-only App Store distribution validation run independently. PRs avoid
the distribution rebuild; main checks it before preview packaging. The iPad build matrix runs engine
integration, simulator compilation and device compilation in parallel, using
independent engine caches. It produces the simulator test Products once and
passes them to a two-size UI matrix. Each size runs the full suite on its own
standard macOS runner; no runner boots two iPads. Each command has a timeout,
and failed boot/test operations save resource diagnostics. CI device
builds are unsigned; simulator tests do not establish physical-device performance.

The current main-branch ruleset requires `build and test` and 80% coverage, but
has no separate iPad check requirements. The existing `build and test` check now
aggregates Mac regression, Mac App Store validation, all iPad builds, both UI
sizes, iPad coverage and independent memory checks. A failed, cancelled or unexpectedly skipped prerequisite cannot produce
a successful aggregate. Only the main-only App Store job's expected skip is
accepted on PRs. This PR does not change repository rules. The main-only Mac preview
still depends on Mac validation; platform release targets remain independent.

Existing Mac release tags do not publish an iPad build. Apple supports adding an
[iOS platform to the same app record](https://developer.apple.com/help/app-store-connect/create-an-app-record/add-platforms)
with the same bundle identifier and independently selected platform versions and
builds. The iPad app uses the Mac App Store bundle identifier and iCloud container.
The separate iPad archive/export/upload pipeline and initial `1.0.0 (1)` release
metadata are described in [ipad-app-store.md](ipad-app-store.md). The pipeline
prepares the iOS record, subscription and production profile using existing
credentials. Apple requires the first subscription to be submitted with the app
through the website; the pipeline records this handoff rather than claiming
submission. Later releases can submit through the API after subscription approval.
Development signing does not validate production signing or Apple review.

## Current parity and release gaps

| Area | Current iPad behavior | Remaining work or evidence |
| --- | --- | --- |
| Local typesetting and PDF | Live preview and native PDF sharing; fallback/system fonts supplied | Matching fonts/assets required for equal pagination; large-book performance unmeasured |
| Preview to source | A preview tap reveals the main `.typ` file's UTF-16 source position; split view stays split | Included-file editing/navigation is missing and reports that limitation |
| Source to preview | Live updates and outline-to-editor navigation | Explicit caret-to-preview reveal is missing |
| Templates/packages | Shared bilingual search, distinct category icons, offline catalog, downloads and installation; window-sized adaptive gallery with catalog/detail panes; built-in documents and SICP within discovery | Physical community-template creation and broad package compatibility need verification |
| Editor assistance | Syntax styling, checks, outline, command insertion, formatting, native undo/find | Completion, signature-help and hover UI are missing |
| Projects | Built-in/community templates and folder import | Folder import expects `main.typ`; only the entry file can be edited |
| History and recovery | Shared snapshots, version restore and conflict-aware saves | Mac's full history diff UI is missing; background/relaunch recovery needs stress testing |
| Native workflows | Adaptive writing/preview/split, rotation, touch controls, common shortcuts and complete project ZIP export | Multiwindow, complete keyboard-menu parity and printing are missing |
| Input/accessibility | Native UIKit editor with composition safeguards | Chinese IME, hardware keyboard/trackpad, VoiceOver and Dynamic Type need manual verification |
| Cloud/lifecycle | Shared iCloud library services and background save hook | Cross-device conflicts, suspension/resume and memory-pressure behavior need device testing |

This PR establishes the native iPad app and shared boundaries. It is not complete
Mac feature parity or a distribution-ready release. Record physical test evidence
in [ipad.md](ipad.md); keep unmeasured performance and missing features explicit.

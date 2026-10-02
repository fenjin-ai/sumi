# iPad development

The native iPad target requires iPadOS 17 or later and Xcode 26.3 or later. Open
`iPad/LeftBlank.xcodeproj` and use the **LeftBlank-iPad** scheme. Set the signing
team before installing on a physical iPad; the app uses the same bundle identifier
and iCloud document container as the Mac App Store target.

## Shared behavior

The app shares document storage, conflict-aware saves, recovery snapshots,
revision history, built-in templates, command insertion, package discovery, SICP
import, Typst diagnostics, formatting, and PDF export with the Mac implementation.
Tinymist 0.15.8 / Typst 0.15.1 is pinned to the same engine generation as Mac.

On iPad, Tinymist runs as a Rust static library on a background worker, with the
same framed LSP and local WebKit preview. It does not launch an executable. Pipes
connect the Swift client to the engine without replacing application stdin/stdout
or changing its working directory. Each document connection owns its worker and
runtime. Closing the client delivers EOF and shuts down that worker. CoreText
font URLs are copied into an application cache and explicitly included in LSP
initialization, so package-cache options cannot replace the font search path.
Typst's default fonts are also embedded as a fallback. Identical pagination still requires the same fonts and assets on both
platforms; platform system font sets may differ.

The UIKit editor preserves native selection, IME composition, undo, find,
keyboard and trackpad behavior. Wide detail panes offer writing and preview side
by side; narrow multitasking windows and portrait layouts switch between them.
The library uses native navigation, menus, document pickers, sheets and sharing.
Keyboard shortcuts include save, command discovery, outline and PDF export.

## Build and validation

Run from an SSD-backed worktree under `/Volumes/SSD/Developer`:

```sh
scripts/test-ipad-engine.sh
scripts/build-ipad.sh simulator
scripts/build-ipad.sh device
scripts/lint.sh
```

These scripts install Rust 1.92.0 and keep dependency sources and targets on the
external development volume. Cargo.lock includes upstream's Typst and preview
patches; do not replace them with unpatched crates.io releases. The app builds
link the static engine for the selected SDK. Builds are unsigned by default.

The engine integration probe runs the C bridge in a native host executable. It
checks initialization, Unicode edits, outline updates, live preview HTTP, PDF
export from an unsaved buffer (including actual text drawing commands), and
orderly shutdown. It establishes engine and
transport behavior, but does not replace iPad runtime testing.

The UI test target checks editing, autosave, preview switching, rotation, command
insertion, preview-to-source navigation, template discovery, package import and
PDF sharing. Run it with an available iPad simulator:

```sh
xcodebuild -project iPad/LeftBlank.xcodeproj -scheme LeftBlank-iPad \
  -destination 'platform=iOS Simulator,id=<iPad simulator UUID>' \
  -derivedDataPath build/iPad -clonedSourcePackagesDirPath .build/xcode-packages \
  CODE_SIGNING_ALLOWED=NO test
```

CI has a separate `.github/workflows/ipad.yml` workflow, with parallel jobs for
engine integration, simulator build/UI tests and device build. Mac regression
tests remain in `scripts/test.sh`. Platform build/release boundaries, engine
tradeoffs and the feature-gap inventory are in [ipad-architecture.md](ipad-architecture.md).

Successful compilation is cached before UI testing, so a failed UI test does not
discard the Rust build. Cache uploads are bounded and optional. CI boots an iPad
on the newest available iOS runtime explicitly, with a three-minute boot limit.
UI execution is serial, with a twelve-minute step limit and 150/180-second
default/maximum per-test allowances. Test cases stop at their first failure and
terminate the app after each case.

## Current evidence and remaining work

On October 2, 2026, the Mac regression suite passed with 85.89% coverage after
merging the current main branch. The embedded-engine integration passed, and both
simulator and device builds succeeded. All four expanded UI tests passed on a
physical iPad Air 13-inch (M4), iPadOS 26.6.1, in 119 seconds. They verified
full-selection replacement, autosave, live preview, rotation, command insertion,
undo/redo, preview-to-source navigation, template discovery, package import and
the native PDF sharing sheet. Earlier runs also verified blank-page preview.
The rendered preview
was visually inspected, and the physical-device PDF was checked for actual text
drawing commands. UI tests use local storage with iCloud disabled.

The shared catalog/gallery refactor and source-navigation callback also passed
simulator and device compilation, including the expanded UI test target. GitHub
CI's iOS 18.5 simulator passed preview-to-source navigation and command/PDF tests.
It exposed selection instability after switching layouts and typographic quotes
in programmatic package insertion. The editor now avoids changing typing
attributes on selection-only updates and inserts code verbatim through text
storage, with undo/redo registration. The package test waits for visible inserted
source and checks preservation around the preamble insertion point. The expanded
physical suite passed with these fixes; the updated GitHub simulator run has not
yet been verified.

The initial blank preview was traced to missing fallback fonts and initialization
options replacing the CoreText font directory. Both are corrected. iPad now uses
the Mac Phosphor resources and syntax palette, with compact titles, rows and view
controls. Preview chrome and WebKit rendering setup are shared with Mac.

The local simulator could not be created on the external SSD: CoreSimulator
reported Cocoa error 513 and POSIX `Operation not permitted`. No internal-disk
simulator fallback was used; runtime evidence comes from the physical iPad.

Before shipping, manually verify Chinese IMEs, VoiceOver, Dynamic Type,
keyboard/trackpad editing, large books, background/relaunch recovery, preview
after suspension, and iCloud synchronization with a Mac. Compare PDF pagination
using matching fonts. Signed installation and UI tests do not establish all of
these behaviors.

The current project importer expects `main.typ` in the chosen folder. The iPad
editor exposes one active entry file; Mac's included-file navigation, agent/MCP
integration, multiwindow workflows and full completion UI are not yet ported.
This is the initial iPad implementation, not a claim of complete feature parity.

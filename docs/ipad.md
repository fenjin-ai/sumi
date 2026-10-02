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
font URLs are copied into an application cache for the engine's explicit font
search. Identical pagination still requires the same fonts and assets on both
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
export from an unsaved buffer, and orderly shutdown. It establishes engine and
transport behavior, but does not replace iPad runtime testing.

The UI test target checks editing, autosave, preview switching, rotation, command
insertion and PDF sharing. Run it with an available iPad simulator:

```sh
xcodebuild -project iPad/LeftBlank.xcodeproj -scheme LeftBlank-iPad \
  -destination 'platform=iOS Simulator,id=<iPad simulator UUID>' \
  -derivedDataPath build/iPad -clonedSourcePackagesDirPath .build/xcode-packages \
  CODE_SIGNING_ALLOWED=NO test
```

CI has a separate iPad job for engine integration, both SDK builds and UI tests.
Mac regression tests remain in `scripts/test.sh`.

## Current evidence and remaining work

During implementation on October 2, 2026, the Mac regression suite passed with
86.01% coverage, the embedded-engine integration passed, and the simulator app
device app and UI test target compiled successfully. The local simulator could not be
created on the external SSD: CoreSimulator reported Cocoa error 513 and POSIX
`Operation not permitted` both in the Codex temporary directory and directly
under `/Volumes/SSD/Developer`. UI tests have therefore been authored and built,
but have not been executed locally. No internal-disk simulator fallback was used.

Before shipping, run the UI suite and manually verify Chinese IMEs, VoiceOver,
Dynamic Type, keyboard/trackpad editing, large books, background/relaunch recovery,
preview after suspension, and signed iCloud synchronization with a Mac. Compare
PDF pagination on both platforms using matching fonts. Device compilation does
not establish on-device runtime behavior or signing/iCloud readiness.

The current project importer expects `main.typ` in the chosen folder. The iPad
editor exposes one active entry file; Mac's included-file navigation, agent/MCP
integration, multiwindow workflows and full completion UI are not yet ported.
This is the initial iPad implementation, not a claim of complete feature parity.

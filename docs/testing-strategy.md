# Testing Sumi as a writing application

Sumi's primary automated checks are feature integration tests, with an 80% production source-line coverage gate. Coverage is a useful floor; it cannot establish that a menu looks right or that a person can complete a workflow.

## Running today

Run `scripts/test.sh` from an SSD checkout. It exercises the real AppKit editor, SwiftUI hosting views, document storage, undo, Tinymist compilation, WebKit preview, the local MCP socket and an MCP client process. Tests use isolated document directories and injected cloud stores, never a personal iCloud account. CI also builds the final app bundle, verifies its development signature and cold-launches a relocated copy with the build-directory resource bundle hidden. The launch check uses a fresh library and verifies Chinese starter content plus a ready Tinymist service. Its isolated logs are retained as artifacts. All native UI scenarios share one serialized suite because AppKit menus, field editors and sheet presentation are process-wide. Codecov publishes project and changed-line coverage on each PR.

For build-system-specific resource failures, the native SwiftPM builder can be reproduced separately on toolchains that still support it:

```sh
source scripts/environment.sh
swift test --build-system native --scratch-path .build/native-validation \
  --filter bundledLanguagesResolveWithoutChangingSystemSettings
```

Keep the scratch path inside the SSD checkout. The hosted CI toolchain is deliberately older than the development machine, so local success is not a substitute for its result.

## Recommended next layer

Use Apple's [XCTest and XCUIAutomation](https://developer.apple.com/documentation/xcuiautomation) for a small set of complete macOS user journeys. Keep Swift Testing for the existing integration suite. UI tests need a dedicated Xcode UI-test target and a logged-in graphical runner; the current Swift package does **not** yet include this target.

Start with six journeys:

1. Launch an isolated library, create a document, type Unicode text, quit and reopen.
2. Search for a table, change parameters, insert, move through placeholders, undo and redo.
3. Search document content, rename, trash, restore and reopen without losing edits.
4. Switch interface language while preserving the editor buffer and selection.
5. Switch writing views, pin the outline and verify the manuscript's position stays fixed.
6. Render a valid document, introduce a syntax error, retain the last successful preview, recover and export a new PDF.

Use stable accessibility identifiers and wait for observable states, not fixed delays or screen coordinates. Preserve failed screenshots, the accessibility hierarchy, `.xcresult`, compiler diagnostics and isolated action logs as CI artifacts. A retry may diagnose a flaky test; it must not silently turn a failed workflow into a passing gate.

Add [SnapshotTesting](https://github.com/pointfreeco/swift-snapshot-testing) only to test targets for a few important visual states: the compact toolbar hint, library header, command list/form and narrow/wide outline. Pin the macOS version, display scale, fonts, locale, appearance and fixture timestamps. Review changed reference images explicitly; do not regenerate them automatically in CI. This is a proposed addition, not an existing screenshot gate.

## Release acceptance

Run the release workflow manually after a passing main commit to exercise Developer ID signing, profile embedding, notarization and Gatekeeper validation without publishing a version tag. Use the resulting artifact to test capabilities that an ad hoc local build does not have.

Real iCloud delivery remains a two-Mac acceptance check: offline edits, nonoverlapping and overlapping changes, account changes, pending downloads and assets. A deterministic injected-store test does not prove Apple's cross-device delivery or latency. Full input-method composition and VoiceOver also need real user-interface checks.

## Issues found during 0.4 acceptance

- Swift 6.2.4 crashed while converting an actor-isolated setting method to a SwiftUI binding closure; explicit closures compile successfully in the hosted toolchain.
- The native SwiftPM builder emitted `zh-hans.lproj` while the newer builder preserved `zh-Hans.lproj`. Bundle lookup is case-sensitive; localization now selects the actual bundled identifier. The failure and fix were reproduced locally with the native builder.
- Native menu labels ignored the SwiftUI image frame and used the PDF icon's 256-point artboard. The shared template images now have a compact intrinsic size, with a resource regression check.
- A packaged native SwiftPM app could still depend on the build checkout for localized resources. App-bundle resource lookup and the relocated launch gate remove that dependency.
- Managed-document titles support single-click inline rename and double-click navigation; the library exposes direct trash/restore actions. Preview colors keep a fixed 68 × 28 hit target in both states.
- Managed-document export dialogs now suggest the document title instead of the internal `main` filename.

The first two were caught by CI and the icon defect by a real-window visual check. This is why Sumi needs complementary behavior and visual checks, in addition to its line-coverage target.

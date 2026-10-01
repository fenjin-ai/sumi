import AppKit
import Foundation
import SwiftUI
import Testing
import WebKit
@testable import SumiApp
import SumiCore

extension WritingFlowTests {
    @Test func realSemanticAndCodeHighlightingPreservesTypingUndoAndDocumentSwitches() async throws {
        let source = "= 中文😀\n\n```python\ntotal = sum(range(1, 11))\nprint(total)\n```\n\n$alpha + beta = gamma$\n"
        let app = try WritingFixture(text: source)
        defer { app.close() }
        try await app.ready()
        try await app.wait { app.workspace.syntaxSnapshot?.source == source }
        let editor = try #require(app.workspace.editor)
        let sum = (source as NSString).range(of: "sum")
        let number = (source as NSString).range(of: "11")
        let code = (source as NSString).range(of: "total")
        #expect(editorColor(editor, at: sum.location) == NSColor(hex: 0x9DBBCD))
        #expect(editorColor(editor, at: number.location) == NSColor(hex: 0xD9B97C))
        #expect(editorColor(editor, at: code.location) != NSColor(hex: 0x9DBBCD))
        #expect(editor.string == source)
        #expect(editor.selectedRange().location == source.utf16.count)
        editor.insertSnippet(Snippet(text: "42"), replacing: number)
        let edited = editor.string
        try await app.wait { app.workspace.syntaxSnapshot?.source == edited }
        editor.undoManager?.undo()
        try await app.wait { app.workspace.syntaxSnapshot?.source == source }
        #expect(editor.string == source)
        #expect(app.workspace.text == source)
        // Rapid edits and switching documents must never apply old UTF-16 ranges.
        for _ in 0..<8 { editor.insertSnippet(Snippet(text: "😀"), replacing: NSRange(location: 0, length: 0)) }
        let next = app.root.appendingPathComponent("next.typ")
        try Data("= Next\n\n#let value = 7\n".utf8).write(to: next)
        #expect(app.workspace.open(next))
        try await app.wait { app.workspace.syntaxSnapshot?.source == "= Next\n\n#let value = 7\n" }
        #expect(editor.string == app.workspace.text)
    }

    @Test func readingStylesRevealSourceWithoutChangingUndoOrText() async throws {
        let source = "= 中文😀标题\n\n*bold* and _italic_ and `code`.\n\nEnd\n"
        let app = try WritingFixture(text: source, startService: false)
        defer { app.close() }
        let editor = try #require(app.workspace.editor)
        editor.highlight()
        let storage = try #require(editor.textStorage)
        let hiddenFont = try #require(storage.attribute(.font, at: 0, effectiveRange: nil) as? NSFont)
        #expect(hiddenFont.pointSize < 1)
        #expect(editor.string == source)
        editor.setSelectedRange(NSRange(location: 3, length: 0))
        editor.highlight()
        #expect((storage.attribute(.font, at: 0, effectiveRange: nil) as? NSFont)?.pointSize ?? 0 > 1)
        let bold = (source as NSString).range(of: "bold")
        editor.insertSnippet(Snippet(text: "changed"), replacing: bold)
        #expect(app.workspace.text.contains("*changed*"))
        app.workspace.styledSource = false
        editor.undoManager?.undo()
        #expect(editor.string == source)
        #expect(app.workspace.text == source)
        editor.undoManager?.redo()
        #expect(app.workspace.text == editor.string)
        #expect(app.workspace.text.contains("changed"))
        app.workspace.styledSource = true
        editor.setSelectedRange(NSRange(location: editor.string.utf16.count, length: 0))
        editor.highlight()
        #expect(app.workspace.text == editor.string)
        editor.setMarkedText("中文输入", selectedRange: NSRange(location: 4, length: 0), replacementRange: editor.selectedRange())
        #expect(editor.hasMarkedText())
        editor.highlight()
        #expect(editor.hasMarkedText(), "Styling must not interrupt IME composition")
        editor.unmarkText()
    }

    @Test func nestedDiscoveryMathInsertionAndEditingCommands() async throws {
        let app = try WritingFixture(text: "= Formula\n\n$ x + y $\n\n")
        defer { app.close() }
        try await app.ready()
        let editor = try #require(app.workspace.editor)
        editor.setSelectedRange((editor.string as NSString).range(of: "x"))
        app.workspace.togglePalette()
        app.window.sendEvent(app.key("m", code: 46))
        #expect(app.workspace.paletteGroups.count == 3)
        await app.layout()
        app.window.sendEvent(app.key("b", code: 11))
        #expect(app.workspace.paletteGroup == "math-basic")
        await app.layout()
        let fraction = try #require(WritingCommand.all.first { $0.id == "fraction" })
        #expect(app.workspace.keyPath(for: fraction) == "m b f")
        app.workspace.selectCommand(fraction)
        try await app.wait { !app.workspace.applyingCommand }
        #expect(editor.string.filter { $0 == "$" }.count == 2)
        #expect(editor.string.contains("frac("))
        editor.undoManager?.undo()
        #expect(app.workspace.text == "= Formula\n\n$ x + y $\n\n")
        editor.setSelectedRange(NSRange(location: 0, length: 9))
        for id in ["indent", "outdent", "comment", "comment", "previewDark", "styledSource"] {
            app.workspace.execute(try #require(WritingCommand.all.first { $0.id == id }))
        }
        #expect(app.workspace.previewDark)
        #expect(!app.workspace.styledSource)
        #expect(editor.string.hasPrefix("= Formula"))
        editor.insertSnippet(Snippet(text: "#let    a= (1,2,3)\n"), replacing: NSRange(location: editor.string.utf16.count, length: 0))
        let before = editor.string
        app.workspace.formatDocument()
        try await app.wait { editor.string != before || app.workspace.message != nil }
        #expect(!editor.string.contains("#let    a="))
        editor.undoManager?.undo()
        #expect(editor.string == before)
        #expect(app.workspace.text == before)
    }

    @Test func universeImportIsPinnedDeduplicatedAndUndoable() async throws {
        let app = try WritingFixture(text: "= Package import\n", startService: false)
        defer { app.close() }
        let package = try JSONDecoder().decode(UniversePackage.self, from: Data(#"{"name":"cetz","version":"0.5.2","compiler":"0.14.0"}"#.utf8))
        let editor = try #require(app.workspace.editor)
        app.workspace.layout = .preview
        try app.workspace.importPackage(package)
        #expect(app.workspace.layout == .split)
        #expect(editor.string.hasPrefix("#import \"@preview/cetz:0.5.2\"\n\n"))
        #expect(throws: CommandError.self) { try app.workspace.importPackage(package) }
        editor.undoManager?.undo()
        #expect(app.workspace.text == "= Package import\n")
        let newer = try JSONDecoder().decode(UniversePackage.self, from: Data(#"{"name":"example","version":"1.0.0","compiler":"99.0.0"}"#.utf8))
        #expect(throws: CommandError.self) { try app.workspace.importPackage(newer) }
    }

    @Test(.enabled(if: ProcessInfo.processInfo.environment["SUMI_BOOK_PREVIEW"] == "1"))
    func completeBookPreviewRemainsUsableInLargeWindow() async throws {
        let app = try WritingFixture(text: "", startService: false)
        defer { app.close() }
        let repository = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        #expect(app.workspace.open(repository.appendingPathComponent("Examples/Books/SICP/main.typ")))
        app.window.setContentSize(NSSize(width: 1920, height: 1300))
        try await app.ready()
        app.workspace.layout = .preview
        await app.layout()
        let web = try #require(findWebView(app.window.contentView))
        web.configuration.preferences.inactiveSchedulingPolicy = .none
        web.configuration.userContentController.addUserScript(WKUserScript(source: "window.requestAnimationFrame = callback => setTimeout(() => callback(performance.now()), 16); window.cancelAnimationFrame = clearTimeout;", injectionTime: .atDocumentStart, forMainFrameOnly: true))
        web.reload()
        try await waitForJavaScript(web, condition: "document.querySelectorAll('#typst-app .typst-doc > g.typst-page').length === 448")
        #expect(try await web.evaluateJavaScript("document.querySelectorAll('canvas').length") as? Int == 0)
        for page in [0, 223, 447, 0] {
            _ = try await web.evaluateJavaScript("document.querySelector('.typst-doc > g.typst-page[data-page-number=\"\(page)\"]').scrollIntoView({block:'start'})")
            try await waitForJavaScript(web, condition: "(() => { const page = document.querySelector('.typst-doc > g.typst-page[data-page-number=\"\(page)\"]'); return page && page.querySelectorAll('use').length > 20 && page.getBoundingClientRect().top < innerHeight && page.getBoundingClientRect().bottom > 0; })()")
            let snapshot = try await web.takeSnapshot(configuration: nil)
            #expect(snapshot.size.width >= 1800)
            let snapshotData = try #require(snapshot.tiffRepresentation)
            let bitmap = try #require(NSBitmapImageRep(data: snapshotData))
            var darkPixels = 0, lightPixels = 0
            for y in stride(from: 0, to: bitmap.pixelsHigh, by: 16) {
                for x in stride(from: 0, to: bitmap.pixelsWide, by: 16) {
                    guard let color = bitmap.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB) else { continue }
                    let luminance = (color.redComponent + color.greenComponent + color.blueComponent) / 3
                    if luminance < 0.3 { darkPixels += 1 }
                    if luminance > 0.9 { lightPixels += 1 }
                }
            }
            #expect(darkPixels > 10 && lightPixels > 100, "The WebKit snapshot must contain painted page content, not a blank surface")
            let artifacts = repository.appendingPathComponent("build/benchmarks")
            try FileManager.default.createDirectory(at: artifacts, withIntermediateDirectories: true)
            try bitmap.representation(using: .png, properties: [:])?.write(to: artifacts.appendingPathComponent("book-preview-\(page + 1).png"))
            #expect(try await web.evaluateJavaScript("document.querySelectorAll('canvas').length") as? Int == 0)
        }
        #expect(try await web.evaluateJavaScript("document.querySelectorAll('#typst-app .typst-doc > g.typst-page').length") as? Int == 448)
    }

    @Test func previewProcessTerminationRecoversOnceThenReportsFailure() async throws {
        var errors: [String] = []
        let coordinator = PreviewView.Coordinator { errors.append($0) }
        let web = WKWebView()
        coordinator.webViewWebContentProcessDidTerminate(web)
        #expect(errors.isEmpty)
        coordinator.webViewWebContentProcessDidTerminate(web)
        #expect(errors.count == 1)
    }

    @Test func realPreviewRetainsPagesOnErrorThenRecoversAndTogglesDark() async throws {
        let app = try WritingFixture(text: "= Preview sentinel\n\nA short paragraph.\n")
        defer { app.close() }
        try await app.ready()
        app.workspace.layout = .split
        await app.layout()
        let web = try #require(findWebView(app.window.contentView))
        // A hidden test window has no display ticks. Drive animation frames with
        // a timer so the real Tinymist WASM renderer can update its actual DOM.
        web.configuration.preferences.inactiveSchedulingPolicy = .none
        web.configuration.userContentController.addUserScript(WKUserScript(source: "window.requestAnimationFrame = callback => setTimeout(() => callback(performance.now()), 16); window.cancelAnimationFrame = clearTimeout;", injectionTime: .atDocumentStart, forMainFrameOnly: true))
        web.reload()
        try await waitForJavaScript(web, condition: "document.querySelectorAll('#typst-app .typst-doc > g').length > 0")
        try await app.wait { app.workspace.hasSuccessfulPreview }
        let initialURL = app.workspace.previewURL
        let before = try await web.evaluateJavaScript("document.querySelectorAll('#typst-app .typst-doc > g').length") as? Int
        #expect((before ?? 0) > 0)
        app.workspace.previewDark = true
        await app.layout()
        try await waitForJavaScript(web, condition: "document.getElementById('typst-app').classList.contains('invert-colors') && document.getElementById('typst-app').classList.contains('normal-image')")
        app.workspace.previewZoom = 1.4
        await app.layout()
        try await waitForJavaScript(web, condition: "document.getElementById('typst-container').style.width === '140%'")
        let editor = try #require(app.workspace.editor)
        editor.insertSnippet(Snippet(text: "#unknown-function("), replacing: NSRange(location: editor.string.utf16.count, length: 0))
        try await app.wait { app.workspace.diagnostics.contains { $0.severity == 1 } }
        #expect(app.workspace.previewStale)
        #expect(app.workspace.hasSuccessfulPreview)
        #expect(app.workspace.previewURL == initialURL)
        #expect(try await web.evaluateJavaScript("document.querySelectorAll('#typst-app .typst-doc > g').length") as? Int == before)
        editor.undoManager?.undo()
        try await app.wait { !app.workspace.previewStale && app.workspace.diagnostics.isEmpty }
        #expect(app.workspace.previewURL == initialURL)
        editor.insertSnippet(Snippet(text: "\n#pagebreak()\n= Recovered page\n"), replacing: NSRange(location: editor.string.utf16.count, length: 0))
        try await app.wait { !app.workspace.previewStale }
        try await waitForJavaScript(web, condition: "document.querySelectorAll('#typst-app .typst-doc > g').length === 2")
        app.workspace.previewDark = false
        await app.layout()
        try await waitForJavaScript(web, condition: "!document.getElementById('typst-app').classList.contains('invert-colors')")
    }
}

@MainActor
private func findWebView(_ view: NSView?) -> WKWebView? {
    guard let view else { return nil }
    if let web = view as? WKWebView { return web }
    return view.subviews.compactMap { findWebView($0) }.first
}

@MainActor
private func waitForJavaScript(_ web: WKWebView, condition: String) async throws {
    let deadline = ContinuousClock.now + .seconds(15)
    while ContinuousClock.now < deadline {
        if (try? await web.evaluateJavaScript(condition)) as? Bool == true { return }
        try await Task.sleep(for: .milliseconds(50))
    }
    Issue.record("Preview did not reach expected state: \(condition)")
    throw CommandError.invalid("Preview state timed out")
}

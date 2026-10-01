import AppKit
import Darwin
import PDFKit
import Testing
import SumiCore
@testable import SumiApp

extension WritingFlowTests {
    /// Opt-in: fetch the real fixture with scripts/prepare-large-document.py.
    /// This drives the production text view, native layout and real Tinymist.
    @Test(.enabled(if: ProcessInfo.processInfo.environment["SUMI_LARGE_FIXTURE"] != nil))
    func realMultiMegabyteDocumentNavigationScrollingAndTyping() async throws {
        let path = try #require(ProcessInfo.processInfo.environment["SUMI_LARGE_FIXTURE"])
        let data = try Data(contentsOf: URL(fileURLWithPath: path))
        let source = try #require(String(data: data, encoding: .utf8))
        #expect(data.count > 1_000_000)
        let initialMemory = physicalFootprint()
        let opened = ContinuousClock.now
        let app = try WritingFixture(text: source, startService: false)
        defer { app.close() }
        let openTime = seconds(opened.duration(to: .now))
        for name in ["fig", "styles"] {
            let dependency = URL(fileURLWithPath: path).deletingLastPathComponent().appendingPathComponent(name)
            if FileManager.default.fileExists(atPath: dependency.path) {
                try FileManager.default.copyItem(at: dependency, to: app.root.appendingPathComponent(name))
            }
        }
        print("SUMI LARGE open: \(openTime)s, \(data.count) bytes")
        let editor = try #require(app.workspace.editor)
        let scroll = try #require(editor.enclosingScrollView)
        let manager = try #require(editor.layoutManager)
        let container = try #require(editor.textContainer)
        let bitmap = try #require(editor.bitmapImageRepForCachingDisplay(in: editor.visibleRect))
        var report: [String: Any] = ["bytes": data.count, "utf16": source.utf16.count, "open_seconds": openTime,
                                     "memory_before_mib": initialMemory, "memory_open_mib": physicalFootprint()]
        let serviceStarted = ContinuousClock.now
        app.workspace.startService()
        let deadline = ContinuousClock.now + .seconds(120)
        while app.workspace.syntaxSnapshot?.source != source, .now < deadline {
            try await Task.sleep(for: .milliseconds(100))
        }
        #expect(app.workspace.syntaxSnapshot?.source == source, "Real semantic highlighting must finish")
        report["semantic_ready_seconds"] = seconds(serviceStarted.duration(to: .now))
        report["syntax_tokens"] = app.workspace.syntaxSnapshot?.tokens.count ?? 0
        report["memory_highlighted_mib"] = physicalFootprint()
        let codeWord = ProcessInfo.processInfo.environment["SUMI_CODE_WORD"] ?? "sum(range"
        let sum = (source as NSString).range(of: codeWord)
        #expect(sum.location != NSNotFound)
        if sum.location != NSNotFound { #expect(editorColor(editor, at: sum.location) == Theme.sourceFunction) }
        // Publishing semantic tokens precedes SwiftUI's next native layout.
        // Finish and report that initial presentation before timing navigation,
        // just as we settle the window between every subsequent jump below.
        let presentationStart = ContinuousClock.now
        await app.layout()
        editor.prepareForPointerInteraction()
        editor.cacheDisplay(in: editor.visibleRect, to: bitmap)
        report["initial_presentation_ms"] = seconds(presentationStart.duration(to: .now)) * 1000
        report["editor_ready_seconds"] = seconds(opened.duration(to: .now))
        var navigation: [Double] = [], hitTesting: [Double] = [], search: [Double] = []
        var jumpTimes: [Double] = [], highlightTimes: [Double] = [], layoutTimes: [Double] = []
        var navigationSamples: [[String: Double]] = []
        let ns = source as NSString
        let offsets = [0.1, 0.9, 0.5, 0.99, 0.01, 0.75].map { fraction in
            let start = Int(Double(ns.length) * fraction)
            let range = ns.paragraphRange(for: NSRange(location: start, length: 0))
            return min(ns.length - 1, range.location + min(4, max(0, range.length - 2)))
        }
        for offset in offsets {
            let start = ContinuousClock.now
            app.workspace.jump(to: offset)
            jumpTimes.append(seconds(start.duration(to: .now)))
            let highlightStart = ContinuousClock.now
            editor.highlight()
            highlightTimes.append(seconds(highlightStart.duration(to: .now)))
            let layoutStart = ContinuousClock.now
            editor.prepareForPointerInteraction()
            editor.cacheDisplay(in: editor.visibleRect, to: bitmap)
            layoutTimes.append(seconds(layoutStart.duration(to: .now)))
            navigation.append(seconds(start.duration(to: .now)))
            navigationSamples.append(["offset": Double(offset), "total_ms": navigation.last! * 1000,
                                      "jump_ms": jumpTimes.last! * 1000, "highlight_ms": highlightTimes.last! * 1000,
                                      "draw_ms": layoutTimes.last! * 1000])
            #expect(editor.selectedRange().location == offset)
            await app.layout()
            let hitStart = ContinuousClock.now
            // Independently map a rendered glyph back to an insertion point.
            let glyphs = manager.glyphRange(forCharacterRange: NSRange(location: offset, length: 1), actualCharacterRange: nil)
            let glyph = manager.boundingRect(forGlyphRange: glyphs, in: container)
            let point = NSPoint(x: glyph.minX + editor.textContainerOrigin.x + 1, y: glyph.midY + editor.textContainerOrigin.y)
            let hit = editor.characterIndexForInsertion(at: point)
            #expect(abs(hit - offset) <= 1, "Hit \(hit), wanted \(offset), point \(point)")
            hitTesting.append(seconds(hitStart.duration(to: .now)))
            let searchStart = ContinuousClock.now
            let found = ns.range(of: ProcessInfo.processInfo.environment["SUMI_SEARCH_WORD"] ?? "Prince Andrew", options: [], range: NSRange(location: offset, length: ns.length - offset))
            _ = found.location
            search.append(seconds(searchStart.duration(to: .now)))
        }
        report["navigation_ms"] = milliseconds(navigation)
        report["navigation_samples"] = navigationSamples
        report["jump_ms"] = milliseconds(jumpTimes)
        report["highlight_ms"] = milliseconds(highlightTimes)
        report["layout_ms"] = milliseconds(layoutTimes)
        report["hit_testing_ms"] = milliseconds(hitTesting)
        report["search_ms"] = milliseconds(search)
        var scrolling: [Double] = [], drawing: [Double] = []
        for index in 0..<60 {
            let start = ContinuousClock.now
            let y = max(0, scroll.contentView.bounds.origin.y + (index < 30 ? 80 : -80))
            scroll.contentView.scroll(to: NSPoint(x: 0, y: y))
            scroll.reflectScrolledClipView(scroll.contentView)
            editor.prepareForPointerInteraction()
            let glyphs = manager.glyphRange(forBoundingRect: editor.visibleRect.offsetBy(dx: -editor.textContainerOrigin.x, dy: -editor.textContainerOrigin.y), in: container)
            #expect(glyphs.length > 0)
            scrolling.append(seconds(start.duration(to: .now)))
            editor.cacheDisplay(in: editor.visibleRect, to: bitmap)
            drawing.append(seconds(start.duration(to: .now)))
        }
        report["scroll_layout_ms"] = milliseconds(scrolling)
        report["scroll_draw_ms"] = milliseconds(drawing)
        app.workspace.jump(to: offsets[2])
        editor.highlight()
        var typing: [Double] = [], insertTimes: [Double] = [], metricTimes: [Double] = []
        editor.breakUndoCoalescing()
        editor.undoManager?.beginUndoGrouping()
        for character in "Smooth 中文😀 input" {
            let start = ContinuousClock.now
            editor.insertText(String(character), replacementRange: editor.selectedRange())
            insertTimes.append(seconds(start.duration(to: .now)))
            let metricsStart = ContinuousClock.now
            _ = app.workspace.position
            _ = app.workspace.wordCount
            metricTimes.append(seconds(metricsStart.duration(to: .now)))
            typing.append(seconds(start.duration(to: .now)))
            try await Task.sleep(for: .milliseconds(25))
        }
        editor.undoManager?.endUndoGrouping()
        report["typing_ms"] = milliseconds(typing)
        #expect(typing.sorted()[typing.count - 1] < 0.1, "Native input plus document metrics must stay below 100 ms")
        #expect(navigation.max()! < 0.2, "Distant navigation including drawing must stay below 200 ms")
        report["insert_ms"] = milliseconds(insertTimes)
        report["metrics_ms"] = milliseconds(metricTimes)
        editor.undoManager?.undo()
        #expect(editor.string == source)
        #expect(app.workspace.text == source)
        report["memory_after_mib"] = physicalFootprint()
        report["preview_status"] = app.workspace.serviceStatus
        if ProcessInfo.processInfo.environment["SUMI_BENCH_EXPORT"] == "1" {
            let started = ContinuousClock.now
            let pdfURL = app.root.appendingPathComponent("complete-book.pdf")
            try await app.workspace.exportPDF(to: pdfURL)
            report["export_seconds"] = seconds(started.duration(to: .now))
            let pdf = try #require(PDFDocument(url: pdfURL))
            report["export_pages"] = pdf.pageCount
            #expect(pdf.pageCount > 400)
        }
        let json = try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys])
        if let output = ProcessInfo.processInfo.environment["SUMI_PERFORMANCE_REPORT"] {
            try json.write(to: URL(fileURLWithPath: output), options: .atomic)
        }
        print("SUMI LARGE REPORT\n" + String(decoding: json, as: UTF8.self))
    }
}

private func seconds(_ duration: Duration) -> Double {
    Double(duration.components.seconds) + Double(duration.components.attoseconds) / 1e18
}

private func milliseconds(_ values: [Double]) -> [String: Double] {
    let sorted = values.sorted()
    return ["median": sorted[sorted.count / 2] * 1000, "p95": sorted[min(sorted.count - 1, Int(Double(sorted.count) * 0.95))] * 1000, "max": sorted.last! * 1000]
}

private func physicalFootprint() -> Double {
    var info = task_vm_info_data_t()
    var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<integer_t>.size)
    let result = withUnsafeMutablePointer(to: &info) { pointer in
        pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
            task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
        }
    }
    return result == KERN_SUCCESS ? Double(info.phys_footprint) / 1_048_576 : -1
}

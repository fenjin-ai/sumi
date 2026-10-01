import SumiTestSupport
import AppKit
import Foundation
import PDFKit
import SumiAutomation
import SumiCore
import Testing
@testable import SumiApp

extension WritingFlowTests {
    @Test func agentReadsLiveBufferAppliesCASAndNativeUndoRestoresSource() async throws {
        let app = try WritingFixture(text: "= Notes\n\nHello 😀", startService: false)
        defer { app.close() }
        let fixture = try AgentFixture(app.workspace)
        defer { fixture.close() }
        let editor = try #require(app.workspace.editor)
        editor.insertSnippet(Snippet(text: " unsaved"), replacing: NSRange(location: editor.string.utf16.count, length: 0))
        let before = try await fixture.client.send(.init("get_document"))
        #expect(before["text"].string == app.workspace.text)
        #expect(before["text"].string?.contains("unsaved") == true)
        let range = (app.workspace.text as NSString).range(of: "Hello")
        let arguments: JSONValue = .object([
            "document_id": before["document_id"], "expected_revision": before["revision"],
            "edits": .array([.object(["start": .number(Double(range.location)), "end": .number(Double(NSMaxRange(range))), "text": .string("Welcome")])])
        ])
        let changed = try await fixture.client.send(.init("apply_edits", arguments: arguments))
        #expect(changed["text"].string == "= Notes\n\nWelcome 😀 unsaved")
        #expect(changed["revision"].string != before["revision"].string)
        #expect(editor.string == app.workspace.text)
        do { _ = try await fixture.client.send(.init("apply_edits", arguments: arguments)); Issue.record("Stale edit accepted") }
        catch let failure as AutomationFailure { #expect(failure.code == "revision_conflict") }
        editor.undoManager?.undo()
        #expect(app.workspace.text == before["text"].string)
        let restored = try await fixture.client.send(.init("get_document"))
        #expect(restored["revision"].string != before["revision"].string, "Undo does not resurrect a stale edit revision")
        app.workspace.documentTransitionInProgress = true
        await #expect(throws: AutomationFailure.self) { try await fixture.client.send(.init("apply_edits", arguments: arguments)) }
        app.workspace.documentTransitionInProgress = false
        fixture.controller.stop()
        await #expect(throws: AutomationFailure.self) { try await fixture.controller.handle(.init("get_document")) }
    }

    @Test func agentUsesLibraryIDsAndCannotReadArbitraryPaths() async throws {
        let app = try WritingFixture(text: "= First\n", startService: false)
        defer { app.close() }
        let fixture = try AgentFixture(app.workspace)
        defer { fixture.close() }
        let second = app.root.appendingPathComponent("second.typ")
        try Data("= Second\n".utf8).write(to: second)
        fixture.controller.library = .init(
            currentID: { app.workspace.documentURL == second ? "second" : "first" },
            list: { query in [AutomationDocument(id: "second", title: "Second")].filter { query.isEmpty || $0.title.contains(query) } },
            open: { id in
                guard id == "second", app.workspace.open(second) else { throw AutomationFailure("document_not_found", "Unknown document ID.") }
            },
            create: { title, text in
                let destination = app.root.appendingPathComponent("created.typ")
                try Data(text.utf8).write(to: destination)
                guard app.workspace.open(destination) else { throw AutomationFailure("create_failed", title) }
            })
        let results = try await fixture.client.send(.init("list_documents", arguments: .object(["query": .string("Second")])))
        #expect(results["documents"].array.first?["id"].string == "second")
        await #expect(throws: AutomationFailure.self) {
            try await fixture.client.send(.init("open_document", arguments: .object(["document_id": .string("/etc/passwd")])))
        }
        let opened = try await fixture.client.send(.init("open_document", arguments: .object(["document_id": .string("second")])))
        #expect(opened["text"].string == "= Second\n")
        let created = try await fixture.client.send(.init("create_document", arguments: .object(["title": .string("Fresh"), "text": .string("= Fresh\n")])))
        #expect(created["text"].string == "= Fresh\n")
    }

    @Test func agentSettingsAreAllowlistedAndValidatedAtomically() async throws {
        _ = NSApplication.shared
        let originalAppearance = NSApp.appearance
        defer { NSApp.appearance = originalAppearance }
        let app = try WritingFixture(text: "= Preferences\n", startService: false)
        defer { app.close() }
        let fixture = try AgentFixture(app.workspace)
        defer { fixture.close() }
        let result = try await fixture.client.send(.init("set_settings", arguments: .object([
            "layout": .string("split"), "font_size": .number(20), "preview_dark": .bool(true), "styled_source": .bool(false), "appearance": .string("light")
        ])))
        #expect(result["font_size"].int == 20)
        #expect(result["appearance"].string == "light")
        #expect(app.workspace.appearance == .light)
        #expect(NSApp.appearance?.name == .aqua)
        #expect(app.workspace.layout == .split && app.workspace.previewDark && !app.workspace.styledSource)
        for arguments: JSONValue in [
            .object(["layout": .string("writing"), "font_size": .number(200)]),
            .object(["layout": .string("invalid")]), .object(["styled_source": .string("true")]),
            .object(["layout": .string("writing"), "appearance": .string("invalid")]),
            .object(["appearance": .bool(false)]),
            .object(["agent_access": .bool(false)]), .object(["iCloud": .bool(true)])
        ] {
            await #expect(throws: AutomationFailure.self) { try await fixture.client.send(.init("set_settings", arguments: arguments)) }
            #expect(app.workspace.layout == .split && app.workspace.fontSize == 20)
        }
        #expect(try await fixture.client.send(.init("get_settings"))["layout"].string == "split")
        await #expect(throws: AutomationFailure.self) { try await fixture.client.send(.init("shell")) }
    }

    @Test func agentCompilesUnsavedSourceAndSeesErrorsWithoutExportingStalePDF() async throws {
        let app = try WritingFixture(text: "= Agent review\n\nOriginal text\n")
        defer { app.close() }
        try await app.ready()
        let fixture = try AgentFixture(app.workspace)
        defer { fixture.close() }
        let editor = try #require(app.workspace.editor)
        editor.insertSnippet(Snippet(text: "Unsaved live addition"), replacing: NSRange(location: editor.string.utf16.count, length: 0))
        let snapshot = try await fixture.client.send(.init("get_document"))
        let args: JSONValue = .object(["document_id": snapshot["document_id"], "expected_revision": snapshot["revision"]])
        let export = try await fixture.client.send(.init("export_pdf", arguments: args))
        let path = try #require(export["path"].string)
        let document = try #require(PDFDocument(url: URL(fileURLWithPath: path)))
        #expect(document.string?.contains("Unsaved live addition") == true)
        #expect(export["page_count"].int == 1)
        #expect(Data(base64Encoded: try #require(export["image_png"].string))?.starts(with: [137, 80, 78, 71]) == true)
        editor.insertSnippet(Snippet(text: "\n#not-a-valid-function()"), replacing: NSRange(location: editor.string.utf16.count, length: 0))
        try await app.wait { app.workspace.diagnostics.contains { $0.severity == 1 } }
        let current = try await fixture.client.send(.init("get_document"))
        let preview = try await fixture.client.send(.init("get_preview", arguments: .object(["document_id": current["document_id"]])))
        #expect(!preview["diagnostics"].array.isEmpty)
        await #expect(throws: AutomationFailure.self) {
            try await fixture.client.send(.init("export_pdf", arguments: .object(["document_id": current["document_id"], "expected_revision": current["revision"]])))
        }
        #expect(try FileManager.default.contentsOfDirectory(atPath: app.workspace.stateDirectory.appendingPathComponent("AgentExports").path).count == 1)
    }
}

@MainActor
private struct AgentFixture {
    let root: URL
    let controller: WorkspaceAutomation
    let client: AutomationBridgeClient
    init(_ workspace: Workspace) throws {
        root = TestPaths.temporaryDirectory.appendingPathComponent("a" + UUID().uuidString.prefix(8))
        let endpoint = AutomationContract.socketURL(in: root)
        controller = WorkspaceAutomation(workspace: workspace, socketURL: endpoint)
        client = AutomationBridgeClient(socketURL: endpoint)
        try controller.start()
    }
    func close() { controller.stop(); try? FileManager.default.removeItem(at: root) }
}

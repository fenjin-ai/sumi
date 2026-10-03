import AppKit
@testable import LeftBlankApp
import LeftBlankAutomation
import LeftBlankCore
import LeftBlankTestSupport
import Testing

extension WritingFlowTests {
    @Test func agentLibraryPagesRenameTrashAndRestoreWithoutReturningSource() async throws {
        let app = try WritingFixture(text: "External draft", startService: false)
        defer { app.close() }
        let first = try await app.workspace.library.store.create(title: "First", text: "First manuscript")
        let second = try await app.workspace.library.store.create(title: "Second", text: "Second manuscript")
        await app.workspace.library.refresh()
        try await app.workspace.library.open(first.id)
        let agent = try CapabilityAgentFixture(app.workspace)
        defer { agent.close() }
        let page = try await agent.send("list_documents", ["limit": .number(1)])
        #expect(page["documents"].array.count == 1)
        #expect(page["next_cursor"].string != nil)
        #expect(page["active_document_id"].string == first.id.uuidString)
        #expect(page["documents"].array.first?["text"].isNull == true)
        let next = try await agent.send("list_documents", ["limit": .number(1), "cursor": page["next_cursor"]])
        #expect(next["documents"].array.count == 1)
        #expect(next["documents"].array.first?["id"].string != page["documents"].array.first?["id"].string)
        #expect(next["next_cursor"].isNull)
        let renamed = try await agent.send("rename_document", [
            "document_id": .string(first.id.uuidString), "title": .string("Research notebook"),
        ])
        #expect(renamed["title"].string == "Research notebook")
        #expect(app.workspace.title == "Research notebook")
        let found = try await agent.send("list_documents", ["query": .string("First manuscript")])
        #expect(found["documents"].array.count == 1)
        #expect(found["documents"].array.first?["id"].string == first.id.uuidString)
        await #expect(throws: AutomationFailure.self) {
            try await agent.send("list_documents", ["limit": .number(0)])
        }
        await #expect(throws: AutomationFailure.self) {
            try await agent.send("list_documents", ["cursor": page["next_cursor"]])
        }
        await #expect(throws: AutomationFailure.self) {
            try await agent.send("trash_document", ["document_id": .string(first.id.uuidString)])
        }
        let editor = try #require(app.workspace.editor)
        editor.insertSnippet(
            Snippet(text: " unsaved"),
            replacing: NSRange(location: editor.string.utf16.count, length: 0),
        )
        let before = try await agent.send("get_document")
        let trashed = try await agent.send("trash_document", [
            "document_id": before["document_id"], "expected_revision": before["revision"],
        ])
        #expect(trashed["trashed"].foundationValue as? Bool == true)
        #expect(app.workspace.managedDocumentID == second.id)
        #expect(try await app.workspace.library.store.read(first.id).text == "First manuscript unsaved")
        let trash = try await agent.send("list_documents", ["trashed": .bool(true)])
        #expect(trash["documents"].array.count == 1)
        #expect(trash["documents"].array.first?["id"].string == first.id.uuidString)
        let restored = try await agent.send("restore_document", ["document_id": .string(first.id.uuidString)])
        #expect(restored["trashed"].foundationValue as? Bool == false)
        #expect(try await app.workspace.library.store.list().count == 2)
        await #expect(throws: AutomationFailure.self) { try await agent.send("empty_trash") }
    }

    @Test func agentResourceImportIsBoundedAndProjectExportFlushesLiveWriting() async throws {
        let app = try WritingFixture(text: "External draft", startService: false)
        defer { app.close() }
        try await app.workspace.library.create(title: "Resource project", text: "= Notebook\n")
        let agent = try CapabilityAgentFixture(app.workspace)
        defer { agent.close() }
        let before = try await agent.send("get_document")
        let bytes = Data("@book{demo, title = {An example}}".utf8)
        var arguments: [String: JSONValue] = [
            "document_id": before["document_id"], "expected_revision": before["revision"],
            "kind": .string("bibliography"), "name": .string("references.bib"),
            "data_base64": .string(bytes.base64EncodedString()),
        ]
        let imported = try await agent.send("import_resource", arguments)
        let relative = try #require(imported["relative_path"].string)
        let source = app.workspace.documentURL.deletingLastPathComponent().appendingPathComponent(relative)
        #expect(try Data(contentsOf: source) == bytes)
        #expect(imported["revision"].string != before["revision"].string)
        #expect(imported["text"].isNull)
        #expect(app.workspace.text == "= Notebook\n")
        let resources = try await agent.send("list_resources", [
            "document_id": imported["document_id"], "kind": .string("bibliography"),
        ])
        #expect(resources["resources"].array.first?["relative_path"].string == relative)
        #expect(resources["resources"].array.first?["file_id"].string == imported["file_id"].string)
        arguments["expected_revision"] = imported["revision"]
        for invalid in [
            "../escape.bib",
            "/escape.bib",
            "folder/escape.bib",
            "bad\\escape.bib",
            ".private.bib",
            "image.png",
        ] {
            arguments["name"] = .string(invalid)
            await #expect(throws: AutomationFailure.self) { try await agent.send("import_resource", arguments) }
        }
        arguments["name"] = .string("references.bib")
        arguments["data_base64"] = .string(Data(repeating: 65, count: 4 * 1024 * 1024 + 1).base64EncodedString())
        await #expect(throws: AutomationFailure.self) { try await agent.send("import_resource", arguments) }
        let editor = try #require(app.workspace.editor)
        editor.insertSnippet(
            Snippet(text: "Unsaved project text\n"), replacing: NSRange(location: editor.string.utf16.count, length: 0),
        )
        let current = try await agent.send("get_document")
        let exported = try await agent.send("export_project", [
            "document_id": current["document_id"], "expected_revision": current["revision"],
        ])
        let destination = try URL(fileURLWithPath: #require(exported["path"].string))
        #expect(destination.path
            .hasPrefix(app.workspace.stateDirectory.appendingPathComponent("AgentExports").path + "/"))
        #expect(try String(contentsOf: destination.appendingPathComponent("main.typ"), encoding: .utf8) == app.workspace
            .text)
        #expect(try Data(contentsOf: destination.appendingPathComponent(relative)) == bytes)
        #expect(app.workspace.savedText == app.workspace.text)
        #expect(!FileManager.default.fileExists(atPath: destination.appendingPathComponent("document.json").path))
        let assets = app.workspace.resourceRoot.appendingPathComponent("assets", isDirectory: true)
        try FileManager.default.moveItem(
            at: assets,
            to: app.workspace.resourceRoot.appendingPathComponent("saved-assets"),
        )
        try FileManager.default.createSymbolicLink(at: assets, withDestinationURL: app.root)
        arguments["expected_revision"] = current["revision"]
        arguments["data_base64"] = .string(bytes.base64EncodedString())
        await #expect(throws: AutomationFailure.self) { try await agent.send("import_resource", arguments) }
    }

    @Test func agentHistoryReadsSlicesRestoresAndPreservesNativeUndo() async throws {
        let original = (1 ... 230).map { "Line \($0)" }.joined(separator: "\n")
        let app = try WritingFixture(text: original, startService: false)
        defer { app.close() }
        let agent = try CapabilityAgentFixture(app.workspace)
        defer { agent.close() }
        let editor = try #require(app.workspace.editor)
        editor.insertSnippet(
            Snippet(text: "\nLater thought"), replacing: NSRange(location: editor.string.utf16.count, length: 0),
        )
        let current = app.workspace.text
        let snapshot = try await agent.send("get_document")
        let history = try await agent.send("list_history", ["document_id": snapshot["document_id"]])
        let revision = try #require(history["revisions"].array.first?["revision_id"])
        #expect(history["revisions"].array.count == 1)
        #expect(history["revisions"].array.first?["text"].isNull == true)
        let slice = try await agent.send("get_history", [
            "document_id": snapshot["document_id"], "revision_id": revision,
            "start_line": .number(10), "line_count": .number(5),
        ])
        #expect(slice["text"].string == (10 ... 14).map { "Line \($0)" }.joined(separator: "\n") + "\n")
        #expect(slice["total_lines"].int == 230)
        #expect(slice["next_line"].int == 15)
        await #expect(throws: AutomationFailure.self) {
            try await agent.send("get_history", [
                "document_id": snapshot["document_id"], "revision_id": revision, "line_count": .number(201),
            ])
        }
        await #expect(throws: AutomationFailure.self) {
            try await agent.send("restore_history", [
                "document_id": snapshot["document_id"], "revision_id": revision, "expected_revision": .string("stale"),
            ])
        }
        let restored = try await agent.send("restore_history", [
            "document_id": snapshot["document_id"], "revision_id": revision, "expected_revision": snapshot["revision"],
        ])
        #expect(restored["text"].isNull)
        #expect(app.workspace.text == original)
        let preserved = try await app.workspace.history.store.revisions(for: app.workspace.historyKey)
        #expect(preserved.first?.reason == .beforeRestore)
        #expect(try await app.workspace.history.store.source(
            for: #require(preserved.first),
            key: app.workspace.historyKey,
        ) == current)
        editor.undoManager?.undo()
        #expect(app.workspace.text == current)
    }

    @Test func agentBuiltinTemplatesAndPackageCatalogWorkOffline() async throws {
        let app = try WritingFixture(text: "Existing writing", startService: false)
        defer { app.close() }
        let agent = try CapabilityAgentFixture(app.workspace)
        defer { agent.close() }
        let templates = try await agent.send("list_templates")
        #expect(templates["templates"].array.contains { $0["template_id"].string == "builtin:blank" })
        #expect(templates["templates"].array.contains { $0["template_id"].string == "builtin:welcome" })
        let created = try await agent.send("create_from_template", [
            "template_id": .string("builtin:blank"), "title": .string("Agent notebook"),
        ])
        #expect(created["title"].string == "Agent notebook")
        #expect(app.workspace.text == BuiltInTemplate.blank.source)
        #expect(created["text"].isNull)
        let bounded = try await agent.send("list_packages", ["limit": .number(2)])
        #expect(bounded["packages"].array.count == 2)
        let packages = try await agent.send("list_packages", ["limit": .number(50)])
        let id = try #require(packages["packages"].array.first {
            $0["compatible"].foundationValue as? Bool == true
        }?["package_id"])
        let before = app.workspace.text
        let inserted = try await agent.send("import_package", [
            "document_id": created["document_id"], "expected_revision": created["revision"], "package_id": id,
        ])
        #expect(app.workspace.text.contains("#import \"" + (id.string ?? "") + "\""))
        #expect(inserted["text"].isNull)
        app.workspace.editor?.undoManager?.undo()
        #expect(app.workspace.text == before)
        await #expect(throws: AutomationFailure.self) {
            try await agent.send("create_from_template", ["template_id": .string("../../fake")])
        }
    }
}

@MainActor
private struct CapabilityAgentFixture {
    let root: URL
    let controller: WorkspaceAutomation
    let client: AutomationBridgeClient

    init(_ workspace: Workspace) throws {
        root = TestPaths.temporaryDirectory.appendingPathComponent("c" + UUID().uuidString.prefix(8))
        let endpoint = AutomationContract.socketURL(in: root)
        controller = WorkspaceAutomation(workspace: workspace, socketURL: endpoint)
        client = AutomationBridgeClient(socketURL: endpoint)
        controller.library = .init(
            currentID: { workspace.managedDocumentID?.uuidString ?? workspace.compilationURL.absoluteString },
            list: { query in
                try await workspace.library.store.list(query: query).map {
                    AutomationDocument(id: $0.id.uuidString, title: $0.title)
                }
            },
            open: { id in
                guard let uuid = UUID(uuidString: id) else {
                    throw AutomationFailure("document_not_found", "Unknown document ID.")
                }
                try await workspace.library.open(uuid)
            },
            create: { title, text in try await workspace.library.create(title: title, text: text) },
        )
        try controller.start()
    }

    func send(_ operation: String, _ values: [String: JSONValue] = [:]) async throws -> JSONValue {
        try await client.send(.init(operation, arguments: .object(values)))
    }

    func close() {
        controller.stop()
        try? FileManager.default.removeItem(at: root)
    }
}

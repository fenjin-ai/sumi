import AppKit
import Foundation
@testable import LeftBlankApp
import LeftBlankAutomation
import LeftBlankCore
import Testing

extension WritingFlowTests {
    @Test func agentSourceReadsAreBoundedAndResumeUnicodeLongLines() async throws {
        let long = String(repeating: "中文😀e\u{301}", count: 2500)
        let app = try WritingFixture(text: "First\r\n" + long + "\nLast\n", startService: false)
        defer { app.close() }
        let fixture = try AgentFixture(app.workspace)
        defer { fixture.close() }
        let status = try await fixture.client.send(.init("get_status"))
        #expect(status["active_document"]["text"].isNull)
        #expect(status["active_document"]["total_lines"].int == 4)
        var character = 0, collected = ""
        repeat {
            let read = try await fixture.client.send(.init("get_document", arguments: .object([
                "start_line": .number(2), "line_count": .number(1),
                "start_character": .number(Double(character)),
            ])))
            let part = try #require(read["text"].string)
            #expect(part.utf8.count <= AutomationContract.maximumReadBytes)
            collected += part
            if let next = read["next_character"].int {
                character = next
            } else {
                break
            }
        } while true
        #expect(collected == long + "\n")
        let end = try await fixture.client.send(.init("get_document", arguments: .object([
            "start_line": .number(3), "line_count": .number(2),
        ])))
        #expect(end["text"].string == "Last\n")
        #expect(end["next_line"].isNull)
        for args: JSONValue in [.object(["line_count": .number(201)]),
                                .object(["start_line": .number(0)]),
                                .object(["start_line": .number(2), "start_character": .number(3)])]
        {
            await #expect(throws: AutomationFailure.self) { try await fixture.client.send(.init(
                "get_document", arguments: args,
            )) }
        }
        app.workspace.showLibraryHome()
        let home = try await fixture.client.send(.init("get_status"))
        #expect(home["active_document"].isNull)
        await #expect(throws: AutomationFailure.self) { try await fixture.client.send(.init("get_document")) }
    }

    @Test func agentReadsDocumentsLargerThanMutationLimitInChunks() async throws {
        let large = String(repeating: "A long source line.\n", count: 120_000)
        let app = try WritingFixture(text: large, startService: false)
        defer { app.close() }
        let fixture = try AgentFixture(app.workspace)
        defer { fixture.close() }
        #expect(large.utf8.count > AutomationContract.maximumSourceBytes)
        let read = try await fixture.client.send(.init("get_document", arguments: .object([
            "start_line": .number(119_990), "line_count": .number(2),
        ])))
        #expect(read["text"].string == "A long source line.\nA long source line.\n")
        #expect(read["next_line"].int == 119_992)
    }

    @Test func agentExactReplacementsAreAtomicUniqueAndUndoable() async throws {
        let original = "= Notes\n\nHello 😀\nAgain hello\n"
        let app = try WritingFixture(text: original, startService: false)
        defer { app.close() }
        let fixture = try AgentFixture(app.workspace)
        defer { fixture.close() }
        let before = try await fixture.client.send(.init("get_document"))
        let arguments: JSONValue = .object([
            "document_id": before["document_id"], "expected_revision": before["revision"],
            "edits": .array([.object(["old_text": .string("Hello 😀"), "new_text": .string("Welcome Σ")]),
                             .object(["old_text": .string("Again hello"), "new_text": .string("Second note")])]),
        ])
        let changed = try await fixture.client.send(.init("edit_document", arguments: arguments))
        #expect(changed["text"].isNull)
        #expect(changed["changed_edits"].int == 2)
        #expect(app.workspace.text == "= Notes\n\nWelcome Σ\nSecond note\n")
        await #expect(throws: AutomationFailure.self) { try await fixture.client.send(.init(
            "edit_document",
            arguments: arguments,
        )) }
        app.workspace.editor?.undoManager?.undo()
        #expect(app.workspace.text == original)
        for edits: JSONValue in [
            .array([.object(["old_text": .string("Hello"), "new_text": .string("good")]),
                    .object(["old_text": .string("missing"), "new_text": .string("bad")])]),
            .array([.object(["old_text": .string("Hello 😀"), "new_text": .string("a")]),
                    .object(["old_text": .string("😀"), "new_text": .string("b")])]),
            .array([.object(["old_text": .string("\n"), "new_text": .string(" ")])]),
        ] {
            let current = try await fixture.client.send(.init("get_document"))
            await #expect(throws: AutomationFailure.self) { try await fixture.client.send(.init(
                "edit_document",
                arguments: .object([
                    "document_id": current["document_id"], "expected_revision": current["revision"], "edits": edits,
                ]),
            )) }
            #expect(app.workspace.text == original)
        }
        #expect(throws: AutomationFailure.self) {
            try AutomationContract.replacingText(
                .array([.object(["old_text": .string("aa"), "new_text": .string("b")])]),
                in: "aaa",
            )
        }
    }

    @Test func agentSearchAndOutlineReturnPagedLocations() async throws {
        let app = try WritingFixture(text: "= First\n😀 One one ONE\n= Second\n", startService: false)
        defer { app.close() }
        let fixture = try AgentFixture(app.workspace)
        defer { fixture.close() }
        app.workspace.outline = [.init(title: "First", level: 1, offset: 0),
                                 .init(title: "Second", level: 1, offset: 23)]
        let current = try await fixture.client.send(.init("get_document"))
        let first = try await fixture.client.send(.init("search_document", arguments: .object([
            "document_id": current["document_id"], "query": .string("one"), "limit": .number(2),
        ])))
        #expect(first["matches"].array.count == 2)
        #expect(first["matches"].array.first?["character"].int == 3)
        #expect(first["matches"].array.first?["line"].int == 2)
        let second = try await fixture.client.send(.init("search_document", arguments: .object([
            "document_id": current["document_id"], "query": .string("one"), "cursor": first["next_cursor"],
        ])))
        #expect(second["matches"].array.count == 1)
        #expect(second["next_cursor"].isNull)
        let sensitive = try await fixture.client.send(.init("search_document", arguments: .object([
            "document_id": current["document_id"], "query": .string("one"), "case_sensitive": .bool(true),
        ])))
        #expect(sensitive["matches"].array.count == 1)
        let outline = try await fixture.client.send(.init("get_outline", arguments: .object([
            "document_id": current["document_id"], "limit": .number(1),
        ])))
        #expect(outline["headings"].array.first?["title"].string == "First")
        #expect(outline["next_cursor"].string == "1")
        #expect(outline["text"].isNull)
    }

    @Test func agentProjectFilesPreserveBufferAndRejectTraversalAndSymlinks() async throws {
        let app = try WritingFixture(text: "= Main\n", startService: false)
        defer { app.close() }
        let fixture = try AgentFixture(app.workspace)
        defer { fixture.close() }
        let editor = try #require(app.workspace.editor)
        editor.insertSnippet(
            Snippet(text: "Unsaved\n"),
            replacing: NSRange(location: editor.string.utf16.count, length: 0),
        )
        let current = try await fixture.client.send(.init("get_document"))
        let unchanged = app.workspace.text
        let chapter = try await fixture.client.send(.init("create_file", arguments: .object([
            "document_id": current["document_id"], "expected_revision": current["revision"],
            "path": .string("chapters/intro.typ"), "text": .string("= Intro\n"),
        ])))
        #expect(app.workspace.text == unchanged)
        #expect(chapter["revision"].string != current["revision"].string)
        try FileManager.default.createSymbolicLink(
            at: app.root.appendingPathComponent("outside"),
            withDestinationURL: app.root.deletingLastPathComponent(),
        )
        try FileManager.default.createSymbolicLink(
            at: app.root.appendingPathComponent("linked.typ"),
            withDestinationURL: app.document,
        )
        let files = try await fixture.client.send(.init(
            "list_files",
            arguments: .object(["document_id": chapter["document_id"]]),
        ))
        #expect(files["files"].array.count == 2)
        #expect(!files["files"].array.contains { $0["path"].string == "linked.typ" })
        for path in ["../escape.typ", "/absolute.typ", "outside/escape.typ", "./local.typ", "chapters/intro.typ"] {
            let status = try await fixture.client.send(.init("get_status"))["active_document"]
            await #expect(throws: AutomationFailure.self) { try await fixture.client.send(.init(
                "create_file",
                arguments: .object([
                    "document_id": status["document_id"], "expected_revision": status["revision"],
                    "path": .string(path), "text": .string("bad"),
                ]),
            )) }
        }
        await #expect(throws: AutomationFailure.self) { try await fixture.client.send(.init(
            "open_file",
            arguments: .object([
                "document_id": chapter["document_id"], "file_id": .string("/etc/passwd"),
            ]),
        )) }
        let opened = try await fixture.client.send(.init("open_file", arguments: .object([
            "document_id": chapter["document_id"], "file_id": chapter["file_id"],
        ])))
        #expect(opened["text"].isNull)
        #expect(opened["document_id"].string == chapter["document_id"].string)
        #expect(app.workspace.mainFileURL == app.document)
        #expect(app.workspace.text == "= Intro\n")
        #expect(try String(contentsOf: app.document, encoding: .utf8) == unchanged)
    }
}

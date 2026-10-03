import AppKit
@testable import LeftBlankApp
import LeftBlankCore
import PDFKit
import Testing

extension WritingFlowTests {
    @Test func reconstructedDraftDoesNotSwitchAwayFromChangedWriting() async throws {
        let app = try WritingFixture(text: "Original\n", startService: false)
        defer { app.close() }
        let snapshot = (app.workspace.documentURL, app.workspace.revision)
        let document = try await app.workspace.library.store.create(title: "Reconstructed", text: "Recovered\n")
        let pending = Task { try await app.workspace.library.open(document.id, ifCurrent: snapshot) }
        app.workspace.edited("Still writing\n")
        #expect(try await !pending.value)
        #expect(app.workspace.text == "Still writing\n")
        #expect(app.workspace.documentURL == app.document)
        #expect(try await app.workspace.library.store.read(document.id).text == "Recovered\n")
        let current = (app.workspace.documentURL, app.workspace.revision)
        let cancelled = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try await app.workspace.library.open(document.id, ifCurrent: current)
        }
        #expect(try await !cancelled.value)
        #expect(app.workspace.documentURL == app.document)
    }

    @Test func naturalLanguagePreparesAFormBeforeInsertionAndSharesUndoAndExport() async throws {
        let app = try WritingFixture(text: "= My writing\n\nBody\n")
        defer { app.close() }
        try await app.ready()
        let editor = try #require(app.workspace.editor)
        let original = editor.string
        app.workspace.typesettingResolver = { try TypesettingIntelligence.suggest($0) }
        app.workspace.togglePalette()
        app.workspace.searchMode = true
        app.workspace.query = "插入三行两列表格"
        app.workspace.understandTypesettingRequest()
        try await app.wait { !app.workspace.understandingRequest }
        let command = try #require(app.workspace.activeCommand)
        #expect(command.id == "table")
        #expect(app.workspace.fieldValues == ["columns": "2", "rows": "3"])
        #expect(editor.string == original)
        app.workspace.execute(command)
        try await app.wait { !app.workspace.applyingCommand }
        #expect(editor.string.contains("#table("))
        let inserted = editor.string
        editor.undoManager?.undo()
        #expect(editor.string == original)
        editor.undoManager?.redo()
        #expect(editor.string == inserted)
        let pdf = app.root.appendingPathComponent("typesetting.pdf")
        try await app.workspace.exportPDF(to: pdf)
        #expect(try #require(PDFDocument(url: pdf)).pageCount > 0)
    }

    @Test func requestChangesAndClosingThePaletteDiscardLateModelResults() async throws {
        let app = try WritingFixture(text: "Body\n", startService: false)
        defer { app.close() }
        let gate = TypesettingRequestGate()
        app.workspace.typesettingResolver = { _ in await gate.wait() }
        app.workspace.togglePalette()
        app.workspace.searchMode = true
        app.workspace.query = "make a table"
        app.workspace.understandTypesettingRequest()
        while await !(gate.started) {
            await Task.yield()
        }
        let request = try #require(app.workspace.typesettingRequestTask)
        app.workspace.query = "change paper size"
        #expect(!app.workspace.understandingRequest)
        await gate.finish(.init(commandID: "table"))
        await request.value
        #expect(app.workspace.activeCommand == nil)
        #expect(app.workspace.text == "Body\n")

        let next = TypesettingRequestGate()
        app.workspace.typesettingResolver = { _ in await next.wait() }
        app.workspace.understandTypesettingRequest()
        while await !(next.started) {
            await Task.yield()
        }
        let pending = try #require(app.workspace.typesettingRequestTask)
        app.workspace.closePalette()
        await next.finish(.init(commandID: "paper", values: ["paper": "a5"]))
        await pending.value
        #expect(!app.workspace.paletteOpen)
        #expect(app.workspace.activeCommand == nil)
        #expect(app.workspace.text == "Body\n")
    }

    @Test func unsafeSuggestionsAndUnsupportedRequestsLeaveTheDocumentUnchanged() async throws {
        let app = try WritingFixture(text: "Body\n", startService: false)
        defer { app.close() }
        app.workspace.togglePalette()
        app.workspace.searchMode = true
        app.workspace.query = "do something"
        app.workspace.typesettingResolver = { _ in .init(commandID: "import", values: ["path": "secret.typ"]) }
        app.workspace.understandTypesettingRequest()
        try await app.wait { !app.workspace.understandingRequest }
        #expect(app.workspace.commandError != nil)
        #expect(app.workspace.activeCommand == nil)
        app.workspace.typesettingResolver = { _ in nil }
        app.workspace.understandTypesettingRequest()
        try await app.wait { !app.workspace.understandingRequest }
        #expect(app.workspace.commandError != nil)
        #expect(app.workspace.text == "Body\n")
        #expect(app.workspace.filteredCommands.isEmpty)
        app.workspace.query = "反向"
        #expect(app.workspace.filteredCommands.contains { $0.id == "reconstructPage" })
    }

    @Test func reconstructedPDFOpensAnEditableLibraryDraftAndExports() async throws {
        let app = try WritingFixture(text: "= Original\n\nKeep this writing.\n")
        defer { app.close() }
        try await app.ready()
        let reference = app.root.appendingPathComponent("reference.pdf")
        try await app.workspace.exportPDF(to: reference)
        let original = app.workspace.text
        app.workspace.reconstructPage(from: reference)
        try await app.wait { !app.workspace.reconstructingPage }
        #expect(app.workspace.managedDocumentID != nil)
        #expect(app.workspace.text.contains("Keep this writing."))
        #expect(app.workspace.text.contains("#text("))
        #expect(app.workspace.layout == .split)
        #expect(try String(contentsOf: app.document, encoding: .utf8) == original)
        try await app.ready()
        let editor = try #require(app.workspace.editor)
        editor.insertSnippet(
            Snippet(text: "\n#text(\"Edited draft\")\n"),
            replacing: NSRange(location: editor.string.utf16.count, length: 0),
        )
        #expect(app.workspace.text.contains("Edited draft"))
        let exported = app.root.appendingPathComponent("reconstructed.pdf")
        try await app.workspace.exportPDF(to: exported)
        #expect(try #require(PDFDocument(url: exported)).page(at: 0)?.string?.contains("Edited draft") == true)
    }
}

private actor TypesettingRequestGate {
    private var continuation: CheckedContinuation<TypesettingSuggestion?, Never>?
    var started: Bool {
        continuation != nil
    }

    func wait() async -> TypesettingSuggestion? {
        await withCheckedContinuation { continuation = $0 }
    }

    func finish(_ result: TypesettingSuggestion?) {
        continuation?.resume(returning: result)
        continuation = nil
    }
}

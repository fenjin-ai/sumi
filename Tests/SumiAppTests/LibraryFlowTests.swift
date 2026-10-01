import AppKit
import PDFKit
import SwiftUI
import Testing
@testable import SumiApp
import SumiCore

extension WritingFlowTests {
    @Test func libraryCreateRenameSearchTrashRestoreAndExportPreserveWriting() async throws {
        let app = try WritingFixture(text: "= External\n", startService: false)
        defer { app.close() }
        let library = app.workspace.library
        await library.start()
        try await library.create(title: "Notebook", text: "= Notebook\n\nAn unusual narwhal.\n")
        let id = try #require(app.workspace.managedDocumentID)
        let source = try #require(app.workspace.fileURL)
        let editor = try #require(app.workspace.editor)
        editor.insertSnippet(Snippet(text: "One more thought.\n"), replacing: NSRange(location: editor.string.utf16.count, length: 0))
        try await library.rename(id, title: "Field notes")
        #expect(app.workspace.title == "Field notes")
        #expect(app.workspace.fileURL == source)
        app.workspace.save()
        #expect(try await library.store.list(query: "narwhal").map(\.id) == [id])
        let export = app.root.appendingPathComponent("Exported")
        try await library.exportProject(id, to: export)
        #expect(try String(contentsOf: export.appendingPathComponent("main.typ"), encoding: .utf8).contains("One more thought"))
        try await library.moveToTrash(id)
        #expect(app.workspace.managedDocumentID != id)
        #expect(library.documents.first { $0.id == id }?.trashedAt != nil)
        await #expect(throws: (any Error).self) { try await library.open(id) }
        try await library.restore(id)
        try await library.open(id)
        #expect(editor.string.contains("One more thought"))
        #expect(library.documents.first { $0.id == id }?.trashedAt == nil)
        let view = NSHostingView(rootView: LibraryBrowser(workspace: app.workspace, library: library))
        view.layoutSubtreeIfNeeded()
        #expect(view.fittingSize.width >= 600)
    }

    @Test func liveRemoteMergePreservesFocusSelectionAndUndoAndRejectsConflicts() async throws {
        let base = "= Shared\n\nFirst paragraph\n\nSecond paragraph\n"
        let app = try WritingFixture(text: base, startService: false)
        defer { app.close() }
        try await app.workspace.library.create(title: "Shared", text: base)
        // Explicitly drive delivery so no timer can race the scenario.
        app.workspace.library.stop()
        let editor = try #require(app.workspace.editor)
        editor.insertSnippet(Snippet(text: "My second"), replacing: (editor.string as NSString).range(of: "Second"))
        let local = editor.string
        let remote = base.replacingOccurrences(of: "First", with: "Their first")
        try Data(remote.utf8).write(to: try #require(app.workspace.fileURL), options: .atomic)
        let search = NSTextField(frame: NSRect(x: 0, y: 0, width: 200, height: 24))
        app.window.contentView?.addSubview(search)
        app.window.makeFirstResponder(search)
        let responder = app.window.firstResponder
        editor.setSelectedRange(NSRange(location: local.utf16.count, length: 0))
        await app.workspace.refreshFromLibrary()
        #expect(editor.string.contains("Their first"))
        #expect(editor.string.contains("My second"))
        #expect(editor.selectedRange().location == editor.string.utf16.count)
        #expect(app.window.firstResponder === responder)
        #expect(app.workspace.savedText == remote)
        editor.undoManager?.undo()
        #expect(editor.string == local)
        app.workspace.save()
        let saved = editor.string
        editor.insertSnippet(Snippet(text: "Local replacement"), replacing: (editor.string as NSString).range(of: "First"))
        let conflict = saved.replacingOccurrences(of: "First", with: "Remote replacement")
        let url = try #require(app.workspace.fileURL)
        try Data(conflict.utf8).write(to: url, options: .atomic)
        await app.workspace.refreshFromLibrary()
        #expect(editor.string.contains("Local replacement"))
        #expect(app.workspace.message != nil)
        app.workspace.save()
        #expect(app.workspace.saveStatus == "Save Needs Attention")
        #expect(try String(contentsOf: url, encoding: .utf8) == conflict)
        let recovered = Workspace(stateDirectory: app.workspace.stateDirectory)
        #expect(recovered.text == editor.string)
        recovered.shutdown()
    }

    @Test func codeNotesTemplateCompilesWithBundledPackages() async throws {
        let app = try WritingFixture(text: "", startService: false)
        defer { app.close() }
        try await app.workspace.library.create(template: .codeNotes)
        try await app.ready()
        let output = app.root.appendingPathComponent("code-notes.pdf")
        try await app.workspace.exportPDF(to: output)
        let text = try #require(PDFDocument(url: output)?.string)
        #expect(text.contains("total"))
        #expect(app.workspace.text.contains("@preview/codly:1.3.0"))
        #expect(!app.workspace.diagnostics.contains { $0.severity == 1 })
        let cache = app.workspace.stateDirectory.appendingPathComponent("PackageCache/preview/codly/1.3.0/typst.toml")
        #expect(FileManager.default.fileExists(atPath: cache.path))
    }

    @Test func writingPreferencesPersistWithoutReplacingTheEditor() async throws {
        let app = try WritingFixture(text: "= Keep me\n", startService: false)
        defer { app.close() }
        let suite = "Sumi.tests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        let oldLanguage = L10n.language
        defer { defaults.removePersistentDomain(forName: suite); L10n.setLanguage(oldLanguage) }
        let settings = WorkspaceSettings(workspace: app.workspace, defaults: defaults)
        defer { settings.stop() }
        let editor = try #require(app.workspace.editor)
        app.workspace.fontSize = 20
        app.workspace.previewDark = true
        app.workspace.commandKey = "k"
        app.workspace.documentTemplate = .codeNotes
        try await app.wait { settings.preferences.values.documentTemplate == "codeNotes" }
        #expect(settings.preferences.values.fontSize == 20)
        #expect(settings.preferences.values.previewDark)
        #expect(settings.preferences.values.commandKey == "k")
        #expect(app.workspace.editor === editor)
        #expect(editor.string == "= Keep me\n")
        let saved = LibraryPreferences(defaults: defaults)
        #expect(saved.values == settings.preferences.values)
        #expect(!settings.agentEnabled)
        #expect(settings.connectionCommand.hasPrefix("codex mcp add sumi --"))
        let view = NSHostingView(rootView: WritingSettingsView(workspace: app.workspace, settings: settings, library: app.workspace.library))
        view.layoutSubtreeIfNeeded()
        #expect(view.fittingSize.width == 530)
        await #expect(throws: (any Error).self) { try await app.workspace.library.setCloudEnabled(true) }
        #expect(!app.workspace.library.cloudEnabled)
        #expect(app.workspace.editor?.isEditable == true)
    }
}

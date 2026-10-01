import AppKit
import PDFKit
import SwiftUI
import Testing
@testable import SumiApp
import SumiCore

extension WritingFlowTests {
    @Test func newDocumentDiscoversTemplatesWithoutCreatingOrReplacingWriting() async throws {
        let app = try WritingFixture(text: "= My unfinished idea\n", startService: false)
        defer { app.close() }
        let delegate = AppDelegate(workspace: app.workspace)
        let previousMenu = NSApp.mainMenu, previousWindowsMenu = NSApp.windowsMenu
        defer { NSApp.mainMenu = previousMenu; NSApp.windowsMenu = previousWindowsMenu }
        delegate.installMenu()
        let menu = try #require(NSApp.mainMenu)
        #expect(menu.performKeyEquivalent(with: app.key("n", code: 45, modifiers: .command)))
        #expect(app.workspace.discoveryMode == .templates)
        #expect(app.workspace.libraryOpen)
        #expect(try await app.workspace.library.store.list().isEmpty)
        #expect(app.workspace.text == "= My unfinished idea\n")
        app.workspace.openLibrary()
        #expect(app.workspace.discoveryMode == nil)
        app.workspace.execute(try #require(WritingCommand.all.first { $0.id == "universe" }))
        #expect(app.workspace.discoveryMode == .packages)
        app.workspace.newDocument()
        #expect(app.workspace.discoveryMode == .templates)
        #expect(app.workspace.fileURL == app.document)
        #expect(!WritingCommand.all.contains { $0.id == "newCodeNotes" })
        #expect(WritingCommand.search("模板").contains { $0.id == "new" })

        // A saved legacy preference must not turn the explicit blank choice into code notes.
        app.workspace.documentTemplate = .codeNotes
        try await app.workspace.library.create(builtIn: .blank)
        #expect(!app.workspace.libraryOpen)
        #expect(app.workspace.managedDocumentID != nil)
        #expect(app.workspace.text == DocumentTemplate.blank.source)
        #expect(try String(contentsOf: app.document, encoding: .utf8) == "= My unfinished idea\n")
        app.workspace.showLibraryHome()
        app.workspace.newDocument()
        #expect(app.workspace.discoveryMode == .templates)
        #expect(!app.workspace.libraryOpen, "An empty library changes its inline route, never presents a sheet on itself")
    }

    @Test func welcomeCreationCompilesBothLanguagesAndPreservesExistingWriting() async throws {
        let app = try WritingFixture(text: "= My own words\n", startService: false)
        defer { app.close() }
        let language = L10n.language
        defer { L10n.setLanguage(language) }
        var previousID: UUID?
        for language in [AppLanguage.english, .simplifiedChinese] {
            L10n.setLanguage(language)
            try await app.workspace.library.create(builtIn: .welcome)
            let id = try #require(app.workspace.managedDocumentID)
            #expect(id != previousID)
            previousID = id
            #expect(app.workspace.text == WelcomeDocument.source(language: language))
            try await app.ready()
            let pdf = app.root.appendingPathComponent("welcome-\(language.rawValue).pdf")
            try await app.workspace.exportPDF(to: pdf)
            let result = try #require(PDFDocument(url: pdf))
            #expect(result.pageCount == 2)
            #expect(result.string?.contains(language == .english ? "Follow the thread" : "顺着思路写下去") == true)
            #expect(result.string?.contains("observations") == true)
            #expect(!app.workspace.diagnostics.contains { $0.severity == 1 })
        }
        #expect(try String(contentsOf: app.document, encoding: .utf8) == "= My own words\n")
        let saved = app.workspace.text
        L10n.setLanguage(.english)
        #expect(app.workspace.text == saved, "Interface language changes never replace writing")
        #expect(try await app.workspace.library.store.list().count == 2)
        let fresh = Workspace(stateDirectory: app.root.appendingPathComponent("Fresh"))
        defer { fresh.shutdown() }
        #expect(fresh.text == WelcomeDocument.source(language: .english))
        #expect(fresh.layout == .split)
        #expect(fresh.text.contains("@preview/cetz:0.5.2"))
        fresh.save()
        let recovered = Workspace(stateDirectory: fresh.stateDirectory)
        defer { recovered.shutdown() }
        #expect(recovered.text == fresh.text)
    }

}

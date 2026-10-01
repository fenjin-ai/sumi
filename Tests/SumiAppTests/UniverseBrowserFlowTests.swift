import AppKit
import SwiftUI
import Testing
@testable import SumiApp
import SumiCore

extension WritingFlowTests {
    private static let index = Data(#"[{"name":"cetz","version":"0.5.2","description":"Draw diagrams with CeTZ","categories":["visualization"],"keywords":["diagram"],"license":"LGPL-3.0-or-later","authors":["CeTZ contributors"],"compiler":"0.14.0"},{"name":"fletcher","version":"0.5.8","description":"Flowcharts and diagrams","categories":["visualization"],"license":"MIT","compiler":"0.14.0"}]"#.utf8)

    @Test func cachedPackageBrowserRendersWithoutNetwork() async throws {
        let app = try WritingFixture(text: "= Package discovery\n", startService: false)
        defer { app.close() }
        let cache = app.root.appendingPathComponent("universe.json")
        let fixtureData = Self.index
        let store = UniverseCatalogStore(cacheURL: cache, transport: { _ in UniverseHTTPResponse(data: fixtureData, statusCode: 200) })
        _ = try await store.load()
        let browser = NSHostingView(rootView: UniverseBrowser(cacheURL: cache, size: CGSize(width: 790, height: 590), onImport: app.workspace.importPackage))
        let browserWindow = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 790, height: 590), styleMask: [.titled, .closable], backing: .buffered, defer: false)
        browserWindow.isReleasedWhenClosed = false
        browserWindow.contentView = browser
        defer { browserWindow.close() }
        browser.layoutSubtreeIfNeeded()
        try await Task.sleep(for: .milliseconds(100))
        browser.layoutSubtreeIfNeeded()
        #expect(browser.fittingSize == NSSize(width: 790, height: 590))
        let bitmap = try #require(browser.bitmapImageRepForCachingDisplay(in: browser.bounds))
        browser.cacheDisplay(in: browser.bounds, to: bitmap)
        #expect(bitmap.pixelsWide >= 790)
        #expect(bitmap.pixelsHigh >= 590)
        #expect(bitmap.representation(using: .png, properties: [:])?.isEmpty == false)
        #expect(app.workspace.text == "= Package discovery\n", "Browsing must not insert package code before a user chooses import")
        #expect(await store.cached()?.packages.count == 2)
    }

    @Test func templateGalleryAdaptsToNarrowAndWideWindowsWithoutChangingWriting() async throws {
        let app = try WritingFixture(text: "= My current writing\n", startService: false)
        defer { app.close() }
        let cache = app.root.appendingPathComponent("templates.json")
        let fixtureData = Data(#"[{"name":"basic-resume","version":"0.2.9","description":"A calm resume with clear typography","categories":["cv"],"template":{"path":"template","entrypoint":"main.typ"}},{"name":"research-paper","version":"1.0.0","description":"A paper for your next idea","categories":["paper"],"template":{"path":"template","entrypoint":"main.typ"}}]"#.utf8)
        let store = UniverseCatalogStore(cacheURL: cache, transport: { _ in UniverseHTTPResponse(data: fixtureData, statusCode: 200) })
        _ = try await store.load()
        let model = UniverseBrowserModel(store: store, mode: .templates)
        await model.load()
        model.query = "简历"
        #expect(model.selected?.name == "basic-resume")
        model.query = ""
        model.group = "research"
        #expect(model.results.map(\.name) == ["research-paper"])
        model.changeMode(.packages)
        #expect(model.group.isEmpty)
        #expect(model.results.isEmpty)
        model.changeMode(.templates)
        #expect(model.results.count == 2)

        for size in [CGSize(width: 620, height: 530), CGSize(width: 1040, height: 720)] {
            let browser = NSHostingView(rootView: UniverseBrowser(cacheURL: cache, mode: .templates, size: size,
                onCreate: app.workspace.library.create(from:), onCreateBuiltIn: app.workspace.library.create(builtIn:), onAddSample: { try await app.workspace.library.create(sample: $0) }, onImport: app.workspace.importPackage))
            let window = NSWindow(contentRect: NSRect(origin: .zero, size: size), styleMask: [.titled, .closable], backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            window.contentView = browser
            defer { window.close() }
            browser.layoutSubtreeIfNeeded()
            try await Task.sleep(for: .milliseconds(120))
            browser.layoutSubtreeIfNeeded()
            #expect(browser.fittingSize == size, "Discovery must not force a narrow window wider")
            let bitmap = try #require(browser.bitmapImageRepForCachingDisplay(in: browser.bounds))
            browser.cacheDisplay(in: browser.bounds, to: bitmap)
            #expect(bitmap.pixelsWide >= Int(size.width))
            let image = try #require(bitmap.representation(using: .png, properties: [:]))
            #expect(!image.isEmpty)
            if let path = ProcessInfo.processInfo.environment["SUMI_DISCOVERY_ARTIFACTS"] {
                let directory = URL(fileURLWithPath: path)
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                try image.write(to: directory.appendingPathComponent("gallery-\(Int(size.width)).png"))
            }
        }
        #expect(app.workspace.text == "= My current writing\n")
        #expect(try await app.workspace.library.store.list().isEmpty, "Browsing must not create a document")
    }

    @Test(.enabled(if: ProcessInfo.processInfo.environment["SUMI_UNIVERSE_NETWORK"] == "1"))
    func templateCreationOpensIndependentManagedDocumentAndPreservesPreviousWriting() async throws {
        let app = try WritingFixture(text: "= Preserve my writing\n", startService: false)
        defer { app.close() }
        let beforeURL = try #require(app.workspace.fileURL)
        let package = try JSONDecoder().decode(UniversePackage.self, from: Data(#"{"name":"charged-ieee","version":"0.1.4","compiler":"0.12.0","template":{"path":"template","entrypoint":"main.typ","thumbnail":"thumbnail.png"}}"#.utf8))
        try await app.workspace.library.create(from: package)
        await app.layout()
        #expect(app.workspace.managedDocumentID != nil)
        #expect(app.workspace.title == "charged-ieee")
        #expect(app.workspace.text.contains("@preview/charged-ieee:0.1.4"))
        #expect(app.workspace.editor?.string == app.workspace.text)
        #expect(!app.workspace.libraryOpen)
        #expect(!app.workspace.library.busy)
        #expect(try String(contentsOf: beforeURL, encoding: .utf8) == "= Preserve my writing\n")
        let staging = app.workspace.stateDirectory.appendingPathComponent("TemplateDownloads")
        #expect(try FileManager.default.contentsOfDirectory(atPath: staging.path).isEmpty)
        #expect(try await app.workspace.library.store.list().count == 1)
    }

    @Test func sampleBookCreationPreservesWritingAndLocalStyleNavigation() async throws {
        let app = try WritingFixture(text: "= Keep my writing\n", startService: false)
        defer { app.close() }
        let previous = try #require(app.workspace.fileURL)
        let repository = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let data = try Data(contentsOf: repository.appendingPathComponent("Examples/Books/SICP/" + SampleBook.sicp.archiveName))
        let store = SampleBookStore(cacheURL: app.root.appendingPathComponent("Books"), transport: { _ in UniverseHTTPResponse(data: data, statusCode: 200) })
        try await app.workspace.library.create(sample: .sicp, using: store)
        await app.layout()
        #expect(app.workspace.title == SampleBook.sicp.title)
        #expect(app.workspace.text.contains("#import \"styles/book.typ\""))
        #expect(try String(contentsOf: previous, encoding: .utf8) == "= Keep my writing\n")
        let id = app.workspace.managedDocumentID
        let main = try #require(app.workspace.fileURL)
        let style = main.deletingLastPathComponent().appendingPathComponent("styles/book.typ")
        #expect(app.workspace.open(style, preservingMain: true))
        await app.workspace.library.refresh()
        #expect(app.workspace.managedDocumentID == id)
        #expect(app.workspace.compilationURL == main)
        #expect(app.workspace.text.contains("#let book(body)"))
        #expect(!app.workspace.library.busy)
        #expect(try FileManager.default.contentsOfDirectory(atPath: app.workspace.stateDirectory.appendingPathComponent("SampleDownloads").path).isEmpty)
        let failed = SampleBookStore(cacheURL: app.root.appendingPathComponent("NoCache"), transport: { _ in throw URLError(.notConnectedToInternet) })
        await #expect(throws: URLError.self) { try await app.workspace.library.create(sample: .sicp, using: failed) }
        #expect(app.workspace.fileURL == style)
        #expect(!app.workspace.library.busy)
    }

    @Test func discoveryModelSearchSelectRefreshAndOfflineRecovery() async throws {
        let app = try WritingFixture(text: "= Catalog states\n", startService: false)
        defer { app.close() }
        let cache = app.root.appendingPathComponent("universe.json")
        let fixtureData = Self.index
        let model = UniverseBrowserModel(store: UniverseCatalogStore(cacheURL: cache, transport: { _ in UniverseHTTPResponse(data: fixtureData, statusCode: 200) }))
        await model.load()
        #expect(model.results.map(\.name) == ["cetz", "fletcher"])
        model.query = "flowchart"
        #expect(model.selected?.name == "fletcher")
        model.query = ""
        model.selectedID = "fletcher"
        #expect(model.selected?.reference == "@preview/fletcher:0.5.8")
        model.group = "math"
        #expect(model.results.isEmpty)
        #expect(model.selected == nil)
        model.group = "draw"
        await model.load(forceRefresh: true)
        #expect(model.error == nil)
        #expect(!model.isLoading)
        let offline = UniverseBrowserModel(store: UniverseCatalogStore(cacheURL: cache, transport: { _ in throw URLError(.notConnectedToInternet) }))
        await offline.load(forceRefresh: true)
        #expect(offline.snapshot?.source == .offlineCache)
        #expect(offline.results.count == 2)
        let uncached = UniverseBrowserModel(store: UniverseCatalogStore(cacheURL: app.root.appendingPathComponent("absent.json"), transport: { _ in throw URLError(.notConnectedToInternet) }))
        await uncached.load()
        #expect(uncached.error != nil)
        #expect(uncached.results.isEmpty)
    }
    @Test(.enabled(if: ProcessInfo.processInfo.environment["SUMI_UNIVERSE_NETWORK"] == "1"))
    func officialTemplateGalleryLoadsRealThumbnails() async throws {
        let app = try WritingFixture(text: "= Keep writing\n", startService: false)
        defer { app.close() }
        let cache = app.root.appendingPathComponent("universe.json")
        let store = UniverseCatalogStore(cacheURL: cache)
        let snapshot = try await store.load()
        let template = try #require(snapshot.discover("charged-ieee", mode: .templates).first)
        let url = try #require(template.thumbnailURL)
        let (data, response) = try await URLSession.shared.data(from: url)
        #expect((response as? HTTPURLResponse)?.statusCode == 200)
        #expect(NSImage(data: data) != nil, "Official thumbnail must decode on macOS")
        let size = CGSize(width: 1040, height: 720)
        let browser = NSHostingView(rootView: UniverseBrowser(cacheURL: cache, mode: .templates, size: size,
            onCreate: app.workspace.library.create(from:), onCreateBuiltIn: app.workspace.library.create(builtIn:), onAddSample: { try await app.workspace.library.create(sample: $0) }, onImport: app.workspace.importPackage))
        let window = NSWindow(contentRect: NSRect(origin: .zero, size: size), styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = browser
        defer { window.close() }
        browser.layoutSubtreeIfNeeded()
        try await Task.sleep(for: .seconds(5))
        browser.layoutSubtreeIfNeeded()
        if let path = ProcessInfo.processInfo.environment["SUMI_DISCOVERY_ARTIFACTS"] {
            let bitmap = try #require(browser.bitmapImageRepForCachingDisplay(in: browser.bounds))
            browser.cacheDisplay(in: browser.bounds, to: bitmap)
            let image = try #require(bitmap.representation(using: .png, properties: [:]))
            let directory = URL(fileURLWithPath: path)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try image.write(to: directory.appendingPathComponent("gallery-official.png"))
        }
        #expect(app.workspace.text == "= Keep writing\n")
    }

}

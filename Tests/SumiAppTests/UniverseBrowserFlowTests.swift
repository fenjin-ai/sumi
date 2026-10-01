import AppKit
import SwiftUI
import Testing
@testable import SumiApp
import SumiCore

@Suite(.serialized, .enabled(if: ProcessInfo.processInfo.environment["SUMI_INTEGRATION"] == "1"))
@MainActor
struct UniverseBrowserFlowTests {
    private static let index = Data(#"[{"name":"cetz","version":"0.5.2","description":"Draw diagrams with CeTZ","categories":["visualization"],"keywords":["diagram"],"license":"LGPL-3.0-or-later","authors":["CeTZ contributors"],"compiler":"0.14.0"},{"name":"fletcher","version":"0.5.8","description":"Flowcharts and diagrams","categories":["visualization"],"license":"MIT","compiler":"0.14.0"}]"#.utf8)

    @Test func cachedPackageBrowserRendersWithoutNetwork() async throws {
        let app = try WritingFixture(text: "= Package discovery\n", startService: false)
        defer { app.close() }
        let cache = app.root.appendingPathComponent("universe.json")
        let fixtureData = Self.index
        let store = UniverseCatalogStore(cacheURL: cache, transport: { _ in UniverseHTTPResponse(data: fixtureData, statusCode: 200) })
        _ = try await store.load()
        let browser = NSHostingView(rootView: UniverseBrowser(cacheURL: cache, onImport: app.workspace.importPackage))
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
        model.category = "text"
        #expect(model.results.isEmpty)
        #expect(model.selected == nil)
        model.category = "visualization"
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
}

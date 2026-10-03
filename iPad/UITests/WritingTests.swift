import Nimble
import StoreKitTest
import XCTest

@MainActor
final class WritingTests: XCTestCase {
    private var storeSession: SKTestSession?

    override func setUp() async throws {
        try await super.setUp()
        continueAfterFailure = false
        let session = try SKTestSession(configurationFileNamed: "LeftBlank")
        session.resetToDefaultState()
        session.disableDialogs = true
        session.clearTransactions()
        if !name.contains("testSubscriptionPurchaseAndExpiredProjectExport") {
            _ = try await session.buyProduct(identifier: "app.leftblank.writer.ipad.monthly")
        }
        storeSession = session
    }

    override func tearDown() async throws {
        await MainActor.run {
            XCUIApplication().terminate()
            storeSession?.clearTransactions()
            storeSession = nil
        }
        try await super.tearDown()
    }

    private func startWriting(template: String = "blank", language: String = "en") -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-AppleLanguages", "(en)", "-AppleLocale", "en_US", "-appLanguage", language,
                               "-iPadCloudEnabled", "NO"]
        XCUIDevice.shared.orientation = .landscapeLeft
        app.launch()
        let create = app.buttons["new-document"]
        let actions = app.buttons["document-actions"]
        let loading = app.progressIndicators["document-loading"]
        // First launch opens Welcome and hides the sidebar asynchronously.
        // Wait for that transition before deciding whether to reveal the library.
        let launched = NSPredicate { _, _ in
            !loading.exists && ((create.exists && create.isEnabled && create.isHittable) ||
                (actions.exists && actions.isHittable))
        }
        expectation(for: launched, evaluatedWith: app)
        waitForExpectations(timeout: 60)
        if !create.waitForExistence(timeout: 3) || !create.isHittable {
            let sidebar = app.buttons["sidebar-toggle"]
            expect(sidebar.waitForExistence(timeout: 60)) == true
            sidebar.tap()
        }
        expect(create.waitForExistence(timeout: 60)) == true
        let enabled = NSPredicate { _, _ in create.exists && create.isEnabled && create.isHittable }
        expectation(for: enabled, evaluatedWith: app)
        waitForExpectations(timeout: 60)
        create.tap()
        app.buttons["universe.builtin." + template].tap()
        expect(app.textViews["manuscript"].waitForExistence(timeout: 60)) == true
        let settled = NSPredicate { _, _ in !app.progressIndicators["document-loading"].exists }
        expectation(for: settled, evaluatedWith: app)
        waitForExpectations(timeout: 60)
        if app.buttons["Show Sidebar"].exists || app.buttons["Hide Sidebar"].exists {
            capture("Duplicate sidebar controls")
            let hierarchy = XCTAttachment(string: app.debugDescription)
            hierarchy.name = "Duplicate sidebar hierarchy"
            hierarchy.lifetime = .keepAlways
            add(hierarchy)
        }
        expect(app.buttons["Show Sidebar"].exists) == false
        expect(app.buttons["Hide Sidebar"].exists) == false
        return app
    }

    private func capture(_ name: String) {
        let screenshot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        screenshot.name = name
        screenshot.lifetime = .keepAlways
        add(screenshot)
    }

    private func expectShareSheet(in app: XCUIApplication) {
        // The system sharing extension can still be loading on a cold hosted simulator.
        let share = app.descendants(matching: .any)["Save to Files"].firstMatch
        let visible = share.waitForExistence(timeout: 60)
        if !visible {
            capture("Share sheet unavailable")
            let hierarchy = XCTAttachment(string: app.debugDescription)
            hierarchy.name = "Share sheet hierarchy"
            hierarchy.lifetime = .keepAlways
            add(hierarchy)
        }
        expect(visible) == true
    }

    private func reveal(_ element: XCUIElement, in form: XCUIElement, scrollingUp: Bool = true) {
        for _ in 0 ..< 6 {
            if element.exists, element.isHittable {
                return
            }
            if scrollingUp {
                form.swipeUp()
            } else {
                form.swipeDown()
            }
        }
        if !element.exists || !element.isHittable {
            capture("Subscription control unavailable")
            let hierarchy = XCTAttachment(string: form.debugDescription)
            hierarchy.name = "Subscription form hierarchy"
            hierarchy.lifetime = .keepAlways
            add(hierarchy)
        }
        expect(element.exists && element.isHittable) == true
    }

    func testSubscriptionPurchaseAndExpiredProjectExport() throws {
        let session = try XCTUnwrap(storeSession)
        session.clearTransactions()
        let app = XCUIApplication()
        app.launchArguments = ["-AppleLanguages", "(en)", "-AppleLocale", "en_US", "-appLanguage", "en",
                               "-iPadCloudEnabled", "NO"]
        XCUIDevice.shared.orientation = .landscapeLeft
        app.launch()
        let banner = app.buttons["subscription-banner"]
        if !banner.waitForExistence(timeout: 3) || !banner.isHittable {
            app.buttons["sidebar-toggle"].tap()
        }
        expect(banner.waitForExistence(timeout: 30)) == true
        banner.tap()
        let form = app.collectionViews["subscription-form"]
        expect(form.waitForExistence(timeout: 30)) == true
        let restore = app.buttons["subscription-restore"]
        reveal(restore, in: form)
        restore.tap()
        let noPurchases = app.staticTexts["No active subscription was found for this Apple Account."]
        reveal(noPurchases, in: form)
        let purchase = app.buttons["subscription-purchase"]
        reveal(purchase, in: form, scrollingUp: false)
        // Introductory eligibility belongs to the Apple account's subscription group;
        // prior writing tests may already have consumed its introductory offer.
        expect(["Subscribe", "Start free trial"].contains(purchase.label)) == true
        capture("Monthly subscription")
        purchase.tap()
        reveal(app.staticTexts["subscription-status"], in: form, scrollingUp: false)
        expectation(
            for: NSPredicate(format: "label BEGINSWITH %@", "Writing access until"),
            evaluatedWith: app.staticTexts["subscription-status"],
        )
        waitForExpectations(timeout: 30)
        // Locate legal controls by their accessible names across supported runtimes.
        let privacy = app.descendants(matching: .any)["Privacy policy"].firstMatch
        reveal(privacy, in: form)
        expect(privacy.exists) == true
        let terms = app.descendants(matching: .any)["Terms of use"].firstMatch
        reveal(terms, in: form)
        expect(terms.exists) == true
        app.buttons["Done"].tap()
        app.terminate()
        _ = startWriting()
        let title = "Expired export " + UUID().uuidString.prefix(8)
        app.buttons["document-actions"].tap()
        app.buttons["Rename"].tap()
        let titleField = app.alerts.textFields.firstMatch
        titleField.tap()
        titleField.typeText(String(
            repeating: XCUIKeyboardKey.delete.rawValue,
            count: (titleField.value as? String)?.count ?? 0,
        ) + title)
        app.alerts.buttons["Save"].tap()
        app.textViews["manuscript"].tap()
        app.textViews["manuscript"].typeText("\nPreserved after subscription expiration.\n")
        expectation(for: NSPredicate(format: "label == %@", "Saved"), evaluatedWith: app.staticTexts["save-status"])
        waitForExpectations(timeout: 30)
        let manuscript = app.textViews["manuscript"].value as? String
        try session.expireSubscription(productIdentifier: "app.leftblank.writer.ipad.monthly")
        app.terminate()
        app.launch()
        expect(app.buttons["library-actions"].waitForExistence(timeout: 30)) == true
        app.buttons["library-actions"].tap()
        app.buttons["Settings"].tap()
        app.buttons["subscription-settings"].tap()
        expect(form.waitForExistence(timeout: 30)) == true
        // StoreKitTest's imperative expiration needs a sync to invalidate cached signed status.
        reveal(restore, in: form)
        restore.tap()
        reveal(app.staticTexts["subscription-status"], in: form, scrollingUp: false)
        expectation(
            for: NSPredicate(format: "label BEGINSWITH %@", "Your subscription has expired"),
            evaluatedWith: app.staticTexts["subscription-status"],
        )
        waitForExpectations(timeout: 30)
        app.buttons["Done"].tap()
        expect(banner.exists) == true
        app.staticTexts[title].tap()
        expect(app.textViews["manuscript"].waitForExistence(timeout: 30)) == true
        expect(app.textViews["manuscript"].value as? String) == manuscript
        app.buttons["document-actions"].tap()
        app.buttons["export-project"].tap()
        expectShareSheet(in: app)
        capture("Expired subscription project export")
    }

    func testWelcomePreviewAndPDFExport() {
        let app = startWriting(template: "welcome")
        capture("English writing")
        expect((app.textViews["manuscript"].value as? String)?.contains("leftblank-mark.svg")) == true
        app.buttons["layout-preview"].tap()
        expectation(
            for: NSPredicate(format: "value == %@", "Preview Updated"),
            evaluatedWith: app.staticTexts["engine-status"],
        )
        waitForExpectations(timeout: 60)
        expect(app.buttons["preview-error"].exists) == false
        capture("Welcome rendered")
        app.buttons["check-source"].tap()
        expect(app.navigationBars["Check Source"].waitForExistence(timeout: 10)) == true
        expect(app.buttons.matching(NSPredicate(format: "value == %@", "error")).count) == 0
        expect(app.buttons["unknown font family: noto sans sc"].exists) == false
        capture("Welcome diagnostics")
        app.buttons["Done"].tap()
        app.buttons["document-actions"].tap()
        app.buttons["Export PDF…"].tap()
        expectShareSheet(in: app)
        capture("Welcome PDF sharing")
    }

    func testChineseWelcomePreview() {
        let app = startWriting(template: "welcome", language: "zh-Hans")
        expect((app.textViews["manuscript"].value as? String)?.contains("此中有真意")) == true
        app.buttons["layout-preview"].tap()
        expectation(
            for: NSPredicate(format: "value == %@", "排版已更新"),
            evaluatedWith: app.staticTexts["engine-status"],
        )
        waitForExpectations(timeout: 60)
        expect(app.buttons["preview-error"].exists) == false
        capture("Chinese welcome rendered")
        app.buttons["check-source"].tap()
        expect(app.navigationBars["检查源码"].waitForExistence(timeout: 10)) == true
        expect(app.buttons.matching(NSPredicate(format: "value == %@", "error")).count) == 0
        expect(app.buttons["unknown font family: noto sans sc"].exists) == false
        capture("Chinese welcome diagnostics")
    }

    func testEditingPersistsAcrossPreviewAndRotation() {
        let app = startWriting()
        app.buttons["layout-preview"].tap()
        expectation(
            for: NSPredicate(format: "value == %@", "Preview Updated"),
            evaluatedWith: app.staticTexts["engine-status"],
        )
        waitForExpectations(timeout: 30)
        app.buttons["layout-writing"].tap()
        let editor = app.textViews["manuscript"]
        editor.tap()
        editor.press(forDuration: 1.2)
        let selectAll = app.descendants(matching: .any)["Select All"].firstMatch
        expect(selectAll.waitForExistence(timeout: 10)) == true
        selectAll.tap()
        editor.typeText("= iPad writing\nA shared local document.\n")
        expect(editor.value as? String) == "= iPad writing\nA shared local document.\n"
        let saved = NSPredicate(format: "label == %@", "Saved")
        expectation(for: saved, evaluatedWith: app.staticTexts["save-status"])
        waitForExpectations(timeout: 30)
        let rendered = NSPredicate(format: "label == %@", "Preview Updated")
        expectation(for: rendered, evaluatedWith: app.staticTexts["engine-status"])
        waitForExpectations(timeout: 60)
        app.buttons["layout-preview"].tap()
        expect(app.webViews.firstMatch.waitForExistence(timeout: 30)) == true
        expectation(
            for: NSPredicate(format: "value == %@", "Preview Updated"),
            evaluatedWith: app.staticTexts["engine-status"],
        )
        waitForExpectations(timeout: 20)
        let screenshot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        screenshot.lifetime = .keepAlways
        add(screenshot)
        XCUIDevice.shared.orientation = .portrait
        app.buttons["layout-writing"].tap()
        expect((app.textViews["manuscript"].value as? String)?.contains("iPad writing")) == true
        app.buttons["document-actions"].tap()
        app.buttons["Export PDF…"].tap()
        expectShareSheet(in: app)
    }

    func testCommandInsertionAndPDFExport() {
        let app = startWriting()
        let original = app.textViews["manuscript"].value as? String
        app.buttons["commands"].tap()
        expect(app.navigationBars["Discover Commands"].waitForExistence(timeout: 10)) == true
        app.buttons["command-heading"].tap()
        app.buttons["Insert"].tap()
        let editor = app.textViews["manuscript"]
        expect(editor.waitForExistence(timeout: 10)) == true
        expect((editor.value as? String)?.contains("=")) == true
        let inserted = editor.value as? String
        app.buttons["commands"].tap()
        app.buttons["Undo"].tap()
        expectation(for: NSPredicate { _, _ in editor.value as? String == original }, evaluatedWith: app)
        waitForExpectations(timeout: 10)
        app.buttons["commands"].tap()
        app.buttons["Redo"].tap()
        expectation(for: NSPredicate { _, _ in editor.value as? String == inserted }, evaluatedWith: app)
        waitForExpectations(timeout: 10)
        let ready = NSPredicate(format: "label IN %@", ["Ready", "Preview Updated"])
        expectation(for: ready, evaluatedWith: app.staticTexts["engine-status"])
        waitForExpectations(timeout: 60)
        app.buttons["document-actions"].tap()
        app.buttons["Export PDF…"].tap()
        expectShareSheet(in: app)
        capture("Command PDF sharing")
    }

    func testPreviewTapRevealsSourcePosition() {
        let app = startWriting()
        let editor = app.textViews["manuscript"]
        editor.tap()
        editor.press(forDuration: 1.2)
        let selectAll = app.descendants(matching: .any)["Select All"].firstMatch
        expect(selectAll.waitForExistence(timeout: 10)) == true
        selectAll.tap()
        editor.typeText("= Source navigation\nTap this paragraph to reveal its source.\n")
        app.buttons["layout-preview"].tap()
        expectation(
            for: NSPredicate(format: "value == %@", "Preview Updated"),
            evaluatedWith: app.staticTexts["engine-status"],
        )
        waitForExpectations(timeout: 60)
        let preview = app.webViews.firstMatch
        expect(preview.waitForExistence(timeout: 10)) == true
        let screenshot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        screenshot.lifetime = .keepAlways
        add(screenshot)
        // The page fits the preview width; use page-scaled coordinates so the
        // paragraph stays the target on both 11-inch and 13-inch devices.
        let paragraphY = preview.frame.width * 0.157 / preview.frame.height
        preview.coordinate(withNormalizedOffset: CGVector(dx: 0.2, dy: paragraphY)).tap()
        let revealed = NSPredicate { _, _ in editor.isHittable }
        expectation(for: revealed, evaluatedWith: app)
        waitForExpectations(timeout: 15)
        expect((app.staticTexts["source-position"].value as? String)?.hasPrefix("1:")) == true
        expect(editor.value as? String) == "= Source navigation\nTap this paragraph to reveal its source.\n"
    }

    func testTemplateDiscoveryAndPackageImport() {
        let app = startWriting()
        let original = app.textViews["manuscript"].value as? String
        app.buttons["sidebar-toggle"].tap()
        expect(app.staticTexts["library-title"].waitForExistence(timeout: 10)) == true
        expect(app.staticTexts["library-title"].label) == "Your writing"
        capture("Library landscape")
        expect(app.buttons["Show Sidebar"].exists) == false
        app.buttons["library-actions"].tap()
        expect(app.buttons["Settings"].waitForExistence(timeout: 10)) == true
        capture("Library actions")
        app.buttons["Settings"].tap()
        expect(app.navigationBars["Settings"].waitForExistence(timeout: 10)) == true
        app.buttons["Done"].tap()
        app.buttons["new-document"].tap()
        expect(app.navigationBars["Templates & Packages"].waitForExistence(timeout: 10)) == true
        expect(app.navigationBars["Templates & Packages"].frame.width) > app.frame.width * 0.7
        capture("Templates landscape")
        let search = app.textFields["universe.search"]
        expect(search.waitForExistence(timeout: 10)) == true
        expect(search.placeholderValue) == "Find a resume, paper, presentation…"
        search.tap()
        search.typeText("basic-resume")
        let resume = app.descendants(matching: .any)["universe.result.basic-resume"].firstMatch
        expect(resume.waitForExistence(timeout: 20)) == true
        search.typeText("\n")
        XCUIDevice.shared.orientation = .portrait
        expect(resume.waitForExistence(timeout: 10)) == true
        expect(search.value as? String) == "basic-resume"
        capture("Templates portrait")
        resume.tap()
        let templateApply = app.buttons["universe.apply"]
        expect(templateApply.waitForExistence(timeout: 10)) == true
        expect(templateApply.isHittable) == true
        capture("Template details portrait")
        XCUIDevice.shared.orientation = .landscapeLeft
        let landscape = NSPredicate { _, _ in
            templateApply.isHittable && search.isHittable && resume.isHittable
        }
        expectation(for: landscape, evaluatedWith: app)
        waitForExpectations(timeout: 15)
        expect(templateApply.isHittable) == true
        expect(search.isHittable) == true
        expect(resume.isHittable) == true
        capture("Template details landscape")
        app.buttons["universe.back-results"].tap()
        expect(search.waitForExistence(timeout: 10)) == true
        expect(search.value as? String) == "basic-resume"
        app.buttons["universe.clear-search"].tap()
        app.buttons["Writing tools"].tap()
        expect(search.placeholderValue) == "Try diagrams, plots, code blocks…"
        capture("Packages landscape")
        search.tap()
        search.typeText("cetz")
        let package = app.descendants(matching: .any)["universe.result.cetz"].firstMatch
        expect(package.waitForExistence(timeout: 20)) == true
        search.typeText("\n")
        package.tap()
        let apply = app.buttons["universe.apply"]
        expect(apply.waitForExistence(timeout: 10)) == true
        expect(apply.label) == "Insert Import"
        expect(search.isHittable) == true
        expect(package.isHittable) == true
        capture("Package details landscape")
        apply.tap()
        let editor = app.textViews["manuscript"]
        let imported = NSPredicate { _, _ in
            editor.isHittable && (editor.value as? String)?.contains("#import \"@preview/cetz:") == true
        }
        expectation(for: imported, evaluatedWith: app)
        waitForExpectations(timeout: 15)
        let source = editor.value as? String ?? ""
        let importLines = source.split(separator: "\n").filter { $0.hasPrefix("#import ") }
        expect(importLines.count) == 1
        expect(importLines.first?.hasSuffix("\"")) == true
        let preserved = source.split(separator: "\n").filter { !$0.hasPrefix("#import ") }
        expect(preserved) == (original ?? "").split(separator: "\n")
    }
}

import Nimble
import XCTest

@MainActor
final class WritingTests: XCTestCase {
    override func setUp() {
        super.setUp()
        continueAfterFailure = false
    }

    override func tearDown() {
        XCUIApplication().terminate()
        super.tearDown()
    }

    private func startWriting(template: String = "blank", language: String = "en") -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-AppleLanguages", "(en)", "-AppleLocale", "en_US", "-appLanguage", language,
                               "-iPadCloudEnabled", "NO"]
        XCUIDevice.shared.orientation = .landscapeLeft
        app.launch()
        let create = app.buttons["new-document"]
        if !create.waitForExistence(timeout: 3) || !create.isHittable {
            let sidebar = app.buttons["sidebar-toggle"]
            expect(sidebar.waitForExistence(timeout: 60)) == true
            sidebar.tap()
        }
        expect(create.waitForExistence(timeout: 60)) == true
        let enabled = NSPredicate { _, _ in create.isEnabled && create.isHittable }
        expectation(for: enabled, evaluatedWith: app)
        waitForExpectations(timeout: 60)
        create.tap()
        app.buttons["universe.builtin." + template].tap()
        expect(app.textViews["manuscript"].waitForExistence(timeout: 60)) == true
        let settled = NSPredicate { _, _ in !app.progressIndicators["document-loading"].exists }
        expectation(for: settled, evaluatedWith: app)
        waitForExpectations(timeout: 60)
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

    func testWelcomePreviewAndPDFExport() {
        let app = startWriting(template: "welcome")
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
        expect(app.descendants(matching: .any)["Save to Files"].firstMatch.waitForExistence(timeout: 30)) == true
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
        expect(app.descendants(matching: .any)["Save to Files"].firstMatch.waitForExistence(timeout: 30)) == true
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
        let share = app.descendants(matching: .any)["Save to Files"].firstMatch
        let visible = share.waitForExistence(timeout: 30)
        let screenshot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        screenshot.lifetime = .keepAlways
        add(screenshot)
        expect(visible) == true
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

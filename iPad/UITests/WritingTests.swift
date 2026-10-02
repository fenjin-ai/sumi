import Nimble
import XCTest

@MainActor
final class WritingTests: XCTestCase {
    private func startWriting() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-AppleLanguages", "(en)", "-AppleLocale", "en_US", "-iPadCloudEnabled", "NO"]
        XCUIDevice.shared.orientation = .landscapeLeft
        app.launch()
        let create = app.buttons["new-document"]
        if !create.waitForExistence(timeout: 3), app.buttons["document-actions"].exists {
            app.buttons["document-actions"].tap()
        }
        expect(create.waitForExistence(timeout: 60)) == true
        let enabled = NSPredicate { _, _ in create.isEnabled && create.isHittable }
        expectation(for: enabled, evaluatedWith: app)
        waitForExpectations(timeout: 60)
        create.tap()
        app.buttons["Blank page"].tap()
        expect(app.textViews["manuscript"].waitForExistence(timeout: 60)) == true
        let settled = NSPredicate { _, _ in !app.progressIndicators["document-loading"].exists }
        expectation(for: settled, evaluatedWith: app)
        waitForExpectations(timeout: 60)
        return app
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
        app.buttons["commands"].tap()
        expect(app.navigationBars["Discover Commands"].waitForExistence(timeout: 10)) == true
        app.buttons["command-heading"].tap()
        app.buttons["Insert"].tap()
        let editor = app.textViews["manuscript"]
        expect(editor.waitForExistence(timeout: 10)) == true
        expect((editor.value as? String)?.contains("=")) == true
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
        app.buttons["document-actions"].tap()
        app.buttons["Templates & Packages"].tap()
        expect(app.navigationBars["Templates & Packages"].waitForExistence(timeout: 10)) == true
        let search = app.searchFields.firstMatch
        expect(search.waitForExistence(timeout: 10)) == true
        search.tap()
        search.typeText("basic-resume")
        let resume = app.descendants(matching: .any)["universe.result.basic-resume"].firstMatch
        expect(resume.waitForExistence(timeout: 20)) == true
        let gallery = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        gallery.lifetime = .keepAlways
        add(gallery)
        search.buttons["Clear text"].tap()
        app.buttons["Writing tools"].tap()
        search.tap()
        search.typeText("cetz")
        let package = app.descendants(matching: .any)["universe.result.cetz"].firstMatch
        expect(package.waitForExistence(timeout: 20)) == true
        package.tap()
        let apply = app.buttons["universe.apply"]
        expect(apply.waitForExistence(timeout: 10)) == true
        expect(apply.label) == "Insert Import"
        apply.tap()
        let editor = app.textViews["manuscript"]
        expect(editor.waitForExistence(timeout: 10)) == true
        let source = editor.value as? String ?? ""
        expect(source.contains("#import \"@preview/cetz:")) == true
        expect(source.hasSuffix(original ?? "")) == true
    }
}

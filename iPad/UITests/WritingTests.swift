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
}

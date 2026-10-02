import Nimble
import XCTest

@MainActor
final class WritingTests: XCTestCase {
    private func startWriting() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        XCUIDevice.shared.orientation = .landscapeLeft
        app.launch()
        let create = app.buttons["new-document"]
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
        let editor = app.textViews["manuscript"]
        editor.tap()
        editor.typeText("\n= iPad writing\nA shared local document.\n")
        expect((editor.value as? String)?.contains("iPad writing")) == true
        let saved = NSPredicate(format: "label == %@", "Saved")
        expectation(for: saved, evaluatedWith: app.staticTexts["save-status"])
        waitForExpectations(timeout: 30)
        app.segmentedControls["editor-layout"].buttons["Preview"].tap()
        expect(app.webViews.firstMatch.waitForExistence(timeout: 30)) == true
        XCUIDevice.shared.orientation = .portrait
        app.segmentedControls["editor-layout"].buttons["Writing"].tap()
        expect((app.textViews["manuscript"].value as? String)?.contains("iPad writing")) == true
    }

    func testCommandInsertionAndPDFExport() {
        let app = startWriting()
        app.buttons["commands"].tap()
        expect(app.navigationBars["Discover Commands"].waitForExistence(timeout: 10)) == true
        app.buttons["Heading"].firstMatch.tap()
        app.buttons["Insert"].tap()
        let editor = app.textViews["manuscript"]
        expect(editor.waitForExistence(timeout: 10)) == true
        expect((editor.value as? String)?.contains("=")) == true
        let ready = NSPredicate(format: "label IN %@", ["Ready", "Preview Updated"])
        expectation(for: ready, evaluatedWith: app.staticTexts["engine-status"])
        waitForExpectations(timeout: 60)
        app.buttons["document-actions"].tap()
        app.buttons["Export PDF…"].tap()
        expect(app.buttons["Copy"].waitForExistence(timeout: 60)) == true
    }
}

#if SUMI_PREVIEW
import AppKit
import Sparkle
import SumiCore

/// Sparkle owns consent, scheduling, download verification and installation UI.
/// Creating this object performs no network work; startup follows window setup.
@MainActor
final class PreviewUpdater: NSObject, NSMenuItemValidation {
    let controller: SPUStandardUpdaterController

    override init() {
        controller = SPUStandardUpdaterController(startingUpdater: false, updaterDelegate: nil, userDriverDelegate: nil)
        super.init()
    }

    func start() {
        // A SwiftPM test executable has no app update identity or signing keys.
        guard Bundle.main.bundleIdentifier == AppDistribution.preview.bundleIdentifier else { return }
        controller.startUpdater()
    }

    func makeCheckMenuItem() -> NSMenuItem {
        let item = NSMenuItem(title: L10n.text("Check for Updates…"), action: #selector(SPUStandardUpdaterController.checkForUpdates(_:)), keyEquivalent: "")
        item.target = controller
        item.identifier = NSUserInterfaceItemIdentifier("preview.checkForUpdates")
        return item
    }

    func makeAutomaticChecksMenuItem() -> NSMenuItem {
        let item = NSMenuItem(title: L10n.text("Automatically Check for Updates"), action: #selector(toggleAutomaticChecks(_:)), keyEquivalent: "")
        item.target = self
        item.identifier = NSUserInterfaceItemIdentifier("preview.automaticChecks")
        return item
    }

    @objc private func toggleAutomaticChecks(_ sender: NSMenuItem) {
        // Keep a single source of truth in Sparkle; only explicit user actions
        // write this preference. Info.plist requires confirmation to install.
        controller.updater.automaticallyChecksForUpdates.toggle()
    }

    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        guard menuItem.action == #selector(toggleAutomaticChecks(_:)) else { return false }
        menuItem.state = controller.updater.automaticallyChecksForUpdates ? .on : .off
        return true
    }
}
#endif

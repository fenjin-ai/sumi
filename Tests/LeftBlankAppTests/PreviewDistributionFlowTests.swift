import AppKit
import Testing
import LeftBlankCore
import LeftBlankAutomation
@testable import LeftBlankApp
#if LEFTBLANK_PREVIEW
import Sparkle
#endif

extension WritingFlowTests {
    @Test func distributionUsesMatchingAppAndAgentIdentity() async throws {
        let app = try WritingFixture(text: "A separate preview", startService: false)
        defer { app.close() }
        let suite = "LeftBlank.preview.test." + UUID().uuidString
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let settings = WorkspaceSettings(workspace: app.workspace, defaults: defaults)
        defer { settings.stop() }
        #expect(settings.connectionCommand.contains("codex mcp add " + AppDistribution.current.agentName + " --"))
        #expect(AutomationContract.defaultStateDirectory == AppDistribution.defaultStateDirectory)
        let previousMenu = NSApp.mainMenu, previousWindowsMenu = NSApp.windowsMenu
        defer { NSApp.mainMenu = previousMenu; NSApp.windowsMenu = previousWindowsMenu }
        let delegate = AppDelegate(workspace: app.workspace)
        delegate.installMenu()
        let appMenu = try #require(NSApp.mainMenu?.items.first?.submenu)
        #expect(appMenu.title == AppDistribution.current.applicationName)
        let check = appMenu.items.first { $0.identifier?.rawValue == "preview.checkForUpdates" }
        #if LEFTBLANK_PREVIEW
        #expect(AppDistribution.current == .preview)
        #expect(!LibraryCloudEnvironment.preferenceSyncAvailable())
        #expect(throws: LibraryError.self) { try LibraryCloudEnvironment.containerURL() }
        #expect(check?.target is SPUStandardUpdaterController)
        let controller = try #require(check?.target as? SPUStandardUpdaterController)
        #expect(!controller.updater.sessionInProgress, "Menu construction must not check the network")
        #else
        #expect(AppDistribution.current == .standard)
        #expect(check == nil, "Direct and App Store builds must not expose an external updater")
        #endif
    }

    #if LEFTBLANK_PREVIEW
    @Test func sparkleAcceptsIncreasingBuildNumbersWithoutMarketingVersionBumps() throws {
        let comparator = SUStandardVersionComparator()
        #expect(comparator.compareVersion("9.1", toVersion: "10.1") == .orderedAscending)
        #expect(comparator.compareVersion("10.1", toVersion: "10.2") == .orderedAscending)
        #expect(comparator.compareVersion("10.2", toVersion: "10.1") == .orderedDescending)
        #expect(comparator.compareVersion("10.2", toVersion: "10.2") == .orderedSame)
        let updater = PreviewUpdater()
        let check = updater.makeCheckMenuItem()
        #expect(check.target === updater.controller)
        #expect(check.action == #selector(SPUStandardUpdaterController.checkForUpdates(_:)))
        let automatic = updater.makeAutomaticChecksMenuItem()
        #expect(updater.validateMenuItem(automatic))
        #expect(automatic.state == (updater.controller.updater.automaticallyChecksForUpdates ? .on : .off))
        let original = updater.controller.updater.automaticallyChecksForUpdates
        defer { updater.controller.updater.automaticallyChecksForUpdates = original }
        let action = try #require(automatic.action)
        #expect(NSApp.sendAction(action, to: automatic.target, from: automatic))
        #expect(updater.controller.updater.automaticallyChecksForUpdates != original)
        #expect(updater.validateMenuItem(automatic))
        #expect(automatic.state == (original ? .off : .on))
        #expect(NSApp.sendAction(action, to: automatic.target, from: automatic))
        #expect(updater.controller.updater.automaticallyChecksForUpdates == original)
        updater.start()
        #expect(!updater.controller.updater.sessionInProgress)
        #expect(!updater.validateMenuItem(check))
    }
    #endif
}

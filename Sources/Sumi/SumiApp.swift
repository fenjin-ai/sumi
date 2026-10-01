import AppKit
import Combine
import SumiCore
import SwiftUI

public enum SumiApplication {
    @MainActor public static func main() {
        let application = NSApplication.shared
        let delegate = AppDelegate()
        application.delegate = delegate
        application.setActivationPolicy(.regular)
        application.run()
        withExtendedLifetime(delegate) {}
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    private let workspace: Workspace
    private var window: NSWindow!
    private var windowToolbar: WindowToolbar?
    private var settingsWindow: NSWindow?
    private var settingsController: WorkspaceSettings?
    private var languageObserver: AnyCancellable?

    init(workspace: Workspace = Workspace()) {
        self.workspace = workspace
        super.init()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        installMenu()
        NSApp.appearance = NSAppearance(named: .darkAqua)
        let writingWindow = WritingWindow(contentRect: NSRect(x: 0, y: 0, width: 1220, height: 820), styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
        writingWindow.workspace = workspace
        window = writingWindow
        window.title = workspace.title + " — Sumi"
        window.titleVisibility = .hidden
        window.toolbarStyle = .unifiedCompact
        windowToolbar = WindowToolbar(workspace: workspace)
        window.toolbar = windowToolbar?.makeToolbar()
        window.backgroundColor = NSColor(hex: 0x171A1D)
        window.minSize = NSSize(width: 820, height: 580)
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.contentView = NSHostingView(rootView: ContentView(workspace: workspace))
        window.setFrameAutosaveName("SumiMainWindow")
        window.center()
        window.makeKeyAndOrderFront(nil)
        workspace.onTitleChange = { [weak self] title in self?.window.title = title + " — Sumi" }
        workspace.onShortcutChange = { [weak self] in self?.installMenu() }
        settingsController = WorkspaceSettings(workspace: workspace)
        languageObserver = NotificationCenter.default.publisher(for: .sumiLanguageChanged).sink { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.installMenu()
                self?.settingsWindow?.title = L10n.text("Settings")
                if let self { self.window.title = self.workspace.title + " — Sumi" }
            }
        }
        workspace.startService()
        Task { await workspace.library.start() }
        NSApp.activate(ignoringOtherApps: true)
        DispatchQueue.main.async { [weak self] in
            guard let self, !self.workspace.paletteOpen, let editor = self.workspace.editor else { return }
            self.window.makeFirstResponder(editor)
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        window?.makeFirstResponder(nil)
        return workspace.prepareToClose() ? .terminateNow : .terminateCancel
    }
    func windowShouldClose(_ sender: NSWindow) -> Bool { NSApp.terminate(nil); return false }
    func applicationWillTerminate(_ notification: Notification) {
        settingsController?.stop()
        workspace.shutdown()
    }
    func application(_ sender: NSApplication, openFiles filenames: [String]) {
        if let path = filenames.first { workspace.open(URL(fileURLWithPath: path)) }
    }

    func installMenu() {
        let menu = NSMenu()
        func section(_ title: String) -> NSMenu {
            let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
            let submenu = NSMenu(title: title)
            menu.addItem(item); item.submenu = submenu
            return submenu
        }
        func item(_ title: String, _ action: Selector, _ key: String, _ owner: NSMenu, modifiers: NSEvent.ModifierFlags = .command, target: AnyObject? = nil) {
            let entry = NSMenuItem(title: title, action: action, keyEquivalent: key)
            entry.keyEquivalentModifierMask = modifiers
            entry.target = target
            owner.addItem(entry)
        }
        func commandItem(_ id: String, in menu: NSMenu) {
            guard let command = WritingCommand.all.first(where: { $0.id == id }), let shortcut = command.shortcuts.first else { return }
            let entry = NSMenuItem(title: command.title, action: #selector(runWritingCommand(_:)), keyEquivalent: shortcut.key)
            var flags: NSEvent.ModifierFlags = []
            if shortcut.modifiers.contains(.command) { flags.insert(.command) }
            if shortcut.modifiers.contains(.shift) { flags.insert(.shift) }
            if shortcut.modifiers.contains(.option) { flags.insert(.option) }
            if shortcut.modifiers.contains(.control) { flags.insert(.control) }
            entry.keyEquivalentModifierMask = flags
            entry.representedObject = id; entry.target = self
            menu.addItem(entry)
        }
        let app = section("Sumi")
        item(L10n.text("About Sumi"), #selector(about), "", app, target: self)
        item(L10n.text("Settings…"), #selector(settings), ",", app, target: self)
        app.addItem(.separator())
        item(L10n.text("Hide Sumi"), #selector(NSApplication.hide(_:)), "h", app)
        item(L10n.text("Quit Sumi"), #selector(NSApplication.terminate(_:)), "q", app)
        let file = section(L10n.text("Documents"))
        item(L10n.text("New Document"), #selector(newDocument), "n", file, target: self)
        item(L10n.text("Your writing…"), #selector(openLibrary), "o", file, target: self)
        item(L10n.text("Import a document…"), #selector(importDocument), "o", file, modifiers: [.command, .shift], target: self)
        item(L10n.text("Open external file…"), #selector(openDocument), "", file, target: self)
        file.addItem(.separator())
        item(L10n.text("Save"), #selector(saveDocument), "s", file, target: self)
        item(L10n.text("Save As…"), #selector(saveAs), "s", file, modifiers: [.command, .shift], target: self)
        item(L10n.text("Recover Draft Copy…"), #selector(recoverDraft), "", file, target: self)
        item(L10n.text("Export PDF…"), #selector(exportPDF), "e", file, modifiers: [.command, .shift], target: self)
        file.addItem(.separator())
        item(L10n.text("Close Window"), #selector(NSWindow.performClose(_:)), "w", file)
        let edit = section(L10n.text("Edit"))
        item(L10n.text("Undo"), Selector(("undo:")), "z", edit)
        item(L10n.text("Redo"), Selector(("redo:")), "z", edit, modifiers: [.command, .shift])
        edit.addItem(.separator())
        item(L10n.text("Cut"), #selector(NSText.cut(_:)), "x", edit)
        item(L10n.text("Copy"), #selector(NSText.copy(_:)), "c", edit)
        item(L10n.text("Paste"), #selector(NSText.paste(_:)), "v", edit)
        item(L10n.text("Select All"), #selector(NSText.selectAll(_:)), "a", edit)
        edit.addItem(.separator())
        item(L10n.text("Find…"), #selector(find), "f", edit, target: self)
        item(L10n.text("Complete Syntax"), #selector(completion), ".", edit, modifiers: .control, target: self)
        for id in ["indent", "outdent", "comment", "format"] { commandItem(id, in: edit) }
        let view = section(L10n.text("View"))
        item(L10n.text("Discover Commands"), #selector(palette), workspace.commandKey, view, target: self)
        item(L10n.text("Open Diagnostic Logs"), #selector(revealLogs), "", view, target: self)
        item(L10n.text("Focus on Writing"), #selector(writing), "1", view, target: self)
        item(L10n.text("Side-by-side Preview"), #selector(split), "2", view, target: self)
        item(L10n.text("Read the Preview"), #selector(preview), "3", view, target: self)
        for id in ["outline", "diagnostics", "universe"] { commandItem(id, in: view) }
        view.addItem(.separator())
        item(L10n.text("Increase Text Size"), #selector(increaseFont), "+", view, target: self)
        item(L10n.text("Decrease Text Size"), #selector(decreaseFont), "-", view, target: self)
        let windowMenu = section(L10n.text("Window"))
        item(L10n.text("Minimize"), #selector(NSWindow.performMiniaturize(_:)), "m", windowMenu)
        item(L10n.text("Zoom"), #selector(NSWindow.performZoom(_:)), "", windowMenu)
        NSApp.windowsMenu = windowMenu
        NSApp.mainMenu = menu
    }

    @objc private func runWritingCommand(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? String, let command = WritingCommand.all.first(where: { $0.id == id }) else { return }
        workspace.execute(command)
    }
    @objc private func about() {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "development"
        NSApp.orderFrontStandardAboutPanel(options: [.applicationName: "Sumi", .applicationVersion: version, .credits: NSAttributedString(string: L10n.text("A quiet space to write."))])
    }
    @objc private func settings() {
        if settingsController == nil { settingsController = WorkspaceSettings(workspace: workspace) }
        guard let settingsController else { return }
        if settingsWindow == nil {
            let panel = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 530, height: 640), styleMask: [.titled, .closable], backing: .buffered, defer: false)
            panel.isReleasedWhenClosed = false
            panel.contentView = NSHostingView(rootView: WritingSettingsView(workspace: workspace, settings: settingsController, library: workspace.library))
            panel.center()
            settingsWindow = panel
        }
        settingsWindow?.title = L10n.text("Settings")
        settingsWindow?.makeKeyAndOrderFront(nil)
    }
    @objc private func openLibrary() { workspace.libraryOpen = true }
    @objc private func importDocument() { workspace.library.importPanel() }
    @objc private func newDocument() { workspace.newDocument() }
    @objc private func openDocument() { workspace.openPanel() }
    @objc private func recoverDraft() { workspace.openPanel(recovery: true) }
    @objc private func saveDocument() { workspace.save() }
    @objc private func saveAs() { workspace.saveAs() }
    @objc private func exportPDF() { workspace.exportPDF() }
    @objc private func palette() { workspace.togglePalette() }
    @objc private func revealLogs() { workspace.revealLogs() }
    @objc private func writing() { workspace.layout = .writing }
    @objc private func split() { workspace.layout = .split }
    @objc private func preview() { workspace.layout = .preview }
    @objc private func increaseFont() { workspace.fontSize = min(28, workspace.fontSize + 1) }
    @objc private func decreaseFont() { workspace.fontSize = max(12, workspace.fontSize - 1) }
    @objc private func completion() { workspace.requestCompletion() }
    @objc private func find() {
        let sender = NSMenuItem()
        sender.tag = NSTextFinder.Action.showFindInterface.rawValue
        workspace.editor?.performFindPanelAction(sender)
    }
}

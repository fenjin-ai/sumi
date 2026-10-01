import AppKit
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
        workspace.startService()
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
        item("关于 Sumi", #selector(about), "", app, target: self)
        item("设置…", #selector(settings), ",", app, target: self)
        app.addItem(.separator())
        item("隐藏 Sumi", #selector(NSApplication.hide(_:)), "h", app)
        item("退出 Sumi", #selector(NSApplication.terminate(_:)), "q", app)
        let file = section("文件")
        item("新建文稿", #selector(newDocument), "n", file, target: self)
        item("打开…", #selector(openDocument), "o", file, target: self)
        file.addItem(.separator())
        item("保存", #selector(saveDocument), "s", file, target: self)
        item("另存为…", #selector(saveAs), "s", file, modifiers: [.command, .shift], target: self)
        item("恢复草稿副本…", #selector(recoverDraft), "", file, target: self)
        item("导出 PDF…", #selector(exportPDF), "e", file, modifiers: [.command, .shift], target: self)
        file.addItem(.separator())
        item("关闭窗口", #selector(NSWindow.performClose(_:)), "w", file)
        let edit = section("编辑")
        item("撤销", Selector(("undo:")), "z", edit)
        item("重做", Selector(("redo:")), "z", edit, modifiers: [.command, .shift])
        edit.addItem(.separator())
        item("剪切", #selector(NSText.cut(_:)), "x", edit)
        item("复制", #selector(NSText.copy(_:)), "c", edit)
        item("粘贴", #selector(NSText.paste(_:)), "v", edit)
        item("全选", #selector(NSText.selectAll(_:)), "a", edit)
        edit.addItem(.separator())
        item("查找…", #selector(find), "f", edit, target: self)
        item("补全 Typst", #selector(completion), ".", edit, modifiers: .control, target: self)
        for id in ["indent", "outdent", "comment", "format"] { commandItem(id, in: edit) }
        let view = section("视图")
        item("发现命令", #selector(palette), workspace.commandKey, view, target: self)
        item("打开诊断日志", #selector(revealLogs), "", view, target: self)
        item("专注写作", #selector(writing), "1", view, target: self)
        item("并排预览", #selector(split), "2", view, target: self)
        item("阅读成稿", #selector(preview), "3", view, target: self)
        for id in ["outline", "diagnostics", "universe"] { commandItem(id, in: view) }
        view.addItem(.separator())
        item("放大文字", #selector(increaseFont), "+", view, target: self)
        item("缩小文字", #selector(decreaseFont), "-", view, target: self)
        let windowMenu = section("窗口")
        item("最小化", #selector(NSWindow.performMiniaturize(_:)), "m", windowMenu)
        item("缩放", #selector(NSWindow.performZoom(_:)), "", windowMenu)
        NSApp.windowsMenu = windowMenu
        NSApp.mainMenu = menu
    }

    @objc private func runWritingCommand(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? String, let command = WritingCommand.all.first(where: { $0.id == id }) else { return }
        workspace.execute(command)
    }
    @objc private func about() {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "development"
        NSApp.orderFrontStandardAboutPanel(options: [.applicationName: "Sumi", .applicationVersion: version, .credits: NSAttributedString(string: "给想法一点留白。\nA quiet space to write.")])
    }
    @objc private func settings() {
        let alert = NSAlert()
        alert.messageText = "写作习惯"
        alert.informativeText = "选择发现命令的快捷键。正文空格和常规 macOS 编辑快捷键始终保留。"
        let selector = NSPopUpButton(frame: NSRect(x: 0, y: 0, width: 250, height: 28))
        selector.addItems(withTitles: ["⌘J · 发现命令", "⌘K · 发现命令"])
        selector.selectItem(at: workspace.commandKey == "k" ? 1 : 0)
        selector.setAccessibilityLabel("命令入口快捷键")
        alert.accessoryView = selector
        alert.addButton(withTitle: "完成")
        alert.addButton(withTitle: "取消")
        if alert.runModal() == .alertFirstButtonReturn { workspace.commandKey = selector.indexOfSelectedItem == 1 ? "k" : "j" }
    }
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

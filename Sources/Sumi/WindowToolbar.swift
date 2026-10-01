import AppKit
import SwiftUI
import Combine
import SumiCore

@MainActor
final class WindowToolbar: NSObject, NSToolbarDelegate {
    private let workspace: Workspace
    private let documentID = NSToolbarItem.Identifier("SumiDocument")
    private let actionsID = NSToolbarItem.Identifier("SumiActions")

    private let titleSize = ToolbarTitleSize()
    private var subscriptions: Set<AnyCancellable> = []

    init(workspace: Workspace) {
        self.workspace = workspace
        super.init()
        Publishers.CombineLatest(workspace.$managedTitle, workspace.$fileURL)
            .receive(on: RunLoop.main).sink { [weak self] _ in self?.resizeTitle() }.store(in: &subscriptions)
        NotificationCenter.default.publisher(for: NSWindow.didResizeNotification, object: workspace.window)
            .sink { [weak self] _ in self?.resizeTitle() }.store(in: &subscriptions)
        resizeTitle()
    }

    private func resizeTitle() {
        let textWidth = (workspace.title as NSString).size(withAttributes: [.font: NSFont.systemFont(ofSize: 12, weight: .medium)]).width
        // Reserve traffic lights, native toolbar spacing and the fixed actions.
        // A short title hugs its content; long names can use the remaining space.
        let available = max(120, (workspace.window?.frame.width ?? 820) - 340)
        let width = min(available, max(160, ceil(textWidth) + 64))
        if titleSize.width != width { titleSize.width = width }
    }

    func makeToolbar() -> NSToolbar {
        let toolbar = NSToolbar(identifier: "SumiToolbar")
        toolbar.delegate = self
        toolbar.displayMode = .iconOnly
        toolbar.allowsUserCustomization = false
        return toolbar
    }

    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        [documentID, .flexibleSpace, actionsID]
    }

    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        toolbarDefaultItemIdentifiers(toolbar)
    }

    func toolbar(_ toolbar: NSToolbar, itemForItemIdentifier identifier: NSToolbarItem.Identifier, willBeInsertedIntoToolbar flag: Bool) -> NSToolbarItem? {
        let item = NSToolbarItem(itemIdentifier: identifier)
        if identifier == documentID {
            item.label = L10n.text("Current Document")
            item.view = NSHostingView(rootView: AdaptiveDocumentTitle(workspace: workspace, size: titleSize))
        } else if identifier == actionsID {
            item.label = L10n.text("Writing Views and Export")
            item.view = NSHostingView(rootView: WritingActions(workspace: workspace).frame(height: 30))
        } else { return nil }
        return item
    }
}

@MainActor
private final class ToolbarTitleSize: ObservableObject {
    @Published var width: CGFloat = 240
}

private struct AdaptiveDocumentTitle: View {
    let workspace: Workspace
    @ObservedObject var size: ToolbarTitleSize
    var body: some View { DocumentTitle(workspace: workspace).frame(width: size.width, height: 30) }
}

private struct DocumentTitle: View {
    @ObservedObject var workspace: Workspace
    @ObservedObject private var localization = AppLocalization.shared
    var body: some View {
        HStack(spacing: 8) {
            Button { workspace.openLibrary() } label: {
                PhosphorIcon(name: "books", size: 16).foregroundStyle(Theme.muted).frame(width: 26, height: 30)
            }.buttonStyle(.plain).accessibilityLabel(L10n.text("Your writing"))
                .learningHelp(L10n.text("Your writing"), shortcut: "⌘O")
            EditableDocumentName(title: workspace.title, documentID: workspace.managedDocumentID,
                onOpen: { workspace.openLibrary() },
                onRename: { [id = workspace.managedDocumentID] title in
                    guard let id else { return }
                    workspace.library.perform { try await workspace.library.rename(id, title: title) }
                },
                onFinish: { workspace.editor?.window?.makeFirstResponder(workspace.editor) })
                .frame(height: 16).frame(height: 30)
                .learningHelp(L10n.text("Click to rename. Double-click to open your writing."))
            if workspace.text != workspace.savedText, workspace.fileURL != nil {
                Circle().fill(Theme.accent).frame(width: 5, height: 5).accessibilityLabel(L10n.text("Unsaved"))
            }
        }.frame(height: 30).foregroundStyle(Theme.text)
    }
}

private struct WritingActions: View {
    @ObservedObject var workspace: Workspace
    @ObservedObject private var localization = AppLocalization.shared
    var body: some View {
        HStack(spacing: 10) {
            QuietButton(icon: "pencil-simple", help: L10n.text("Focus on Writing"), shortcut: WritingCommand.all.first { $0.id == "writing" }?.shortcuts.first?.label, detail: L10n.text("A quiet space for your words."), active: workspace.layout == .writing) { workspace.layout = .writing }
            QuietButton(icon: "columns", help: L10n.text("Side-by-side Preview"), shortcut: WritingCommand.all.first { $0.id == "split" }?.shortcuts.first?.label, detail: L10n.text("Write on the left, see the live page on the right."), active: workspace.layout == .split) { workspace.layout = .split }
            QuietButton(icon: "eye", help: L10n.text("Read the Preview"), shortcut: WritingCommand.all.first { $0.id == "preview" }?.shortcuts.first?.label, detail: L10n.text("Fill the workspace with your finished pages."), active: workspace.layout == .preview) { workspace.layout = .preview }
            Rectangle().fill(Theme.border).frame(width: 1, height: 14)
            QuietButton(icon: "arrow-square-out", help: L10n.text("Export PDF"), shortcut: WritingCommand.all.first { $0.id == "export" }?.shortcuts.first?.label, detail: L10n.text("Export the current document in its original colors.")) { workspace.exportPDF() }.disabled(workspace.exporting)
        }.fixedSize().disabled(workspace.isLibraryHome)
    }
}

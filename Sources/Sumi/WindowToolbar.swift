import AppKit
import SwiftUI

@MainActor
final class WindowToolbar: NSObject, NSToolbarDelegate {
    private let workspace: Workspace
    private let documentID = NSToolbarItem.Identifier("SumiDocument")
    private let actionsID = NSToolbarItem.Identifier("SumiActions")

    init(workspace: Workspace) { self.workspace = workspace }

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
            item.label = "当前文稿"
            item.view = NSHostingView(rootView: DocumentTitle(workspace: workspace).frame(width: 240, height: 30))
        } else if identifier == actionsID {
            item.label = "写作视图与导出"
            item.view = NSHostingView(rootView: WritingActions(workspace: workspace).frame(height: 30))
        } else { return nil }
        return item
    }
}

private struct DocumentTitle: View {
    @ObservedObject var workspace: Workspace
    var body: some View {
        HStack(spacing: 8) {
            Text(workspace.title).font(.system(size: 12, weight: .medium)).lineLimit(1).truncationMode(.middle)
            if workspace.text != workspace.savedText, workspace.fileURL != nil {
                Circle().fill(Theme.accent).frame(width: 5, height: 5).accessibilityLabel("尚未保存")
            }
            Spacer(minLength: 0)
        }.foregroundStyle(Theme.text).preferredColorScheme(.dark)
    }
}

private struct WritingActions: View {
    @ObservedObject var workspace: Workspace
    var body: some View {
        HStack(spacing: 10) {
            QuietButton(icon: "list", help: "文稿大纲", active: workspace.sidePanel == .outline) { workspace.sidePanel = workspace.sidePanel == .outline ? nil : .outline }
            Rectangle().fill(Theme.border).frame(width: 1, height: 14)
            QuietButton(icon: "pencil-simple", help: "专注写作", active: workspace.layout == .writing) { workspace.layout = .writing }
            QuietButton(icon: "columns", help: "并排预览", active: workspace.layout == .split) { workspace.layout = .split }
            QuietButton(icon: "eye", help: "阅读成稿", active: workspace.layout == .preview) { workspace.layout = .preview }
            Rectangle().fill(Theme.border).frame(width: 1, height: 14)
            QuietButton(icon: "arrow-square-out", help: "导出 PDF") { workspace.exportPDF() }.disabled(workspace.exporting)
        }.fixedSize().preferredColorScheme(.dark)
    }
}

import LeftBlankCore
import SwiftUI

@available(iOS 18.0, *)
struct TabletUniverseSizing: PresentationSizing {
    let windowSize: CGSize

    func proposedSize(for _: PresentationSizingRoot, context _: PresentationSizingContext) -> ProposedViewSize {
        let margin: CGFloat = windowSize.width >= 700 ? 64 : 0
        return ProposedViewSize(
            width: min(1120, max(320, windowSize.width - margin)),
            height: min(1100, max(320, windowSize.height - 32)),
        )
    }
}

struct TabletPanel: View {
    @ObservedObject var workspace: TabletWorkspace
    let panel: TabletWorkspace.Panel
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @State private var command: WritingCommand?
    @State private var values: [String: String] = [:]
    @State private var language = L10n.language

    var body: some View {
        NavigationStack {
            Group {
                switch panel {
                case .commands: commands
                case .outline: outline
                case .checks: checks
                case .history: history
                case .settings: settings
                case .universe: TabletUniverseBrowser(workspace: workspace)
                case .trash: trash
                }
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button(L10n.text("Done")) { dismiss() } } }
        }.tint(TabletTheme.accent)
    }

    private var title: String {
        switch panel {
        case .commands: L10n.text("Discover Commands")
        case .outline: L10n.text("Outline")
        case .checks: L10n.text("Check Source")
        case .history: L10n.text("Document History")
        case .settings: L10n.text("Settings")
        case .universe: L10n.text("Templates & Packages")
        case .trash: L10n.text("Trash")
        }
    }

    private var commands: some View {
        List {
            if let command {
                Section(command.title) {
                    Text(command.detail).foregroundStyle(.secondary)
                    ForEach(command.fields) { field in
                        TextField(
                            field.title,
                            text: Binding(get: { values[field.id] ?? field.initial }, set: { values[field.id] = $0 }),
                        )
                        .autocorrectionDisabled().textInputAutocapitalization(.never)
                    }
                    Button(L10n.text("Insert")) { workspace.insert(command, values: values) }
                    Button(L10n.text("Back")) { self.command = nil }
                }
            } else {
                Section {
                    Button(L10n.text("Undo")) { workspace.editor?.undoManager?.undo()
                        dismiss()
                    }
                    Button(L10n.text("Redo")) { workspace.editor?.undoManager?.redo()
                        dismiss()
                    }
                    Button(L10n.text("Indent")) { workspace.lineAction(.indent)
                        dismiss()
                    }
                    Button(L10n.text("Outdent")) { workspace.lineAction(.outdent)
                        dismiss()
                    }
                    Button(L10n.text("Toggle Comment")) { workspace.lineAction(.comment)
                        dismiss()
                    }
                    Button(L10n.text("Format Document")) { Task { await workspace.format() } }
                        .disabled(!workspace.serviceReady)
                }
                ForEach(CommandGroup.all) { group in
                    let choices = WritingCommand.search(query).filter { $0.isInsertion && $0.group == group.id }
                    if !choices.isEmpty {
                        Section(group.title) {
                            ForEach(choices) { item in
                                Button { command = item
                                    values = Dictionary(uniqueKeysWithValues: item.fields.map { ($0.id, $0.initial) })
                                } label: {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(item.title)
                                        Text(item.detail).font(.subheadline).foregroundStyle(.secondary)
                                    }.padding(.vertical, 4)
                                }.accessibilityIdentifier("command-" + item.id)
                            }
                        }
                    }
                }
            }
        }.searchable(text: $query, prompt: L10n.text("Search Commands"))
    }

    private var outline: some View {
        List {
            ForEach(Array(headings(workspace.outline).enumerated()), id: \.offset) { _, item in
                Button(item["name"].string ?? "") {
                    let position = item["selectionRange"]["start"]
                    workspace.jump(TextPosition(
                        line: position["line"].int ?? 0,
                        character: position["character"].int ?? 0,
                    ))
                }.frame(minHeight: 44)
            }
        }.overlay {
            if workspace.outline.isEmpty {
                TabletEmptyState(title: L10n.text("Outline"), icon: "list-bullets")
            }
        }
    }

    private func headings(_ nodes: [JSONValue]) -> [JSONValue] {
        nodes.flatMap { node in
            (node["kind"].int == 3 ? [node] : []) + headings(node["children"].array)
        }
    }

    private var checks: some View {
        List {
            Text(L10n.text(workspace.serviceStatus)).foregroundStyle(.secondary)
            ForEach(Array(workspace.diagnostics.enumerated()), id: \.offset) { _, item in
                Button {
                    let position = item["range"]["start"]
                    workspace.jump(TextPosition(
                        line: position["line"].int ?? 0,
                        character: position["character"].int ?? 0,
                    ))
                } label: {
                    Label { Text(item["message"].string ?? "") } icon: { TabletIcon(name: "warning-circle") }
                        .foregroundStyle(.primary)
                }
                .accessibilityValue(item["severity"].int == 1 ? "error" : "warning")
            }
            if workspace.diagnostics.isEmpty {
                Label { Text(L10n.text("No issues found")) } icon: { TabletIcon(name: "check") }
            }
        }
    }

    private var history: some View {
        List(workspace.revisions) { revision in
            NavigationLink {
                TabletRevision(workspace: workspace, revision: revision)
            } label: {
                VStack(alignment: .leading) {
                    Text(revision.createdAt, format: .dateTime.month().day().hour().minute())
                    Text(ByteCountFormatter.string(fromByteCount: Int64(revision.bytes), countStyle: .file))
                        .font(.subheadline).foregroundStyle(.secondary)
                }.padding(.vertical, 6)
            }
        }.overlay {
            if workspace.revisions.isEmpty {
                TabletEmptyState(title: L10n.text("No history yet"), icon: "clock-counter-clockwise")
            }
        }
    }

    private var trash: some View {
        List(workspace.trashedDocuments) { item in
            HStack {
                Text(item.title)
                Spacer()
                Button(L10n.text("Restore")) { Task { await workspace.restoreDocument(item) } }.buttonStyle(.bordered)
            }
        }
    }

    private var settings: some View {
        Form {
            Section(L10n.text("Writing")) {
                Stepper(
                    L10n.format("Text size: %@", String(Int(workspace.fontSize))),
                    value: $workspace.fontSize,
                    in: 12 ... 28,
                )
                Picker(L10n.text("Language"), selection: $language) {
                    Text(L10n.text("Follow System")).tag(AppLanguage.system)
                    Text("English").tag(AppLanguage.english)
                    Text("简体中文").tag(AppLanguage.simplifiedChinese)
                }.onChange(of: language) { _, language in L10n.setLanguage(language) }
            }
            Section("iCloud") {
                Toggle(
                    L10n.text("iCloud Sync"),
                    isOn: Binding(
                        get: { workspace.cloudEnabled },
                        set: { enabled in Task { await workspace.setCloud(enabled) } },
                    ),
                )
                .disabled(workspace.busy)
            }
        }
    }
}

private struct TabletRevision: View {
    @ObservedObject var workspace: TabletWorkspace
    let revision: DocumentRevision
    @State private var confirming = false
    @State private var source = ""

    var body: some View {
        Form {
            Text(revision.createdAt, format: .dateTime)
            ScrollView { Text(source).font(.system(.body, design: .monospaced)).textSelection(.enabled) }
            Text(L10n.text("Your current writing will be preserved before restoring this version."))
            Button(L10n.text("Restore")) { confirming = true }
        }.task {
            do { source = try await workspace.revisionSource(revision) }
            catch { workspace.message = error.localizedDescription }
        }.confirmationDialog(L10n.text("Restore this version?"), isPresented: $confirming) {
            Button(L10n.text("Restore")) { Task { await workspace.restore(revision) } }
        }
        .navigationBarBackButtonHidden()
        .toolbar { ToolbarItem(placement: .topBarLeading) { TabletBackButton(title: L10n.text("Back")) } }
    }
}

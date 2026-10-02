import LeftBlankCore
import SwiftUI

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
                case .universe: universe
                case .trash: trash
                }
            }
            .navigationTitle(title)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button(L10n.text("Done")) { dismiss() } } }
        }
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
                ContentUnavailableView(L10n.text("Outline"), systemImage: "list.bullet")
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
                    Label(item["message"].string ?? "", systemImage: "exclamationmark.circle").foregroundStyle(.primary)
                }
            }
            if workspace.diagnostics.isEmpty {
                Label(L10n.text("No issues found"), systemImage: "checkmark.circle")
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
                ContentUnavailableView(L10n.text("No history yet"), systemImage: "clock")
            }
        }
    }

    private var universe: some View {
        List(workspace.packages
            .filter { query.isEmpty || ($0.name + " " + $0.description).localizedCaseInsensitiveContains(query)
            }) { package in
                VStack(alignment: .leading, spacing: 10) {
                    Text(package.name).font(.headline)
                    Text(package.description).font(.subheadline).foregroundStyle(.secondary)
                    Text(package.reference).font(.caption.monospaced())
                    HStack {
                        Link(L10n.text("Documentation"), destination: package.documentationURL)
                        Spacer()
                        if package.isTemplate {
                            Button(L10n.text("Use Template")) { Task { await workspace.createTemplate(package) } }
                                .disabled(workspace.busy || !package
                                    .isCompatible(with: "0.15.1"))
                        } else {
                            Button(L10n.text("Insert Import")) { workspace.addPackage(package) }
                                .disabled(workspace.document == nil)
                        }
                    }.buttonStyle(.bordered)
                }.padding(.vertical, 8)
            }.searchable(text: $query, prompt: L10n.text("Search Packages"))
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
                    ForEach(AppLanguage.allCases, id: \.self) { language in Text(language.displayName).tag(language) }
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
    }
}

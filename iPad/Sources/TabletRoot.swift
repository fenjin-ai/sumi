import LeftBlankCore
import SwiftUI
import UniformTypeIdentifiers

struct TabletRoot: View {
    @ObservedObject var workspace: TabletWorkspace
    @State private var column: NavigationSplitViewColumn = .sidebar
    @State private var query = ""
    @State private var importing = false
    @State private var importingProject = false
    @State private var renaming = false
    @State private var title = ""

    var body: some View {
        NavigationSplitView(preferredCompactColumn: $column) {
            List {
                ForEach(workspace.documents
                    .filter { query.isEmpty || $0.title.localizedCaseInsensitiveContains(query) })
                { item in
                    Button {
                        Task { await workspace.open(item)
                            if workspace.document?.id == item.id {
                                column = .detail
                            }
                        }
                    } label: {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(item.title).font(.headline).foregroundStyle(.primary)
                            Text(item.snippet).font(.subheadline).foregroundStyle(.secondary).lineLimit(2)
                        }.padding(.vertical, 6)
                    }.disabled(workspace.busy)
                        .swipeActions(allowsFullSwipe: false) {
                            Button(L10n.text("Move to Trash"), role: .destructive) {
                                Task { await workspace.trash(item) }
                            }
                        }
                }
            }
            .navigationTitle(L10n.text("Your writing"))
            .searchable(text: $query, prompt: L10n.text("Search"))
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        ForEach(BuiltInTemplate.allCases) { template in
                            Button(template.title) { Task { await workspace.create(template)
                                column = .detail
                            } }
                        }
                        Button(L10n.text("Import a document…")) { importing = true }
                        Button(L10n.text("Import Project…")) { importingProject = true }
                        Button(L10n.text("Templates & Packages")) { Task { await workspace.showUniverse() } }
                        Button(SampleBook.sicp.title) { Task { await workspace.addSampleBook() } }
                    } label: { Label(L10n.text("New Document"), systemImage: "square.and.pencil") }
                        .disabled(workspace.busy).accessibilityIdentifier("new-document")
                }
                ToolbarItem(placement: .bottomBar) {
                    Menu {
                        Button(L10n.text("Settings")) { workspace.panel = .settings }
                        Button(L10n.text("Trash")) { Task { await workspace.showTrash() } }
                    } label: { Label(
                        L10n.text("Settings"),
                        systemImage: "gearshape",
                    ) }
                }
            }
        } detail: {
            if workspace.document != nil {
                writing
            } else {
                ContentUnavailableView(
                    L10n.text("Your writing"),
                    systemImage: "doc.text",
                    description: Text(L10n.text("Choose a document to begin writing.")),
                )
            }
        }
        .tint(TabletTheme.accent)
        .fileImporter(
            isPresented: $importing,
            allowedContentTypes: [.plainText, UTType(filenameExtension: "typ") ?? .plainText],
        ) { result in
            switch result {
            case let .success(url): Task { await workspace.importDocument(url)
                    column = .detail
                }
            case let .failure(error): workspace.message = error.localizedDescription
            }
        }
        .environment(\.locale, L10n.locale)
        .onReceive(NotificationCenter.default.publisher(for: .leftblankLanguageChanged)) { _ in
            workspace.objectWillChange.send()
        }
        .fileImporter(isPresented: $importingProject, allowedContentTypes: [.folder]) { result in
            switch result {
            case let .success(url): Task { await workspace.importProject(url)
                    column = .detail
                }
            case let .failure(error): workspace.message = error.localizedDescription
            }
        }
        .sheet(item: $workspace.panel) { panel in
            TabletPanel(workspace: workspace, panel: panel)
                .presentationDetents(panel == .commands ? [.large] : [.medium, .large])
        }
        .sheet(isPresented: Binding(get: { workspace.shareURL != nil }, set: {
            if !$0 {
                workspace.shareURL = nil
            }
        })) {
            if let url = workspace.shareURL {
                TabletShare(url: url)
            }
        }
        .alert(
            L10n.text("Save Needs Attention"),
            isPresented: Binding(get: { workspace.message != nil }, set: {
                if !$0 {
                    workspace.message = nil
                }
            }),
        ) {
            Button(L10n.text("OK")) { workspace.message = nil }
        } message: { Text(workspace.message ?? "") }
        .alert(L10n.text("Rename"), isPresented: $renaming) {
            TextField(L10n.text("Title"), text: $title)
            Button(L10n.text("Save")) { Task { await workspace.rename(title) } }
            Button(L10n.text("Cancel"), role: .cancel) {}
        }
    }

    private var writing: some View {
        GeometryReader { geometry in
            let sideBySide = geometry.size.width >= 800 && workspace.layout == .split
            let reading = workspace.layout == .preview
            VStack(spacing: 0) {
                Picker(L10n.text("View"), selection: $workspace.layout) {
                    Text(L10n.text("Writing")).tag(TabletWorkspace.Layout.writing)
                    if geometry.size
                        .width >= 800
                    {
                        Text(L10n.text("Side-by-side Preview")).tag(TabletWorkspace.Layout.split)
                    }
                    Text(L10n.text("Preview")).tag(TabletWorkspace.Layout.preview)
                }.accessibilityIdentifier("editor-layout").pickerStyle(.segmented).padding(.horizontal).padding(
                    .vertical,
                    8,
                )
                HStack(spacing: 0) {
                    TabletEditor(workspace: workspace)
                        .frame(width: reading ? 0 : sideBySide ? geometry.size.width / 2 : geometry.size.width)
                        .clipped().opacity(reading ? 0 : 1).accessibilityHidden(reading)
                    ZStack {
                        TabletPreview(url: workspace.previewURL)
                        if workspace.previewURL == nil {
                            ContentUnavailableView(
                                L10n.text("Your words are becoming pages"),
                                systemImage: "doc.text",
                                description: Text(L10n.text(workspace.serviceStatus)),
                            )
                        }
                    }.frame(width: reading ? geometry.size.width : sideBySide ? geometry.size.width / 2 : 0)
                        .clipped().opacity(reading || sideBySide ? 1 : 0).accessibilityHidden(!reading && !sideBySide)
                }
                HStack {
                    Text(L10n.text(workspace.saveStatus)).accessibilityIdentifier("save-status")
                    Text(L10n.text(workspace.serviceStatus)).accessibilityIdentifier("engine-status")
                    Spacer()
                    Text(L10n.format("%@ words", String(DocumentMetrics(workspace.text).wordCount)))
                    Button { workspace.panel = .checks } label: {
                        Image(systemName: workspace.diagnostics
                            .isEmpty ? "checkmark.circle" : "exclamationmark.circle")
                    }
                    .accessibilityLabel(L10n.text("Check Source")).frame(minWidth: 44, minHeight: 44)
                }.font(.footnote).foregroundStyle(.secondary).padding(.horizontal)
            }
            .overlay {
                if workspace.busy {
                    ProgressView().accessibilityIdentifier("document-loading")
                }
            }
            .onChange(of: geometry.size.width) { _, width in
                if width < 800, workspace.layout == .split {
                    workspace.layout = .writing
                }
            }
            .onAppear {
                if geometry.size.width < 800, workspace.layout == .split {
                    workspace.layout = .writing
                }
            }
        }
        .navigationTitle(workspace.document?.title ?? L10n.text("Untitled"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { workspace.panel = .commands } label: { Label(
                    L10n.text("Discover Commands"),
                    systemImage: "command",
                ) }
                .keyboardShortcut("j").accessibilityIdentifier("commands")
            }
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button(L10n.text("Outline")) { workspace.panel = .outline }.keyboardShortcut("4")
                    Button(L10n.text("Document History…")) { Task { await workspace.showHistory() } }
                    Button(L10n.text("Rename")) { title = workspace.document?.title ?? ""
                        renaming = true
                    }
                    Button(L10n.text("Save")) { Task { await workspace.save() } }.keyboardShortcut("s")
                    Button(L10n.text("Export PDF…")) { Task { await workspace.exportPDF() } }
                        .keyboardShortcut("e", modifiers: [.command, .shift]).disabled(!workspace.serviceReady)
                    Button(L10n.text("Templates & Packages")) { Task { await workspace.showUniverse() } }
                    Button(L10n.text("Reconnect")) { Task { await workspace.connect() } }
                } label: { Label(L10n.text("Documents"), systemImage: "ellipsis.circle") }
                    .accessibilityIdentifier("document-actions")
            }
        }
        .onChange(of: workspace.layout) { _, layout in
            if layout == .preview {
                workspace.editor?.resignFirstResponder()
            }
        }
    }
}

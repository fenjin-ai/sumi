import LeftBlankCore
import SwiftUI
import UniformTypeIdentifiers

struct TabletRoot: View {
    @ObservedObject var workspace: TabletWorkspace
    @State private var column: NavigationSplitViewColumn = .sidebar
    @State private var visibility: NavigationSplitViewVisibility = .all
    @State private var detailWidth: CGFloat = 0
    @State private var windowSize: CGSize = .zero
    @State private var query = ""
    @State private var importing = false
    @State private var importingProject = false
    @State private var renaming = false
    @State private var title = ""

    var body: some View {
        NavigationSplitView(columnVisibility: $visibility, preferredCompactColumn: $column) {
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
                        VStack(alignment: .leading, spacing: 3) {
                            Text(item.title).font(.system(size: 15, weight: .medium)).foregroundStyle(.primary)
                            Text(item.snippet).font(.system(size: 12)).foregroundStyle(.secondary).lineLimit(1)
                        }.padding(.vertical, 3)
                    }.disabled(workspace.busy)
                        .swipeActions(allowsFullSwipe: false) {
                            Button(L10n.text("Move to Trash"), role: .destructive) {
                                Task { await workspace.trash(item) }
                            }
                        }
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .background(TabletTheme.background)
            .safeAreaInset(edge: .top, spacing: 0) { libraryHeader }
            .navigationSplitViewColumnWidth(min: 280, ideal: 320, max: 400)
            .toolbar(removing: .sidebarToggle)
            .toolbar(.hidden, for: .navigationBar)
        } detail: {
            Group {
                if workspace.document != nil {
                    writing
                } else {
                    TabletEmptyState(
                        title: L10n.text("Your writing"),
                        icon: "book-open-text",
                        detail: L10n.text("Choose a document to begin writing."),
                    )
                    .toolbar { ToolbarItem(placement: .topBarLeading) { sidebarToggle } }
                }
            }.toolbar(removing: .sidebarToggle)
        }
        .tint(TabletTheme.accent)
        .onChange(of: workspace.document?.id) { _, id in
            if id != nil {
                visibility = .detailOnly
                column = .detail
            }
        }
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
        .background {
            GeometryReader { geometry in
                Color.clear.onChange(of: geometry.size, initial: true) { _, size in windowSize = size }
            }
        }
        .sheet(item: panelBinding) { panel in
            if panel == .universe, #available(iOS 18.0, *) {
                TabletPanel(workspace: workspace, panel: panel)
                    .presentationSizing(TabletUniverseSizing(windowSize: windowSize))
            } else {
                TabletPanel(workspace: workspace, panel: panel)
                    .presentationDetents(panel == .commands ? [.large] : [.medium, .large])
            }
        }
        .fullScreenCover(isPresented: legacyUniverseBinding) {
            TabletPanel(workspace: workspace, panel: .universe)
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

    private var libraryHeader: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(L10n.text("Your writing")).font(.system(size: 23, weight: .medium, design: .serif))
                .foregroundStyle(Color(uiColor: TabletTheme.nativeText))
                .fixedSize(horizontal: false, vertical: true).accessibilityIdentifier("library-title")
            HStack(spacing: 4) {
                HStack(spacing: 8) {
                    TabletIcon(name: "magnifying-glass", size: 15).foregroundStyle(TabletTheme.secondary)
                    TextField(L10n.text("Search"), text: $query).font(.system(size: 13))
                        .textFieldStyle(.plain).autocorrectionDisabled()
                        .accessibilityIdentifier("library-search")
                }.padding(.horizontal, 10).frame(height: 44)
                    .background(Color(uiColor: TabletTheme.nativeEditor), in: RoundedRectangle(cornerRadius: 8))
                Button { workspace.showUniverse() } label: {
                    TabletIcon(name: "grid-four").frame(width: 44, height: 44)
                }.buttonStyle(.plain).disabled(workspace.busy)
                    .accessibilityLabel(L10n.text("Browse templates")).accessibilityIdentifier("new-document")
                Menu {
                    Button { importing = true } label: {
                        Label { Text(L10n.text("Import a document…")) } icon: { TabletIcon.menuImage(
                            "file-text",
                            title: L10n.text("Import a document…"),
                        ) }
                    }
                    Button { importingProject = true } label: {
                        Label { Text(L10n.text("Import Project…")) } icon: { TabletIcon.menuImage(
                            "folder-open",
                            title: L10n.text("Import Project…"),
                        ) }
                    }
                    Divider()
                    Button { workspace.panel = .settings } label: {
                        Label { Text(L10n.text("Settings")) } icon: { TabletIcon.menuImage(
                            "gear",
                            title: L10n.text("Settings"),
                        ) }
                    }
                    Button { Task { await workspace.showTrash() } } label: {
                        Label { Text(L10n.text("Trash")) } icon: { TabletIcon.menuImage(
                            "trash",
                            title: L10n.text("Trash"),
                        ) }
                    }
                } label: {
                    TabletIcon(name: "dots-three-vertical").frame(width: 44, height: 44)
                }.buttonStyle(.plain).accessibilityLabel(L10n.text("Library actions"))
                    .accessibilityIdentifier("library-actions")
            }
        }.padding(16).foregroundStyle(TabletTheme.secondary).background(TabletTheme.background)
            .overlay(alignment: .bottom) { Rectangle().fill(TabletTheme.border).frame(height: 0.5) }
    }

    private var sidebarToggle: some View {
        Button {
            withAnimation {
                if windowSize.width < 700 {
                    column = .sidebar
                    visibility = .all
                } else {
                    visibility = visibility == .all ? .detailOnly : .all
                }
            }
        } label: {
            TabletIcon(name: "sidebar-simple").frame(width: 44, height: 44)
        }.buttonStyle(.plain).foregroundStyle(TabletTheme.secondary)
            .accessibilityLabel(L10n.text("Browse Library")).accessibilityIdentifier("sidebar-toggle")
    }

    private var panelBinding: Binding<TabletWorkspace.Panel?> {
        Binding(get: {
            if #available(iOS 18.0, *) {
                return workspace.panel
            }
            return workspace.panel == .universe ? nil : workspace.panel
        }, set: { workspace.panel = $0 })
    }

    private var legacyUniverseBinding: Binding<Bool> {
        Binding(get: {
            if #available(iOS 18.0, *) {
                return false
            }
            return workspace.panel == .universe
        }, set: { presented in
            if !presented, workspace.panel == .universe {
                workspace.panel = nil
            }
        })
    }

    private var writing: some View {
        GeometryReader { geometry in
            let sideBySide = geometry.size.width >= 800 && workspace.layout == .split
            let reading = workspace.layout == .preview
            VStack(spacing: 0) {
                HStack(spacing: 0) {
                    TabletEditor(workspace: workspace)
                        .frame(width: reading ? 0 : sideBySide ? geometry.size.width / 2 : geometry.size.width)
                        .clipped().opacity(reading ? 0 : 1).accessibilityHidden(reading)
                    ZStack {
                        TabletPreview(workspace: workspace)
                        if !workspace.previewReady {
                            TabletEmptyState(
                                title: L10n.text("Your words are becoming pages"),
                                icon: "file-text",
                                detail: workspace.previewIssue ?? L10n.text(workspace.serviceStatus),
                            )
                        }
                    }.overlay(alignment: .top) {
                        if workspace.serviceStatus == "Document Needs Attention" {
                            Button { workspace.panel = .checks } label: {
                                HStack(spacing: 8) {
                                    TabletIcon(name: "warning-circle", size: 16)
                                    Text(workspace.diagnostics.first(where: { $0["severity"].int == 1 })?["message"]
                                        .string ?? L10n.text("Document Needs Attention"))
                                        .font(.system(size: 12)).lineLimit(2)
                                    Spacer()
                                    Text(L10n.text("Check Source")).font(.system(size: 12, weight: .medium))
                                }.padding(12).frame(maxWidth: .infinity).background(TabletTheme.background)
                            }.buttonStyle(.plain).accessibilityIdentifier("preview-error")
                        }
                    }.overlay(alignment: .leading) {
                        if sideBySide {
                            Rectangle().fill(TabletTheme.border).frame(width: 0.5)
                        }
                    }.frame(width: reading ? geometry.size.width : sideBySide ? geometry.size.width / 2 : 0)
                        .clipped().opacity(reading || sideBySide ? 1 : 0).accessibilityHidden(!reading && !sideBySide)
                }
                HStack {
                    Text(L10n.text(workspace.saveStatus)).accessibilityIdentifier("save-status")
                    Text(L10n.text(workspace.serviceStatus)).accessibilityIdentifier("engine-status")
                        .accessibilityValue(workspace.previewReady ? L10n.text("Preview Updated") : L10n
                            .text("Waiting for Typesetting"))
                    Spacer()
                    let position = workspace.metrics.position(at: workspace.selection.location)
                    Text("\(position.line + 1):\(position.character + 1)")
                        .accessibilityIdentifier("source-position")
                        .accessibilityValue("\(position.line):\(position.character)")
                    Text(L10n.format("%@ words", String(workspace.metrics.wordCount)))
                    Button { workspace.panel = .checks } label: {
                        TabletIcon(name: workspace.diagnostics.isEmpty ? "check" : "warning-circle", size: 14)
                    }
                    .accessibilityLabel(L10n.text("Check Source")).frame(minWidth: 44, minHeight: 44)
                    .accessibilityIdentifier("check-source")
                }.font(.system(size: 11)).foregroundStyle(.secondary).padding(.horizontal, 14)
                    .background(TabletTheme.background)
                    .overlay(alignment: .top) { Rectangle().fill(TabletTheme.border).frame(height: 0.5) }
            }
            .overlay {
                if workspace.busy {
                    ProgressView().accessibilityIdentifier("document-loading")
                }
            }
            .onChange(of: geometry.size.width) { _, width in
                detailWidth = width
                if width < 800, workspace.layout == .split {
                    workspace.layout = .writing
                }
            }
            .onAppear {
                detailWidth = geometry.size.width
                if geometry.size.width < 800, workspace.layout == .split {
                    workspace.layout = .writing
                }
            }
        }
        .navigationTitle(workspace.document?.title ?? L10n.text("Untitled"))
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden()
        .toolbarBackground(TabletTheme.background, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) { sidebarToggle }
            ToolbarItem(placement: .principal) {
                Text(workspace.document?.title ?? L10n.text("Untitled")).font(.system(size: 15, weight: .medium))
                    .lineLimit(1)
            }
            ToolbarItemGroup(placement: .topBarTrailing) {
                layoutButton(.writing, icon: "pencil-simple", title: "Writing", key: "1")
                if detailWidth >= 800 {
                    layoutButton(.split, icon: "columns", title: "Side-by-side Preview", key: "2")
                }
                layoutButton(.preview, icon: "eye", title: "Preview", key: "3")
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button { workspace.panel = .commands } label: {
                    TabletIcon(name: "command").frame(width: 44, height: 44)
                }
                .accessibilityLabel(L10n.text("Discover Commands"))
                .keyboardShortcut("j").accessibilityIdentifier("commands")
            }
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button { workspace.showUniverse() } label: {
                        Label { Text(L10n.text("New Document")) } icon: { TabletIcon.menuImage(
                            "grid-four",
                            title: L10n.text("New Document"),
                        ) }
                    }.accessibilityIdentifier("new-document")
                    Button(L10n.text("Outline")) { workspace.panel = .outline }.keyboardShortcut("4")
                    Button(L10n.text("Document History…")) { Task { await workspace.showHistory() } }
                    Button(L10n.text("Rename")) { title = workspace.document?.title ?? ""
                        renaming = true
                    }
                    Button(L10n.text("Save")) { Task { await workspace.save() } }.keyboardShortcut("s")
                    Button(L10n.text("Export PDF…")) { Task { await workspace.exportPDF() } }
                        .keyboardShortcut("e", modifiers: [.command, .shift]).disabled(!workspace.serviceReady)
                    Button(L10n.text("Templates & Packages")) { workspace.showUniverse() }
                    Button(L10n.text("Reconnect")) { Task { await workspace.connect() } }
                } label: {
                    TabletIcon(name: "dots-three-vertical").frame(width: 44, height: 44)
                        .accessibilityLabel(L10n.text("Documents"))
                }
                .accessibilityIdentifier("document-actions")
            }
        }
        .onChange(of: workspace.layout) { _, layout in
            if layout == .preview {
                workspace.editor?.resignFirstResponder()
            }
        }
    }

    private func layoutButton(
        _ layout: TabletWorkspace.Layout,
        icon: String,
        title: String,
        key: KeyEquivalent,
    ) -> some View {
        Button { workspace.layout = layout } label: {
            TabletIcon(name: icon).frame(width: 44, height: 44)
                .foregroundStyle(workspace.layout == layout ? TabletTheme.accent : TabletTheme.secondary)
                .overlay(alignment: .bottom) {
                    if workspace
                        .layout == layout
                    {
                        Capsule().fill(TabletTheme.accent).frame(width: 10, height: 1.5).padding(
                            .bottom,
                            4,
                        )
                    }
                }
        }.buttonStyle(.plain).accessibilityLabel(L10n.text(title)).accessibilityIdentifier("layout-" + layout.rawValue)
            .accessibilityAddTraits(workspace.layout == layout ? .isSelected : [])
            .keyboardShortcut(key)
    }
}

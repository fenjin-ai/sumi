import SwiftUI
import SumiCore

@MainActor
final class UniverseBrowserModel: ObservableObject {
    @Published private(set) var snapshot: UniverseCatalogSnapshot?
    @Published private(set) var isLoading = false
    @Published private(set) var error: String?
    @Published var query = ""
    @Published var category = "visualization"
    @Published var selectedID: String?
    private let store: UniverseCatalogStore

    init(store: UniverseCatalogStore) { self.store = store }
    var results: [UniversePackage] { snapshot?.search(query, category: category) ?? [] }
    var selected: UniversePackage? { results.first { $0.id == selectedID } ?? results.first }

    func load(forceRefresh: Bool = false) async {
        guard !isLoading else { return }
        isLoading = true
        error = nil
        defer { isLoading = false }
        if snapshot == nil { snapshot = await store.cached() }
        do { snapshot = try await store.load(forceRefresh: forceRefresh) }
        catch is CancellationError { return }
        catch { self.error = error.localizedDescription }
    }
}

/// A metadata-only browser; the caller inserts the user's explicitly selected, pinned import.
struct UniverseBrowser: View {
    @ObservedObject private var localization = AppLocalization.shared
    private let onImport: (UniversePackage) throws -> Void
    private let compilerVersion: String
    @Environment(\.dismiss) private var dismiss
    @StateObject private var model: UniverseBrowserModel
    @State private var importError: String?
    @FocusState private var searchFocused: Bool

    init(cacheURL: URL, compilerVersion: String = "0.15.1", onImport: @escaping (UniversePackage) throws -> Void) {
        self.onImport = onImport
        self.compilerVersion = compilerVersion
        _model = StateObject(wrappedValue: UniverseBrowserModel(store: UniverseCatalogStore(cacheURL: cacheURL)))
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 7) {
                    Text("Typst Universe").font(.system(size: 24, weight: .medium, design: .serif)).foregroundStyle(Theme.text)
                    Text(L10n.text("Find the right tools for your document, from drawing to typesetting."))
                        .font(.system(size: 12)).foregroundStyle(Theme.secondary)
                }
                Spacer()
                Button(L10n.text("Done")) { dismiss() }.keyboardShortcut(.cancelAction).buttonStyle(.plain).foregroundStyle(Theme.secondary)
            }.padding(24)
            HStack(spacing: 12) {
                PhosphorIcon(name: "magnifying-glass", size: 16).foregroundStyle(Theme.muted)
                TextField(L10n.text("Search package names, uses or keywords"), text: $model.query)
                    .textFieldStyle(.plain).focused($searchFocused).accessibilityIdentifier("universe.search")
                Picker(L10n.text("Category"), selection: $model.category) {
                    ForEach(UniverseCategory.all) { category in Text(category.title).tag(category.id) }
                }.labelsHidden().frame(width: 156).accessibilityLabel(L10n.text("Universe package category"))
            }.font(.system(size: 13)).padding(.horizontal, 14).padding(.vertical, 10)
                .background(Theme.editor, in: RoundedRectangle(cornerRadius: 7)).padding(.horizontal, 24).padding(.bottom, 18)
            Rectangle().fill(Theme.border.opacity(0.7)).frame(height: 1)
            HStack(spacing: 0) {
                packageList.frame(width: 285)
                Rectangle().fill(Theme.border.opacity(0.7)).frame(width: 1)
                if let package = model.selected { details(package).id(package.reference) }
                else { emptyDetails }
            }.frame(maxHeight: .infinity)
            Rectangle().fill(Theme.border.opacity(0.7)).frame(height: 1)
            HStack(spacing: 12) {
                if model.isLoading { ProgressView().controlSize(.small).scaleEffect(0.75).frame(width: 14, height: 14) }
                Text(statusText).font(.system(size: 11)).foregroundStyle(model.snapshot?.source == .offlineCache ? Theme.accent : Theme.muted)
                    .lineLimit(2).frame(maxWidth: .infinity, alignment: .leading)
                Button(L10n.text("Refresh Index")) { Task { await model.load(forceRefresh: true) } }
                    .buttonStyle(.plain).font(.system(size: 12)).foregroundStyle(Theme.secondary).disabled(model.isLoading)
                    .keyboardShortcut("r", modifiers: .command)
            }.padding(.horizontal, 24).padding(.vertical, 14)
        }
        .frame(width: 790, height: 590).background(Theme.background).foregroundStyle(Theme.text)
        .preferredColorScheme(.dark)
        .task { searchFocused = true; await model.load() }
    }

    private var packageList: some View {
        let results = model.results
        let selectedID = model.selected?.id
        return ScrollView {
            LazyVStack(alignment: .leading, spacing: 3) {
                ForEach(results) { package in
                    Button { model.selectedID = package.id; importError = nil } label: {
                        VStack(alignment: .leading, spacing: 5) {
                            HStack {
                                Text(package.name).font(.system(size: 13, weight: .medium))
                                Spacer(minLength: 8)
                                Text(package.version).font(.system(size: 10, design: .monospaced)).foregroundStyle(Theme.muted)
                            }
                            Text(package.description).font(.system(size: 11)).foregroundStyle(Theme.secondary).lineLimit(2)
                        }.padding(12).frame(maxWidth: .infinity, alignment: .leading)
                            .background(selectedID == package.id ? Theme.border.opacity(0.5) : .clear, in: RoundedRectangle(cornerRadius: 6))
                    }.buttonStyle(.plain).accessibilityLabel(L10n.format("%@, version %@", package.name, package.version))
                }
            }.padding(10)
        }.overlay {
            if results.isEmpty && !model.isLoading {
                Text(model.snapshot == nil ? L10n.text("Index not loaded yet") : L10n.text("No matching packages\nTry another keyword or category."))
                    .font(.system(size: 12)).foregroundStyle(Theme.muted).multilineTextAlignment(.center).padding(22)
            }
        }
    }

    private func details(_ package: UniversePackage) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(package.name).font(.system(size: 25, weight: .medium, design: .serif))
                        Text(L10n.format("Version %@", package.version)).font(.system(size: 11, design: .monospaced)).foregroundStyle(Theme.accent)
                    }
                    Text(package.description).font(.system(size: 13)).lineSpacing(5).foregroundStyle(Theme.secondary).textSelection(.enabled)
                    Text(package.categories.map(UniverseCategory.title(for:)).joined(separator: " · "))
                        .font(.system(size: 11)).foregroundStyle(Theme.muted)
                    Rectangle().fill(Theme.border.opacity(0.6)).frame(height: 1)
                    VStack(alignment: .leading, spacing: 9) {
                        Text(L10n.text("Import into This Document")).font(.system(size: 11, weight: .medium)).foregroundStyle(Theme.secondary)
                        Text("#import \"\(package.reference)\"")
                            .font(.system(size: 11, design: .monospaced)).foregroundStyle(Theme.accent).textSelection(.enabled)
                            .padding(12).frame(maxWidth: .infinity, alignment: .leading).background(Theme.editor, in: RoundedRectangle(cornerRadius: 6))
                        Text(L10n.text("This version is pinned. Typst downloads and caches the package when needed. See the documentation for usage."))
                            .font(.system(size: 11)).lineSpacing(4).foregroundStyle(Theme.muted)
                    }
                    VStack(alignment: .leading, spacing: 7) {
                        Text(L10n.format("License  %@", package.license))
                        if let required = package.compiler { Text(L10n.format("Requires Typst %@ or later", required)) }
                        if !package.authors.isEmpty { Text(package.authors.joined(separator: " · ")).lineLimit(3) }
                    }.font(.system(size: 10)).foregroundStyle(Theme.muted)
                    if !package.isCompatible(with: compilerVersion) {
                        Text(L10n.format("The current engine is Typst %@. This package requires a newer version.", compilerVersion))
                            .font(.system(size: 11)).foregroundStyle(Theme.accent)
                    }
                }.frame(maxWidth: .infinity, alignment: .leading).padding(24)
            }
            VStack(alignment: .leading, spacing: 12) {
                if let importError { Text(importError).font(.system(size: 11)).foregroundStyle(Theme.red) }
                HStack {
                    Link(L10n.text("Documentation ↗"), destination: package.documentationURL).font(.system(size: 12)).foregroundStyle(Theme.secondary)
                    Spacer()
                    Button(L10n.text("Insert Import")) {
                        do { try onImport(package); dismiss() }
                        catch { importError = error.localizedDescription }
                    }.buttonStyle(.borderedProminent).tint(Theme.accent).foregroundStyle(Theme.background)
                        .disabled(!package.isCompatible(with: compilerVersion)).accessibilityIdentifier("universe.import")
                }
            }.padding(24).padding(.top, -8)
        }
    }

    private var emptyDetails: some View {
        VStack(spacing: 12) {
            Text(L10n.text("Make room for more ideas")).font(.system(size: 23, design: .serif)).foregroundStyle(Theme.secondary)
            Text(L10n.text("Try CeTZ for drawings or Fletcher for diagrams.\nChoose a package to read about it and see how to use it."))
                .font(.system(size: 12)).lineSpacing(6).foregroundStyle(Theme.muted).multilineTextAlignment(.center)
        }.frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var statusText: String {
        if let error = model.error { return error }
        guard let snapshot = model.snapshot else { return L10n.text("Connecting to packages.typst.org…") }
        let date = snapshot.fetchedAt.formatted(date: .abbreviated, time: .shortened)
        switch snapshot.source {
        case .network: return L10n.format("%@ packages · Updated %@", String(snapshot.packages.count), date)
        case .cache: return L10n.format("%@ packages · Local index %@", String(snapshot.packages.count), date)
        case .offlineCache: return L10n.format("Offline · Using index from %@ · %@ packages", date, String(snapshot.packages.count))
        }
    }
}

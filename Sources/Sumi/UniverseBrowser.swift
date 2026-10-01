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
                    Text("从绘图到排版，为文稿找到合适的工具。")
                        .font(.system(size: 12)).foregroundStyle(Theme.secondary)
                }
                Spacer()
                Button("完成") { dismiss() }.keyboardShortcut(.cancelAction).buttonStyle(.plain).foregroundStyle(Theme.secondary)
            }.padding(24)
            HStack(spacing: 12) {
                PhosphorIcon(name: "magnifying-glass", size: 16).foregroundStyle(Theme.muted)
                TextField("搜索包名称、用途或关键词", text: $model.query)
                    .textFieldStyle(.plain).focused($searchFocused).accessibilityIdentifier("universe.search")
                Picker("分类", selection: $model.category) {
                    ForEach(UniverseCategory.all) { category in Text(category.title).tag(category.id) }
                }.labelsHidden().frame(width: 156).accessibilityLabel("Universe 包分类")
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
                Button("刷新索引") { Task { await model.load(forceRefresh: true) } }
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
                    }.buttonStyle(.plain).accessibilityLabel("\(package.name)，版本 \(package.version)")
                }
            }.padding(10)
        }.overlay {
            if results.isEmpty && !model.isLoading {
                Text(model.snapshot == nil ? "尚未载入索引" : "没有找到相符的包\n试试其他关键词或分类。")
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
                        Text("版本 \(package.version)").font(.system(size: 11, design: .monospaced)).foregroundStyle(Theme.accent)
                    }
                    Text(package.description).font(.system(size: 13)).lineSpacing(5).foregroundStyle(Theme.secondary).textSelection(.enabled)
                    Text(package.categories.map(UniverseCategory.title(for:)).joined(separator: " · "))
                        .font(.system(size: 11)).foregroundStyle(Theme.muted)
                    Rectangle().fill(Theme.border.opacity(0.6)).frame(height: 1)
                    VStack(alignment: .leading, spacing: 9) {
                        Text("导入到当前文稿").font(.system(size: 11, weight: .medium)).foregroundStyle(Theme.secondary)
                        Text("#import \"\(package.reference)\"")
                            .font(.system(size: 11, design: .monospaced)).foregroundStyle(Theme.accent).textSelection(.enabled)
                            .padding(12).frame(maxWidth: .infinity, alignment: .leading).background(Theme.editor, in: RoundedRectangle(cornerRadius: 6))
                        Text("固定此版本。导入后，Typst 会按需下载并缓存包；具体用法可在文档中查看。")
                            .font(.system(size: 11)).lineSpacing(4).foregroundStyle(Theme.muted)
                    }
                    VStack(alignment: .leading, spacing: 7) {
                        Text("许可  \(package.license)")
                        if let required = package.compiler { Text("需要 Typst \(required) 或更新版本") }
                        if !package.authors.isEmpty { Text(package.authors.joined(separator: " · ")).lineLimit(3) }
                    }.font(.system(size: 10)).foregroundStyle(Theme.muted)
                    if !package.isCompatible(with: compilerVersion) {
                        Text("当前排版引擎为 Typst \(compilerVersion)，此包需要更新版本。")
                            .font(.system(size: 11)).foregroundStyle(Theme.accent)
                    }
                }.frame(maxWidth: .infinity, alignment: .leading).padding(24)
            }
            VStack(alignment: .leading, spacing: 12) {
                if let importError { Text(importError).font(.system(size: 11)).foregroundStyle(Theme.red) }
                HStack {
                    Link("使用文档 ↗", destination: package.documentationURL).font(.system(size: 12)).foregroundStyle(Theme.secondary)
                    Spacer()
                    Button("插入导入语句") {
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
            Text("让想法延伸").font(.system(size: 23, design: .serif)).foregroundStyle(Theme.secondary)
            Text("搜索 CeTZ 绘图，或 Fletcher 流程图。\n在左侧选择一个包，查看介绍和用法。")
                .font(.system(size: 12)).lineSpacing(6).foregroundStyle(Theme.muted).multilineTextAlignment(.center)
        }.frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var statusText: String {
        if let error = model.error { return error }
        guard let snapshot = model.snapshot else { return "正在连接 packages.typst.org…" }
        let date = snapshot.fetchedAt.formatted(date: .abbreviated, time: .shortened)
        switch snapshot.source {
        case .network: return "\(snapshot.packages.count) 个包 · 索引更新于 \(date)"
        case .cache: return "\(snapshot.packages.count) 个包 · 本地索引 \(date)"
        case .offlineCache: return "当前离线，使用 \(date) 的本地索引 · \(snapshot.packages.count) 个包"
        }
    }
}

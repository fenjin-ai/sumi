import ImageIO
import LeftBlankCore
import SwiftUI

/// The platform supplies layout and image decoding; discovery and caching are shared with Mac.
struct TabletUniverseBrowser: View {
    @ObservedObject var workspace: TabletWorkspace
    @StateObject private var model = UniverseBrowserModel(
        store: UniverseCatalogStore(cacheURL: AppDistribution.defaultStateDirectory
            .appendingPathComponent("Universe.json")),
        mode: .templates,
    )
    private let previewCache = AppDistribution.defaultStateDirectory.appendingPathComponent("UniversePreviews")

    var body: some View {
        VStack(spacing: 0) {
            Picker(L10n.text("Templates & Packages"), selection: Binding(
                get: { model.mode }, set: { model.changeMode($0) },
            )) {
                Text(L10n.text("New document")).tag(UniverseDiscoveryMode.templates)
                Text(L10n.text("Writing tools")).tag(UniverseDiscoveryMode.packages)
            }.pickerStyle(.segmented).padding(.horizontal, 20).padding(.vertical, 12)
                .accessibilityIdentifier("universe-mode")
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(UniverseDiscoveryGroup.groups(for: model.mode)) { group in
                        Button { model.group = group.id } label: {
                            HStack(spacing: 6) {
                                TabletIcon(name: group.symbolName, size: 14)
                                Text(group.title).font(.system(size: 12, weight: .medium))
                            }.padding(.horizontal, 12).frame(minHeight: 44)
                                .background(
                                    model.group == group.id ? TabletTheme.accent.opacity(0.1) : .clear,
                                    in: RoundedRectangle(cornerRadius: 8),
                                )
                        }.buttonStyle(.plain)
                            .foregroundStyle(model.group == group.id ? TabletTheme.accent : TabletTheme.secondary)
                    }
                }.padding(.horizontal, 20)
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    let builtIn = BuiltInTemplate.allCases.filter { $0.matches(model.query) }
                    if model.mode == .templates, !builtIn.isEmpty {
                        Text(L10n.text("From LeftBlank")).font(.system(size: 12, weight: .medium))
                            .foregroundStyle(.secondary)
                        HStack(spacing: 12) {
                            ForEach(builtIn) { template in
                                Button { Task { await workspace.create(template)
                                    workspace.panel = nil
                                } } label: {
                                    HStack(spacing: 10) {
                                        TabletIcon(name: template == .blank ? "file-plus" : "book-open-text")
                                        Text(template.title).font(.system(size: 13, weight: .medium))
                                        Spacer(minLength: 0)
                                        TabletIcon(name: "arrow-right", size: 14)
                                    }.padding(14).frame(minHeight: 60).background(
                                        .background,
                                        in: RoundedRectangle(cornerRadius: 10),
                                    )
                                }.buttonStyle(.plain).accessibilityIdentifier("universe.builtin." + template.rawValue)
                            }
                        }
                    }
                    Text(L10n.text("From the community")).font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.secondary)
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 170, maximum: 280), spacing: 16)], spacing: 20) {
                        ForEach(model.results) { package in
                            NavigationLink {
                                details(package)
                            } label: {
                                card(package)
                            }.buttonStyle(.plain).accessibilityIdentifier("universe.result." + package.name)
                        }
                    }
                    if model.results.isEmpty, !model.isLoading {
                        TabletEmptyState(title: L10n.text("No matches yet"), icon: "magnifying-glass")
                            .frame(minHeight: 160)
                    }
                }.padding(20)
            }.refreshable { await model.load(forceRefresh: true) }
            HStack(spacing: 10) {
                if model.isLoading {
                    ProgressView().controlSize(.small)
                }
                Text(model.statusText).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(2)
                Spacer(minLength: 0)
                Button { Task { await model.load(forceRefresh: true) } } label: {
                    TabletIcon(name: "arrow-clockwise", size: 16).frame(width: 44, height: 44)
                }.disabled(model.isLoading).accessibilityLabel(L10n.text("Refresh Index"))
            }.padding(.horizontal, 16)
                .overlay(alignment: .top) { Rectangle().fill(TabletTheme.border).frame(height: 0.5) }
        }.background(TabletTheme.background).disabled(workspace.busy)
            .searchable(text: $model.query, prompt: L10n.text("Search Packages"))
            .task { await model.load() }
    }

    private func card(_ package: UniversePackage) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            if package.isTemplate {
                TabletUniverseThumbnail(package: package, cacheURL: previewCache)
                    .id("\(package.reference)-\(model.previewGeneration)")
                    .aspectRatio(0.75, contentMode: .fit).clipShape(RoundedRectangle(cornerRadius: 8))
            } else {
                TabletIcon(name: "package", size: 24).foregroundStyle(TabletTheme.accent).padding(.bottom, 4)
            }
            Text(package.name).font(.system(size: 14, weight: .medium)).foregroundStyle(.primary).lineLimit(1)
            Text(package.description).font(.system(size: 12)).foregroundStyle(.secondary).lineLimit(2)
                .frame(height: 34, alignment: .topLeading)
            Text(package.version).font(.system(size: 10, design: .monospaced)).foregroundStyle(.secondary)
        }.padding(package.isTemplate ? 0 : 14).frame(maxWidth: .infinity, alignment: .leading)
            .background(
                package.isTemplate ? .clear : Color(uiColor: .secondarySystemBackground),
                in: RoundedRectangle(cornerRadius: 10),
            )
            .accessibilityElement(children: .combine)
    }

    private func details(_ package: UniversePackage) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if package.isTemplate {
                    TabletUniverseThumbnail(package: package, cacheURL: previewCache)
                        .aspectRatio(0.75, contentMode: .fit).frame(maxWidth: 280).frame(maxWidth: .infinity)
                }
                Text(package.name).font(.system(size: 24, weight: .medium, design: .serif))
                Text(package.description).font(.system(size: 14)).foregroundStyle(.secondary)
                Text(package.reference).font(.system(size: 12, design: .monospaced)).textSelection(.enabled)
                LabeledContent(L10n.text("Authors"), value: package.authors.joined(separator: ", "))
                LabeledContent(L10n.text("License"), value: package.license)
                if !package.isCompatible(with: "0.15.1"), let compiler = package.compiler {
                    Text(L10n.format("Requires Typst %@ or later", compiler)).foregroundStyle(.orange)
                }
                Button(L10n.text(package.isTemplate ? "Use Template" : "Insert Import")) {
                    if package.isTemplate {
                        Task { await workspace.createTemplate(package) }
                    } else {
                        workspace.addPackage(package)
                    }
                }.buttonStyle(.borderedProminent).frame(minHeight: 44)
                    .disabled(workspace.busy || !package.isCompatible(with: "0.15.1") ||
                        (!package.isTemplate && workspace.document == nil))
                    .accessibilityIdentifier("universe.apply")
                Link(L10n.text("Documentation"), destination: package.documentationURL).frame(minHeight: 44)
            }.padding(24).frame(maxWidth: 620, alignment: .leading).frame(maxWidth: .infinity)
        }.background(TabletTheme.background).navigationTitle(package.name).navigationBarTitleDisplayMode(.inline)
    }
}

private struct TabletUniverseThumbnail: View {
    let package: UniversePackage
    let cacheURL: URL
    @State private var image: UIImage?

    var body: some View {
        ZStack {
            Color(uiColor: .secondarySystemBackground)
            if let image {
                Image(uiImage: image).resizable().scaledToFit().padding(8)
            } else {
                VStack(spacing: 10) {
                    TabletIcon(name: "file-text", size: 28).foregroundStyle(TabletTheme.secondary)
                    Text(L10n.text("Preview unavailable")).font(.system(size: 11)).foregroundStyle(.secondary)
                }
            }
        }.accessibilityHidden(true).task(id: package.thumbnailURL) {
            guard let url = package.thumbnailURL else {
                return
            }
            if let cached = TabletUniverseImages.cache.object(forKey: url as NSURL) {
                image = cached
                return
            }
            guard let data = await UniversePreviewLoader.shared.data(for: url, cacheURL: cacheURL),
                  !Task.isCancelled
            else {
                return
            }
            let thumbnail = await Task.detached(priority: .utility) { () -> CGImage? in
                guard let source = CGImageSourceCreateWithData(data as CFData, nil) else {
                    return nil
                }
                let options: [CFString: Any] = [kCGImageSourceCreateThumbnailFromImageAlways: true,
                                                kCGImageSourceThumbnailMaxPixelSize: 600,
                                                kCGImageSourceCreateThumbnailWithTransform: true,
                                                kCGImageSourceShouldCacheImmediately: true]
                return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
            }.value
            guard let thumbnail, !Task.isCancelled else {
                return
            }
            let result = UIImage(cgImage: thumbnail)
            TabletUniverseImages.cache.setObject(
                result,
                forKey: url as NSURL,
                cost: thumbnail.bytesPerRow * thumbnail.height,
            )
            image = result
        }
    }
}

@MainActor private enum TabletUniverseImages {
    static let cache: NSCache<NSURL, UIImage> = {
        let cache = NSCache<NSURL, UIImage>()
        cache.countLimit = 40
        cache.totalCostLimit = 16 * 1024 * 1024
        return cache
    }()
}

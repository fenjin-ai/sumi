import Foundation

/// Metadata from Typst's official preview index. Browsing never downloads package code.
public struct UniversePackage: Codable, Identifiable, Equatable, Sendable {
    public let name: String
    public let version: String
    public let description: String
    public let authors: [String]
    public let license: String
    public let keywords: [String]
    public let categories: [String]
    public let disciplines: [String]
    public let compiler: String?

    public var id: String { name }
    public var reference: String { "@preview/\(name):\(version)" }
    public var documentationURL: URL { URL(string: "https://typst.app/universe/package/")!.appendingPathComponent(name, isDirectory: true).appendingPathComponent(version, isDirectory: true) }

    private enum CodingKeys: String, CodingKey {
        case name, version, description, authors, license, keywords, categories, disciplines, compiler
    }

    public init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        name = try values.decode(String.self, forKey: .name)
        version = try values.decode(String.self, forKey: .version)
        description = try values.decodeIfPresent(String.self, forKey: .description) ?? ""
        authors = try values.decodeIfPresent([String].self, forKey: .authors) ?? []
        license = try values.decodeIfPresent(String.self, forKey: .license) ?? "未注明"
        keywords = try values.decodeIfPresent([String].self, forKey: .keywords) ?? []
        categories = try values.decodeIfPresent([String].self, forKey: .categories) ?? []
        disciplines = try values.decodeIfPresent([String].self, forKey: .disciplines) ?? []
        compiler = try values.decodeIfPresent(String.self, forKey: .compiler)
    }

    public func pinnedImport() throws -> Snippet {
        guard isValid else { throw UniverseError.invalidPackage }
        return Snippet(text: "#import \"\(reference)\"\n")
    }

    public func isCompatible(with compilerVersion: String) -> Bool {
        guard let compiler, let required = UniverseVersion(compiler), let installed = UniverseVersion(compilerVersion) else { return true }
        return installed >= required
    }

    fileprivate var isValid: Bool {
        name.count <= 128 && name.range(of: "^[a-z][a-z0-9]*(-[a-z0-9]+)*\\z", options: .regularExpression) != nil && UniverseVersion(version) != nil
    }
}

private struct UniverseVersion: Comparable {
    let components: [Int]
    init?(_ value: String) {
        let parts = value.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 3, value.count <= 32,
              parts.allSatisfy({ !$0.isEmpty && $0.utf8.allSatisfy { (48...57).contains($0) } }) else { return nil }
        let numbers = parts.compactMap { Int($0) }
        guard numbers.count == 3 else { return nil }
        components = numbers
    }
    static func < (lhs: Self, rhs: Self) -> Bool { lhs.components.lexicographicallyPrecedes(rhs.components) }
}

public struct UniverseCategory: Identifiable, Sendable {
    public let id: String
    public let title: String
    public static let all: [Self] = [
        .init(id: "", title: "全部包"), .init(id: "visualization", title: "绘图与可视化"),
        .init(id: "components", title: "组件"), .init(id: "text", title: "文字"),
        .init(id: "layout", title: "布局"), .init(id: "model", title: "文档结构"),
        .init(id: "presentation", title: "演示文稿"), .init(id: "paper", title: "论文"),
        .init(id: "thesis", title: "学位论文"), .init(id: "report", title: "报告"),
        .init(id: "book", title: "书籍"), .init(id: "poster", title: "海报"),
        .init(id: "cv", title: "简历"), .init(id: "flyer", title: "传单"),
        .init(id: "office", title: "办公"), .init(id: "languages", title: "语言"),
        .init(id: "integration", title: "集成"), .init(id: "scripting", title: "脚本"),
        .init(id: "utility", title: "实用工具"), .init(id: "fun", title: "趣味")
    ]
    public static func title(for id: String) -> String { all.first { $0.id == id }?.title ?? id }
}

public struct UniverseCatalogSnapshot: Sendable {
    public enum Source: Sendable { case network, cache, offlineCache }
    public let packages: [UniversePackage]
    public let fetchedAt: Date
    public let source: Source

    public func search(_ query: String, category: String = "") -> [UniversePackage] {
        let words = Self.normalized(query).split(whereSeparator: \.isWhitespace)
        return packages.filter { package in
            guard category.isEmpty || package.categories.contains(category) else { return false }
            let translated = package.categories.map(UniverseCategory.title(for:))
            let haystack = Self.normalized(([package.name, package.description] + package.keywords + package.categories + translated + package.disciplines).joined(separator: " "))
            return words.allSatisfy { haystack.contains($0) }
        }.sorted { left, right in
            // Exact package names stay easy to find, even among packages mentioning them.
            let name = Self.normalized(query.trimmingCharacters(in: .whitespacesAndNewlines))
            if (left.name == name) != (right.name == name) { return left.name == name }
            return left.name < right.name
        }
    }
    private static func normalized(_ value: String) -> String {
        value.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX"))
    }
}

public enum UniverseError: LocalizedError {
    case invalidIndex, invalidPackage, unavailable
    public var errorDescription: String? {
        switch self {
        case .invalidIndex: "Universe 索引格式无效，请稍后重新刷新。"
        case .invalidPackage: "包名称或版本无效，无法生成导入语句。"
        case .unavailable: "暂时无法连接 Typst Universe。连接网络后可重新刷新；已缓存的索引仍可浏览。"
        }
    }
}

public struct UniverseHTTPResponse: Sendable {
    public let data: Data
    public let statusCode: Int
    public init(data: Data, statusCode: Int) { self.data = data; self.statusCode = statusCode }
}

public actor UniverseCatalogStore {
    public typealias Transport = @Sendable (URLRequest) async throws -> UniverseHTTPResponse
    public static let indexURL = URL(string: "https://packages.typst.org/preview/index.json")!
    public static let cacheLifetime: TimeInterval = 24 * 60 * 60
    private let cacheURL: URL
    private let transport: Transport
    private let now: @Sendable () -> Date
    private static let maximumBytes = 12 * 1_024 * 1_024

    public init(cacheURL: URL, transport: @escaping Transport = UniverseCatalogStore.fetch, now: @escaping @Sendable () -> Date = { Date() }) {
        self.cacheURL = cacheURL
        self.transport = transport
        self.now = now
    }

    public static func fetch(_ request: URLRequest) async throws -> UniverseHTTPResponse {
        let (data, response) = try await URLSession.shared.data(for: request)
        return UniverseHTTPResponse(data: data, statusCode: (response as? HTTPURLResponse)?.statusCode ?? 0)
    }

    public func cached() -> UniverseCatalogSnapshot? {
        guard let data = try? Data(contentsOf: cacheURL), data.count <= Self.maximumBytes,
              let saved = try? JSONDecoder().decode(Cache.self, from: data), saved.schema == 1,
              let packages = try? Self.latest(saved.packages), saved.fetchedAt <= now().addingTimeInterval(300) else { return nil }
        return UniverseCatalogSnapshot(packages: packages, fetchedAt: saved.fetchedAt, source: .cache)
    }

    public func load(forceRefresh: Bool = false) async throws -> UniverseCatalogSnapshot {
        let fallback = cached()
        if !forceRefresh, let fallback, now().timeIntervalSince(fallback.fetchedAt) < Self.cacheLifetime { return fallback }
        do {
            var request = URLRequest(url: Self.indexURL, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 20)
            request.setValue("application/json", forHTTPHeaderField: "Accept")
            let response = try await transport(request)
            try Task.checkCancellation()
            guard response.statusCode == 200 else { throw UniverseError.unavailable }
            let packages = try Self.decodeIndex(response.data)
            let snapshot = UniverseCatalogSnapshot(packages: packages, fetchedAt: now(), source: .network)
            let cache = Cache(schema: 1, fetchedAt: snapshot.fetchedAt, packages: packages)
            // A read-only or full cache directory must not prevent online discovery.
            if let data = try? JSONEncoder().encode(cache) {
                try? FileManager.default.createDirectory(at: cacheURL.deletingLastPathComponent(), withIntermediateDirectories: true)
                try? data.write(to: cacheURL, options: .atomic)
            }
            return snapshot
        } catch is CancellationError { throw CancellationError() }
        catch {
            if Task.isCancelled { throw CancellationError() }
            if let fallback { return UniverseCatalogSnapshot(packages: fallback.packages, fetchedAt: fallback.fetchedAt, source: .offlineCache) }
            if let error = error as? UniverseError { throw error }
            throw UniverseError.unavailable
        }
    }

    public static func decodeIndex(_ data: Data) throws -> [UniversePackage] {
        guard data.count <= maximumBytes,
              let packages = try? JSONDecoder().decode([UniversePackage].self, from: data) else { throw UniverseError.invalidIndex }
        return try latest(packages)
    }

    private static func latest(_ packages: [UniversePackage]) throws -> [UniversePackage] {
        var result: [String: UniversePackage] = [:]
        for package in packages where package.isValid {
            if let existing = result[package.name], UniverseVersion(existing.version)! >= UniverseVersion(package.version)! { continue }
            result[package.name] = package
        }
        guard !result.isEmpty else { throw UniverseError.invalidIndex }
        return result.values.sorted { $0.name < $1.name }
    }
    private struct Cache: Codable { let schema: Int; let fetchedAt: Date; let packages: [UniversePackage] }
}

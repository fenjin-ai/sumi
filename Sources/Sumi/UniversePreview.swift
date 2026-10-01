import AppKit
import ImageIO
import SwiftUI
import SumiCore

/// Official, versioned thumbnails are a visual aid only. A missing preview never
/// blocks catalog browsing or template creation, and loading stays off the UI thread.
struct UniversePreview: View {
    let package: UniversePackage
    let cacheURL: URL
    @State private var image: NSImage?

    var body: some View {
        ZStack {
            Color(hex: 0xE5E3DD)
            if let image {
                Image(nsImage: image).resizable().interpolation(.high).scaledToFit().padding(9)
            } else {
                VStack(spacing: 10) {
                    Text(package.name.split(separator: "-").prefix(2).map { String($0.prefix(1)).uppercased() }.joined())
                        .font(.system(size: 42, weight: .light, design: .serif)).foregroundStyle(Color(hex: 0x73736F))
                    Text(L10n.text("Preview unavailable")).font(.system(size: 9)).foregroundStyle(Color(hex: 0x83837D))
                }.padding(14)
            }
        }.accessibilityHidden(true)
        .task(id: package.thumbnailURL) {
            image = nil
            guard let url = package.thumbnailURL else { return }
            if let cached = UniversePreviewImages.cache.object(forKey: url as NSURL) { image = cached; return }
            guard let data = await UniversePreviewLoader.shared.data(for: url, cacheURL: cacheURL), !Task.isCancelled else { return }
            let thumbnail = await Task.detached(priority: .utility) { () -> CGImage? in
                guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
                let options: [CFString: Any] = [kCGImageSourceCreateThumbnailFromImageAlways: true,
                                               kCGImageSourceThumbnailMaxPixelSize: 600,
                                               kCGImageSourceCreateThumbnailWithTransform: true,
                                               kCGImageSourceShouldCacheImmediately: true]
                return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
            }.value
            guard let thumbnail, !Task.isCancelled else { return }
            let result = NSImage(cgImage: thumbnail, size: .zero)
            UniversePreviewImages.cache.setObject(result, forKey: url as NSURL, cost: thumbnail.bytesPerRow * thumbnail.height)
            image = result
        }
    }
}

@MainActor
private enum UniversePreviewImages {
    static let cache: NSCache<NSURL, NSImage> = {
        let cache = NSCache<NSURL, NSImage>()
        cache.countLimit = 60
        cache.totalCostLimit = 32 * 1_024 * 1_024
        return cache
    }()
}

private actor UniversePreviewLoader {
    static let shared = UniversePreviewLoader()
    private var sessions: [URL: URLSession] = [:]
    private var inflight: [URL: Task<Data?, Never>] = [:]
    private var failures: [URL: Date] = [:]

    func data(for url: URL, cacheURL: URL) async -> Data? {
        guard url.scheme == "https", url.host == "packages.typst.org", url.path.hasPrefix("/preview/thumbnails/") else { return nil }
        if let failed = failures[url], Date().timeIntervalSince(failed) < 300 { return nil }
        if let task = inflight[url] { return await task.value }
        let session: URLSession
        if let existing = sessions[cacheURL] { session = existing }
        else {
            let configuration = URLSessionConfiguration.ephemeral
            configuration.urlCache = URLCache(memoryCapacity: 4 * 1_024 * 1_024, diskCapacity: 48 * 1_024 * 1_024, directory: cacheURL)
            configuration.requestCachePolicy = .returnCacheDataElseLoad
            configuration.httpMaximumConnectionsPerHost = 4
            configuration.timeoutIntervalForRequest = 12
            configuration.timeoutIntervalForResource = 20
            session = URLSession(configuration: configuration)
            if sessions.count >= 4, let oldest = sessions.keys.first {
                sessions.removeValue(forKey: oldest)?.finishTasksAndInvalidate()
            }
            sessions[cacheURL] = session
        }
        let task = Task<Data?, Never> {
            do {
                let (bytes, response) = try await session.bytes(from: url)
                guard let http = response as? HTTPURLResponse, http.statusCode == 200,
                      response.expectedContentLength <= 5 * 1_024 * 1_024 else { return nil }
                var data = Data()
                if response.expectedContentLength > 0 { data.reserveCapacity(Int(response.expectedContentLength)) }
                for try await byte in bytes {
                    guard data.count < 5 * 1_024 * 1_024 else { return nil }
                    data.append(byte)
                }
                return data
            } catch { return nil }
        }
        inflight[url] = task
        defer { inflight[url] = nil }
        let result = await task.value
        if result == nil {
            if failures.count >= 256 { failures = failures.filter { Date().timeIntervalSince($0.value) < 300 } }
            failures[url] = Date()
        }
        return result
    }
}

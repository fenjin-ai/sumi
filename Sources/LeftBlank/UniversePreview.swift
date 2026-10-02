import AppKit
import ImageIO
import SwiftUI
import LeftBlankCore

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

actor UniversePreviewLoader {
    static let shared = UniversePreviewLoader()
    private struct Request {
        let task: Task<Void, Never>
        var readers: [UUID: CheckedContinuation<Data?, Never>]
    }
    private let transport: UniverseCatalogStore.Transport?
    private var sessions: [URL: URLSession] = [:]
    private var inflight: [URL: Request] = [:]
    private var failures: [URL: Date] = [:]

    init(transport: UniverseCatalogStore.Transport? = nil) { self.transport = transport }

    func allowRetry() { failures.removeAll() }

    func data(for url: URL, cacheURL: URL) async -> Data? {
        guard url.scheme == "https", url.host == "packages.typst.org", url.path.hasPrefix("/preview/thumbnails/") else { return nil }
        if let failed = failures[url], Date().timeIntervalSince(failed) < 300 { return nil }
        let reader = UUID()
        return await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                guard !Task.isCancelled else { continuation.resume(returning: nil); return }
                if inflight[url] != nil {
                    inflight[url]?.readers[reader] = continuation
                } else {
                    let task = Task {
                        let data = await fetch(url, cacheURL: cacheURL)
                        finish(url, data: data)
                    }
                    inflight[url] = Request(task: task, readers: [reader: continuation])
                }
            }
        } onCancel: {
            Task { await self.cancel(reader, url: url) }
        }
    }

    private func cancel(_ reader: UUID, url: URL) {
        guard var request = inflight[url] else { return }
        request.readers.removeValue(forKey: reader)?.resume(returning: nil)
        if request.readers.isEmpty {
            inflight.removeValue(forKey: url)
            request.task.cancel()
        } else { inflight[url] = request }
    }

    private func finish(_ url: URL, data: Data?) {
        // A canceled offscreen request must not finish a newer request for the same URL.
        guard !Task.isCancelled, let request = inflight.removeValue(forKey: url) else { return }
        if data == nil {
            if failures.count >= 256 { failures = failures.filter { Date().timeIntervalSince($0.value) < 300 } }
            failures[url] = Date()
        }
        for reader in request.readers.values { reader.resume(returning: data) }
    }

    private func fetch(_ url: URL, cacheURL: URL) async -> Data? {
        let request = URLRequest(url: url, cachePolicy: .returnCacheDataElseLoad, timeoutInterval: 12)
        do {
            if let transport {
                let response = try await transport(request)
                return response.statusCode == 200 && response.data.count <= 5 * 1_024 * 1_024 ? response.data : nil
            }
            let session: URLSession
            if let existing = sessions[cacheURL] { session = existing }
            else {
                // A normal session honors the disk cache across app launches.
                // Ephemeral sessions can keep the same responses only in memory.
                let configuration = URLSessionConfiguration.default
                configuration.urlCache = URLCache(memoryCapacity: 4 * 1_024 * 1_024, diskCapacity: 48 * 1_024 * 1_024, directory: cacheURL)
                configuration.httpCookieStorage = nil
                configuration.urlCredentialStorage = nil
                configuration.httpShouldSetCookies = false
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
            let (bytes, response) = try await session.bytes(for: request)
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
}

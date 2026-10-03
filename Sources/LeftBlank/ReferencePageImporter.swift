import CoreGraphics
import Foundation
import ImageIO
import LeftBlankCore
import PDFKit
import Vision

struct ReferencePageImport: Sendable {
    enum ExtractionMode: Sendable {
        case pdfText
        case imageOCR
        case pdfOCR
    }

    let source: String
    let extractedText: String
    let extractionMode: ExtractionMode
    let warning: String?
}

enum ReferencePageImporter {
    static let maximumFileBytes = 30 * 1024 * 1024
    static let maximumImagePixels = 24_000_000
    static let maximumRasterEdge = 3072

    /// PDFKit, image decoding and Vision all run off the main actor. Only the
    /// first page/frame is read; no model or network service sees this content.
    static func importPage(from url: URL) async throws -> ReferencePageImport {
        try Task.checkCancellation()
        let cancellation = ReferenceRecognitionCancellation()
        let task = Task.detached(priority: .userInitiated) {
            try extract(from: url, cancellation: cancellation)
        }
        return try await withTaskCancellationHandler {
            let result = try await task.value
            try Task.checkCancellation()
            return result
        } onCancel: {
            task.cancel()
            cancellation.cancel()
        }
    }

    private static func extract(from url: URL, cancellation: ReferenceRecognitionCancellation) throws
        -> ReferencePageImport
    {
        let data = try readBoundedFile(url)
        try Task.checkCancellation()
        let lines: [ReferenceTextLine]
        let mode: ReferencePageImport.ExtractionMode
        if data.starts(with: Data("%PDF-".utf8)) || url.pathExtension.lowercased() == "pdf" {
            guard let document = PDFDocument(data: data) else {
                throw ReferencePageImportError.invalidFile
            }
            guard !document.isEncrypted, !document.isLocked else {
                throw ReferencePageImportError.encryptedPDF
            }
            guard let page = document.page(at: 0) else {
                throw ReferencePageImportError.blankPage
            }
            let bounds = page.bounds(for: .cropBox)
            guard bounds.width.isFinite, bounds.height.isFinite,
                  bounds.width > 0, bounds.height > 0,
                  bounds.width <= 20000, bounds.height <= 20000
            else {
                throw ReferencePageImportError.invalidFile
            }
            let native = try nativeText(in: page, bounds: bounds)
            if native.isEmpty {
                lines = try recognize(render(page, bounds: bounds), cancellation: cancellation)
                mode = .pdfOCR
            } else {
                lines = native
                mode = .pdfText
            }
        } else {
            lines = try recognize(rasterImage(data), cancellation: cancellation)
            mode = .imageOCR
        }
        try Task.checkCancellation()
        let ordered = readingOrder(lines)
        let blocks = paragraphBlocks(ordered)
        guard !blocks.isEmpty else {
            throw ReferencePageImportError.blankPage
        }
        let page = ReconstructedPage(blocks: blocks)
        return try ReferencePageImport(
            source: page.typstSource(),
            extractedText: ordered.map(\.text).joined(separator: "\n"),
            extractionMode: mode,
            warning: L10n
                .text(
                    "Only the first page is reconstructed. Review recognized text; images, equations and exact layout are not preserved.",
                ),
        )
    }

    private static func readBoundedFile(_ url: URL) throws -> Data {
        guard url.isFileURL else {
            throw ReferencePageImportError.invalidFile
        }
        let scoped = url.startAccessingSecurityScopedResource()
        defer {
            if scoped {
                url.stopAccessingSecurityScopedResource()
            }
        }
        do {
            let values = try url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
            guard values.isRegularFile == true else {
                throw ReferencePageImportError.invalidFile
            }
            guard (values.fileSize ?? 0) <= maximumFileBytes else {
                throw ReferencePageImportError.fileTooLarge
            }
            let handle = try FileHandle(forReadingFrom: url)
            defer { try? handle.close() }
            // The extra byte also bounds files that grow after the size check.
            let data = try handle.read(upToCount: maximumFileBytes + 1) ?? Data()
            guard data.count <= maximumFileBytes else {
                throw ReferencePageImportError.fileTooLarge
            }
            guard !data.isEmpty else {
                throw ReferencePageImportError.invalidFile
            }
            return data
        } catch let error as ReferencePageImportError {
            throw error
        } catch {
            throw ReferencePageImportError.unreadableFile
        }
    }

    static func rasterImage(_ data: Data) throws -> CGImage {
        guard let source = CGImageSourceCreateWithData(data as CFData, [
            kCGImageSourceShouldCache: false,
        ] as CFDictionary), CGImageSourceGetCount(source) > 0,
            let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
            let width = properties[kCGImagePropertyPixelWidth] as? NSNumber,
            let height = properties[kCGImagePropertyPixelHeight] as? NSNumber
        else {
            throw ReferencePageImportError.invalidFile
        }
        let pixels = width.doubleValue * height.doubleValue
        guard width.doubleValue > 0, height.doubleValue > 0,
              pixels.isFinite, pixels <= Double(maximumImagePixels)
        else {
            throw ReferencePageImportError.imageTooLarge
        }
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maximumRasterEdge,
            kCGImageSourceShouldCacheImmediately: true,
        ] as CFDictionary) else {
            throw ReferencePageImportError.invalidFile
        }
        return image
    }

    private static func nativeText(in page: PDFPage, bounds: CGRect) throws -> [ReferenceTextLine] {
        guard let text = page.string, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return []
        }
        guard text.count <= ReconstructedPage.maximumTextLength else {
            throw ReferencePageImportError.textTooLong
        }
        guard let selection = page.selection(for: bounds) else {
            return []
        }
        let selections = selection.selectionsByLine()
        guard selections.count <= 1000 else {
            throw ReferencePageImportError.textTooLong
        }
        var lines: [ReferenceTextLine] = []
        for selection in selections {
            try Task.checkCancellation()
            let text = (selection.string ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else {
                continue
            }
            let rect = selection.bounds(for: page)
            guard !rect.isEmpty, rect.minX.isFinite, rect.minY.isFinite,
                  rect.width.isFinite, rect.height.isFinite
            else {
                continue
            }
            lines.append(.init(text: text, bounds: CGRect(
                x: (rect.minX - bounds.minX) / bounds.width,
                y: (rect.minY - bounds.minY) / bounds.height,
                width: rect.width / bounds.width,
                height: rect.height / bounds.height,
            )))
        }
        return lines
    }

    private static func render(_ page: PDFPage, bounds: CGRect) throws -> CGImage {
        try Task.checkCancellation()
        let scale = min(2, Double(maximumRasterEdge) / max(bounds.width, bounds.height))
        let width = max(1, Int(ceil(bounds.width * scale)))
        let height = max(1, Int(ceil(bounds.height * scale)))
        guard let context = CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue,
        ) else {
            throw ReferencePageImportError.invalidFile
        }
        context.setFillColor(CGColor(gray: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        context.scaleBy(x: scale, y: scale)
        context.translateBy(x: -bounds.minX, y: -bounds.minY)
        page.draw(with: .cropBox, to: context)
        guard let image = context.makeImage() else {
            throw ReferencePageImportError.invalidFile
        }
        return image
    }

    private static func recognize(_ image: CGImage, cancellation: ReferenceRecognitionCancellation) throws
        -> [ReferenceTextLine]
    {
        try Task.checkCancellation()
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        request.automaticallyDetectsLanguage = true
        request.minimumTextHeight = 0.003
        let languages = try request.supportedRecognitionLanguages()
        request.recognitionLanguages = ["zh-Hans", "en-US"].filter(languages.contains)
        cancellation.install(request)
        defer { cancellation.clear() }
        do {
            try VNImageRequestHandler(cgImage: image).perform([request])
        } catch {
            try Task.checkCancellation()
            throw ReferencePageImportError.recognitionFailed
        }
        try Task.checkCancellation()
        var length = 0
        return try (request.results ?? []).compactMap { observation in
            guard let candidate = observation.topCandidates(1).first else {
                return nil
            }
            let text = candidate.string.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else {
                return nil
            }
            length += text.count
            guard length <= ReconstructedPage.maximumTextLength else {
                throw ReferencePageImportError.textTooLong
            }
            return ReferenceTextLine(text: text, bounds: observation.boundingBox)
        }
    }

    /// Simple two-column pages are read down each column. Wide lines delimit
    /// bands (such as a full-width title); ambiguous layouts retain row order.
    static func readingOrder(_ lines: [ReferenceTextLine]) -> [ReferenceTextLine] {
        func topToBottom(_ lines: [ReferenceTextLine]) -> [ReferenceTextLine] {
            lines.sorted {
                let tolerance = min($0.bounds.height, $1.bounds.height) * 0.35
                if abs($0.bounds.maxY - $1.bounds.maxY) > tolerance {
                    return $0.bounds.maxY > $1.bounds.maxY
                }
                return $0.bounds.minX < $1.bounds.minX
            }
        }
        let wide = topToBottom(lines.filter { $0.bounds.width >= 0.65 })
        let narrow = lines.filter { $0.bounds.width < 0.65 }
        let left = narrow.filter { $0.bounds.maxX <= 0.55 }
        let right = narrow.filter { $0.bounds.minX >= 0.45 }
        guard left.count >= 3, right.count >= 3,
              left.count + right.count == narrow.count,
              let leftTop = left.map(\.bounds.maxY).max(),
              let leftBottom = left.map(\.bounds.minY).min(),
              let rightTop = right.map(\.bounds.maxY).max(),
              let rightBottom = right.map(\.bounds.minY).min(),
              min(leftTop, rightTop) > max(leftBottom, rightBottom)
        else {
            return topToBottom(lines)
        }
        var ordered: [ReferenceTextLine] = []
        var ceiling = Double.infinity
        for divider in wide {
            let band = narrow.filter { $0.bounds.midY < ceiling && $0.bounds.midY > divider.bounds.midY }
            ordered += topToBottom(band.filter { $0.bounds.maxX <= 0.55 })
            ordered += topToBottom(band.filter { $0.bounds.minX >= 0.45 })
            ordered.append(divider)
            ceiling = divider.bounds.midY
        }
        let band = narrow.filter { $0.bounds.midY < ceiling }
        ordered += topToBottom(band.filter { $0.bounds.maxX <= 0.55 })
        ordered += topToBottom(band.filter { $0.bounds.minX >= 0.45 })
        return ordered
    }

    static func paragraphBlocks(_ lines: [ReferenceTextLine]) -> [ReconstructedBlock] {
        guard !lines.isEmpty else {
            return []
        }
        let heights = lines.map(\.bounds.height).sorted()
        let median = heights[heights.count / 2]
        var blocks: [ReconstructedBlock] = []
        var paragraph = ""
        var previous: ReferenceTextLine?
        func finishParagraph() {
            if !paragraph.isEmpty {
                blocks.append(.init(kind: .paragraph, text: paragraph))
                paragraph = ""
            }
        }
        for line in lines {
            let heading = line.bounds.height > median * 1.35 && line.text.count <= 120
            if heading {
                finishParagraph()
                blocks.append(.init(kind: .heading, text: line.text))
                previous = nil
                continue
            }
            if let previous {
                let gap = previous.bounds.minY - line.bounds.maxY
                if gap > max(median * 0.8, 0.006) || gap < -median * 0.35 ||
                    abs(previous.bounds.minX - line.bounds.minX) > 0.05
                {
                    finishParagraph()
                }
            }
            if !paragraph.isEmpty, !joinsWithoutSpace(paragraph, line.text) {
                paragraph += " "
            }
            paragraph += line.text
            previous = line
        }
        finishParagraph()
        return blocks
    }

    private static func joinsWithoutSpace(_ lhs: String, _ rhs: String) -> Bool {
        guard let last = lhs.unicodeScalars.last, let first = rhs.unicodeScalars.first else {
            return false
        }
        func isCJK(_ value: Unicode.Scalar) -> Bool {
            (0x3400 ... 0x9FFF).contains(value.value) || (0x3000 ... 0x303F).contains(value.value) ||
                (0xFF00 ... 0xFFEF).contains(value.value)
        }
        return isCJK(last) && isCJK(first)
    }
}

struct ReferenceTextLine: Sendable {
    let text: String
    /// Coordinates normalized to the page, with the origin at the bottom left.
    let bounds: CGRect
}

enum ReferencePageImportError: LocalizedError, Equatable {
    case invalidFile
    case unreadableFile
    case fileTooLarge
    case imageTooLarge
    case encryptedPDF
    case blankPage
    case textTooLong
    case recognitionFailed

    var errorDescription: String? {
        switch self {
        case .invalidFile: L10n.text("Choose a valid image or PDF file.")
        case .unreadableFile: L10n.text("The reference file could not be read. Choose it again.")
        case .fileTooLarge: L10n.text("Choose a reference file smaller than 30 MB.")
        case .imageTooLarge: L10n.text("Choose an image with no more than 24 million pixels.")
        case .encryptedPDF: L10n.text("Encrypted PDFs cannot be reconstructed. Export an unencrypted page first.")
        case .blankPage: L10n.text("No readable text was found on the first page.")
        case .textTooLong: L10n.text("This page contains too much text. Choose a simpler page.")
        case .recognitionFailed: L10n.text("Text recognition failed. Try a clearer image.")
        }
    }
}

/// Vision's synchronous perform can outlive task cancellation. This narrow
/// lock-protected bridge lets the caller cancel the active native request.
private final class ReferenceRecognitionCancellation: @unchecked Sendable {
    private let lock = NSLock()
    private var request: VNRequest?
    private var cancelled = false

    func install(_ request: VNRequest) {
        lock.lock()
        self.request = request
        let cancelled = cancelled
        lock.unlock()
        if cancelled {
            request.cancel()
        }
    }

    func clear() {
        lock.lock()
        request = nil
        lock.unlock()
    }

    func cancel() {
        lock.lock()
        cancelled = true
        let request = request
        lock.unlock()
        request?.cancel()
    }
}

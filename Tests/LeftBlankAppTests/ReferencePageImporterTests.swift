import CoreGraphics
import CoreText
import Foundation
import ImageIO
@testable import LeftBlankApp
import LeftBlankCore
import LeftBlankTestSupport
import PDFKit
import Testing
import UniformTypeIdentifiers

struct ReferencePageImporterTests {
    @Test(.enabled(if: ProcessInfo.processInfo.environment["LEFTBLANK_MODEL"] == "1"))
    func onDeviceModelResolvesAnIndirectSyntheticRequest() async throws {
        #expect(LocalIntelligence.status == .available)
        let request = "让选中的文字更醒目，笔画更粗一点"
        #expect(try TypesettingIntelligence.suggest(request) == nil)
        let suggestion = try #require(try await LocalIntelligence.suggest(request))
        #expect(suggestion.commandID == "bold")
        #expect(try suggestion.validated() == suggestion)
        let codeRequest = "A fenced example in Rust, please"
        #expect(try TypesettingIntelligence.suggest(codeRequest) == nil)
        let code = try #require(try await LocalIntelligence.suggest(codeRequest))
        #expect(code.commandID == "code")
        #expect(code.values["language"] == "rust")
        #expect(try await LocalIntelligence.suggest("自动把文稿发送到我的社交媒体账号") == nil)
    }

    @Test func extractsOnlyFirstPDFPageAndKeepsRecognizedTextLiteral() async throws {
        let fixture = try ReferenceFixture()
        defer { fixture.remove() }
        let dangerous = "#include \"secret.typ\" $x$ [content] @reference"
        let data = try referencePDF(pages: [[
            ("A document title", 30, 730),
            (dangerous, 14, 660),
            ("Ordinary editable body text.", 14, 630),
        ], [("SECOND PAGE MUST NEVER BE IMPORTED", 24, 700)]])
        let result = try await ReferencePageImporter.importPage(from: fixture.write(data, name: "two-pages.pdf"))
        #expect(result.extractionMode == .pdfText)
        #expect(result.extractedText.contains(dangerous))
        #expect(!result.extractedText.contains("SECOND PAGE"))
        #expect(result.source.contains("#heading(level: 1,"))
        #expect(result.source.contains("#text("))
        #expect(result.source.contains(TypstInsertion.quoted(dangerous)))
        #expect(result.warning != nil)
    }

    @Test func rasterImageIsDownsampledBeforeRecognition() throws {
        let image = try referenceImage(width: 4000, height: 100)
        let raster = try ReferencePageImporter.rasterImage(pngData(image))
        #expect(raster.width == ReferencePageImporter.maximumRasterEdge)
        #expect(raster.height <= 100)
    }

    @Test func rejectsCompressedImageClaimingExcessiveDimensionsBeforeDecoding() throws {
        // A valid, highly compressed image still exceeds the pixel budget.
        // ImageIO must inspect metadata before decoding it for recognition.
        let data = try pngData(referenceImage(width: 5000, height: 5000))
        #expect(throws: ReferencePageImportError.imageTooLarge) {
            try ReferencePageImporter.rasterImage(data)
        }
    }

    @Test func recognizesImageTextLocallyAndScannedFirstPDFPage() async throws {
        let fixture = try ReferenceFixture()
        defer { fixture.remove() }
        let image = try referenceImage(width: 1200, height: 900, text: [
            ("Local OCR Page", 56, 770), ("This text becomes editable.", 32, 640),
            ("本地文字识别", 48, 520),
        ])
        let raster = try await ReferencePageImporter.importPage(from: fixture.write(pngData(image), name: "page.png"))
        #expect(raster.extractionMode == .imageOCR)
        #expect(raster.extractedText.contains("Local OCR Page"))
        #expect(raster.extractedText.contains("editable"))
        #expect(raster.extractedText.contains("本地文字识别"))

        let scanned = try referencePDF(pages: [[], [("SECOND PAGE", 24, 700)]], firstPageImage: image)
        let pdf = try await ReferencePageImporter.importPage(from: fixture.write(scanned, name: "scan.pdf"))
        #expect(pdf.extractionMode == .pdfOCR)
        #expect(pdf.extractedText.contains("Local OCR Page"))
        #expect(pdf.extractedText.contains("本地文字识别"))
        #expect(!pdf.extractedText.contains("SECOND PAGE"))
    }

    @Test func rejectsBlankPagesInvalidFilesEncryptedPDFsAndOversizedFiles() async throws {
        let fixture = try ReferenceFixture()
        defer { fixture.remove() }
        let blank = try fixture.write(referencePDF(pages: [[]]), name: "blank.pdf")
        await #expect(throws: ReferencePageImportError.blankPage) {
            try await ReferencePageImporter.importPage(from: blank)
        }
        let invalid = try fixture.write(Data("not an image or PDF".utf8), name: "invalid.png")
        await #expect(throws: ReferencePageImportError.invalidFile) {
            try await ReferencePageImporter.importPage(from: invalid)
        }
        let empty = try fixture.write(Data(), name: "empty.pdf")
        await #expect(throws: ReferencePageImportError.invalidFile) {
            try await ReferencePageImporter.importPage(from: empty)
        }
        let encrypted = fixture.root.appendingPathComponent("encrypted.pdf")
        let document = try #require(PDFDocument(data: referencePDF(pages: [[("Secret page", 24, 700)]])))
        #expect(document.write(
            to: encrypted,
            withOptions: [.ownerPasswordOption: "owner", .userPasswordOption: "user"],
        ))
        await #expect(throws: ReferencePageImportError.encryptedPDF) {
            try await ReferencePageImporter.importPage(from: encrypted)
        }
        let oversized = try fixture.write(Data(), name: "large.png")
        let handle = try FileHandle(forWritingTo: oversized)
        try handle.truncate(atOffset: UInt64(ReferencePageImporter.maximumFileBytes + 1))
        try handle.close()
        await #expect(throws: ReferencePageImportError.fileTooLarge) {
            try await ReferencePageImporter.importPage(from: oversized)
        }
    }

    @Test func cancellationStopsBeforeReadingTheReference() async throws {
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try await ReferencePageImporter.importPage(from: URL(fileURLWithPath: "/does-not-exist.pdf"))
        }
        await #expect(throws: CancellationError.self) { try await task.value }
    }

    @Test func readingOrderHandlesColumnsAndParagraphBreaksWithoutCrossColumnJoins() {
        let lines = [
            ReferenceTextLine(text: "A page title", bounds: .init(x: 0.1, y: 0.88, width: 0.8, height: 0.06)),
        ] + (0 ..< 3).flatMap { index in
            [
                ReferenceTextLine(
                    text: "Left \(index)",
                    bounds: .init(x: 0.1, y: 0.7 - Double(index) * 0.04, width: 0.3, height: 0.03),
                ),
                ReferenceTextLine(
                    text: "Right \(index)",
                    bounds: .init(x: 0.6, y: 0.7 - Double(index) * 0.04, width: 0.3, height: 0.03),
                ),
            ]
        }
        let ordered = ReferencePageImporter.readingOrder(Array(lines.reversed()))
        #expect(ordered.map(\.text) == ["A page title", "Left 0", "Left 1", "Left 2", "Right 0", "Right 1", "Right 2"])
        let blocks = ReferencePageImporter.paragraphBlocks(ordered)
        #expect(blocks.count == 3)
        #expect(blocks[0].kind == .heading)
        #expect(blocks[1].text == "Left 0 Left 1 Left 2")
        #expect(blocks[2].text == "Right 0 Right 1 Right 2")
        let chinese = ReferencePageImporter.paragraphBlocks([
            .init(text: "中文正文", bounds: .init(x: 0.1, y: 0.7, width: 0.8, height: 0.03)),
            .init(text: "继续编辑。", bounds: .init(x: 0.1, y: 0.66, width: 0.8, height: 0.03)),
        ])
        #expect(chinese.first?.text == "中文正文继续编辑。")
    }

    @Test func localIntelligenceUsesRulesAndRejectsUnsupportedNumberedCodeWithoutModel() async throws {
        let result = try await LocalIntelligence.suggest("插入一个三列表格")
        #expect(result?.commandID == "table")
        #expect(result?.values["columns"] == "3")
        #expect(try await LocalIntelligence.suggest("给 Python 代码块加行号") == nil)
        await #expect(throws: LocalIntelligenceError.self) {
            try await LocalIntelligence.suggest(String(repeating: "a", count: 513))
        }
    }
}

private struct ReferenceFixture {
    let root: URL

    init() throws {
        root = TestPaths.temporaryDirectory.appendingPathComponent("reference-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    func write(_ data: Data, name: String) throws -> URL {
        let url = root.appendingPathComponent(name)
        try data.write(to: url)
        return url
    }

    func remove() {
        try? FileManager.default.removeItem(at: root)
    }
}

private func drawReferenceText(_ text: String, size: CGFloat, y: CGFloat, in context: CGContext) {
    let font = CTFontCreateWithName("Helvetica" as CFString, size, nil)
    let attributes: [NSAttributedString.Key: Any] = [
        NSAttributedString.Key(kCTFontAttributeName as String): font,
        NSAttributedString.Key(kCTForegroundColorAttributeName as String): CGColor(gray: 0, alpha: 1),
    ]
    let line = CTLineCreateWithAttributedString(NSAttributedString(string: text, attributes: attributes))
    context.textPosition = CGPoint(x: 50, y: y)
    CTLineDraw(line, context)
}

private func referencePDF(pages: [[(String, CGFloat, CGFloat)]], firstPageImage: CGImage? = nil) throws -> Data {
    let data = NSMutableData()
    let consumer = try #require(CGDataConsumer(data: data as CFMutableData))
    var bounds = CGRect(x: 0, y: 0, width: 612, height: 792)
    let context = try #require(CGContext(consumer: consumer, mediaBox: &bounds, nil))
    for (index, lines) in pages.enumerated() {
        context.beginPDFPage(nil)
        if index == 0, let firstPageImage {
            context.draw(firstPageImage, in: bounds)
        }
        for (text, size, y) in lines {
            drawReferenceText(text, size: size, y: y, in: context)
        }
        context.endPDFPage()
    }
    context.closePDF()
    return data as Data
}

private func referenceImage(width: Int, height: Int, text: [(String, CGFloat, CGFloat)] = []) throws -> CGImage {
    let context = try #require(CGContext(
        data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
        space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue,
    ))
    context.setFillColor(CGColor(gray: 1, alpha: 1))
    context.fill(CGRect(x: 0, y: 0, width: width, height: height))
    for (text, size, y) in text {
        drawReferenceText(text, size: size, y: y, in: context)
    }
    return try #require(context.makeImage())
}

private func pngData(_ image: CGImage) throws -> Data {
    let data = NSMutableData()
    let destination = try #require(CGImageDestinationCreateWithData(
        data as CFMutableData,
        UTType.png.identifier as CFString,
        1,
        nil,
    ))
    CGImageDestinationAddImage(destination, image, nil)
    #expect(CGImageDestinationFinalize(destination))
    return data as Data
}

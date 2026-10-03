import Foundation
@testable import LeftBlankCore
import LeftBlankTestSupport
import PDFKit
import Testing

@Test func simpleTypesettingRequestsUseRealBilingualCommandsAndParameters() throws {
    for (request, id, values) in [
        ("插入三行两列的表格", "table", ["rows": "3", "columns": "2"]),
        ("Create a table with 4 columns and 3 rows", "table", ["rows": "3", "columns": "4"]),
        ("插入二十行八列表格", "table", ["rows": "20", "columns": "8"]),
        ("Insert a table with two columns and four rows", "table", ["rows": "4", "columns": "2"]),
        ("请插入表格", "table", [:]),
        ("两栏排版", "columns", ["columns": "2"]),
        ("Use three columns", "columns", ["columns": "3"]),
        ("设为二级标题", "heading", ["level": "2"]),
        ("Insert heading level 3", "heading", ["level": "3"]),
        ("插入 Python 代码块", "code", ["language": "python"]),
        ("Insert a C++ code block", "code", ["language": "c++"]),
        ("Use A5 paper", "paper", ["paper": "a5"]),
        ("页边距 20 毫米", "margin", ["margin": "20"]),
        ("Set page margins to 20 mm", "margin", ["margin": "20"]),
        ("字号12磅", "fontSize", ["size": "12"]),
        ("Add page numbers", "pageNumber", [:]),
        ("添加标题编号", "headingNumbering", [:]),
        ("右对齐", "align", ["alignment": "right"]),
        ("插入无序列表", "bullet", [:]),
        ("Insert a numbered list", "numbered", [:]),
    ] {
        let suggestion = try #require(try TypesettingIntelligence.suggest(request), "\(request)")
        #expect(suggestion.commandID == id, "\(request)")
        #expect(suggestion.values == values, "\(request)")
        let command = try #require(suggestion.command)
        #expect(WritingCommand.all.contains { $0.id == command.id && $0.isInsertion })
        #expect(try !TypstInsertion.make(command.id, values: suggestion.values).text.isEmpty)
    }
}

@Test func typesettingRejectsUnsafeModelOutputsAndOutOfRangeParameters() throws {
    for suggestion in [
        TypesettingSuggestion(commandID: "missing"),
        .init(commandID: "import", values: ["path": "helpers.typ"]),
        .init(commandID: "include", values: ["path": "section.typ"]),
        .init(commandID: "image", values: ["path": "images/figure.png"]),
        .init(commandID: "table", values: ["columns": "3", "source": "#read(\"secret\")"]),
        .init(commandID: "pageNumber", values: ["numbering": "1"]),
        .init(commandID: "table", values: ["rows": "0"]),
        .init(commandID: "table", values: ["rows": "21"]),
        .init(commandID: "table", values: ["columns": "9"]),
        .init(commandID: "columns", values: ["columns": "1"]),
        .init(commandID: "heading", values: ["level": "7"]),
        .init(commandID: "code", values: ["language": "python\n#import \"helper.typ\": *"]),
        .init(commandID: "code", values: ["language": String(repeating: "x", count: 257)]),
        .init(commandID: "paper", values: ["paper": "a4\u{0}"]),
        .init(commandID: "margin", values: ["margin": "20); read(\"secret\")"]),
    ] {
        #expect(throws: CommandError.self) { try suggestion.validated() }
    }
    for request in ["9列表格", "0行表格", "21行表格", "2.5列表格", "-2列表格", "负二行表格", "五栏排版", "字号73磅", "边距1毫米",
                    "插入三列四列表格", "插入一百行表格"]
    {
        #expect(throws: CommandError.self) { try TypesettingIntelligence.suggest(request) }
    }
    #expect(throws: CommandError.self) { try TypesettingIntelligence.suggest("  \n ") }
    #expect(throws: CommandError.self) {
        try TypesettingIntelligence.suggest(String(
            repeating: "表",
            count: TypesettingIntelligence.maximumRequestLength + 1,
        ))
    }
}

@Test func ambiguousOrUnsupportedTypesettingDoesNotProduceAnAction() throws {
    for request in [
        "Please improve this",
        "Make this editable",
        "Comfortable spacing",
        "插入一个带行号的 Python 代码块",
        "Use Codly",
        "Insert numbered code",
        "Create a table and add a heading",
        "设置A4纸张和20毫米页边距",
        "加粗并斜体",
    ] {
        #expect(try TypesettingIntelligence.suggest(request) == nil)
    }
    #expect(TypesettingIntelligence.requiresNumberedCode("Python code with line numbers"))
    #expect(!TypesettingIntelligence.requiresNumberedCode("Add page numbers"))
}

@Test func typesettingSuggestionSchemaRejectsMalformedPayloads() throws {
    let expected = TypesettingSuggestion(commandID: "table", values: ["columns": "2", "rows": "3"])
    let restored = try JSONDecoder().decode(TypesettingSuggestion.self, from: JSONEncoder().encode(expected))
    #expect(try restored.validated() == expected)
    for json in [#"{"commandID":"table","values":{"columns":2}}"#,
                 #"{"commandID":"table","values":[]}"#, #"{"values":{}}"#]
    {
        #expect(throws: (any Error).self) {
            try JSONDecoder().decode(TypesettingSuggestion.self, from: Data(json.utf8))
        }
    }
    let unknown = try JSONDecoder().decode(
        TypesettingSuggestion.self,
        from: Data(##"{"commandID":"table","values":{"unknown":"#import"}}"##.utf8),
    )
    #expect(throws: CommandError.self) { try unknown.validated() }
}

@Test func reconstructedPageKeepsOCRSourceInsideEscapedLiterals() throws {
    let literal = "中文😀 Café #read(\"missing.txt\") #import \"missing.typ\": * $x$ [body] \\path\nnext\trow"
    let page = ReconstructedPage(blocks: [
        .init(kind: .heading, text: literal, level: 2),
        .init(kind: .paragraph, text: literal),
        .init(kind: .bulletList, items: [literal, "Second"]),
        .init(kind: .numberedList, items: ["First", literal]),
        .init(kind: .table, rows: [["Heading", literal], [literal, ""]]),
    ])
    let source = try page.typstSource()
    let quoted = TypstInsertion.quoted(literal)
    #expect(source.contains("#heading(level: 2, \(quoted))"))
    #expect(source.contains("#text(\(quoted))"))
    #expect(source.components(separatedBy: quoted).count == 7)
    #expect(quoted.contains("\\\"missing.typ\\\""))
    #expect(quoted.contains("\\\\path\\nnext\\trow"))
    #expect(source.contains("#table(\n  columns: 2,"))
    #expect(source.contains("#list("))
    #expect(source.contains("#enum("))
    let restored = try JSONDecoder().decode(ReconstructedPage.self, from: JSONEncoder().encode(page))
    #expect(restored == page)
    #expect(try restored.typstSource() == source)
}

@Test func reconstructionRejectsInvalidStructureAndOversizedOCR() {
    let invalidBlocks: [[ReconstructedBlock]] = [
        [],
        [.init(kind: .heading, text: "Title", level: 0)],
        [.init(kind: .paragraph, text: "Text", level: 2)],
        [.init(kind: .paragraph, text: "Text", items: ["ignored"])],
        [.init(kind: .paragraph, text: "  \n ")],
        [.init(kind: .paragraph, text: "unsupported\u{0}")],
        [.init(kind: .table, rows: [["One", "Two"], ["Ragged"]])],
        [.init(kind: .table, rows: [[]])],
        [.init(kind: .table, rows: [Array(repeating: "Cell", count: 9)])],
        [.init(kind: .table, rows: Array(repeating: ["Cell"], count: 22))],
        [.init(kind: .bulletList)],
        [.init(kind: .bulletList, items: ["One", ""])],
        [.init(kind: .numberedList, text: "ignored", items: ["One"])],
        [.init(kind: .numberedList, items: Array(repeating: "One", count: 101))],
        [.init(kind: .paragraph, text: String(repeating: "a", count: ReconstructedPage.maximumTextLength + 1))],
        [.init(kind: .paragraph, text: String(repeating: "a", count: 20001)),
         .init(kind: .paragraph, text: String(repeating: "b", count: 20000))],
        Array(repeating: .init(kind: .paragraph, text: "Text"), count: ReconstructedPage.maximumBlockCount + 1),
    ]
    for blocks in invalidBlocks {
        #expect(throws: CommandError.self) { try ReconstructedPage(blocks: blocks).typstSource() }
    }
    #expect(throws: (any Error).self) {
        try JSONDecoder().decode(ReconstructedPage.self, from: Data(#"{"blocks":[{"kind":"source"}]}"#.utf8))
    }
}

@MainActor
@Test(.enabled(if: ProcessInfo.processInfo.environment["LEFTBLANK_INTEGRATION"] == "1"))
func reconstructedLiteralBlocksCompileWithoutExecutingOCRInstructions() async throws {
    let root = TestPaths.temporaryDirectory.appendingPathComponent("LeftBlank-reconstructed-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let file = root.appendingPathComponent("page.typ")
    let hostile = "#read(\"missing.txt\") #import \"missing.typ\": * $x$ [body] \\path 中文😀"
    let page = ReconstructedPage(blocks: [
        .init(kind: .heading, text: "Recovered heading"),
        .init(kind: .paragraph, text: hostile),
        .init(kind: .bulletList, items: ["First bullet", hostile]),
        .init(kind: .numberedList, items: ["First step", "Second step"]),
        .init(kind: .table, rows: [["Column A", "Column B"], [hostile, "Editable cell"]]),
    ])
    let source = try page.typstSource()
    try Data(source.utf8).write(to: file)
    let client = TinymistClient()
    defer { client.stop() }
    try await client.start(root: root, outputDirectory: root)
    try client.open(file, text: source, version: 1)
    let result = try await client.command("tinymist.exportPdf", arguments: [file.path])
    let pdfPath = try #require(result["path"].string)
    let rendered = try #require(PDFDocument(url: URL(fileURLWithPath: pdfPath))?.string)
    #expect(rendered.contains("Recovered heading"))
    #expect(rendered.contains("missing.txt"))
    #expect(rendered.contains("missing.typ"))
    #expect(rendered.contains("Editable cell"))
    #expect(!FileManager.default.fileExists(atPath: root.appendingPathComponent("missing.txt").path))
}

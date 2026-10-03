import Foundation

/// Suggestions refer to existing commands and their fields. They never contain executable source.
public struct TypesettingSuggestion: Codable, Equatable, Sendable {
    public let commandID: String
    public let values: [String: String]

    public init(commandID: String, values: [String: String] = [:]) {
        self.commandID = commandID
        self.values = values
    }

    public var command: WritingCommand? {
        TypesettingIntelligence.catalog.first { $0.id == commandID }
    }

    @discardableResult
    public func validated() throws -> Self {
        guard let command else {
            throw CommandError.invalid("Choose a supported typesetting command.")
        }
        let fields = Set(command.fields.map(\.id))
        guard values.count <= fields.count, values.keys.allSatisfy(fields.contains) else {
            throw CommandError.invalid("The suggestion contains an unsupported command field.")
        }
        for value in values.values {
            try TypesettingIntelligence.validateLiteral(value, maximumLength: 256)
        }
        // Use the same validation as manual command execution, including numeric bounds and enums.
        _ = try TypstInsertion.make(commandID, values: values)
        return self
    }
}

public enum TypesettingIntelligence {
    public static let maximumRequestLength = 2000

    private static let commandIDs: Set<String> = [
        "heading", "table", "code", "bullet", "numbered", "columns", "align", "paper", "margin",
        "fontSize", "pageNumber", "language", "leading", "paragraphSpacing", "firstLineIndent", "justify",
        "headingNumbering", "bold", "italic", "highlight",
    ]

    /// Files, resource paths, imports and arbitrary expressions are deliberately outside this catalog.
    public static var catalog: [WritingCommand] {
        WritingCommand.all.filter { $0.isInsertion && commandIDs.contains($0.id) }
    }

    public static func requiresNumberedCode(_ request: String) -> Bool {
        let text = request.lowercased()
        return text.contains("codly") ||
            (containsAny(text, ["code", "codeblock", "代码"]) &&
                containsAny(text, ["行号", "line number", "line numbers", "numbered code"]))
    }

    /// A small offline baseline for straightforward requests. Ambiguous or unsupported requests return nil.
    public static func suggest(_ request: String) throws -> TypesettingSuggestion? {
        try validateLiteral(request, maximumLength: maximumRequestLength)
        let text = request.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !text.isEmpty else {
            throw CommandError.invalid("Describe the typesetting you want.")
        }
        guard !requiresNumberedCode(text) else {
            return nil
        }

        var candidates: [TypesettingSuggestion] = []
        func append(_ id: String, _ values: [String: String] = [:]) {
            candidates.append(.init(commandID: id, values: values))
        }

        if containsAny(text, ["table", "tables", "表格"]) {
            var values: [String: String] = [:]
            values["columns"] = try number(in: text, patterns: [before("列|columns?"), after("columns?")])
            values["rows"] = try number(in: text, patterns: [before("行|rows?"), after("rows?")])
            append("table", values)
        } else if containsAny(text, ["分栏", "栏排版", "栏布局", "columns", "column layout"]) {
            var values: [String: String] = [:]
            values["columns"] = try number(in: text, patterns: [before("栏|columns?"), after("columns?")])
            append("columns", values)
        }
        if containsAny(text, ["代码", "code block", "codeblock"]) {
            let languages = ["python", "swift", "rust", "javascript", "typescript", "java", "c++", "c", "go",
                             "sql", "json", "yaml", "bash", "sh", "typst"]
            let language = languages.first { language in
                text.range(
                    of: "(?<![a-z])" + NSRegularExpression.escapedPattern(for: language) + "(?![a-z])",
                    options: .regularExpression,
                ) != nil
            }
            append("code", language.map { ["language": $0] } ?? [:])
        }
        if containsAny(text, ["heading", "headings", "标题"]), !containsAny(text, ["heading numbering", "标题编号"]) {
            var values: [String: String] = [:]
            values["level"] = try number(in: text, patterns: [
                before("级标题|级\\s*heading"), after("heading\\s+level|level"), before("heading"),
            ])
            append("heading", values)
        }
        if containsAny(text, ["纸张", "paper", "页面大小", "page size", "a4", "a5", "us-letter"]) {
            let paper = ["a4", "a5", "us-letter"].first { text.contains($0) }
            append("paper", paper.map { ["paper": $0] } ?? [:])
        }
        if containsAny(text, ["页边距", "边距", "margin", "margins"]) {
            var values: [String: String] = [:]
            values["margin"] = try number(in: text, patterns: [
                before("mm|毫米"), after("margins?|页边距|边距"), before("页边距|边距"),
            ])
            append("margin", values)
        }
        if containsAny(text, ["字号", "font size", "号字"]) {
            var values: [String: String] = [:]
            values["size"] = try number(in: text, patterns: [
                before("pt|磅|号字"), after("font\\s+size|字号"),
            ])
            append("fontSize", values)
        }
        if containsAny(text, ["页码", "page number", "page numbers"]) {
            append("pageNumber")
        }
        if containsAny(text, ["heading numbering", "标题编号"]) {
            append("headingNumbering")
        }
        if containsAny(text, ["bullet list", "bulleted", "无序列表", "项目列表"]) {
            append("bullet")
        }
        if containsAny(text, ["numbered list", "有序列表", "编号列表"]) {
            append("numbered")
        }
        if containsAny(text, ["两端对齐", "justify", "justified"]) {
            append("justify")
        }
        if containsAny(text, ["居中", "center align", "centre align"]) {
            append("align", ["alignment": "center"])
        }
        if containsAny(text, ["左对齐", "left align"]) {
            append("align", ["alignment": "left"])
        }
        if containsAny(text, ["右对齐", "right align"]) {
            append("align", ["alignment": "right"])
        }
        if containsAny(text, ["加粗", "bold"]) {
            append("bold")
        }
        if containsAny(text, ["斜体", "italic"]) {
            append("italic")
        }
        if containsAny(text, ["高亮", "highlight"]) {
            append("highlight")
        }

        guard candidates.count == 1, let candidate = candidates.first else {
            return nil
        }
        return try candidate.validated()
    }

    static func validateLiteral(_ value: String, maximumLength: Int) throws {
        guard value.count <= maximumLength, value.utf8.count <= maximumLength * 4,
              value.unicodeScalars.allSatisfy({ $0.value >= 32 || [9, 10, 13].contains($0.value) })
        else {
            throw CommandError.invalid("The text is too long or contains unsupported control characters.")
        }
    }

    private static func containsAny(_ text: String, _ terms: [String]) -> Bool {
        terms.contains { term in
            if term.unicodeScalars.contains(where: { $0.value > 127 }) {
                return text.contains(term)
            }
            let pattern = "(?<![a-z0-9])" + NSRegularExpression.escapedPattern(for: term) + "(?![a-z0-9])"
            return text.range(of: pattern, options: .regularExpression) != nil
        }
    }

    private static let numberPattern = "([+-]?[0-9]+(?:\\.[0-9]+)?|负?[零〇一二两三四五六七八九十百千万]+|one|two|three|four|five|six|seven|eight|nine|ten|eleven|twelve|thirteen|fourteen|fifteen|sixteen|seventeen|eighteen|nineteen|twenty)"

    private static func before(_ unit: String) -> String {
        "(?<![0-9.a-z])" + numberPattern + "\\s*[- ]?\\s*(?:" + unit + ")(?![a-z])"
    }

    private static func after(_ label: String) -> String {
        "(?:" + label + ")\\s*[:：]?\\s*" + numberPattern + "(?![0-9.a-z])"
    }

    private static func number(in text: String, patterns: [String]) throws -> String? {
        var values = Set<String>()
        for pattern in patterns {
            let expression = try NSRegularExpression(pattern: pattern)
            for match in expression.matches(in: text, range: NSRange(text.startIndex..., in: text)) {
                guard let range = Range(match.range(at: 1), in: text), let value = integer(String(text[range])) else {
                    throw CommandError.invalid("Use a whole number for this setting.")
                }
                values.insert(String(value))
            }
        }
        guard values.count <= 1 else {
            throw CommandError.invalid("Specify one value for each typesetting setting.")
        }
        return values.first
    }

    private static func integer(_ text: String) -> Int? {
        if let value = Int(text) {
            return value
        }
        let english = ["one", "two", "three", "four", "five", "six", "seven", "eight", "nine", "ten",
                       "eleven", "twelve", "thirteen", "fourteen", "fifteen", "sixteen", "seventeen", "eighteen",
                       "nineteen", "twenty"]
        if let index = english.firstIndex(of: text) {
            return index + 1
        }
        let digits: [Character: Int] = ["零": 0, "〇": 0, "一": 1, "二": 2, "两": 2, "三": 3, "四": 4,
                                        "五": 5, "六": 6, "七": 7, "八": 8, "九": 9]
        let characters = Array(text)
        if characters.count == 1 {
            return text == "十" ? 10 : digits[characters[0]]
        }
        if characters.count == 2, characters[0] == "十", let ones = digits[characters[1]] {
            return 10 + ones
        }
        if characters.count == 2, characters[1] == "十", let tens = digits[characters[0]] {
            return tens * 10
        }
        if characters.count == 3, characters[1] == "十", let tens = digits[characters[0]],
           let ones = digits[characters[2]]
        {
            return tens * 10 + ones
        }
        return nil
    }
}

/// A single page's editable structure. All content is treated as literal text, including OCR output.
public struct ReconstructedBlock: Codable, Equatable, Sendable {
    public enum Kind: String, Codable, Sendable {
        case heading
        case paragraph
        case bulletList = "bulletList"
        case numberedList = "numberedList"
        case table
    }

    public let kind: Kind
    public let text: String
    public let level: Int
    public let items: [String]
    public let rows: [[String]]

    public init(kind: Kind, text: String = "", level: Int = 1, items: [String] = [], rows: [[String]] = []) {
        self.kind = kind
        self.text = text
        self.level = level
        self.items = items
        self.rows = rows
    }
}

public struct ReconstructedPage: Codable, Equatable, Sendable {
    public static let maximumTextLength = 40000
    public static let maximumBlockCount = 256
    public let blocks: [ReconstructedBlock]

    public init(blocks: [ReconstructedBlock]) {
        self.blocks = blocks
    }

    public func typstSource() throws -> String {
        guard !blocks.isEmpty, blocks.count <= Self.maximumBlockCount else {
            throw CommandError.invalid("Import one page with between 1 and 256 text blocks.")
        }
        var totalLength = 0
        func literal(_ text: String) throws -> String {
            try TypesettingIntelligence.validateLiteral(text, maximumLength: Self.maximumTextLength)
            totalLength += text.count
            guard totalLength <= Self.maximumTextLength else {
                throw CommandError.invalid("The page contains too much text to import.")
            }
            return TypstInsertion.quoted(text)
        }
        var rendered: [String] = []
        for block in blocks {
            switch block.kind {
            case .heading, .paragraph:
                guard block.items.isEmpty, block.rows.isEmpty,
                      !block.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                      block.kind == .heading ? (1 ... 6).contains(block.level) : block.level == 1
                else {
                    throw CommandError.invalid("The page contains an invalid text block.")
                }
                let text = try literal(block.text)
                rendered.append(block.kind == .heading ? "#heading(level: \(block.level), \(text))" : "#text(\(text))")
            case .bulletList, .numberedList:
                guard block.text.isEmpty, block.level == 1, block.rows.isEmpty,
                      (1 ... 100).contains(block.items.count),
                      block.items.allSatisfy({ !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty })
                else {
                    throw CommandError.invalid("The page contains an invalid list.")
                }
                let items = try block.items.map(literal).joined(separator: ",\n  ")
                rendered.append("#\(block.kind == .bulletList ? "list" : "enum")(\n  \(items),\n)")
            case .table:
                guard block.text.isEmpty, block.level == 1, block.items.isEmpty,
                      (1 ... 21).contains(block.rows.count), let columns = block.rows.first?.count,
                      (1 ... 8).contains(columns), block.rows.allSatisfy({ $0.count == columns })
                else {
                    throw CommandError.invalid("Import a rectangular table with at most 8 columns and 21 rows.")
                }
                let cells = try block.rows.flatMap(\.self).map(literal).joined(separator: ",\n  ")
                rendered.append("#table(\n  columns: \(columns),\n  inset: 8pt,\n  \(cells),\n)")
            }
        }
        return "#set page(paper: \"a4\", margin: 24mm)\n#set text(font: (\"Libertinus Serif\", \"PingFang SC\"), size: 11pt)\n\n" +
            rendered.joined(separator: "\n\n") + "\n"
    }
}

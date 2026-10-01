import Foundation

public struct CommandGroup: Identifiable, Sendable {
    public let id: String
    public let key: String
    public let title: String
    public let subtitle: String
    public let icon: String
    public static let all: [Self] = [
        .init(id: "insert", key: "i", title: "插入", subtitle: "标题、图片、公式与表格", icon: "plus-circle"),
        .init(id: "style", key: "s", title: "样式", subtitle: "让文字有恰当的强调", icon: "text-aa"),
        .init(id: "page", key: "p", title: "页面", subtitle: "纸张、留白与文字大小", icon: "file-text"),
        .init(id: "view", key: "v", title: "视图", subtitle: "专注写作，或看看成稿", icon: "sidebar-simple"),
        .init(id: "file", key: "f", title: "文件", subtitle: "打开、保存与导出", icon: "folder-open")
    ]
}

public struct CommandField: Identifiable, Sendable {
    public let id: String
    public let title: String
    public let initial: String
    public init(_ id: String, _ title: String, _ initial: String) {
        self.id = id; self.title = title; self.initial = initial
    }
}

public struct WritingCommand: Identifiable, Sendable {
    public let id: String
    public let group: String
    public let key: String
    public let title: String
    public let detail: String
    public let keywords: String
    public let fields: [CommandField]

    public init(_ id: String, _ group: String, _ key: String, _ title: String, _ detail: String, _ keywords: String = "", fields: [CommandField] = []) {
        self.id = id; self.group = group; self.key = key; self.title = title
        self.detail = detail; self.keywords = keywords; self.fields = fields
    }

    public static let all: [Self] = [
        .init("heading", "insert", "h", "标题", "为当前段落添加标题层级。", "heading title 标题", fields: [.init("level", "标题层级 · 1–6", "1")]),
        .init("image", "insert", "i", "图片", "插入图片，并为它添加说明。", "image figure 图片", fields: [.init("path", "图片路径", "images/figure.png"), .init("caption", "图片说明", "图片说明")]),
        .init("table", "insert", "t", "表格", "生成一个清晰的表格，Tab 在单元格之间移动。", "table rows columns 表格", fields: [.init("columns", "列数 · 1–8", "3"), .init("rows", "内容行数 · 1–20", "2")]),
        .init("math", "insert", "m", "行内公式", "在段落中插入 $公式$。", "math equation 数学"),
        .init("equation", "insert", "e", "独立公式", "让公式独占一行，保留清晰的呼吸空间。", "block equation 数学"),
        .init("code", "insert", "c", "代码块", "插入指定语言的代码片段。", "code programming 代码", fields: [.init("language", "代码语言", "rust")]),
        .init("link", "insert", "l", "链接", "为选中的文字添加链接。", "link url 网址", fields: [.init("url", "链接地址", "https://typst.app")]),
        .init("bullet", "insert", "b", "无序列表", "逐条整理你的想法。", "bullet list 列表"),
        .init("numbered", "insert", "n", "有序列表", "用编号表达顺序和步骤。", "numbered list 列表"),
        .init("quote", "insert", "q", "引用段落", "引用一段值得保留的文字。", "quote quotation 引用"),
        .init("footnote", "insert", "f", "脚注", "补充背景，同时保持正文流畅。", "footnote note 注释"),
        .init("label", "insert", "a", "标签", "给标题、公式或图片一个可引用的名字。", "label anchor 标签", fields: [.init("name", "标签名称", "section-intro")]),
        .init("reference", "insert", "r", "交叉引用", "引用已有标签；目标标题、公式或图片需要开启编号。", "reference cross 引用", fields: [.init("name", "标签名称", "section-intro")]),
        .init("bold", "style", "b", "加粗", "用 *文字* 强调选中的内容。", "bold strong 加粗"),
        .init("italic", "style", "i", "斜体", "用 _文字_ 设置斜体。", "italic emphasis 斜体"),
        .init("highlight", "style", "h", "高亮", "为选中的文字加上背景标记。", "highlight mark 高亮"),
        .init("paper", "page", "p", "纸张尺寸", "在文稿顶部设置纸张。", "paper a4 letter", fields: [.init("paper", "纸张 · a4 / us-letter / a5", "a4")]),
        .init("margin", "page", "m", "页边距", "在文稿顶部设置统一的页面留白。", "margin page 边距", fields: [.init("margin", "页边距 · 毫米", "24")]),
        .init("fontSize", "page", "s", "成稿字号", "设置排版输出的正文字号。", "font size 字号", fields: [.init("size", "字号 · pt", "11")]),
        .init("pageNumber", "page", "n", "页码", "为页面添加居中页码。", "page number 页码"),
        .init("writing", "view", "w", "专注写作", "留出整个窗口，给正在写的文字。", "focus writing 专注"),
        .init("split", "view", "s", "并排预览", "一边写作，一边查看 Typst 成稿。", "split preview 分屏"),
        .init("preview", "view", "p", "阅读成稿", "用整个窗口查看排版结果。", "preview reading 预览"),
        .init("outline", "view", "o", "文稿大纲", "沿着标题整理文章的结构。", "outline headings 大纲"),
        .init("diagnostics", "view", "d", "检查文稿", "查看错误和建议，并跳转到对应位置。", "diagnostics errors 错误"),
        .init("revealPreview", "view", "r", "在成稿中定位", "找到光标所在段落的排版位置。", "reveal jump sync 定位"),
        .init("restart", "view", "l", "重新连接排版服务", "重启 Tinymist，并重新同步当前文稿。", "restart language server"),
        .init("new", "file", "n", "新建文稿", "从一张安静的空白页开始。", "new document 新建"),
        .init("open", "file", "o", "打开文稿", "打开一个 .typ 文件。", "open file 打开"),
        .init("save", "file", "s", "保存", "将当前文稿保存到磁盘。", "save 保存"),
        .init("saveAs", "file", "a", "另存为", "为文稿选择新的名称和位置。", "save as 另存为"),
        .init("export", "file", "e", "导出 PDF", "把当前文稿排版为可分享的 PDF。", "export pdf 导出"),
        .init("drafts", "file", "d", "恢复草稿副本", "重新打开切换文稿时保留的草稿或重新加载前的副本。", "draft recovery 恢复"),
        .init("reload", "file", "r", "重新加载磁盘版本", "本地编辑先保留为恢复副本，再读取磁盘文件。", "reload disk conflict 重新加载")
    ]

    public static func search(_ query: String) -> [Self] {
        let words = query.lowercased().split(whereSeparator: \.isWhitespace)
        return all.filter { command in
            let haystack = "\(command.title) \(command.keywords) \(command.detail)".lowercased()
            return words.allSatisfy { haystack.contains($0) }
        }
    }
}

public struct Snippet: Equatable, Sendable {
    public let text: String
    public let selections: [NSRange]
    public init(text: String, selections: [NSRange] = []) { self.text = text; self.selections = selections }

    public func padded(before: String, after: String) -> Snippet {
        Snippet(text: before + text + after, selections: selections.map { NSRange(location: $0.location + before.utf16.count, length: $0.length) })
    }

    public func replacingLiteral(_ token: String, with value: String) -> Snippet {
        let source = text as NSString
        let range = source.range(of: token)
        guard range.location != NSNotFound else { return self }
        let delta = value.utf16.count - range.length
        return Snippet(text: source.replacingCharacters(in: range, with: value), selections: selections.map {
            NSRange(location: $0.location >= NSMaxRange(range) ? $0.location + delta : $0.location, length: $0.length)
        })
    }

    public init(_ marked: String) {
        var output = ""
        var ranges: [NSRange] = []
        var cursor = marked.startIndex
        while let open = marked[cursor...].firstIndex(of: "«"), let close = marked[marked.index(after: open)...].firstIndex(of: "»") {
            output += marked[cursor..<open]
            let content = String(marked[marked.index(after: open)..<close])
            ranges.append(NSRange(location: output.utf16.count, length: content.utf16.count))
            output += content
            cursor = marked.index(after: close)
        }
        output += marked[cursor...]
        self.text = output
        self.selections = ranges
    }
}

public enum CommandError: LocalizedError {
    case invalid(String)
    public var errorDescription: String? { switch self { case .invalid(let message): message } }
}

public enum TypstInsertion {
    public static func quoted(_ value: String) -> String {
        "\"" + value.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"").replacingOccurrences(of: "\n", with: "\\n").replacingOccurrences(of: "\r", with: "\\r").replacingOccurrences(of: "\t", with: "\\t") + "\""
    }

    public static func make(_ id: String, values: [String: String] = [:], selection: String = "") throws -> Snippet {
        func value(_ key: String, _ fallback: String) -> String { values[key] ?? fallback }
        func number(_ key: String, _ fallback: String, _ range: ClosedRange<Int>) throws -> Int {
            guard let n = Int(value(key, fallback)), range.contains(n) else { throw CommandError.invalid("请输入 \(range.lowerBound)–\(range.upperBound) 之间的整数。") }
            return n
        }
        func label() throws -> String {
            let name = value("name", "section-intro")
            guard name.range(of: "^[A-Za-z][A-Za-z0-9_-]*$", options: .regularExpression) != nil else { throw CommandError.invalid("标签请以英文字母开头，使用字母、数字、短横线或下划线。") }
            return name
        }
        var literals: [(String, String)] = []
        func protect(_ value: String) -> String {
            let token = "SUMI_LITERAL_" + UUID().uuidString
            literals.append((token, value))
            return token
        }
        func snippet(_ marked: String) -> Snippet {
            literals.reduce(Snippet(marked)) { $0.replacingLiteral($1.0, with: $1.1) }
        }
        let selectedSource = protect(selection)
        let selected = selection.isEmpty ? "«文字»" : selectedSource
        switch id {
        case "heading": return snippet(String(repeating: "=", count: try number("level", "1", 1...6)) + " " + (selection.isEmpty ? "«标题»" : selectedSource))
        case "bold": return snippet("*\(selected)*")
        case "italic": return snippet("_\(selected)_")
        case "highlight": return snippet("#highlight[\(selected)]")
        case "math": return snippet("$\(selection.isEmpty ? "«x^2 + y^2»" : selectedSource)$")
        case "equation": return snippet("\n$ \(selection.isEmpty ? "«E = m c^2»" : selectedSource) $\n")
        case "bullet": return snippet("- \(selection.isEmpty ? "«第一项»" : selectedSource)\n- «第二项»")
        case "numbered": return snippet("+ \(selection.isEmpty ? "«第一步»" : selectedSource)\n+ «第二步»")
        case "quote": return snippet("#quote(block: true)[\n  \(selected)\n]")
        case "footnote": return snippet("#footnote[\(selected)]")
        case "label": return snippet("<\(try label())>")
        case "reference": return snippet("@\(try label())")
        case "link": return snippet("#link(\(protect(quoted(value("url", "https://typst.app")))))[\(selected)]")
        case "image": return snippet("#figure(\n  image(\(protect(quoted(value("path", "images/figure.png")))), width: 80%),\n  caption: \(protect(quoted(value("caption", "图片说明")))),\n)")
        case "code":
            let language = value("language", "rust")
            guard language.range(of: "^[A-Za-z0-9_+-]*$", options: .regularExpression) != nil else { throw CommandError.invalid("代码语言只能包含字母、数字、下划线、加号或短横线。") }
            let backticks = selection.split(whereSeparator: { $0 != "`" }).map(\.count).max() ?? 0
            let fence = String(repeating: "`", count: max(3, backticks + 1))
            return snippet("\(fence)\(language)\n\(selection.isEmpty ? "«// 在这里写代码»" : selectedSource)\n\(fence)")
        case "table":
            let columns = try number("columns", "3", 1...8)
            let rows = try number("rows", "2", 1...20)
            var source = "#table(\n  columns: \(columns),\n  inset: 10pt,\n  table.header(\(Array(1...columns).map { "[«标题\($0)»]" }.joined(separator: ", "))),\n"
            for row in 1...rows { source += "  " + (1...columns).map { "[«内容\(row).\($0)»]" }.joined(separator: ", ") + ",\n" }
            return snippet(source + ")")
        case "paper":
            let paper = value("paper", "a4").lowercased()
            guard ["a4", "a5", "us-letter"].contains(paper) else { throw CommandError.invalid("纸张请选择 a4、a5 或 us-letter。") }
            return snippet("#set page(paper: \(quoted(paper)))\n")
        case "margin": return snippet("#set page(margin: \(try number("margin", "24", 5...80))mm)\n")
        case "fontSize": return snippet("#set text(size: \(try number("size", "11", 6...72))pt)\n")
        case "pageNumber": return snippet("#set page(numbering: \"1\")\n")
        default: throw CommandError.invalid("这个命令不能插入文字。")
        }
    }
}

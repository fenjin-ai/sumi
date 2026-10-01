import Foundation

public struct CommandGroup: Identifiable, Sendable {
    public let id: String
    public let key: String
    public let title: String
    public let subtitle: String
    public let icon: String
    public let parentID: String?

    public init(id: String, key: String, title: String, subtitle: String, icon: String, parentID: String? = nil) {
        self.id = id; self.key = key; self.title = title; self.subtitle = subtitle
        self.icon = icon; self.parentID = parentID
    }

    public static var roots: [Self] { children(of: nil) }
    public static func children(of parentID: String?) -> [Self] { all.filter { $0.parentID == parentID } }
    public static let all: [Self] = [
        .init(id: "insert", key: "i", title: "插入内容", subtitle: "标题、图片、公式与表格", icon: "plus-circle"),
        .init(id: "style", key: "s", title: "文字样式", subtitle: "让文字有恰当的强调", icon: "text-aa"),
        .init(id: "page", key: "p", title: "纸张设置", subtitle: "纸张、页边距与页码", icon: "file"),
        .init(id: "math", key: "m", title: "数学", subtitle: "从分式到矩阵，逐层发现", icon: "sigma"),
        .init(id: "layout", key: "l", title: "文稿排版", subtitle: "文稿中的分栏、对齐与容器", icon: "layout"),
        .init(id: "references", key: "r", title: "引用与目录", subtitle: "引文、书目与文章导航", icon: "books"),
        .init(id: "code", key: "c", title: "编辑与代码", subtitle: "编辑操作、代码与 Universe", icon: "brackets-curly"),
        .init(id: "view", key: "v", title: "工作空间", subtitle: "编辑器、预览与辅助工具", icon: "desktop"),
        .init(id: "file", key: "f", title: "文件", subtitle: "打开、保存与导出", icon: "folder-open"),
        .init(id: "math-basic", key: "b", title: "基本运算", subtitle: "分式、根式与上下标", icon: "function", parentID: "math"),
        .init(id: "math-structures", key: "s", title: "公式结构", subtitle: "矩阵、分段函数与微积分", icon: "grid-four", parentID: "math"),
        .init(id: "math-symbols", key: "y", title: "符号与字形", subtitle: "希腊字母、集合与向量", icon: "pi", parentID: "math")
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

public enum InsertionPlacement: Sendable { case inline, block, preamble }
public enum InsertionContext: String, Sendable { case markup, math }

public struct WritingCommand: Identifiable, Sendable {
    public let id: String
    public let group: String
    public let key: String
    public let title: String
    public let detail: String
    public let keywords: String
    public let fields: [CommandField]
    public let placement: InsertionPlacement
    public let supportsMath: Bool
    private let documentationPath: String?

    public let isInsertion: Bool
    public var documentationURL: URL? {
        guard isInsertion else { return nil }
        return URL(string: "https://typst.app/docs/reference/" + (documentationPath ?? Self.documentationPath(for: id)))
    }
    public var example: String? { Self.examples[id] }
    private static let examples = Dictionary(uniqueKeysWithValues: all.filter(\.isInsertion).compactMap { command in
        (try? TypstInsertion.make(command.id).text).map { (command.id, $0) }
    })
    public var keyPath: String { Self.keyPaths[id] ?? key }
    private static let keyPaths: [String: String] = Dictionary(uniqueKeysWithValues: all.map { command in
        var path = [command.key]
        var group = CommandGroup.all.first { $0.id == command.group }
        while let current = group {
            path.insert(current.key, at: 0)
            group = CommandGroup.all.first { $0.id == current.parentID }
        }
        return (command.id, path.joined(separator: " "))
    })
    public var shortcuts: [DirectShortcut] { Self.directShortcuts[id] ?? [] }
    private static let directShortcuts: [String: [DirectShortcut]] = [
        "writing": [.init("1")], "split": [.init("2")], "preview": [.init("3")],
        "outline": [.init("4")], "diagnostics": [.init("5")],
        "new": [.init("n")], "open": [.init("o")], "save": [.init("s")],
        "saveAs": [.init("s", modifiers: [.shift, .command])], "export": [.init("e", modifiers: [.shift, .command])],
        "universe": [.init("u", modifiers: [.shift, .command])],
        "completion": [.init(".", modifiers: [.control])],
        "undo": [.init("z")], "redo": [.init("z", modifiers: [.shift, .command])],
        "cut": [.init("x")], "copy": [.init("c")], "paste": [.init("v")], "selectAll": [.init("a")], "find": [.init("f")],
        "fontLarger": [.init("+")], "fontSmaller": [.init("-")],
        "indent": [.init("]")], "outdent": [.init("[")], "comment": [.init("/")],
        "format": [.init("f", modifiers: [.option, .shift])]
    ]
    public var icon: String { Self.icons[id] ?? "command" }
    private static let icons: [String: String] = [
        "undo": "arrow-counter-clockwise", "redo": "arrow-clockwise", "cut": "scissors", "copy": "copy", "paste": "clipboard",
        "selectAll": "selection-all", "find": "magnifying-glass", "fontLarger": "magnifying-glass-plus", "fontSmaller": "magnifying-glass-minus",
        "heading": "text-h",
        "image": "image",
        "table": "table",
        "math": "math-operations",
        "equation": "equals",
        "code": "file-code",
        "link": "link",
        "bullet": "list-bullets",
        "numbered": "list-numbers",
        "quote": "quotes",
        "footnote": "asterisk-simple",
        "label": "tag-simple",
        "reference": "link-simple-horizontal",
        "terms": "book-open-text",
        "lineBreak": "arrow-elbow-down-left",
        "bold": "text-b",
        "italic": "text-italic",
        "highlight": "highlighter",
        "underline": "text-underline",
        "strike": "text-strikethrough",
        "superscript": "text-superscript",
        "subscript": "text-subscript",
        "smallcaps": "text-aa",
        "textColor": "text-a-underline",
        "paper": "file",
        "margin": "bounding-box",
        "fontSize": "arrows-out",
        "pageNumber": "number-square-one",
        "font": "text-t",
        "language": "translate",
        "leading": "arrows-out-line-vertical",
        "paragraphSpacing": "paragraph",
        "firstLineIndent": "arrow-line-right",
        "justify": "text-align-justify",
        "headingNumbering": "text-h-one",
        "equationNumbering": "number-circle-one",
        "header": "align-top-simple",
        "footer": "align-bottom-simple",
        "documentInfo": "info",
        "fraction": "divide",
        "squareRoot": "radical",
        "nthRoot": "function",
        "power": "arrow-up-right",
        "mathSubscript": "arrow-down-right",
        "binomial": "brackets-round",
        "matrix": "grid-four",
        "vector": "dots-three-vertical",
        "cases": "brackets-curly",
        "aligned": "list",
        "sum": "sigma",
        "integral": "wave-sine",
        "limit": "arrow-line-down",
        "greek": "pi",
        "setMembership": "intersect",
        "arrow": "arrow-right",
        "upright": "text-align-left",
        "accent": "arrow-line-up",
        "align": "text-align-center",
        "columns": "columns",
        "grid": "grid-nine",
        "block": "textbox",
        "padding": "arrows-in-simple",
        "stack": "stack-simple",
        "pageBreak": "file-dashed",
        "verticalSpace": "arrows-vertical",
        "horizontalSpace": "arrows-horizontal",
        "divider": "minus",
        "contents": "list-dashes",
        "bibliography": "books",
        "citation": "book-bookmark",
        "include": "files",
        "import": "package",
        "variable": "code",
        "rawInline": "brackets-angle",
        "universe": "planet",
        "format": "broom",
        "indent": "text-indent",
        "outdent": "text-outdent",
        "comment": "chat-text",
        "completion": "magic-wand",
        "writing": "pencil-simple",
        "split": "sidebar-simple",
        "preview": "eye",
        "outline": "tree-structure",
        "diagnostics": "warning-circle",
        "revealPreview": "crosshair",
        "restart": "plugs-connected",
        "logs": "terminal-window",
        "previewDark": "moon",
        "styledSource": "sparkle",
        "new": "file-plus",
        "open": "folder-open",
        "save": "floppy-disk",
        "saveAs": "floppy-disk-back",
        "export": "file-pdf",
        "drafts": "clock-counter-clockwise",
        "reload": "arrows-clockwise",
    ]
    public func acceptsContext(_ mode: String) -> Bool { mode == "markup" || (supportsMath && mode == "math") }

    public init(_ id: String, _ group: String, _ key: String, _ title: String, _ detail: String, _ keywords: String = "", fields: [CommandField] = [], placement: InsertionPlacement? = nil, supportsMath: Bool = false, documentation: String? = nil, isInsertion: Bool? = nil) {
        self.id = id; self.group = group; self.key = key; self.title = title
        self.detail = detail; self.keywords = keywords; self.fields = fields
        self.placement = placement ?? (group == "page" ? .preamble : (["heading", "bullet", "numbered", "quote", "image", "table", "code", "equation"].contains(id) ? .block : .inline))
        self.supportsMath = supportsMath
        self.documentationPath = documentation
        self.isInsertion = isInsertion ?? (group != "view" && group != "file")
    }

    private static func documentationPath(for id: String) -> String {
        switch id {
        case "heading", "table", "quote", "footnote", "link": return "model/\(id)/"
        case "bullet": return "model/list/"
        case "numbered": return "model/enum/"
        case "reference": return "model/ref/"
        case "label": return "foundations/label/"
        case "image": return "visualize/image/"
        case "bold": return "model/strong/"
        case "italic": return "model/emph/"
        case "highlight": return "text/highlight/"
        case "code": return "text/raw/"
        case "math", "equation": return "math/equation/"
        case "fontSize": return "text/text/"
        case "paper", "margin", "pageNumber": return "layout/page/"
        default: return "syntax/"
        }
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
        .init("terms", "insert", "d", "术语定义", "让术语和说明成对排列。", "terms definition glossary 名词 定义列表", placement: .block, documentation: "model/terms/"),
        .init("lineBreak", "insert", "w", "换行", "在当前段落内换行，不开始新的段落。", "linebreak soft break 换行 断行", documentation: "text/linebreak/"),
        .init("bold", "style", "b", "加粗", "用 *文字* 强调选中的内容。", "bold strong 加粗"),
        .init("italic", "style", "i", "斜体", "用 _文字_ 设置斜体。", "italic emphasis 斜体"),
        .init("highlight", "style", "h", "高亮", "为选中的文字加上背景标记。", "highlight mark 高亮"),
        .init("underline", "style", "u", "下划线", "给选中的文字添加下划线。", "underline 下划线", documentation: "text/underline/"),
        .init("strike", "style", "s", "删除线", "保留文字，同时表示删除或修订。", "strike strikethrough 删除线 划掉", documentation: "text/strike/"),
        .init("superscript", "style", "p", "文字上标", "插入上标文字，例如序数或单位。", "super superscript 上标", documentation: "text/super/"),
        .init("subscript", "style", "d", "文字下标", "插入下标文字，例如化学式。", "sub subscript 下标", documentation: "text/sub/"),
        .init("smallcaps", "style", "a", "小型大写", "以小型大写字形排印英文。", "smallcaps capitals 大写", documentation: "text/smallcaps/"),
        .init("textColor", "style", "c", "文字颜色", "用十六进制色值设置选中文字的颜色。", "text fill color 颜色", fields: [.init("color", "颜色 · 十六进制", "245c73")], documentation: "text/text/"),
        .init("paper", "page", "p", "纸张尺寸", "在文稿顶部设置纸张。", "paper a4 letter", fields: [.init("paper", "纸张 · a4 / us-letter / a5", "a4")]),
        .init("margin", "page", "m", "页边距", "在文稿顶部设置统一的页面留白。", "margin page 边距", fields: [.init("margin", "页边距 · 毫米", "24")]),
        .init("fontSize", "page", "s", "成稿字号", "设置排版输出的正文字号。", "font size 字号", fields: [.init("size", "字号 · pt", "11")]),
        .init("pageNumber", "page", "n", "页码", "为页面添加居中页码。", "page number 页码"),
        .init("font", "page", "f", "正文字体", "设置成稿字体；可使用本机已经安装的字体名称。", "font family 字体 宋体 黑体", fields: [.init("font", "字体名称", "Libertinus Serif")], documentation: "text/text/#parameters-font"),
        .init("language", "page", "l", "文稿语言", "设置语言代码，影响断词和自动生成的标题。", "language locale 中文 英文 语言", fields: [.init("language", "语言代码 · zh / en / ja", "zh")], documentation: "text/text/#parameters-lang"),
        .init("leading", "page", "g", "行间距", "设置相邻文字行之间的额外留白。", "leading line spacing 行距", fields: [.init("amount", "行间距 · em", "0.65")], documentation: "model/par/#parameters-leading"),
        .init("paragraphSpacing", "page", "b", "段落间距", "设置段落之间的留白。", "paragraph spacing 段间距", fields: [.init("amount", "段落间距 · em", "1.2")], documentation: "model/par/#parameters-spacing"),
        .init("firstLineIndent", "page", "i", "首行缩进", "为普通段落设置首行缩进。", "indent first line 首行缩进", fields: [.init("amount", "首行缩进 · em", "2")], documentation: "model/par/#parameters-first-line-indent"),
        .init("justify", "page", "j", "两端对齐", "让正文段落同时对齐左右边缘。", "justify paragraph 两端对齐", documentation: "model/par/#parameters-justify"),
        .init("headingNumbering", "page", "h", "标题编号", "为各级标题启用分层编号。", "heading numbering 标题 章节 编号", documentation: "model/heading/#parameters-numbering"),
        .init("equationNumbering", "page", "e", "公式编号", "为独立公式启用括号编号。", "equation numbering 数学 公式 编号", documentation: "math/equation/#parameters-numbering"),
        .init("header", "page", "a", "页眉", "在每页顶部加入固定文字。", "header 页眉", fields: [.init("text", "页眉文字", "文稿标题")], documentation: "layout/page/#parameters-header"),
        .init("footer", "page", "o", "页脚", "在每页底部加入固定文字；会替代默认页码位置。", "footer 页脚", fields: [.init("text", "页脚文字", "草稿")], documentation: "layout/page/#parameters-footer"),
        .init("documentInfo", "page", "d", "文档元信息", "设置 PDF 的标题和作者。", "document metadata title author 作者 元数据", fields: [.init("title", "文档标题", "未命名文稿"), .init("author", "作者", "作者")], documentation: "model/document/"),
        .init("fraction", "math-basic", "f", "分式", "插入分子与分母；在公式内部会直接插入数学语法。", "frac fraction 分数 分式", supportsMath: true, documentation: "math/frac/"),
        .init("squareRoot", "math-basic", "r", "平方根", "对选中公式开平方，或填写新的被开方数。", "sqrt root 根号 根式 平方根", supportsMath: true, documentation: "math/roots/"),
        .init("nthRoot", "math-basic", "n", "任意次根", "插入可以编辑次数的根式。", "root nth cube 立方根 次方根", supportsMath: true, documentation: "math/roots/"),
        .init("power", "math-basic", "p", "幂与上标", "为选中的表达式添加指数。", "power exponent superscript 幂 指数 数学上标", supportsMath: true, documentation: "math/attach/"),
        .init("mathSubscript", "math-basic", "s", "数学下标", "为选中的表达式添加下标。", "subscript index 数学下标 索引", supportsMath: true, documentation: "math/attach/"),
        .init("binomial", "math-basic", "b", "二项式系数", "插入组合数的上下排列形式。", "binom binomial combination 组合数 二项式", supportsMath: true, documentation: "math/binom/"),
        .init("matrix", "math-structures", "m", "矩阵", "逗号分隔列，分号分隔行；Tab 在元素之间移动。", "mat matrix 矩阵 线性代数", supportsMath: true, documentation: "math/mat/"),
        .init("vector", "math-structures", "v", "列向量", "插入竖向排列的向量元素。", "vec vector 列向量", supportsMath: true, documentation: "math/vec/"),
        .init("cases", "math-structures", "c", "分段函数", "用大括号组织表达式与适用条件。", "cases piecewise 分段 条件函数", supportsMath: true, documentation: "math/cases/"),
        .init("aligned", "math-structures", "a", "多行对齐公式", "使用 & 对齐等号，反斜杠开始下一行。", "aligned multiline equation 对齐 方程组 多行", supportsMath: true, documentation: "math/#alignment"),
        .init("sum", "math-structures", "s", "求和", "插入求和符号、上下限和通项。", "sum summation sigma 求和 累加", supportsMath: true, documentation: "math/attach/"),
        .init("integral", "math-structures", "i", "积分", "插入定积分与微分符号。", "integral calculus 积分 微积分", supportsMath: true, documentation: "symbols/sym/"),
        .init("limit", "math-structures", "l", "极限", "插入变量趋近条件和表达式。", "lim limit 极限 趋于", supportsMath: true, documentation: "math/op/"),
        .init("greek", "math-symbols", "g", "希腊字母", "用名称输入希腊字母，Tab 可逐个替换示例。", "alpha beta gamma Greek 希腊 阿尔法 贝塔", supportsMath: true, documentation: "symbols/sym/"),
        .init("setMembership", "math-symbols", "s", "集合与数域", "插入集合属于关系与实数域。", "set membership RR NN ZZ 属于 集合 实数 自然数", supportsMath: true, documentation: "symbols/sym/"),
        .init("arrow", "math-symbols", "a", "箭头与映射", "插入从一个表达式到另一个表达式的箭头。", "arrow mapping maps to 箭头 映射", supportsMath: true, documentation: "symbols/sym/"),
        .init("upright", "math-symbols", "u", "数学直立体", "让单位或数学文字使用直立字形。", "upright roman unit 直立体 单位", supportsMath: true, documentation: "math/variants/"),
        .init("accent", "math-symbols", "v", "向量箭头", "在表达式上方添加向量箭头。", "accent arrow vector 矢量 向量箭头", supportsMath: true, documentation: "math/accent/"),
        .init("align", "layout", "a", "内容对齐", "设置一段内容的水平对齐方式。", "align center left right 居中 左对齐 右对齐", fields: [.init("alignment", "对齐 · left / center / right", "center")], placement: .block, documentation: "layout/align/"),
        .init("columns", "layout", "c", "分栏", "将一段内容排成两栏或更多栏。", "columns newspaper 分栏 双栏", fields: [.init("columns", "栏数 · 2–4", "2")], placement: .block, documentation: "layout/columns/"),
        .init("grid", "layout", "g", "布局网格", "用网格并排组织内容；展示数据请使用表格。", "grid layout 网格 布局", placement: .block, documentation: "layout/grid/"),
        .init("block", "layout", "b", "提示框", "用浅色背景和内边距突出一段内容。", "block callout box 提示框 色块 容器", placement: .block, documentation: "layout/block/"),
        .init("padding", "layout", "p", "内容留白", "在内容四周添加内边距。", "pad padding 内边距 留白", fields: [.init("amount", "内边距 · pt", "12")], placement: .block, documentation: "layout/pad/"),
        .init("stack", "layout", "s", "横向排列", "将两个内容块横向排列，并保持间距。", "stack horizontal 横向 排列", placement: .block, documentation: "layout/stack/"),
        .init("pageBreak", "layout", "n", "分页", "让后续内容从新的一页开始。", "pagebreak new page 分页 换页", placement: .block, documentation: "layout/pagebreak/"),
        .init("verticalSpace", "layout", "v", "垂直间距", "在内容块之间插入指定高度的留白。", "vertical v spacing 垂直间距 空行", fields: [.init("amount", "间距 · pt", "12")], placement: .block, documentation: "layout/v/"),
        .init("horizontalSpace", "layout", "h", "水平间距", "在同一行中插入指定宽度的留白。", "horizontal h spacing 水平间距 空格", fields: [.init("amount", "间距 · pt", "12")], documentation: "layout/h/"),
        .init("divider", "layout", "d", "分隔线", "用一条细线划分文章内容。", "line divider rule 分隔线 横线", placement: .block, documentation: "visualize/line/"),
        .init("contents", "references", "o", "文稿目录", "根据标题生成带页码的目录。", "outline contents toc 目录", placement: .block, documentation: "model/outline/"),
        .init("bibliography", "references", "b", "参考文献表", "从 BibLaTeX 或 Hayagriva 文件生成书目。", "bibliography references bib yaml 参考文献 书目", fields: [.init("path", "文献文件 · .bib / .yaml", "references.bib")], placement: .block, documentation: "model/bibliography/"),
        .init("citation", "references", "c", "引用文献", "通过文献条目的键引用来源；需要文稿中已有参考文献表。", "cite citation bibliography 文献 引文", fields: [.init("name", "文献键", "example")], documentation: "model/cite/"),
        .init("include", "code", "i", "包含子文稿", "在当前位置排版另一个 .typ 文件的内容。", "include chapter subdocument 包含 子文稿 章节", fields: [.init("path", "子文稿路径", "section.typ")], placement: .block, documentation: "scripting/#modules"),
        .init("import", "code", "m", "导入本地模块", "在文稿顶部导入可复用的本地定义。", "import module local 模块 导入", fields: [.init("path", "模块路径", "helpers.typ")], placement: .preamble, documentation: "scripting/#modules"),
        .init("variable", "code", "v", "定义变量", "定义可在后文通过 #名称 使用的文字变量。", "let variable binding 定义 变量", fields: [.init("name", "变量名称", "project"), .init("value", "变量文字", "Sumi")], placement: .preamble, documentation: "scripting/#bindings"),
        .init("rawInline", "code", "r", "行内代码", "把选中内容按原样显示，不解释其中的 Typst 语法。", "raw inline code 行内代码 原样", documentation: "text/raw/"),
        .init("universe", "code", "u", "发现 Universe 包", "寻找绘图、图表和排版扩展，插入带版本的导入语句。", "universe package plugin cetz fletcher 绘图 扩展 插件 包", isInsertion: false),
        .init("format", "code", "f", "整理代码格式", "使用 Tinymist 格式化当前文稿。", "format pretty 格式化 整理", isInsertion: false),
        .init("indent", "code", ">", "增加缩进", "将当前行或选中的多行向右缩进。", "indent 缩进", isInsertion: false),
        .init("outdent", "code", "<", "减少缩进", "将当前行或选中的多行向左缩进。", "outdent unindent 取消缩进", isInsertion: false),
        .init("comment", "code", ";", "切换行注释", "注释或取消注释当前行与选中的多行。", "comment uncomment 注释", isInsertion: false),
        .init("completion", "code", ".", "语法补全", "查看光标位置可用的 Typst 名称和参数。", "completion autocomplete 补全", isInsertion: false),
        .init("undo", "code", "z", "撤销", "撤销最近一次文稿编辑。", "undo 撤销", isInsertion: false),
        .init("redo", "code", "y", "重做", "恢复刚刚撤销的编辑。", "redo 重做", isInsertion: false),
        .init("cut", "code", "x", "剪切", "剪切选中的源码。", "cut 剪切", isInsertion: false),
        .init("copy", "code", "c", "复制", "复制选中的原始 Typst 源码。", "copy 复制", isInsertion: false),
        .init("paste", "code", "p", "粘贴", "在光标处粘贴文本。", "paste 粘贴", isInsertion: false),
        .init("selectAll", "code", "a", "全选", "选中整篇文稿。", "select all 全选", isInsertion: false),
        .init("find", "code", "s", "查找文稿", "在当前文稿中查找文字。", "find search 查找 搜索", isInsertion: false),
        .init("fontLarger", "view", "+", "放大编辑文字", "放大编辑区字号，不改变成稿排版。", "zoom in editor font 放大 字号"),
        .init("fontSmaller", "view", "-", "缩小编辑文字", "缩小编辑区字号，不改变成稿排版。", "zoom out editor font 缩小 字号"),
        .init("writing", "view", "w", "专注写作", "留出整个窗口，给正在写的文字。", "focus writing 专注"),
        .init("split", "view", "s", "并排预览", "一边写作，一边查看 Typst 成稿。", "split preview 分屏"),
        .init("preview", "view", "p", "阅读成稿", "用整个窗口查看排版结果。", "preview reading 预览"),
        .init("outline", "view", "o", "文章脉络", "在左侧留白中查看标题与章节，不移动正文。", "outline headings 大纲 目录 脉络"),
        .init("diagnostics", "view", "d", "检查文稿", "查看错误和建议，并跳转到对应位置。", "diagnostics errors 错误"),
        .init("revealPreview", "view", "r", "在成稿中定位", "找到光标所在段落的排版位置。", "reveal jump sync 定位"),
        .init("restart", "view", "l", "重新连接排版服务", "重启 Tinymist，并重新同步当前文稿。", "restart language server"),
        .init("logs", "view", "g", "打开诊断日志", "查看本地操作记录，帮助排查崩溃和异常。", "logs debug diagnostics 日志"),
        .init("previewDark", "view", "n", "切换深色预览", "切换成稿的阅读配色，PDF 导出保持文档原色。", "dark preview night 深色 暗色 夜间"),
        .init("styledSource", "view", "t", "切换编辑区样式", "为标题和强调文字显示样式，光标所在段落保留清晰源码。", "styled source live markup 编辑区 样式 源码"),
        .init("new", "file", "n", "新建文稿", "从一张安静的空白页开始。", "new document 新建"),
        .init("open", "file", "o", "打开文稿", "打开一个 .typ 文件。", "open file 打开"),
        .init("save", "file", "s", "保存", "将当前文稿保存到磁盘。", "save 保存"),
        .init("saveAs", "file", "a", "另存为", "为文稿选择新的名称和位置。", "save as 另存为"),
        .init("export", "file", "e", "导出 PDF", "把当前文稿排版为可分享的 PDF。", "export pdf 导出"),
        .init("drafts", "file", "d", "恢复草稿副本", "重新打开切换文稿时保留的草稿或重新加载前的副本。", "draft recovery 恢复"),
        .init("reload", "file", "r", "重新加载磁盘版本", "本地编辑先保留为恢复副本，再读取磁盘文件。", "reload disk conflict 重新加载")
    ]

    private static let searchIndex = all.map { "\($0.title) \($0.keywords) \($0.detail) \($0.shortcuts.map(\.label).joined(separator: " "))".lowercased() }
    public static func search(_ query: String) -> [Self] {
        let words = query.lowercased().split(whereSeparator: \.isWhitespace)
        if words.isEmpty { return all }
        return all.enumerated().compactMap { index, command in
            words.allSatisfy { searchIndex[index].contains($0) } ? command : nil
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

    public static func make(_ id: String, values: [String: String] = [:], selection: String = "", context: InsertionContext = .markup) throws -> Snippet {
        func value(_ key: String, _ fallback: String) -> String { values[key] ?? fallback }
        func number(_ key: String, _ fallback: String, _ range: ClosedRange<Int>) throws -> Int {
            guard let n = Int(value(key, fallback)), range.contains(n) else { throw CommandError.invalid("请输入 \(range.lowerBound)–\(range.upperBound) 之间的整数。") }
            return n
        }
        func label(_ fallback: String = "section-intro") throws -> String {
            let name = value("name", fallback)
            guard name.range(of: "^[A-Za-z][A-Za-z0-9_-]*$", options: .regularExpression) != nil else { throw CommandError.invalid("标签请以英文字母开头，使用字母、数字、短横线或下划线。") }
            return name
        }
        func amount(_ fallback: String, range: ClosedRange<Double> = 0...200) throws -> String {
            let source = value("amount", fallback)
            guard source.range(of: "^[0-9]+(?:\\.[0-9]+)?$", options: .regularExpression) != nil,
                  let number = Double(source), range.contains(number) else {
                throw CommandError.invalid("请输入 \(range.lowerBound)–\(range.upperBound) 之间的数字。")
            }
            return source
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
        func math(_ marked: String, block: Bool = false) -> Snippet {
            snippet(context == .math ? marked : (block ? "$ \(marked) $" : "$\(marked)$"))
        }
        let selectedSource = protect(selection)
        let selected = selection.isEmpty ? "«文字»" : selectedSource
        switch id {
        case "heading": return snippet(String(repeating: "=", count: try number("level", "1", 1...6)) + " " + (selection.isEmpty ? "«标题»" : selectedSource))
        case "bold": return snippet("*\(selected)*")
        case "italic": return snippet("_\(selected)_")
        case "highlight": return snippet("#highlight[\(selected)]")
        case "underline", "strike", "smallcaps": return snippet("#\(id)[\(selected)]")
        case "superscript": return snippet("#super[\(selected)]")
        case "subscript": return snippet("#sub[\(selected)]")
        case "textColor":
            let color = value("color", "245c73").trimmingCharacters(in: CharacterSet(charactersIn: "#"))
            guard color.range(of: "^(?:[0-9a-fA-F]{3}|[0-9a-fA-F]{6}|[0-9a-fA-F]{8})$", options: .regularExpression) != nil else { throw CommandError.invalid("请输入 3、6 或 8 位十六进制色值，例如 245c73。") }
            return snippet("#text(fill: rgb(\(quoted(color))))[\(selected)]")
        case "math": return snippet("$\(selection.isEmpty ? "«x^2 + y^2»" : selectedSource)$")
        case "equation": return snippet("\n$ \(selection.isEmpty ? "«E = m c^2»" : selectedSource) $\n")
        case "bullet": return snippet("- \(selection.isEmpty ? "«第一项»" : selectedSource)\n- «第二项»")
        case "numbered": return snippet("+ \(selection.isEmpty ? "«第一步»" : selectedSource)\n+ «第二步»")
        case "terms": return snippet("/ «术语»: \(selection.isEmpty ? "«定义说明»" : selectedSource)")
        case "lineBreak": return snippet("#linebreak()\n")
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
        case "font": return snippet("#set text(font: \(protect(quoted(value("font", "Libertinus Serif")))))\n")
        case "language":
            let language = value("language", "zh")
            guard language.range(of: "^[A-Za-z]{2,3}$", options: .regularExpression) != nil else { throw CommandError.invalid("请填写两个或三个字母的语言代码，例如 zh、en 或 ja。") }
            return snippet("#set text(lang: \(quoted(language.lowercased())))\n")
        case "leading": return snippet("#set par(leading: \(try amount("0.65", range: 0...10))em)\n")
        case "paragraphSpacing": return snippet("#set par(spacing: \(try amount("1.2", range: 0...20))em)\n")
        case "firstLineIndent": return snippet("#set par(first-line-indent: \(try amount("2", range: 0...20))em)\n")
        case "justify": return snippet("#set par(justify: true)\n")
        case "headingNumbering": return snippet("#set heading(numbering: \"1.1\")\n")
        case "equationNumbering": return snippet("#set math.equation(numbering: \"(1)\")\n")
        case "header", "footer": return snippet("#set page(\(id): \(protect(quoted(value("text", id == "header" ? "文稿标题" : "草稿")))))\n")
        case "documentInfo": return snippet("#set document(title: \(protect(quoted(value("title", "未命名文稿")))), author: \(protect(quoted(value("author", "作者")))))\n")
        case "fraction": return math("frac(\(selection.isEmpty ? "«a»" : selectedSource), «b»)")
        case "squareRoot": return math("sqrt(\(selection.isEmpty ? "«x»" : selectedSource))")
        case "nthRoot": return math("root(«3», \(selection.isEmpty ? "«x»" : selectedSource))")
        case "power": return math("(\(selection.isEmpty ? "«x»" : selectedSource))^«2»")
        case "mathSubscript": return math("(\(selection.isEmpty ? "«x»" : selectedSource))_«i»")
        case "binomial": return math("binom(«n», «k»)")
        case "matrix": return math("mat(«1», «2»; «3», «4»)")
        case "vector": return math("vec(«x», «y», «z»)")
        case "cases": return math("f(x) = cases(«x» & \"if\" x >= 0, «-x» & \"otherwise\")", block: true)
        case "aligned": return math("«a» &= «b + c» \\\n  &= «d»", block: true)
        case "sum": return math("sum_(«k = 1»)^«n» «k^2»")
        case "integral": return math("integral_«0»^«1» «x» dif «x»")
        case "limit": return math("lim_(«x -> 0») «sin(x)/x»")
        case "greek": return math("«alpha» + «beta» = «gamma»")
        case "setMembership": return math("«x» in «RR»")
        case "arrow": return math("«A» arrow.r «B»")
        case "upright": return math("upright(\(selection.isEmpty ? "«m»" : selectedSource))")
        case "accent": return math("arrow(\(selection.isEmpty ? "«v»" : selectedSource))")
        case "align":
            let alignment = value("alignment", "center")
            guard ["left", "center", "right"].contains(alignment) else { throw CommandError.invalid("请选择 left、center 或 right。") }
            return snippet("#align(\(alignment))[\(selected)]")
        case "columns": return snippet("#columns(\(try number("columns", "2", 2...4)), gutter: 18pt)[\n  \(selected)\n]")
        case "grid": return snippet("#grid(\n  columns: (1fr, 1fr),\n  gutter: 12pt,\n  [«左侧内容»], [«右侧内容»],\n)")
        case "block": return snippet("#block(fill: luma(95%), inset: 12pt, radius: 4pt)[\n  \(selected)\n]")
        case "padding": return snippet("#pad(\(try amount("12"))pt)[\(selected)]")
        case "stack": return snippet("#stack(dir: ltr, spacing: 12pt, [«左侧内容»], [«右侧内容»])")
        case "pageBreak": return snippet("#pagebreak()")
        case "verticalSpace": return snippet("#v(\(try amount("12"))pt)")
        case "horizontalSpace": return snippet("#h(\(try amount("12"))pt)")
        case "divider": return snippet("#line(length: 100%, stroke: 0.5pt)")
        case "contents": return snippet("#outline(title: \"目录\")")
        case "bibliography": return snippet("#bibliography(\(protect(quoted(value("path", "references.bib")))), style: \"ieee\")")
        case "citation": return snippet("#cite(<\(try label("example"))>)")
        case "include": return snippet("#include \(protect(quoted(value("path", "section.typ"))))")
        case "import": return snippet("#import \(protect(quoted(value("path", "helpers.typ")))): *\n")
        case "variable":
            let name = try label("project")
            guard !["let", "set", "show", "import", "include", "return", "break", "continue", "for", "while", "if", "else", "in", "as", "and", "or", "not", "true", "false", "none", "auto", "context"].contains(name) else { throw CommandError.invalid("变量名称不能使用 Typst 关键字。") }
            return snippet("#let \(name) = \(protect(quoted(value("value", "Sumi"))))\n")
        case "rawInline": return snippet("#raw(\(selection.isEmpty ? "\"«代码»\"" : protect(quoted(selection))))")
        default: throw CommandError.invalid("这个命令不能插入文字。")
        }
    }
}

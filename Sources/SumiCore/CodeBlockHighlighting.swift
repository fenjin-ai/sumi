import Foundation
import JavaScriptCore

/// Runs the bundled, pinned language grammars off the UI actor. Manuscript code
/// is passed as a function argument; it is never evaluated or sent to a network.
public actor CodeBlockHighlighting {
    private var context: JSContext?
    private struct Key: Hashable { let language: String; let text: String }
    private var cache: [Key: [HighlightToken]] = [:]
    public init() {}

    public func tokens(in source: String) -> [HighlightToken] {
        if context == nil {
            let bundle = Bundle.main.url(forResource: "Sumi_SumiCore", withExtension: "bundle").flatMap(Bundle.init(url:)) ?? Bundle.module
            guard let url = bundle.url(forResource: "highlight.min", withExtension: "js"),
                  let script = try? String(contentsOf: url, encoding: .utf8), let engine = JSContext() else { return [] }
            engine.evaluateScript(script)
            engine.evaluateScript("function sumiHighlight(code, language) { return hljs.getLanguage(language) ? hljs.highlight(code, {language: language, ignoreIllegals: true}).value : null; }")
            context = engine
        }
        let text = source as NSString
        var result: [HighlightToken] = [], nextCache: [Key: [HighlightToken]] = [:]
        var budget = 128_000
        for block in SourcePresentation.codeBlocks(in: source).prefix(80) {
            guard !Task.isCancelled else { return [] }
            guard !block.language.isEmpty, block.contentRange.length <= 32_000,
                  block.contentRange.length <= budget else { continue }
            budget -= block.contentRange.length
            let code = text.substring(with: block.contentRange)
            let key = Key(language: block.language, text: code)
            let spans: [HighlightToken]
            if let cached = cache[key] { spans = cached }
            else if let html = context?.objectForKeyedSubscript("sumiHighlight")?.call(withArguments: [code, block.language])?.toString(), html != "null" {
                let reader = HighlightHTMLReader()
                let parser = XMLParser(data: Data(("<code>" + html.replacingOccurrences(of: "\r", with: "&#13;") + "</code>").utf8))
                parser.shouldResolveExternalEntities = false
                parser.delegate = reader
                spans = parser.parse() && reader.text == code ? reader.tokens : []
            } else { spans = [] }
            nextCache[key] = spans
            result += spans.map { .init(range: NSRange(location: block.contentRange.location + $0.range.location, length: $0.range.length), kind: $0.kind) }
        }
        cache = nextCache
        return result
    }
}

private final class HighlightHTMLReader: NSObject, XMLParserDelegate {
    var text = ""
    private var offset = 0
    private var stack: [(start: Int, kind: String)] = []
    private var spans: [HighlightToken] = []
    var tokens: [HighlightToken] { spans.sorted { $0.range.length > $1.range.length } }

    func parser(_ parser: XMLParser, didStartElement name: String, namespaceURI: String?, qualifiedName: String?, attributes: [String: String]) {
        if name == "span" { stack.append((offset, attributes["class"] ?? "")) }
    }
    func parser(_ parser: XMLParser, foundCharacters string: String) {
        text += string; offset += string.utf16.count
    }
    func parser(_ parser: XMLParser, didEndElement name: String, namespaceURI: String?, qualifiedName: String?) {
        if name == "span", let start = stack.popLast(), offset > start.start {
            spans.append(.init(range: NSRange(location: start.start, length: offset - start.start), kind: start.kind))
        }
    }
}

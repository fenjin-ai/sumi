import AppKit
import SumiCore

/// One analysis at a time per editor. Superseded jobs waiting for the actor are
/// skipped, rather than launching unbounded detached scans while typing.
actor ReadingAnalysis {
    func decorations(in source: String) -> [SourceDecoration]? {
        guard !Task.isCancelled else { return nil }
        let result = SourcePresentation.decorations(in: source)
        return Task.isCancelled ? nil : result
    }
}

/// Text storage owns text and metrics-affecting reading styles. The layout
/// manager owns colors, so an asynchronous syntax reply cannot reflow text,
/// move the caret, or create an undo operation.
@MainActor
final class ManuscriptStyler {
    private static let syntaxColor = NSAttributedString.Key("SumiSyntaxColor")
    private static let readingColor = NSAttributedString.Key("SumiReadingColor")
    private static let readingFont = NSAttributedString.Key("SumiReadingFont")
    static let baseColor = NSColor(hex: 0xD5D9DE)
    private(set) var source: String?
    private(set) var sourceRevision = -1
    private var decorations: [SourceDecoration] = []
    private var reading: NSAttributedString?
    private var size: CGFloat = 0
    private var styled = false
    private var active: NSRange?
    private var syntaxRevision = -1
    private var hasSemanticColors = false
    private var fallbackRevision = -1

    func prepare(_ source: String, revision: Int, decorations: [SourceDecoration]) {
        guard sourceRevision != revision else { return }
        self.source = source
        sourceRevision = revision
        self.decorations = decorations
        reading = nil
    }

    static func baseAttributes(size: CGFloat) -> [NSAttributedString.Key: Any] {
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineSpacing = 7
        paragraph.paragraphSpacing = 2
        return [.font: NSFont.monospacedSystemFont(ofSize: size, weight: .regular),
                .foregroundColor: baseColor, .paragraphStyle: paragraph]
    }

    /// Returns whether glyph metrics changed. Color-only changes never require
    /// a synchronous layout pass. TextKit rebases temporary ranges on edits.
    func apply(to editor: ManuscriptTextView, size: CGFloat, styled: Bool,
               snapshot: (source: String, tokens: [HighlightToken])?, revision: Int, documentRevision: Int, syntaxDocumentRevision: Int) -> Bool {
        guard let storage = editor.textStorage, let manager = editor.layoutManager else { return false }
        let content = source ?? ""
        let whole = NSRange(location: 0, length: storage.length)
        var dirty: [NSRange] = []
        var geometryChanged = false
        if syntaxRevision != revision, syntaxDocumentRevision == documentRevision, let snapshot {
            let desired = NSMutableAttributedString(string: snapshot.source)
            for token in snapshot.tokens where token.range.location >= 0 && token.range.length > 0 && NSMaxRange(token.range) <= storage.length {
                desired.addAttribute(Self.syntaxColor, value: Self.color(for: token), range: token.range)
            }
            dirty += Self.updateTemporary(Self.syntaxColor, from: desired, in: whole, manager: manager)
            syntaxRevision = revision
            hasSemanticColors = true
        } else if !hasSemanticColors, fallbackRevision != documentRevision, sourceRevision == documentRevision {
            let desired = NSMutableAttributedString(string: content)
            for (regex, color) in Self.fallback {
                for match in regex.matches(in: content, range: whole) {
                    desired.addAttribute(Self.syntaxColor, value: NSColor(hex: color), range: match.range)
                }
            }
            dirty += Self.updateTemporary(Self.syntaxColor, from: desired, in: whole, manager: manager)
            fallbackRevision = documentRevision
        }

        // A plan is valid only for its exact source. While background analysis
        // catches up, keep the native attributes already shifted by the edit.
        if sourceRevision == documentRevision {
            let nextActive = SourcePresentation.activeParagraph(in: content, selection: editor.selectedRange())
            let resized = self.size != size
            let rebuild = reading == nil || self.size != size || self.styled != styled
            let base = Self.baseAttributes(size: size)
            if rebuild {
                let plan = NSMutableAttributedString(string: content, attributes: [.font: base[.font]!, .paragraphStyle: base[.paragraphStyle]!])
                if styled {
                    for decoration in decorations {
                        switch decoration.kind {
                        case .heading(let level):
                            plan.addAttributes([.font: NSFont.systemFont(ofSize: size + CGFloat(max(2, 8 - level * 2)), weight: .semibold), Self.readingColor: NSColor(hex: 0xEEE8DA)], range: decoration.range)
                        case .strong:
                            plan.addAttributes([.font: NSFont.monospacedSystemFont(ofSize: size, weight: .semibold), Self.readingColor: NSColor(hex: 0xEEE8DA)], range: decoration.range)
                        case .emphasis:
                            plan.addAttribute(.font, value: NSFontManager.shared.convert(base[.font] as! NSFont, toHaveTrait: .italicFontMask), range: decoration.range)
                        case .code:
                            plan.addAttributes([Self.readingColor: NSColor(hex: 0xA8B89A), .backgroundColor: NSColor(hex: 0x272D32)], range: decoration.range)
                        }
                        for marker in decoration.markers {
                            plan.addAttributes([.font: NSFont.systemFont(ofSize: 0.1), Self.readingColor: NSColor.clear], range: marker)
                        }
                    }
                }
                reading = plan
                self.size = size
                self.styled = styled
            }
            if rebuild || active != nextActive, let reading {
                let ranges = rebuild ? [whole] : Self.merged([active ?? .init(), nextActive])
                var drawings: [(NSRange, NSAttributedString)] = []
                storage.beginEditing()
                for range in ranges where range.length > 0 {
                    // Override the active paragraph in the desired plan before
                    // diffing. Never briefly hide it and then reveal it again.
                    let desired = NSMutableAttributedString(attributedString: reading.attributedSubstring(from: range))
                    let overlap = NSIntersectionRange(range, nextActive)
                    if overlap.length > 0 {
                        let local = NSRange(location: overlap.location - range.location, length: overlap.length)
                        desired.addAttribute(.font, value: base[.font]!, range: local)
                        desired.removeAttribute(Self.readingColor, range: local)
                        desired.removeAttribute(.backgroundColor, range: local)
                    }
                    for key in [NSAttributedString.Key.font, .paragraphStyle] {
                        desired.enumerateAttribute(key, in: NSRange(location: 0, length: desired.length)) { value, local, _ in
                            let target = NSRange(location: range.location + local.location, length: local.length)
                            var changes: [NSRange] = []
                            storage.enumerateAttributes(in: target) { current, span, _ in
                                if key == .font {
                                    // AppKit substitutes fonts for CJK and emoji.
                                    // Compare our intended style, not its fallback
                                    // font, or every pass undoes native font fixing.
                                    let readingFont = Self.equal(value, base[.font]) ? nil : value
                                    if resized || !Self.equal(current[Self.readingFont], readingFont) { changes.append(span) }
                                } else if !Self.equal(current[key], value) { changes.append(span) }
                            }
                            for span in changes {
                                if let value { storage.addAttribute(key, value: value, range: span) }
                                else { storage.removeAttribute(key, range: span) }
                                if key == .font {
                                    if let value, !Self.equal(value, base[.font]) { storage.addAttribute(Self.readingFont, value: value, range: span) }
                                    else { storage.removeAttribute(Self.readingFont, range: span) }
                                }
                                geometryChanged = true
                            }
                        }
                    }
                    drawings.append((range, desired))
                }
                storage.endEditing()
                // Temporary attributes can ask TextKit to generate glyphs.
                // They must never be changed inside a text-storage edit batch.
                for (range, desired) in drawings {
                    dirty += Self.updateTemporary(Self.readingColor, from: desired, in: range, manager: manager, local: true)
                    _ = Self.updateTemporary(.backgroundColor, from: desired, in: range, manager: manager, local: true)
                }
                active = nextActive
            }
        }
        for range in Self.merged(dirty) { Self.composeColors(in: range, manager: manager) }
        return geometryChanged
    }

    private static func equal(_ lhs: Any?, _ rhs: Any?) -> Bool {
        if lhs == nil && rhs == nil { return true }
        guard let lhs = lhs as? NSObject, let rhs = rhs as? NSObject else { return false }
        return lhs.isEqual(rhs)
    }

    /// Compare native runs first: identical responses and unaffected regions
    /// perform no writes and generate no display invalidations.
    private static func updateTemporary(_ key: NSAttributedString.Key, from desired: NSAttributedString,
                                        in range: NSRange, manager: NSLayoutManager, local: Bool = false) -> [NSRange] {
        var changes: [(NSRange, Any?)] = []
        let offset = local ? range.location : 0
        desired.enumerateAttribute(key, in: NSRange(location: range.location - offset, length: range.length)) { value, span, _ in
            var cursor = span.location + offset
            let end = NSMaxRange(span) + offset
            while cursor < end {
                var currentRange = NSRange()
                let current = manager.temporaryAttribute(key, atCharacterIndex: cursor, effectiveRange: &currentRange)
                let next = min(end, NSMaxRange(currentRange))
                guard next > cursor else { break }
                if !equal(current, value) { changes.append((NSRange(location: cursor, length: next - cursor), value)) }
                cursor = next
            }
        }
        for (span, value) in changes {
            if let value { manager.addTemporaryAttribute(key, value: value, forCharacterRange: span) }
            else { manager.removeTemporaryAttribute(key, forCharacterRange: span) }
        }
        return changes.map(\.0)
    }

    private static func composeColors(in range: NSRange, manager: NSLayoutManager) {
        var cursor = range.location
        while cursor < NSMaxRange(range) {
            var syntaxRange = NSRange(), readingRange = NSRange(), drawnRange = NSRange()
            let syntax = manager.temporaryAttribute(syntaxColor, atCharacterIndex: cursor, effectiveRange: &syntaxRange)
            let reading = manager.temporaryAttribute(readingColor, atCharacterIndex: cursor, effectiveRange: &readingRange)
            let drawn = manager.temporaryAttribute(.foregroundColor, atCharacterIndex: cursor, effectiveRange: &drawnRange)
            let end = min(NSMaxRange(range), NSMaxRange(syntaxRange), NSMaxRange(readingRange), NSMaxRange(drawnRange))
            guard end > cursor else { break }
            let color = reading ?? syntax
            if !equal(drawn, color) {
                let span = NSRange(location: cursor, length: end - cursor)
                if let color { manager.addTemporaryAttribute(.foregroundColor, value: color, forCharacterRange: span) }
                else { manager.removeTemporaryAttribute(.foregroundColor, forCharacterRange: span) }
            }
            cursor = end
        }
    }

    private static func merged(_ ranges: [NSRange]) -> [NSRange] {
        var result: [NSRange] = []
        for range in ranges.filter({ $0.length > 0 }).sorted(by: { $0.location < $1.location }) {
            if let last = result.last, NSMaxRange(last) >= range.location {
                result[result.count - 1] = NSUnionRange(last, range)
            } else { result.append(range) }
        }
        return result
    }

    private static let fallback: [(NSRegularExpression, UInt32)] = [
        ("(?m)^={1,6}[ \t]+.*$", 0xEEE8DA), ("#[A-Za-z][A-Za-z0-9_.-]*", 0xA5B8C8),
        (#""(?:[^"\\]|\\.)*""#, 0xA8B89A), (#"\$[^$]*\$"#, 0xD9B97C),
        (#"\*[^*\n]+\*"#, 0xEEE8DA), ("(?m)^//.*$", 0x7C8793)
    ].map { (try! NSRegularExpression(pattern: $0.0), $0.1) }

    private static func color(for token: HighlightToken) -> NSColor {
        let kind = token.kind.replacingOccurrences(of: "hljs-", with: "").components(separatedBy: " ").first ?? token.kind
        let color: UInt32
        switch kind {
        case "comment", "punct", "delim", "meta": color = 0x7C8793
        case "string", "regexp", "escape": color = 0xA8B89A
        case "keyword", "operator", "selector-tag": color = 0xBEA4C9
        case "number", "bool", "literal", "symbol", "bullet": color = 0xD9B97C
        case "function", "title", "built_in", "type", "namespace", "link", "ref", "label": color = 0x9DBBCD
        case "heading", "strong": color = 0xEEE8DA
        case "raw", "code": color = 0xBAC4CF
        default: color = token.modifiers.contains("math") ? 0xD9B97C : 0xD5D9DE
        }
        return NSColor(hex: color)
    }
}

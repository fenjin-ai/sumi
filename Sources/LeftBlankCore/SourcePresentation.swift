import Foundation

/// Conservative markup decoration. Ranges always refer to the original UTF-16 source.
/// Unfinished or code-like constructs remain source text instead of being guessed at.
public struct SourceDecoration: Equatable, Sendable {
    public enum Kind: Equatable, Sendable { case heading(Int), strong, emphasis, code }
    public let kind: Kind
    public let range: NSRange
    public let markers: [NSRange]
}

public struct SourceCodeBlock: Sendable {
    public let language: String
    public let contentRange: NSRange
}

public enum SourcePresentation {
    public static func decorations(in text: String) -> [SourceDecoration] {
        scan(text).decorations
    }

    public static func codeBlocks(in text: String) -> [SourceCodeBlock] {
        scan(text).blocks
    }

    private static func scan(_ text: String) -> (decorations: [SourceDecoration], blocks: [SourceCodeBlock]) {
        let source = text as NSString
        let units = Array(text.utf16)
        var excluded: [NSRange] = []
        var result: [SourceDecoration] = []
        var blocks: [SourceCodeBlock] = []
        var cursor = 0
        func escaped(_ index: Int) -> Bool {
            var i = index, count = 0
            while i > 0, units[i - 1] == 92 {
                count += 1
                i -= 1
            }
            return count % 2 == 1
        }
        while cursor < units.count {
            let start = cursor, c = units[cursor]
            if c == 47, cursor + 1 < units.count, units[cursor + 1] == 47 {
                while cursor < units.count, units[cursor] != 10 {
                    cursor += 1
                }
            } else if c == 47, cursor + 1 < units.count, units[cursor + 1] == 42 {
                var depth = 1
                cursor += 2
                while cursor < units.count, depth > 0 {
                    if cursor + 1 < units.count, units[cursor] == 47,
                       units[cursor + 1] == 42
                    {
                        depth += 1
                        cursor += 2
                    } else if cursor + 1 < units.count, units[cursor] == 42,
                              units[cursor + 1] == 47
                    {
                        depth -= 1
                        cursor += 2
                    } else {
                        cursor += 1
                    }
                }
            } else if c == 96, !escaped(cursor) {
                var count = 1
                while cursor + count < units.count, units[cursor + count] == 96 {
                    count += 1
                }
                cursor += count
                var closed = false
                while cursor < units.count {
                    if units[cursor] == 96 {
                        var end = cursor
                        while end < units.count, units[end] == 96 {
                            end += 1
                        }
                        if end - cursor == count {
                            cursor = end
                            closed = true
                            break
                        }
                        cursor = end
                    } else {
                        cursor += 1
                    }
                }
                let range = NSRange(location: start, length: cursor - start)
                if count == 1, closed, !source.substring(with: range).contains("\n") {
                    result.append(.init(
                        kind: .code,
                        range: range,
                        markers: [NSRange(location: start, length: 1), NSRange(location: cursor - 1, length: 1)],
                    ))
                } else if count >= 3 {
                    let bodyStart = start + count
                    let bodyEnd = closed ? cursor - count : cursor
                    let body = NSRange(location: bodyStart, length: bodyEnd - bodyStart)
                    let newline = source.rangeOfCharacter(from: .newlines, range: body)
                    if newline.location != NSNotFound {
                        let language = source.substring(with: NSRange(
                            location: bodyStart,
                            length: newline.location - bodyStart,
                        )).trimmingCharacters(in: .whitespaces).lowercased()
                        let contentStart = NSMaxRange(newline)
                        blocks.append(.init(
                            language: language,
                            contentRange: NSRange(location: contentStart, length: bodyEnd - contentStart),
                        ))
                    }
                }
            } else if c == 36, !escaped(cursor) {
                cursor += 1
                while cursor < units.count, units[cursor] != 36 || escaped(cursor) {
                    cursor += 1
                }
                if cursor < units.count {
                    cursor += 1
                }
            } else if c == 35, !escaped(cursor) {
                // Code expressions may span lines. Track balanced brackets and strings;
                // conservatively leave content arguments inside them undecorated.
                cursor += 1
                var depth = 0, quoted = false
                while cursor < units.count {
                    let next = units[cursor]
                    if next == 34, !escaped(cursor) {
                        quoted.toggle()
                    }
                    if !quoted {
                        if [40, 91, 123].contains(next) {
                            depth += 1
                        }
                        if [41, 93, 125].contains(next) {
                            depth = max(0, depth - 1)
                        }
                        if depth == 0, next == 10 {
                            break
                        }
                    }
                    cursor += 1
                }
            } else {
                cursor += 1
                continue
            }
            excluded.append(NSRange(location: start, length: cursor - start))
        }
        func overlapsExcluded(_ range: NSRange) -> Bool {
            var low = 0, high = excluded.count
            while low < high {
                let mid = (low + high) / 2
                if NSMaxRange(excluded[mid]) <= range.location {
                    low = mid + 1
                } else {
                    high = mid
                }
            }
            return low < excluded.count && excluded[low].location < NSMaxRange(range)
        }
        func add(
            _ pattern: String,
            kind: (NSTextCheckingResult) -> SourceDecoration.Kind,
            markers: (NSTextCheckingResult) -> [NSRange],
        ) {
            guard let regex = try? NSRegularExpression(pattern: pattern) else {
                return
            }
            for match in regex.matches(in: text, range: NSRange(location: 0, length: source.length)) {
                guard !overlapsExcluded(match.range),
                      !markers(match).contains(where: { escaped($0.location) })
                else {
                    continue
                }
                result.append(.init(kind: kind(match), range: match.range, markers: markers(match)))
            }
        }
        add(
            "(?m)^(={1,6})[ \\t]+[^\\r\\n]+",
            kind: { .heading($0.range(at: 1).length) },
            markers: { [$0.range(at: 1)] },
        )
        add(
            "(?<![\\w\\\\])\\*(?=\\S)[^*\\r\\n]+(?<=\\S)\\*(?!\\w)",
            kind: { _ in .strong },
            markers: { [
                .init(location: $0.range.location, length: 1),
                .init(location: NSMaxRange($0.range) - 1, length: 1),
            ] },
        )
        add(
            "(?<![\\w\\\\])_(?=\\S)[^_\\r\\n]+(?<=\\S)_(?!\\w)",
            kind: { _ in .emphasis },
            markers: { [
                .init(location: $0.range.location, length: 1),
                .init(location: NSMaxRange($0.range) - 1, length: 1),
            ] },
        )
        return (result.sorted { $0.range.location < $1.range.location }, blocks)
    }

    public static func activeParagraph(in text: String, selection: NSRange) -> NSRange {
        let source = text as NSString
        let start = min(max(0, selection.location), source.length)
        return source.paragraphRange(for: NSRange(
            location: start,
            length: min(max(0, selection.length), source.length - start),
        ))
    }
}

import Foundation

/// UTF-16 line boundaries for one immutable document revision. The index keeps
/// offsets only, never another copy of the manuscript. Reuse it for batches of
/// LSP positions, such as an outline, rather than rescanning for every heading.
public struct TextLineIndex: Sendable {
    private let starts: [Int]
    private let ends: [Int]
    public let length: Int

    public init(_ text: String) {
        var starts = [0], ends: [Int] = [], offset = 0
        var previousWasCR = false
        for unit in text.utf16 {
            if unit == 10, previousWasCR {
                // CRLF is one terminator; the next line starts after both units.
                starts[starts.count - 1] = offset + 1
            } else if unit == 10 || unit == 13 {
                ends.append(offset)
                starts.append(offset + 1)
            }
            previousWasCR = unit == 13
            offset += 1
        }
        ends.append(offset)
        self.starts = starts
        self.ends = ends
        length = offset
    }

    public func position(at offset: Int) -> TextPosition {
        let offset = min(max(0, offset), length)
        var low = 0, high = starts.count
        while low + 1 < high {
            let middle = (low + high) / 2
            if starts[middle] <= offset { low = middle } else { high = middle }
        }
        // A position inside a line terminator means the preceding line's end.
        return TextPosition(line: low, character: min(offset, ends[low]) - starts[low])
    }

    public func offset(at position: TextPosition) -> Int {
        let line = max(0, position.line)
        guard line < starts.count else { return length }
        return starts[line] + min(max(0, position.character), ends[line] - starts[line])
    }
}

public struct TextPosition: Codable, Equatable, Sendable {
    public let line: Int
    public let character: Int

    public init(line: Int, character: Int) {
        self.line = line
        self.character = character
    }

    public init(offset: Int, in text: String) {
        self = TextLineIndex(text).position(at: offset)
    }

    public func offset(in text: String) -> Int {
        TextLineIndex(text).offset(at: self)
    }

    /// The pinned preview protocol uses UTF-8 columns; LSP uses UTF-16.
    public func utf8Column(in text: String) -> Int {
        let index = TextLineIndex(text)
        let start = index.offset(at: TextPosition(line: line, character: 0))
        let end = index.offset(at: self)
        return (text as NSString).substring(with: NSRange(location: start, length: end - start)).utf8.count
    }

    public var json: [String: Any] { ["line": line, "character": character] }
}

public struct OutlineItem: Identifiable, Equatable, Sendable {
    public let title: String
    public let level: Int
    public let offset: Int
    public var id: Int { offset }
    public init(title: String, level: Int, offset: Int) { self.title = title; self.level = level; self.offset = offset }

}

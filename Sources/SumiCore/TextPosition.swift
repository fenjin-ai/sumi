import Foundation

public struct TextPosition: Codable, Equatable, Sendable {
    public let line: Int
    public let character: Int

    public init(line: Int, character: Int) {
        self.line = line
        self.character = character
    }

    public init(offset: Int, in text: String) {
        let units = Array(text.utf16)
        let end = min(max(0, offset), units.count)
        var row = 0
        var start = 0
        for index in 0..<end where units[index] == 10 {
            row += 1
            start = index + 1
        }
        self.init(line: row, character: end - start)
    }

    public func offset(in text: String) -> Int {
        let units = Array(text.utf16)
        var row = 0
        var start = 0
        while row < max(0, line), start < units.count {
            if units[start] == 10 { row += 1 }
            start += 1
        }
        var end = start
        while end < units.count, units[end] != 10, units[end] != 13 { end += 1 }
        return min(start + max(0, character), end)
    }

    /// The pinned preview protocol uses UTF-8 columns; LSP uses UTF-16.
    public func utf8Column(in text: String) -> Int {
        let start = TextPosition(line: line, character: 0).offset(in: text)
        let end = offset(in: text)
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
